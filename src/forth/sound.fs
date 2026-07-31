\ BasicForth sound.fs -- SDL3 audio backend (mixing channels, square-wave tones)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Plays audio through the default SDL3 playback device. Pulls in its own
\ dependencies -- just:
\
\   require sound.fs
\
\ Independent of graphics.fs/sdl3.fs -- terminal programs can beep too.
\ Usage:  snd-open   440 200 tone   beep   snd-wait   snd-close
\
\ CHANNELS. The device holds snd-channels streams, and SDL mixes everything
\ bound to it, so sounds on DIFFERENT channels play at the same time. Sounds
\ queued on ONE channel play one after another. Channel 0 (tone-ch) belongs to
\ tone, which is why a run of tones still plays in sequence exactly as it
\ always has -- put a tone on another channel if you want it to overlap.
\
\ snd-alloc hands out a free channel, or steals the oldest if they are all
\ busy: a game firing more sounds than it has channels loses its stalest sound
\ rather than its newest.
\
\ Set snd-channels BEFORE snd-open (it is read once, when the device opens):
\
\   32 to snd-channels  snd-open
\
\ tone queues samples and returns at once (SDL's audio thread drains the
\ queue), so game loops keep running while a sound plays. snd-wait blocks
\ until every channel is empty -- use it before bye in a script.
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
0 value (SDL_OpenAudioDevice)        0 value (SDL_CloseAudioDevice)
0 value (SDL_ResumeAudioDevice)
0 value (SDL_PutAudioStreamData)     0 value (SDL_GetAudioStreamQueued)
0 value (SDL_CreateAudioStream)      0 value (SDL_BindAudioStream)
0 value (SDL_DestroyAudioStream)     0 value (SDL_ClearAudioStream)

: (snd-bind) ( -- )
    s" libSDL3.so.0" dlopen to (snd3)
    (snd3) s" SDL_Init"                    dlsym to (SDL_Init)
    (snd3) s" SDL_QuitSubSystem"           dlsym to (SDL_QuitSubSystem)
    (snd3) s" SDL_GetError"                dlsym to (SDL_GetError)
    (snd3) s" SDL_OpenAudioDevice"         dlsym to (SDL_OpenAudioDevice)
    (snd3) s" SDL_CloseAudioDevice"        dlsym to (SDL_CloseAudioDevice)
    (snd3) s" SDL_ResumeAudioDevice"       dlsym to (SDL_ResumeAudioDevice)
    (snd3) s" SDL_PutAudioStreamData"      dlsym to (SDL_PutAudioStreamData)
    (snd3) s" SDL_GetAudioStreamQueued"    dlsym to (SDL_GetAudioStreamQueued)
    (snd3) s" SDL_CreateAudioStream"       dlsym to (SDL_CreateAudioStream)
    (snd3) s" SDL_BindAudioStream"         dlsym to (SDL_BindAudioStream)
    (snd3) s" SDL_DestroyAudioStream"      dlsym to (SDL_DestroyAudioStream)
    (snd3) s" SDL_ClearAudioStream"        dlsym to (SDL_ClearAudioStream) ;
(snd-bind)

\ --- constants (see tools/sdl3off.c) ---
$10       constant SDL_INIT_AUDIO
$8010     constant AUDIO_S16LE         \ SDL_AUDIO_S16LE
$ffffffff constant AUDIO_DEFAULT      \ SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK
44100     constant snd-rate            \ our side; SDL resamples for the device
256       constant snd-unity           \ ch-vol! value meaning "no scaling"

\ --- state ---
\ The channel tables live in the dictionary rather than the heap: they are
\ small, and a fixed ceiling means snd-close can always clear every slot even
\ when snd-open failed halfway through building them.
64 constant snd-max-channels           \ hard ceiling on snd-channels
16 value   snd-channels                \ set BEFORE snd-open; clamped at open
0  constant tone-ch                    \ channel 0 is reserved for tone

create (ch-streams) snd-max-channels cells allot   \ SDL_AudioStream* per channel
create (ch-ages)    snd-max-channels cells allot   \ tick when last allocated
create (ch-vols)    snd-max-channels cells allot   \ 0..snd-unity
variable (ch-tick)                                 \ monotonic allocation counter
variable (ch-next)                                 \ round-robin allocation cursor

0 value snd-stream                     \ channel 0's stream (also owns the device)
0 value snd-dev                        \ logical device the channels bind to
8000 value snd-vol                     \ square-wave amplitude, 0..32767
create (snd-spec) 12 allot             \ SDL_AudioSpec: format l, channels l, freq l

\ C bool comes back in the low 8 bits of the return register; the rest is
\ undefined, so mask before testing.
: (c-bool) ( raw -- flag )  $FF and 0<> ;

: snd-error ( -- )  ." snd: " 0 (SDL_GetError) (ccall) ztype cr abort ;

\ --- channel tables ---
: (ch-ok?) ( ch -- flag )  0 snd-channels within ;
: (ch-stream) ( ch -- stream )
    dup (ch-ok?) if cells (ch-streams) + @ else drop 0 then ;

\ Zeroed at load, not only at open: snd-close walks every slot, and it runs on
\ the failure paths of snd-open before the tables have been filled in.
: (ch-reset) ( -- )
    snd-max-channels 0 ?do
        0         i cells (ch-streams) + !
        0         i cells (ch-ages)    + !
        snd-unity i cells (ch-vols)    + !
    loop  0 (ch-tick) !  0 (ch-next) ! ;
(ch-reset)

: ch-vol@ ( ch -- n )
    dup (ch-ok?) if cells (ch-vols) + @ else drop snd-unity then ;
: ch-vol! ( n ch -- )
    dup (ch-ok?) 0= if 2drop exit then
    swap 0 max snd-unity min swap cells (ch-vols) + ! ;

\ GetAudioStreamQueued returns a C int: mask to 32 bits before testing.
: ch-queued ( ch -- n )
    (ch-stream) ?dup 0= if 0 exit then
    1 (SDL_GetAudioStreamQueued) (ccall) $ffffffff and ;

: ch-playing? ( ch -- flag )  ch-queued 0<> ;

: (ch-touch) ( ch -- )                 \ stamp a channel as most recently used
    dup (ch-ok?) 0= if drop exit then
    1 (ch-tick) +!  (ch-tick) @ swap cells (ch-ages) + ! ;

\ --- open / close ---
\ NOTE: this opens the device with SDL_OpenAudioDevice, not the tidier
\ SDL_OpenAudioDeviceStream that a single-stream version would use. A device
\ opened the convenient way is welded to the one stream it returns, and any
\ later bind fails with "Cannot change stream bindings on device opened with
\ SDL_OpenAudioDeviceStream". Mixing requires the plain device API.
: snd-close ( -- )
    snd-channels 0 ?do
        i cells (ch-streams) + dup @ ?dup if
            1 (SDL_DestroyAudioStream) (ccall) drop  0 swap !
        else drop then
    loop
    snd-dev ?dup if 1 (SDL_CloseAudioDevice) (ccall) drop then
    0 to snd-stream  0 to snd-dev
    SDL_INIT_AUDIO 1 (SDL_QuitSubSystem) (ccall) drop ;

\ Create every channel's stream and bind it to the device.
\ dst_spec is NULL -- binding to a device sets the output format for us.
: (ch-build) ( -- flag )
    snd-channels 0 ?do
        (snd-spec) 0 2 (SDL_CreateAudioStream) (ccall)
        dup 0= if drop false unloop exit then          ( stream )
        dup snd-dev swap 2 (SDL_BindAudioStream) (ccall) (c-bool) 0= if
            1 (SDL_DestroyAudioStream) (ccall) drop  false unloop exit
        then
        i cells (ch-streams) + !
    loop true ;

\ Try to open the default playback device; false (and no device, so the
\ other words stay no-ops) if the system has no working audio. Games use
\ this so they run soundless rather than abort.
\ Two channels is the floor: snd-alloc needs at least one channel that is not
\ the tone channel, and below that its steal scan would count backwards.
: snd-open? ( -- flag )
    snd-channels 2 max snd-max-channels min to snd-channels
    (ch-reset)
    SDL_INIT_AUDIO 1 (SDL_Init) (ccall) (c-bool) 0= if false exit then
    AUDIO_S16LE (snd-spec) l!            \ format: signed 16-bit LE
    1           (snd-spec) 4 + l!        \ channels: mono
    snd-rate    (snd-spec) 8 + l!        \ freq
    AUDIO_DEFAULT (snd-spec) 2 (SDL_OpenAudioDevice) (ccall) to snd-dev
    snd-dev 0= if snd-close false exit then
    (ch-build) 0= if snd-close false exit then
    (ch-streams) @ to snd-stream         \ channel 0 = the tone channel
    \ Resume unconditionally: whether a freshly opened device starts paused is
    \ not documented, and resuming an already-playing device is harmless.
    snd-dev 1 (SDL_ResumeAudioDevice) (ccall) (c-bool) 0= if snd-close false exit then
    true ;

: snd-open ( -- )  snd-open? 0= if snd-error then ;

\ --- channel allocation ---
\ A free channel if there is one, otherwise the least recently allocated.
\ Never returns tone-ch, so sound effects cannot cut a game's tones short.
\
\ The search is round-robin rather than lowest-free, because a channel only
\ becomes busy once audio is queued on it: two snd-alloc calls in a row, before
\ either has been given samples, would otherwise both hand back channel 1 and
\ the second sound would land on top of the first.
: (ch-cycle) ( -- ch )                 \ next channel in 1..snd-channels-1
    (ch-next) @ 1+  dup snd-channels >= if drop 1 then  dup (ch-next) ! ;

: snd-alloc ( -- ch )
    snd-stream 0= if tone-ch exit then
    snd-channels 1- 0 ?do
        (ch-cycle)
        dup ch-playing? 0= if  dup (ch-touch) unloop exit  then
        drop
    loop
    1                                     ( oldest-so-far )
    snd-channels 2 ?do
        i cells (ch-ages) + @  over cells (ch-ages) + @  < if drop i then
    loop
    dup (ch-touch) ;

: ch-stop ( ch -- )
    (ch-stream) ?dup if 1 (SDL_ClearAudioStream) (ccall) drop then ;

: snd-stop ( -- )  snd-channels 0 ?do i ch-stop loop ;

\ --- queueing ---
: (ch-put-raw) ( c-addr u ch -- )
    (ch-stream) ?dup 0= if 2drop exit then
    -rot 3 (SDL_PutAudioStreamData) (ccall) (c-bool) 0= if snd-error then ;

\ Below unity we scale into a COPY: the caller's sample data may be a loaded
\ sound playing on several channels at once, so it must not be touched.
variable (p-buf)  variable (p-vol)  variable (p-src)  variable (p-len)
: (ch-scaled) ( c-addr u ch -- c-addr' u' )
    ch-vol@ (p-vol) !  (p-len) !  (p-src) !
    (p-len) @ allocate abort" snd: out of memory" (p-buf) !
    (p-len) @ 2/ 0 ?do
        (p-src) @ i 2* + w@              \ w@ zero-extends; sign-extend by hand
        dup 32767 > if 65536 - then
        (p-vol) @ snd-unity */
        (p-buf) @ i 2* + w!
    loop
    (p-buf) @ (p-len) @ ;

\ Queue raw 16-bit mono samples on a channel. Sounds queued on the SAME
\ channel play in sequence; different channels mix.
: ch-put ( c-addr u ch -- )
    dup (ch-stream) 0= if drop 2drop exit then
    dup (ch-touch)
    dup ch-vol@ snd-unity = if  (ch-put-raw) exit  then
    dup >r (ch-scaled) r> (ch-put-raw)
    (p-buf) @ free drop ;

\ --- tone synthesis ---
variable (t-n)      \ samples to generate
variable (t-half)   \ samples per half-cycle
variable (t-buf)    \ heap sample buffer (16-bit samples)

: tone-on ( freq ms ch -- )
    dup (ch-stream) 0= if drop 2drop exit then    \ no device: silent no-op
    >r
    snd-rate 1000 */ 0 max (t-n) !                \ ms -> sample count
    (t-n) @ 0= if drop r> drop exit then          \ nothing to play
    1 max  snd-rate swap 2* /                     \ freq -> half-cycle length
    1 max (t-half) !
    (t-n) @ 2* allocate abort" tone: out of memory" (t-buf) !
    (t-n) @ 0 ?do
        i (t-half) @ / 1 and if snd-vol negate else snd-vol then
        (t-buf) @ i 2* + w!
    loop
    (t-buf) @ (t-n) @ 2* r> ch-put
    (t-buf) @ free drop ;

: tone ( freq ms -- )  tone-ch tone-on ;

: beep ( -- )  880 60 tone ;

\ --- drain ---
\ The device buffer holds a last chunk after the queue empties, so linger
\ a moment to let it play out.
: ch-wait ( ch -- )
    begin dup ch-queued while 10 ms repeat drop  50 ms ;

: snd-wait ( -- )
    snd-stream 0= if exit then
    snd-channels 0 ?do
        begin i ch-queued while 10 ms repeat
    loop
    50 ms ;
