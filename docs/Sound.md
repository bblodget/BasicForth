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
require sound.fs      \ the SDL3 audio backend (pulls in ffi.fs itself)
```

## The words (sound.fs)

| Word | Stack | Meaning |
|------|-------|---------|
| `snd-open` | ( -- ior ) | open the default playback device, start it; 0 = success |
| `snd-ready?` | ( -- flag ) | is a device open right now? |
| `snd-why` | ( -- c-addr u ) | why the last `snd-open` failed |
| `tone` | ( freq ms -- ) | queue a square-wave tone; returns at once |
| `beep` | ( -- ) | a short blip (880 Hz, 60 ms) |
| `snd-wait` | ( -- ) | block until everything queued has played |
| `snd-close` | ( -- ) | close the device |
| `tone-amp` | value | wave amplitude 0..32767 (default 8000); `to tone-amp` |

```
> require sound.fs
> snd-open drop
> 440 200 tone        \ concert A for 200 ms — returns immediately
> beep
> snd-wait snd-close
```

`tone` **queues and returns**: SDL's audio thread drains the queue, so a game
loop keeps animating while a sound plays, and back-to-back tones play
back-to-back. Use `snd-wait` before `bye` in a script, or the last tone is cut
off. With no device open, `tone`/`beep`/`snd-wait` are silent no-ops — so a
game writes `snd-open drop` and simply runs soundless on a system with no
working audio (headless, no sound server). `snd-open` returns an **ior** — 0
for success, like `allocate` and `open-file` — so the caller who *requires*
sound writes `snd-open abort" no audio device"`, and the one who wants the
reason writes `snd-open if snd-why type cr then`. One word, no `0=` anywhere.

Opening an already-open device succeeds and does nothing, so a redundant call
(an `on-start` hook after a dirty `:e`) costs nothing and disturbs nothing.

## How it works

`sound.fs` binds twelve SDL3 calls via the FFI (see [FFI.md](FFI.md)) and
synthesizes samples in Forth — integer-only, signed 16-bit mono at 44100 Hz
(SDL converts/resamples to whatever the device wants):

- `snd-open` → `SDL_Init(SDL_INIT_AUDIO)` + `SDL_OpenAudioDevice(default,
  spec)`, then one `SDL_CreateAudioStream` + `SDL_BindAudioStream` per
  channel, then `SDL_ResumeAudioDevice`. Any step failing snapshots
  `SDL_GetError` for `snd-why`, unwinds what came before, and returns a
  non-zero ior. The snapshot has to happen *before* the unwind: `snd-close`
  calls `SDL_QuitSubSystem`, which would replace the message.
- `tone` → fills a heap buffer (`allocate`/`free`) with ±`tone-amp`, flipping
  every `44100 / (2*freq)` samples, then `ch-put` on `tone-ch`.
- `ch-put` → `SDL_PutAudioStreamData` on that channel's stream. Nothing is
  scaled or transformed on the way in; SDL copies the bytes into the stream,
  so the caller's buffer is free again immediately (which is why `tone` frees
  its own on the next line).
- `ch-queued` / `snd-wait` → `SDL_GetAudioStreamQueued`, polled every 10 ms.
- `ch-stop` → `SDL_ClearAudioStream`.
- `snd-close` → `SDL_DestroyAudioStream` per channel, `SDL_CloseAudioDevice`,
  `SDL_QuitSubSystem(SDL_INIT_AUDIO)` — subsystem-scoped, so it never tears
  down a live video session. (`sdl-close`'s full `SDL_Quit` ends audio too;
  close sound first, as `bounce` does.)

### Why the plain device API, not `SDL_OpenAudioDeviceStream`

The obvious setup call is `SDL_OpenAudioDeviceStream`, which opens a device
and hands back a stream in one step — and that is what `sound.fs` used while
it was single-stream. It cannot be used here. A device opened that way is
welded to the stream it returned, and any later bind fails with:

    Cannot change stream bindings on device opened with SDL_OpenAudioDeviceStream

So mixing requires opening the device with `SDL_OpenAudioDevice` and creating
and binding every stream explicitly. Nothing in the header says the two paths
differ this way; it shows up only as a runtime error from
`SDL_BindAudioStream`.

### Channels

The device holds `snd-channels` streams (a fixed 64), all bound to
one logical device, and **SDL mixes them** — there is no mixer code here.
Sounds on different channels play together; sounds queued on one channel play
in sequence.

`next-ch` hands out channels round-robin and **steals the least recently
allocated** when all are busy, so a program that fires more sounds than it has
channels loses its stalest rather than refusing the newest. It is round-robin
rather than lowest-free because a channel only counts as busy once audio is
queued on it — two allocations before either was given samples would otherwise
both return the same channel.

A subsystem that needs a channel to stay its own **claims** it, and `next-ch`
stops offering it until it is released. A claim outlives a `snd-close` /
`snd-open`, because it belongs to whoever took it rather than to the device;
each owner releases its own, so `snd-close` gives back only `tone`'s.

`snd-open` claims a channel for `tone` (`tone-ch`), which is what keeps a run
of plain tones playing in sequence exactly as it did before channels existed.
It is claimed rather than reserved: `next-ch` skips it because somebody holds
it, not because of its number, so `tone` needs no special case anywhere.

Per-channel volume is `SDL_SetAudioStreamGain`, applied by SDL **as it pulls
the audio out**. So it costs nothing at queue time, needs no copy of anyone's
samples, reaches audio already queued, and works whatever format the channel
is carrying — none of which is true of scaling on the way in.

That call takes a `float`, which is why the FFI grew float arguments
(`(ccallf)`, see [FFI.md](FFI.md)); before that this was done by scaling
samples into a copy at queue time, and the description above is what replaced
it.

Constants and the 12-byte `SDL_AudioSpec` layout are verified against the
SDL3 headers by `tools/sdl3off.c`.

## The demo (examples/bounce.fs)

```
include examples/bounce.fs    \ requires sdl3.fs + sound.fs itself
bounce                \ blips on every wall hit
```

`bounce` opens sound alongside the window (`snd-open drop` — soundless if
there's no audio) and `(b-axis)` plays a 660 Hz blip whenever the square
reverses. `bounce-frames` (the automated-test variant) never opens sound, so
its blips are no-ops.

## Testing

The integration tests use SDL's **dummy audio driver**
(`SDL_AUDIO_DRIVER=dummy`), so no sound hardware is needed: `tone` before
opening must leave the stack depth unchanged (the no-op path), then open,
tone (aborts if the queue write fails), zero/negative durations as no-ops,
close. A second case sets a bogus `SDL_AUDIO_DRIVER` and checks `snd-open`
returns false without aborting; a third checks `bye` with the device still
open actually ends the process (SDL spawns threads, so `platform_exit` must
use `exit_group` — see [Platform_Layer.md](Platform_Layer.md)). See the FFI
section of `tests/test_integration.sh`. The QEMU run skips it (no aarch64 libSDL3 in the
qemu sysroot); on the board, SDL3 must be in the Pumpkian image.

## Scope and what's next

Current state: square waves and sampled sound on mixing channels.
`wavcore.fs` decodes WAV files into sample handles — 8, 16, 24 and 32-bit,
integer and float (`help samples`) — and `wav.fs` plays one through `ch-put`,
which is what the channel layer was built for. Speech sits above that as one
more source of samples: `voice.fs` renders phrases to WAV files with an
external engine (`help voice`, [Speech.md](Speech.md)).

Possible next steps: other waveforms (triangle/noise) and a note/duration
music word (`PLAY "CDE"` style).

`wavcore.fs` deliberately requires **nothing** — no FFI, no SDL. That is not
tidiness: `require sound.fs` aborts on a machine with no libSDL3, which
includes the aarch64 QEMU run, so a decoder living inside it would be
untestable on half our architectures. Split out, the decoder's tests run
everywhere and only playback skips.

One limit worth knowing before building on this: audio is **pushed from your
main loop**. SDL3 offers a pull callback, but a Forth word cannot serve as a C
callback, so nothing tops up the queue except code you run. A long frame
starves it and you hear a gap. Looping sound and streaming synthesis will each
need a "service the queue" word called once a frame; a real audio thread would
remove the constraint, and threading is a planned phase.
