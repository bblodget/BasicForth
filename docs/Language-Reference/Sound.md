# Sound — Tones via SDL3 Audio

Square-wave tones through the default playback device. Load the backend
first: `require sound.fs` (it pulls in the FFI itself). Tones queue and play
in the background; with no device open, the sound words are silent no-ops.

    require sound.fs
    snd-open
    440 200 tone      \ concert A, 200 ms
    beep
    snd-wait snd-close

At a glance:

    snd-open   ( -- )             open the audio device
    snd-open?  ( -- flag )        is it open?
    tone       ( freq ms -- )     queue a square-wave tone
    beep       ( -- )             a short default blip
    snd-wait   ( -- )             block until the queue drains
    snd-close  ( -- )             close the device
    snd-vol    ( -- a-addr )      volume variable (0..32767)

## snd-open ( -- )
Open the default audio playback device (signed 16-bit mono, 44100 Hz; SDL
resamples for the hardware) and start it. Aborts with the SDL error message
if no device is available.

## snd-open? ( -- flag )
Like `snd-open`, but returns false instead of aborting when the system has
no working audio. A game opens sound with `snd-open? drop` so it runs
soundless (every sound word a no-op) rather than abort:

    : game ( -- )  ... sdl-open  snd-open? drop  ... ;

## tone ( freq ms -- )
Queue a square-wave tone of `freq` Hz for `ms` milliseconds and return
immediately — SDL's audio thread plays it while your code keeps running.
Back-to-back tones play back-to-back. A no-op if the device isn't open.

    : siren ( -- )  5 0 do  600 150 tone  900 150 tone  loop  snd-wait ;

## beep ( -- )
A short blip: `880 60 tone`.

## snd-wait ( -- )
Block until every queued tone has finished playing. Use before `bye` in a
script, or the last tone is cut off.

## snd-close ( -- )
Stop and close the audio device. Sound words become no-ops again.

## snd-vol ( value: 0..32767 )
Square-wave amplitude, default 8000. Set with `to`:

    2000 to snd-vol   \ quiet
    beep

See `docs/Sound.md` for how the backend works, and `help ffi` for the calling
mechanism.
