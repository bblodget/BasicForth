# Playing — Sounds From WAV Files

`wav.fs` joins the two halves: `wavcore.fs` turns a `.wav` file into a sample,
`sound.fs` owns the device and its mixing channels, and this plays one on the
other.

    require wav.fs
    snd-open drop
    s" blip.wav" wav-load value blip
    blip wav-play drop
    snd-wait  snd-close

Load once, play many times. The same sample can be sounding on several
channels at once, and none of these words copies or alters it — SDL takes its
own copy of the bytes as they are queued.

At a glance:

    wav-play     ( sample -- ch )    play on a channel of its own choosing
    wav-play-on  ( sample ch -- )    play on a channel you pick
    wav-ms       ( sample -- n )     how long it runs, in milliseconds

## wav-play ( sample -- ch )
Play a sample and return the channel it landed on, so you can stop or fade it
later. Picks a free channel, or steals the least recently used one.

    blip wav-play drop                  \ fire and forget
    music wav-play value music-ch       \ keep it, to fade later

A sample that failed to load gives `-1`, which every channel word treats as no
channel — so an unchecked `wav-load` degrades to silence rather than playing on
channel 0 by accident.

## wav-play-on ( sample ch -- )
Play on a channel you choose. Whatever is already queued there plays first, so
a channel is a little playlist: queue three footsteps on one channel and they
follow each other, or put them on three channels and they overlap.

    step 1 wav-play-on
    step 1 wav-play-on          \ plays after the first

## wav-ms ( sample -- n )
How long the sample runs, in milliseconds — `frames / rate`. Useful for
scheduling something to happen when it ends, without polling `ch-playing?`.

    blip wav-ms ms              \ wait exactly as long as it plays

## How a sample reaches the speakers

`wav-play` tells the channel the sample's own format and rate
(`ch-format!`), then hands the bytes over untouched. SDL converts and
resamples on its way to the hardware, so a 48 kHz stereo file and a 16 kHz
mono one can be playing in the same moment.

Nothing is converted at load either, with one exception: **24-bit** audio,
which SDL has no format for, is widened to 32-bit when the file is read. That
is lossless — see `help samples`.

Volume and fading belong to the channel, not the sample, so they work the same
whether the sound came from a file or from `tone`:

    64 music-ch ch-vol!         \ quarter volume, takes effect immediately
    3000 music-ch ch-fade       \ three-second fade, needs snd-pump

## Set the volume before you queue

To play a sound at a particular level, take the channel first, set it, and
then play:

    next-ch value ch
    64 ch ch-vol!
    blip ch wav-play-on

Doing it the other way round — `blip wav-play value ch` then `64 ch ch-vol!` —
is a race. SDL's audio thread pulls audio on its own schedule, and it can take
the first chunk before the new gain is applied, so the sound starts at
whatever level the channel was already at and drops a moment later.

`wav-play` cannot help with this, because it does not hand back the channel
until after the audio is queued. It is the right word when the channel's
current volume is the one you want.

## See Also

- `help samples` — loading files and asking what is in them.
- `help channels` — channels, volume, fading, and `snd-pump`.
- `help sound` — opening the device, and tones.
