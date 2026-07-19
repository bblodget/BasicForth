\ BasicForth sound.fs -- SDL3 audio backend (square-wave tones)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Plays integer square-wave tones through SDL3's default playback device.
\ Pulls in its own dependencies -- just:
\
\   require sound.fs
\
\ Independent of graphics.fs/sdl3.fs -- terminal programs can beep too.
\ Usage:  snd-open   440 200 tone   beep   snd-wait   snd-close
\
\ tone queues samples and returns at once (SDL's audio thread drains the
\ queue), so game loops keep running while a sound plays. snd-wait blocks
\ until the queue is empty -- use it before bye in a script.
\
\ With no device open, tone/beep/snd-wait are silent no-ops. snd-open aborts
\ if audio is unavailable; games use  snd-open? drop  instead, so they run
\ soundless on a system with no audio rather than abort.
\
\ Constants and struct offsets verified against the SDL3 headers by
\ tools/sdl3off.c (SDL 3.4.12).

require ffi.fs

\ --- library ---
\ sdl3.fs binds some of these names too; the rebindings are identical, so
\ the shadowing is harmless whichever loads second.
0 value (snd3)
0 value (SDL_Init)                   0 value (SDL_QuitSubSystem)
0 value (SDL_GetError)
0 value (SDL_OpenAudioDeviceStream)  0 value (SDL_DestroyAudioStream)
0 value (SDL_ResumeAudioStreamDevice)
0 value (SDL_PutAudioStreamData)     0 value (SDL_GetAudioStreamQueued)

: (snd-bind) ( -- )
    s" libSDL3.so.0" dlopen to (snd3)
    (snd3) s" SDL_Init"                    dlsym to (SDL_Init)
    (snd3) s" SDL_QuitSubSystem"           dlsym to (SDL_QuitSubSystem)
    (snd3) s" SDL_GetError"                dlsym to (SDL_GetError)
    (snd3) s" SDL_OpenAudioDeviceStream"   dlsym to (SDL_OpenAudioDeviceStream)
    (snd3) s" SDL_DestroyAudioStream"      dlsym to (SDL_DestroyAudioStream)
    (snd3) s" SDL_ResumeAudioStreamDevice" dlsym to (SDL_ResumeAudioStreamDevice)
    (snd3) s" SDL_PutAudioStreamData"      dlsym to (SDL_PutAudioStreamData)
    (snd3) s" SDL_GetAudioStreamQueued"    dlsym to (SDL_GetAudioStreamQueued) ;
(snd-bind)

\ --- constants (see tools/sdl3off.c) ---
$10       constant SDL_INIT_AUDIO
$8010     constant AUDIO_S16LE         \ SDL_AUDIO_S16LE
$ffffffff constant AUDIO_DEFAULT      \ SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK
44100     constant snd-rate            \ our side; SDL resamples for the device

\ --- state ---
0 value snd-stream
8000 value snd-vol                     \ square-wave amplitude, 0..32767
create (snd-spec) 12 allot             \ SDL_AudioSpec: format l, channels l, freq l

\ C bool comes back in the low 8 bits of the return register; the rest is
\ undefined, so mask before testing.
: (c-bool) ( raw -- flag )  $FF and 0<> ;

: snd-error ( -- )  ." snd: " 0 (SDL_GetError) (ccall) ztype cr abort ;

\ --- open / close ---
: snd-close ( -- )
    snd-stream ?dup if
        1 (SDL_DestroyAudioStream) (ccall) drop   \ also closes the device
        0 to snd-stream
    then
    SDL_INIT_AUDIO 1 (SDL_QuitSubSystem) (ccall) drop ;

\ Try to open the default playback device; false (and no device, so the
\ other words stay no-ops) if the system has no working audio. Games use
\ this so they run soundless rather than abort.
: snd-open? ( -- flag )
    SDL_INIT_AUDIO 1 (SDL_Init) (ccall) (c-bool) 0= if false exit then
    AUDIO_S16LE (snd-spec) l!            \ format: signed 16-bit LE
    1           (snd-spec) 4 + l!        \ channels: mono
    snd-rate    (snd-spec) 8 + l!        \ freq
    AUDIO_DEFAULT (snd-spec) 0 0         \ devid spec callback userdata
    4 (SDL_OpenAudioDeviceStream) (ccall)
    dup 0= if drop snd-close false exit then  to snd-stream
    snd-stream 1 (SDL_ResumeAudioStreamDevice) (ccall)   \ streams open paused
    (c-bool)  dup 0= if snd-close then ;

: snd-open ( -- )  snd-open? 0= if snd-error then ;

\ --- tone synthesis ---
variable (t-n)      \ samples to generate
variable (t-half)   \ samples per half-cycle
variable (t-buf)    \ heap sample buffer (16-bit samples)

: tone ( freq ms -- )
    snd-stream 0= if 2drop exit then     \ no device: silent no-op
    snd-rate 1000 */ 0 max (t-n) !       \ ms -> sample count
    (t-n) @ 0= if drop exit then         \ nothing to play (0 allocate fails)
    1 max  snd-rate swap 2* /            \ freq -> half-cycle length
    1 max (t-half) !
    (t-n) @ 2* allocate abort" tone: out of memory" (t-buf) !
    (t-n) @ 0 ?do
        i (t-half) @ / 1 and if snd-vol negate else snd-vol then
        (t-buf) @ i 2* + w!
    loop
    snd-stream (t-buf) @ (t-n) @ 2*
    3 (SDL_PutAudioStreamData) (ccall) (c-bool)
    (t-buf) @ free drop
    0= if snd-error then ;

: beep ( -- )  880 60 tone ;

\ --- drain ---
\ GetAudioStreamQueued returns a C int: mask to 32 bits before testing.
\ The device buffer holds a last chunk after the queue empties, so linger
\ a moment to let it play out.
: snd-wait ( -- )
    snd-stream 0= if exit then
    begin  snd-stream 1 (SDL_GetAudioStreamQueued) (ccall) $ffffffff and
    while  10 ms  repeat
    50 ms ;
