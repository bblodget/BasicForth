# Sound — Tones via SDL3 Audio

Square-wave tones through the default playback device. Load the backend
first: `require sound.fs` (it pulls in the FFI itself). Tones queue and play
in the background; with no device open, the sound words are silent no-ops.

    require sound.fs
    snd-open drop
    440 200 tone      \ concert A, 200 ms
    beep
    snd-wait snd-close

At a glance:

    snd-open   ( -- ior )         open the audio device; 0 = success
    snd-ready? ( -- flag )        is a device open right now?
    snd-why    ( -- c-addr u )    why the last snd-open failed
    tone       ( freq ms -- )     queue a square-wave tone
    beep       ( -- )             a short default blip
    snd-wait   ( -- )             block until every channel drains
    ch-wait    ( ch -- )          block until one channel drains
    snd-close  ( -- )             close the device
    tone-amp   ( -- n )           tone amplitude, 0..32767 (set with to)

Sounds queued here play one after another. To play sounds **at the same
time**, put them on different channels — see `help channels`.

## snd-open ( -- ior )
Open the default audio playback device (signed 16-bit mono, 44100 Hz; SDL
resamples for the hardware) and start it. Returns **0 on success**, non-zero
if the system has no working audio — an `ior`, like `allocate` and
`open-file`. The magnitude is opaque; test zero/non-zero and ask `snd-why`
for the reason.

One word serves both kinds of caller, with no `0=` in either:

    snd-open drop                     \ don't care; soundless is fine
    snd-open abort" no audio device"  \ sound is a requirement
    snd-open if snd-why type cr then  \ handle it, with SDL's own reason

Opening an **already-open device succeeds and does nothing**. That keeps a
redundant call free — an `on-start` hook runs twice after a dirty `:e` — and
a real re-open would clear every queue, reset every volume and pop the
device. To genuinely reopen (the only reason being a changed
`snd-channels`), say so: `snd-close snd-open drop`.

## snd-ready? ( -- flag )
True if a device is open. `snd-open` is the verb; this is the question.

## snd-why ( -- c-addr u )
SDL's reason for the last failed `snd-open`, empty after a successful one.
The string is copied at the moment of failure, so it survives the cleanup
that follows.

    snd-open if  ." no sound: " snd-why type cr  then

## tone ( freq ms -- )
Queue a square-wave tone of `freq` Hz for `ms` milliseconds and return
immediately — SDL's audio thread plays it while your code keeps running.
Back-to-back tones play back-to-back, because `tone` always uses the same
channel (`tone-ch`). Use `tone-on` for a tone that overlaps other sounds. A
no-op if the device isn't open.

    : siren ( -- )  5 0 do  600 150 tone  900 150 tone  loop  snd-wait ;

## beep ( -- )
A short blip: `880 60 tone`.

## snd-wait ( -- )
Block until every channel has finished playing. Use before `bye` in a
script, or the last tone is cut off.

To wait on **one channel** while the others keep playing, use
`ch-wait ( ch -- )` — `help channels`. It drains that channel, so several
sounds queued there hold it until the last one ends.

## snd-close ( -- )
Stop and close the audio device. Sound words become no-ops again.

## snd-rate ( -- n )
The sample rate `tone` generates at, 44100. SDL converts to whatever the
hardware wants, so this is our side of the conversation, not the device's.
It is also the rate `tone-on` declares on a channel, which is why a tone after
a wav sounds right rather than inheriting the file's rate.

## tone-amp ( -- n )
How **tall** the square wave `tone` builds is — a sample value, default 8000,
against the 32767 a 16-bit sample could hold. A `value`, so it reads without
`@` and is set with `to`:

    2000 to tone-amp   \ quiet
    beep

Named for `tone` the way `tone-ch` is, and deliberately not called a volume.
`ch-vol!` (`help channels`) is the volume: it scales *any* audio on its way
out, whoever made it, 0..`snd-unity`. `tone-amp` is baked into the samples as
they are generated, and only `tone` and `beep` generate any.

See `help channels` for playing several sounds at once, `docs/Sound.md` for
how the backend works, and `help ffi` for the calling mechanism.
