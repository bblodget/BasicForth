# Channels — Playing Sounds at the Same Time

The audio device holds several **channels**, and SDL mixes everything bound to
it. Sounds on *different* channels play **together**; sounds queued on *one*
channel play **one after another**. Load the backend with `require sound.fs`.

    require sound.fs
    snd-open drop
    440 300 1 tone-on        \ channel 1
    660 300 2 tone-on        \ channel 2 -- both sound at once
    snd-wait snd-close

Channel 0 (`tone-ch`) belongs to `tone`, which is why a run of plain tones
still plays in sequence. Ask for another channel when you want overlap.

At a glance:

    snd-channels     ( -- n )          how many channels (64; rarely changed)
    snd-max-channels ( -- n )          hard ceiling, 64
    tone-ch          ( -- 0 )          the channel `tone` uses
    next-ch          ( -- ch )         a free channel, else steal the oldest
    ch-claim         ( ch -- )         keep this channel; next-ch skips it
    ch-release       ( ch -- )         give it back to the rotation
    tone-on          ( freq ms ch -- ) a tone on a chosen channel
    ch-put           ( c-addr u ch -- ) queue raw 16-bit mono samples
    ch-playing?      ( ch -- flag )    is anything queued?
    ch-queued        ( ch -- n )       bytes still to play
    ch-stop          ( ch -- )         drop whatever is queued, at once
    ch-fade          ( ms ch -- )      fade out over ms, then stop
    snd-stop         ( -- )            stop every channel
    snd-pump         ( -- )            service fades; call once a frame
    ch-wait          ( ch -- )         block until this channel drains
    ch-vol!          ( n ch -- )       channel volume, 0..snd-unity
    ch-vol@          ( ch -- n )       read it back
    snd-unity        ( -- 256 )        the ch-vol! value meaning "unchanged"
    ch-format!       ( fmt chans rate ch -- )  what the next samples look like
    ch-format@       ( ch -- fmt chans rate )  read that back
    AUDIO_S16LE      ( -- fmt )        16-bit signed samples
    AUDIO_S32LE      ( -- fmt )        32-bit signed samples
    AUDIO_F32LE      ( -- fmt )        32-bit float samples
    AUDIO_U8         ( -- fmt )        8-bit unsigned samples

## snd-channels ( -- n )
How many channels the device has. It defaults to 64 — the ceiling — because
channels cost almost nothing: 64 instead of 16 measures at about 100 KB of
memory and under a microsecond per `snd-pump`. So most programs never touch
this.

The reason to **shrink** it is to force channel reuse cheaply: filling every
channel to exercise `next-ch`'s stealing takes 10 ms at 4 channels and
218 ms at 64, which is why the test suite turns it down.

Read **once**, when `snd-open` runs, and `snd-open` on an already-open device
does nothing — so changing it needs an explicit close, and the close goes
**first**, while the channels being closed are still the ones that are open:

    snd-close   4 to snd-channels   snd-open drop

(`snd-close` clears every slot regardless, so the other order no longer leaks
streams — but it does orphan anything still playing on a channel above the new
count, which the `ch-` words can no longer reach.)

Clamped into `2 .. snd-max-channels`.

## snd-max-channels ( -- n )
The hard ceiling on `snd-channels`, 64.

## tone-ch ( -- 0 )
The channel `tone` and `beep` use. Reserved: `next-ch` never returns it, so
sound effects cannot cut a game's tones short.

## next-ch ( -- ch )
The next channel to play something on — a free one if there is any, and if
every channel is busy it **steals the one handed out longest ago**, so a
program firing more sounds than it has channels loses its stalest sound rather
than its newest.

Nothing is allocated, in the `allocate` sense, and nothing has to be released:
the channels are a fixed set, and one returns to rotation by itself. It is
named like `tone-ch` because it answers the same kind of question — that is
the channel `tone` uses, this is the next channel to use.

Returns `tone-ch` when no device is open — harmless, since every channel word
is a no-op then — and `-1` when every channel has been claimed, which is not a
channel at all. With a device open it never returns `tone-ch`.

A channel only counts as busy once audio is queued on it, so queue promptly:

    : blip ( -- )  660 40 next-ch tone-on ;

That last point is why **keeping** a channel needs `ch-claim`: a channel held
for later goes back into rotation as soon as it falls silent, so `next-ch`
would hand it to someone else between two of your sounds.

## ch-claim ( ch -- )
Keep a channel. `next-ch` will not hand it out again — not while it is silent,
and not when every other channel is busy and it would otherwise be stolen.

Use it when a subsystem needs a channel of its own for as long as it runs, so
that its sounds queue behind *each other* and nothing else lands among them.
`speech.fs` does exactly this: a spoken phrase must never wait behind a sound
effect, which is only true if the channel stays its own.

    next-ch dup ch-claim value music-ch

Without it the channel is reissued surprisingly quickly — measured, one held
channel came back from `next-ch` 3 times in 200 calls.

Claiming every channel leaves `next-ch` nothing to give, and it answers `-1`.
That is **not** a channel — every channel word ignores it, so the sound is
dropped. It does not fall back to `tone-ch`: channel 0 is reserved so that
effects cannot cut a game's tones short, and handing it out here would do
precisely that, on the one path where the caller has no way to tell.

Ignored for a channel that doesn't exist. `snd-close` releases every claim,
since closing destroys the channels themselves.

## ch-release ( ch -- )
Give a claimed channel back to the rotation. The counterpart to `ch-claim`,
and only meaningful after one — an unclaimed channel is already in rotation.

    music-ch ch-release

## tone-on ( freq ms ch -- )
Like `tone`, but on a channel you choose. `tone` is exactly
`tone-ch tone-on`.

    440 300 1 tone-on  660 300 2 tone-on    \ a two-note chord

## ch-put ( c-addr u ch -- )
Queue `u` bytes of raw signed 16-bit mono samples on a channel. This is the
primitive every sound goes through — `tone` builds a square wave and calls it.

Volume is not applied here — SDL applies the channel's gain as it pulls the
audio out — so *we* neither scale nor duplicate what you hand over, and one
sample can be given to several channels without a copy per channel.

SDL, however, **does copy the bytes into the stream**, so the buffer is yours
again the moment `ch-put` returns. `tone-on` relies on this: it allocates,
fills, calls `ch-put`, and frees on the very next line. A sample you intend to
play repeatedly is worth keeping, but nothing here requires it.

Nothing is declared "finished" here, so consecutive sounds on one channel join
seamlessly — which is what keeps a run of tones sounding like one sweep.

## ch-playing? ( ch -- flag )
True while the channel still has audio to come out.

This asks the *output* side, not `ch-queued`. A channel resampling — any
sample whose rate differs from the device's — keeps a few input bytes back
waiting for more input that never arrives, so `ch-queued` settles at a small
non-zero number and never reaches nought.

Those held-back bytes are not lost: the **next** sound queued on that channel
is converted together with them, which is what lets consecutive sounds join
seamlessly. They are only left unplayed when nothing more is queued — a
fragment at the very end of a run, too short to have been audible.

How much is held is SDL's business, not a number to rely on; it depends on the
rates and format in play. The only thing worth knowing is that it is small
enough to be inaudible, and that a sound *shorter* than whatever the resampler
needs will not come out at all — which is why a channel fed a handful of bytes
stays silent.

    begin  1 ch-playing?  while  ... do other work ...  repeat

## ch-queued ( ch -- n )
Bytes **you put in** that have not been converted yet — not a measure of how
much is left to hear. Use `ch-playing?` for that; the two differ, and a
resampling channel leaves a few bytes here permanently. 0 for a channel that
doesn't exist.

## ch-stop ( ch -- )
Drop everything queued on the channel; it falls silent at once. Stopping a
sound mid-waveform can click — that is the cost of an immediate stop; use
`ch-fade` when you have a moment to spare.

Also cancels a fade in progress, restoring the volume it was moving away from.
Without that, a channel stopped mid-fade would keep its lowered gain and the
*next* sound played there would come out faint for no visible reason.

## ch-fade ( ms ch -- )
Fade the channel to silence over `ms` milliseconds, then stop it and restore
the volume. The gentle counterpart to `ch-stop`.

    2000 3 ch-fade        \ two-second fade out on channel 3

The fade is driven by `snd-pump`, so a program that never pumps never fades.

`ch-vol@` keeps reporting the volume throughout, because a fade moves the
underlying **gain** and never the setting you chose. That also means changing
the volume *during* a fade works as you would expect: the new level is
recorded at once, the fade carries on from it at the next `snd-pump`, and it
is what remains when the fade ends. The gain itself belongs to the fade while
one is running — `ch-vol!` deliberately does not touch it, since applying the
full new volume for one frame and then snapping back is an audible blip.

**A fade belongs to the sound it was started on.** Queueing anything new on
that channel cancels it and restores the volume, because the sound the fade
was for is no longer the one playing. Without that rule a fade could reach
past its own sound and silence something unrelated: a short sound that ends
early leaves the deadline armed, and whatever is playing when it arrives gets
stopped instead.

## snd-pump ( -- )
Service the channels: move any fades along, and stop the ones that finished.
Call it **once a frame**.

Fades are the only thing it does, so with nothing fading it is a no-op — a
program that never uses `ch-fade` never needs it, and a plain `ms` is enough
to wait before a `ch-stop`.

    begin  ... draw ...  snd-pump  sdl-frame  key? until

Nothing else can do this. SDL pulls audio on its own thread, and a Forth word
cannot be a C callback, so your loop is the only clock available.

## snd-stop ( -- )
`ch-stop` every channel, `tone-ch` included. Silence now, device still open.

## ch-wait ( ch -- )
Block until this one channel has finished. `snd-wait` waits for all of them.

## ch-vol! ( n ch -- )
Set a channel's volume, `0` (silent) to `snd-unity` (unchanged). Clamped, and
ignored for a channel that doesn't exist.

Volume is SDL's per-stream gain, applied as it **pulls** the audio out — so it
changes sound that is *already playing*, costs nothing when queueing, needs no
copy of your samples, and works whatever format the channel is carrying.

    64 3 ch-vol!            \ quarter volume on channel 3, immediately

Set it **before** queueing the sound you want it to apply to: SDL pulls audio
on its own schedule and can take the first chunk before a later `ch-vol!`
lands. Take the channel with `next-ch`, set the volume, then play on it.

**Volume belongs to the channel, not to the sound**, and it stays after the
sound ends. Since `next-ch` hands that channel out again later, a program
that quietens one sound and never puts the volume back will eventually play an
unrelated sound quietly for no visible reason. Set it back when you are done,
or use `wav-play-on` with a channel you keep for the purpose.

## ch-vol@ ( ch -- n )
Read a channel's volume back. `snd-unity` for a channel that doesn't exist.

## snd-unity ( -- 256 )
The `ch-vol!` value that means "play at the sample's own level". Volume is a
fraction of this, so `128` is half and `0` is silent.

## ch-format! ( format channels rate ch -- )
Tell a channel what the samples you are about to give it look like. Three
things describe them, and then the channel they are going to:

- **format** — how one sample is stored: `AUDIO_S16LE`, `AUDIO_S32LE`,
  `AUDIO_F32LE` or `AUDIO_U8`.
- **channels** — how many streams of sound are **interleaved** in the data,
  1 to 8. Beware the word: this is *audio* channels, nothing to do with the
  mixing channel the last argument names. SDL's layouts, one frame at a time:

      1  mono    FRONT
      2  stereo  FL FR
      3  2.1     FL FR LFE
      4  quad    FL FR BL BR
      5  4.1     FL FR LFE BL BR
      6  5.1     FL FR FC LFE BL BR
      7  6.1     FL FR FC LFE BC SL SR
      8  7.1     FL FR FC LFE BL BR SL SR

  SDL reorders for platforms that expect something else, and downmixes to
  whatever the device actually has — hand it 7.1 on a stereo laptop and it
  plays. Nothing here is checked before SDL sees it; `wav-load` decodes only
  mono and stereo, but that is the decoder's limit, not this word's.
- **rate** — **sample frames** per second *in the data*, not what the hardware
  runs at; SDL resamples. Frames, not samples: stereo at 48000 carries 48000
  frames a second and so 96000 individual samples.

    AUDIO_F32LE 2 48000 3 ch-format!
    \ 32-bit float, stereo, 48 kHz — queued on mixing channel 3

Each queued chunk keeps the format it was queued with, so this can change
while audio is still playing: a 16-bit tone and a 48 kHz stereo float sample
can sit in one queue and both come out right.

**Whoever queues, sets the format.** `tone-on` does it too, so a channel that
last carried a wav does not reinterpret a square wave as something else.
`wav-play` does it from the sample. You only need this for raw `ch-put`.

## ch-format@ ( ch -- format channels rate )
Read back what a channel is expecting. `0 0 0` for a channel that doesn't
exist.

## AUDIO_S16LE ( -- format )
16-bit signed samples — what `tone` generates, and what most WAV files hold.

The names read left to right: **S** signed (or **U** unsigned, or **F**
floating point), then the bit depth, then **LE** for little-endian — least
significant byte first. So 8000 in `AUDIO_S16LE` sits in memory as `40 1F`.
SDL also defines big-endian twins (`SDL_AUDIO_S16BE`); we bind none, because
both our architectures are little-endian and WAV is little-endian by
specification.

## AUDIO_S32LE ( -- format )
32-bit signed samples. `wav-load` widens 24-bit files to this, since SDL has
no 24-bit format of its own.

## AUDIO_F32LE ( -- format )
32-bit floating-point samples, the usual output of professional audio tools.
Note the bit depth does not tell you this: 32-bit comes in both integer and
float, and only the name (and the WAV `fmt ` code) says which.

## AUDIO_U8 ( -- format )
8-bit unsigned samples — old, small, and noticeably coarse. Unsigned, so
silence is 128 rather than 0.

These four are what `ch-format!` accepts, because they are what SDL can play.
`wav-play` picks the right one from the sample itself, so you only need to
name a format when queueing raw samples with `ch-put`.

## Notes

Every one of these is a silent no-op with no device open, so a program runs
unchanged on a machine with no working audio (`snd-open drop`).

## See Also

- `help sound` — `tone`, `beep`, and opening the device.
- `docs/Sound.md` — how the backend works and why it uses the plain device API.
- `help ffi` — the calling mechanism underneath.
