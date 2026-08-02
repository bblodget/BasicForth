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
    ch-stop          ( ch -- )         drop whatever is queued
    snd-stop         ( -- )            stop every channel
    ch-wait          ( ch -- )         block until this channel drains
    ch-vol!          ( n ch -- )       channel volume, 0..snd-unity
    ch-vol@          ( ch -- n )       read it back
    snd-unity        ( -- 256 )        the ch-vol! value meaning "unchanged"

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

Below `snd-unity` the channel's volume is applied by scaling into a copy, so
your sample data is never modified; the same sound can play on several
channels at once.

## ch-playing? ( ch -- flag )
True while the channel still has audio queued.

    begin  1 ch-playing?  while  ... do other work ...  repeat

## ch-queued ( ch -- n )
Bytes still waiting to play on this channel. Two bytes per sample at
`snd-rate` samples per second. 0 for a channel that doesn't exist.

## ch-stop ( ch -- )
Drop everything queued on the channel; it falls silent at once. Stopping a
sound mid-waveform can click — that is the cost of an immediate stop.

## snd-stop ( -- )
`ch-stop` every channel, `tone-ch` included. Silence now, device still open.

## ch-wait ( ch -- )
Block until this one channel has finished. `snd-wait` waits for all of them.

## ch-vol! ( n ch -- )
Set a channel's volume, `0` (silent) to `snd-unity` (unchanged). Clamped, and
ignored for a channel that doesn't exist.

Volume is applied **as samples are queued**, so it affects what you play
next — it does not change audio already queued.

    64 3 ch-vol!            \ quarter volume on channel 3

## ch-vol@ ( ch -- n )
Read a channel's volume back. `snd-unity` for a channel that doesn't exist.

## snd-unity ( -- 256 )
The `ch-vol!` value that means "play at the sample's own level". Volume is a
fraction of this, so `128` is half and `0` is silent.

## Notes

Every one of these is a silent no-op with no device open, so a program runs
unchanged on a machine with no working audio (`snd-open? drop`).

## See Also

- `help sound` — `tone`, `beep`, and opening the device.
- `docs/Sound.md` — how the backend works and why it uses the plain device API.
- `help ffi` — the calling mechanism underneath.
