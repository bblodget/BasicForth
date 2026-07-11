# Sound — Square-Wave Tones via SDL3 Audio

BasicForth plays sound through **SDL3 audio** (`sound.fs` over the FFI): open
the default playback device, queue integer square-wave tones, keep running
while SDL's audio thread plays them. On a desktop, SDL hands the samples to
PipeWire/PulseAudio; on a console-only system it can drive ALSA directly. The
same library that gives us the window and input gives us sound for free — see
the **Graphics Direction** design decision in [Planning.md](Planning.md).

> History: a raw-ALSA-ioctl backend (like the DRM/KMS display experiment) was
> planned but never built — on a desktop the sound server holds the hardware
> PCM device open, so opening `/dev/snd/pcm*` directly fails with EBUSY, the
> same fight-the-compositor problem that killed the DRM backend. Raw ALSA
> remains the right path for a future no-sound-server appliance mode (see
> [WildIdeas.md](WildIdeas.md)).

Loads **on demand** (not at startup), independent of graphics — terminal
programs can beep too:

```
include ffi.fs        \ dlopen/dlsym/ccall (see docs/FFI.md)
include sound.fs      \ the SDL3 audio backend
```

## The words (sound.fs)

| Word | Stack | Meaning |
|------|-------|---------|
| `snd-open` | ( -- ) | open the default playback device, start it; aborts if none |
| `snd-open?` | ( -- flag ) | tolerant open: false if the system has no audio |
| `tone` | ( freq ms -- ) | queue a square-wave tone; returns at once |
| `beep` | ( -- ) | a short blip (880 Hz, 60 ms) |
| `snd-wait` | ( -- ) | block until everything queued has played |
| `snd-close` | ( -- ) | close the device |
| `snd-vol` | value | amplitude 0..32767 (default 8000); `to snd-vol` |

```
> include ffi.fs  include sound.fs
> snd-open
> 440 200 tone        \ concert A for 200 ms — returns immediately
> beep
> snd-wait snd-close
```

`tone` **queues and returns**: SDL's audio thread drains the queue, so a game
loop keeps animating while a sound plays, and back-to-back tones play
back-to-back. Use `snd-wait` before `bye` in a script, or the last tone is cut
off. With no device open, `tone`/`beep`/`snd-wait` are silent no-ops — so a
game opens sound with `snd-open? drop` and simply runs soundless on a system
with no working audio (headless, no sound server), while `snd-open` aborts
with the SDL error message for when you want to know why.

## How it works

`sound.fs` binds eight SDL3 calls via the FFI (see [FFI.md](FFI.md)) and
synthesizes samples in Forth — integer-only, signed 16-bit mono at 44100 Hz
(SDL converts/resamples to whatever the device wants):

- `snd-open?` → `SDL_Init(SDL_INIT_AUDIO)` +
  `SDL_OpenAudioDeviceStream(default, spec, 0, 0)` — the single-call setup
  path; passing a NULL callback makes it a push queue. Streams open paused,
  so `SDL_ResumeAudioStreamDevice` starts it. Any step failing unwinds what
  came before and returns false; `snd-open` is the same but aborts.
- `tone` → fills a heap buffer (`allocate`/`free`) with ±`snd-vol`, flipping
  every `44100 / (2*freq)` samples, then `SDL_PutAudioStreamData`.
- `snd-wait` → polls `SDL_GetAudioStreamQueued` every 10 ms until empty.
- `snd-close` → `SDL_DestroyAudioStream` (closes the device it opened) +
  `SDL_QuitSubSystem(SDL_INIT_AUDIO)` — subsystem-scoped, so it never tears
  down a live video session. (`sdl-close`'s full `SDL_Quit` ends audio too;
  close sound first, as `bounce` does.)

Constants and the 12-byte `SDL_AudioSpec` layout are verified against the
SDL3 headers by `tools/sdl3off.c`.

## The demo (examples/bounce.fs)

```
include graphics.fs  include ffi.fs  include sdl3.fs
include sound.fs
include examples/bounce.fs
bounce                \ blips on every wall hit
```

`bounce` opens sound alongside the window (`snd-open? drop` — soundless if
there's no audio) and `(b-axis)` plays a 660 Hz blip whenever the square
reverses. `bounce-frames` (the automated-test variant) never opens sound, so
its blips are no-ops.

## Testing

The integration tests use SDL's **dummy audio driver**
(`SDL_AUDIO_DRIVER=dummy`), so no sound hardware is needed: `tone` before
opening must leave the stack depth unchanged (the no-op path), then open,
tone (aborts if the queue write fails), zero/negative durations as no-ops,
close. A second case sets a bogus `SDL_AUDIO_DRIVER` and checks `snd-open?`
returns false without aborting; a third checks `bye` with the device still
open actually ends the process (SDL spawns threads, so `platform_exit` must
use `exit_group` — see [Platform_Layer.md](Platform_Layer.md)). See the FFI
section of `tests/test_integration.sh`. The QEMU run skips it (no aarch64 libSDL3 in the
qemu sysroot); on the board, SDL3 must be in the Pumpkian image.

## Scope and what's next

Current state: square waves only — the authentic 1980s BASIC `BEEP`. Possible
next steps: other waveforms (triangle/noise), a note/duration music word
(`PLAY "CDE"` style), mixing multiple channels, and sampled sound effects for
games.
