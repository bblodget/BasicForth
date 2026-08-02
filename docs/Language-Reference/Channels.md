# Channels — Playing Sounds at the Same Time

The audio device holds several **channels**, and SDL mixes everything bound to
it. Sounds on *different* channels play **together**; sounds queued on *one*
channel play **one after another**. Load the backend with `require sound.fs`.

    require sound.fs
    snd-open
    440 300 1 tone-on        \ channel 1
    660 300 2 tone-on        \ channel 2 -- both sound at once
    snd-wait snd-close

Channel 0 (`tone-ch`) belongs to `tone`, which is why a run of plain tones
still plays in sequence. Ask for another channel when you want overlap.

At a glance:

    snd-channels     ( -- n )          how many channels (set before snd-open)
    snd-max-channels ( -- n )          hard ceiling, 64
    tone-ch          ( -- 0 )          the channel `tone` uses
    snd-alloc        ( -- ch )         a free channel, else steal the oldest
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
How many channels the device has, default 16. Read **once**, when `snd-open`
runs, so set it first:

    32 to snd-channels   snd-open

Clamped into `2 .. snd-max-channels`. Channels are cheap — one SDL stream
each — so raise it freely if a program layers many sounds.

## snd-max-channels ( -- n )
The hard ceiling on `snd-channels`, 64.

## tone-ch ( -- 0 )
The channel `tone` and `beep` use. Reserved: `snd-alloc` never returns it, so
sound effects cannot cut a game's tones short.

## snd-alloc ( -- ch )
Hand out a channel to play something on. Returns a channel that isn't busy if
there is one; if every channel is busy it **steals the least recently
allocated**, so a program firing more sounds than it has channels loses its
stalest sound rather than its newest.

Returns `tone-ch` when no device is open. A channel only counts as busy once
audio is queued on it, so queue promptly:

    : blip ( -- )  660 40 snd-alloc tone-on ;

## tone-on ( freq ms ch -- )
Like `tone`, but on a channel you choose. `tone` is exactly
`tone-ch tone-on`.

    440 300 1 tone-on  660 300 2 tone-on    \ a two-note chord

## ch-put ( c-addr u ch -- )
Queue `u` bytes of raw signed 16-bit mono samples on a channel. This is the
primitive every sound goes through — `tone` builds a square wave and calls it.

Volume is not applied here — SDL applies the channel's gain as it pulls the
audio out — so the bytes go straight through and a sound shared between
channels is never copied or modified.

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
lands. Take the channel with `snd-alloc`, set the volume, then play on it.

**Volume belongs to the channel, not to the sound**, and it stays after the
sound ends. Since `snd-alloc` hands that channel out again later, a program
that quietens one sound and never puts the volume back will eventually play an
unrelated sound quietly for no visible reason. Set it back when you are done,
or use `wav-play-on` with a channel you keep for the purpose.

## ch-vol@ ( ch -- n )
Read a channel's volume back. `snd-unity` for a channel that doesn't exist.

## snd-unity ( -- 256 )
The `ch-vol!` value that means "play at the sample's own level". Volume is a
fraction of this, so `128` is half and `0` is silent.

## ch-format! ( format channels rate ch -- )
Tell a channel what the samples you are about to give it look like — the
format constants are `AUDIO_S16LE`, `AUDIO_S32LE`, `AUDIO_F32LE` and
`AUDIO_U8`. SDL converts and resamples to whatever the hardware wants, so the
rate here is the *sample's* rate, not the device's.

    AUDIO_F32LE 2 48000 3 ch-format!

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

## AUDIO_S32LE ( -- format )
32-bit signed samples. `wav-load` widens 24-bit files to this, since SDL has
no 24-bit format of its own.

## AUDIO_F32LE ( -- format )
32-bit floating-point samples, the usual output of professional audio tools.

## AUDIO_U8 ( -- format )
8-bit unsigned samples — old, small, and noticeably coarse.

These four are what `ch-format!` accepts, because they are what SDL can play.
`wav-play` picks the right one from the sample itself, so you only need to
name a format when queueing raw samples with `ch-put`.

## Notes

Every one of these is a silent no-op with no device open, so a program runs
unchanged on a machine with no working audio (`snd-open? drop`).

## See Also

- `help sound` — `tone`, `beep`, and opening the device.
- `docs/Sound.md` — how the backend works and why it uses the plain device API.
- `help ffi` — the calling mechanism underneath.
