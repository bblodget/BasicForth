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
\ Usage:  snd-open drop   440 200 tone   beep   snd-wait   snd-close
\
\ CHANNELS. The device holds snd-channels streams, and SDL mixes everything
\ bound to it, so sounds on DIFFERENT channels play at the same time. Sounds
\ queued on ONE channel play one after another. Channel 0 (tone-ch) belongs to
\ tone, which is why a run of tones still plays in sequence exactly as it
\ always has -- put a tone on another channel if you want it to overlap.
\
\ next-ch hands out a free channel, or steals the oldest if they are all
\ busy: a game firing more sounds than it has channels loses its stalest sound
\ rather than its newest.
\
\ There are snd-channels of them, 64 by default -- enough that next-ch
\ never has to steal in practice. Shrinking it is the rare case (forcing
\ channel reuse in a test, or trimming streams on a small target), and it is
\ read ONCE, when the device opens, so a change needs an explicit close first
\ -- and the close comes BEFORE the change, so the channels being closed are
\ still the ones that are open:
\
\   snd-close  4 to snd-channels  snd-open drop
\
\ tone queues samples and returns at once (SDL's audio thread drains the
\ queue), so game loops keep running while a sound plays. snd-wait blocks
\ until every channel is empty -- use it before bye in a script.
\
\ With no device open, tone/beep/snd-wait are silent no-ops, so a program runs
\ soundless rather than failing. snd-open returns an IOR -- 0 for success, like
\ allocate and open-file -- which is what lets one word serve both callers:
\
\   snd-open drop                     \ don't care; soundless is fine
\   snd-open abort" no audio device"  \ sound is a requirement
\   snd-open if snd-why type cr then  \ handle it, with SDL's own reason
\
\ It is idempotent: opening an already-open device succeeds and changes
\ nothing. That matters in an on-start hook, which a dirty :e runs twice --
\ and re-opening for real would silence whatever was playing.
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
0 value (SDL_SetAudioStreamGain)     0 value (SDL_SetAudioStreamFormat)
0 value (SDL_GetAudioStreamFormat)   0 value (SDL_GetAudioStreamGain)
0 value (SDL_GetAudioStreamAvailable)

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
    (snd3) s" SDL_ClearAudioStream"        dlsym to (SDL_ClearAudioStream)
    (snd3) s" SDL_SetAudioStreamGain"      dlsym to (SDL_SetAudioStreamGain)
    (snd3) s" SDL_SetAudioStreamFormat"    dlsym to (SDL_SetAudioStreamFormat)
    (snd3) s" SDL_GetAudioStreamFormat"    dlsym to (SDL_GetAudioStreamFormat)
    (snd3) s" SDL_GetAudioStreamGain"      dlsym to (SDL_GetAudioStreamGain)
    (snd3) s" SDL_GetAudioStreamAvailable" dlsym to (SDL_GetAudioStreamAvailable) ;
(snd-bind)

\ --- constants (see tools/sdl3off.c) ---
$10       constant (SDL_INIT_AUDIO)
$8010     constant AUDIO_S16LE         \ SDL_AUDIO_S16LE
$8020     constant AUDIO_S32LE         \ SDL_AUDIO_S32LE
$8120     constant AUDIO_F32LE         \ SDL_AUDIO_F32LE
$0008     constant AUDIO_U8            \ SDL_AUDIO_U8
$ffffffff constant (AUDIO_DEFAULT)      \ SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK
44100     constant snd-rate            \ our side; SDL resamples for the device
256       constant snd-unity           \ ch-vol! value meaning "no scaling"

\ --- state ---
\ The channel tables live in the dictionary rather than the heap: they are
\ small, and a fixed ceiling means snd-close can always clear every slot even
\ when snd-open failed halfway through building them.
64 constant snd-max-channels           \ hard ceiling on snd-channels
64 value   snd-channels                \ set BEFORE snd-open; clamped at open
0  constant tone-ch                    \ channel 0 is reserved for tone

create (ch-streams) snd-max-channels cells allot   \ SDL_AudioStream* per channel
create (ch-ages)    snd-max-channels cells allot   \ tick when last handed out
create (ch-vols)    snd-max-channels cells allot   \ 0..snd-unity
create (ch-fade-t0) snd-max-channels cells allot   \ fade start, ms@
create (ch-owned)   snd-max-channels cells allot   \ claimed by a subsystem
create (ch-fade-ms) snd-max-channels cells allot   \ fade length; 0 = not fading
variable (ch-tick)                                 \ monotonic hand-out counter
variable (ch-next)                                 \ round-robin hand-out cursor

0 value (snd-stream)                     \ channel 0's stream (also owns the device)
0 value (snd-dev)                        \ logical device the channels bind to
\ How TALL the wave tone builds is, as a sample value -- not a volume. The
\ channel gain (ch-vol!, 0..snd-unity) is the volume: it scales any audio on
\ its way out, whoever made it. This is baked into the samples as they are
\ generated, and only tone/beep generate any. Named for tone the way tone-ch
\ is: the amplitude tone uses.
8000 value tone-amp                    \ square-wave amplitude, 0..32767
create (snd-spec) 12 allot             \ SDL_AudioSpec: format l, channels l, freq l

\ C bool comes back in the low 8 bits of the return register; the rest is
\ undefined, so mask before testing.
: (c-bool) ( raw -- flag )  $FF and 0<> ;

: (snd-error) ( -- )  ." snd: " 0 (SDL_GetError) (ccall) ztype cr abort ;

\ --- why the last open failed ---
\ SDL_GetError's string is only good until the next SDL call, and every open
\ failure path runs snd-close (which calls SDL_QuitSubSystem) on its way out.
\ So the message is COPIED here at the moment of failure, before any cleanup;
\ reading it lazily would hand back whatever SDL last had to say instead.
128 constant (snd-why-max)
create (snd-why-buf) (snd-why-max) allot
variable (snd-why-len)
: (snd-why!) ( -- )                    \ snapshot SDL's error, truncating
    0 (snd-why-len) !
    0 (SDL_GetError) (ccall) ?dup 0= if exit then      ( zaddr )
    (snd-why-max) 0 ?do
        dup c@ 0= if unloop drop exit then             \ NUL ends it
        dup c@ (snd-why-buf) i + c!                    ( zaddr )
        1+  i 1+ (snd-why-len) !
    loop drop ;
: snd-why ( -- c-addr u )  (snd-why-buf) (snd-why-len) @ ;

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
        0         i cells (ch-fade-ms)  + !
        0         i cells (ch-fade-t0)  + !
        0         i cells (ch-owned)    + !
    loop  0 (ch-tick) !  0 (ch-next) ! ;
(ch-reset)

\ Volume is SDL's per-stream gain, applied as it PULLS the audio out. So it
\ affects sound already queued, costs nothing at queue time, needs no copy of
\ the caller's samples, and works whatever format the channel is carrying --
\ none of which is true of scaling the samples ourselves on the way in.
: (ch-gain!) ( n ch -- )               \ move the gain WITHOUT recording it,
    (ch-stream) dup 0= if 2drop exit then   \ which is what a fade needs
    swap snd-unity >f32                  ( stream gain-bits )
    1 1 (SDL_SetAudioStreamGain) (ccallf) drop ;

\ The gain SDL is ACTUALLY applying, as f32 bits -- which is not ch-vol@ while
\ a fade is running. Bits rather than a number because Forth has no floats;
\ for positive gains the bit patterns order the same way the values do, so
\ they can be compared directly. Internal: this is how the fade is observed.
: (ch-gain@) ( ch -- f32bits )
    (ch-stream) ?dup 0= if 0 exit then
    1 0 (SDL_GetAudioStreamGain) (ccallf>f) ;

: ch-vol@ ( ch -- n )
    dup (ch-ok?) if cells (ch-vols) + @ else drop snd-unity then ;
: (ch-fading?) ( ch -- flag )
    dup (ch-ok?) if cells (ch-fade-ms) + @ 0<> else drop false then ;

: ch-vol! ( n ch -- )
    dup (ch-ok?) 0= if 2drop exit then
    swap 0 max snd-unity min swap        ( n ch )
    2dup cells (ch-vols) + !             \ remember it for ch-vol@
    \ While a fade is running the gain belongs to the fade, and the next
    \ snd-pump will apply this volume through the ramp. Setting the gain here
    \ as well would jump it to full volume for one frame and then snap back --
    \ an audible blip in the middle of a fade.
    dup (ch-fading?) if 2drop exit then
    (ch-gain!) ;

\ Tell a channel what the samples it is about to be given look like. SDL keeps
\ each queued chunk in the format it was queued WITH, so this can change while
\ audio is still playing: a 16-bit tone and a 48 kHz stereo float sample can
\ sit in the same queue and both come out right. SDL also resamples, so the
\ rate here is the file's rate, not the device's.
\ Whoever queues sets the format -- tone-on does it too, so a channel that
\ last carried a wav does not reinterpret a square wave as something else.
create (ch-spec) 12 allot              \ scratch SDL_AudioSpec for ch-format!
: ch-format! ( format channels rate ch -- )
    (ch-stream) ?dup 0= if 2drop drop exit then    ( fmt chans rate stream )
    >r
    (ch-spec) 8 + l!                   \ freq
    (ch-spec) 4 + l!                   \ channels
    (ch-spec) l!                       \ format
    r> (ch-spec) 0 3 (SDL_SetAudioStreamFormat) (ccall)
    (c-bool) 0= if (snd-error) then ;

\ Read back what a channel is expecting -- the direct way to check that a
\ format actually took, rather than inferring it from how things sound.
: ch-format@ ( ch -- format channels rate )
    (ch-stream) ?dup 0= if 0 0 0 exit then
    (ch-spec) 0 3 (SDL_GetAudioStreamFormat) (ccall) (c-bool) 0= if
        0 0 0 exit
    then
    (ch-spec) l@  (ch-spec) 4 + l@  (ch-spec) 8 + l@ ;

\ A fade lives only as long as the sound it is fading, and moves only the
\ GAIN -- ch-vol@ keeps reporting the volume you chose throughout. So there is
\ nothing to snapshot and restore: ending a fade just puts the gain back to
\ whatever the volume says NOW, which is what makes a ch-vol! made during the
\ fade survive it. (An earlier version saved the volume at ch-fade time and
\ wrote it back, which silently undid any change made while fading.)
: (ch-fade-cancel) ( ch -- )
    dup cells (ch-fade-ms) + @ 0= if drop exit then
    dup 0 swap cells (ch-fade-ms) + !
    dup ch-vol@ swap (ch-gain!) ;

\ GetAudioStreamQueued returns a C int: mask to 32 bits before testing.
: ch-queued ( ch -- n )
    (ch-stream) ?dup 0= if 0 exit then
    1 (SDL_GetAudioStreamQueued) (ccall) $ffffffff and ;

\ Bytes of AUDIO still to come out, as opposed to ch-queued's bytes-you-put-in.
\ The two differ, and the difference matters: a stream that is resampling (any
\ sample whose rate is not the device's) holds a few input bytes back waiting
\ for more input that never arrives, so ch-queued sits at a small non-zero
\ number forever. This one reaches zero.
\ SDL's other answer -- flushing the stream to release those bytes -- would
\ work, but it means declaring end-of-input after every sound, and SDL warns
\ of a gap at the join. That would put a gap between consecutive tones, which
\ is precisely the sequencing tone has always had.
\ The held-back bytes are a fraction of a millisecond and are never heard.
: (ch-avail) ( ch -- n )
    (ch-stream) ?dup 0= if 0 exit then
    1 (SDL_GetAudioStreamAvailable) (ccall) $ffffffff and ;

: ch-playing? ( ch -- flag )  (ch-avail) 0<> ;

: (ch-touch) ( ch -- )                 \ stamp a channel as most recently used
    dup (ch-ok?) 0= if drop exit then
    1 (ch-tick) +!  (ch-tick) @ swap cells (ch-ages) + ! ;

\ --- open / close ---
\ NOTE: this opens the device with SDL_OpenAudioDevice, not the tidier
\ SDL_OpenAudioDeviceStream that a single-stream version would use. A device
\ opened the convenient way is welded to the one stream it returns, and any
\ later bind fails with "Cannot change stream bindings on device opened with
\ SDL_OpenAudioDeviceStream". Mixing requires the plain device API.
\ Walks every slot to snd-max-channels, NOT to snd-channels: snd-channels is a
\ user-writable value, and shrinking it while open hides the tail from its own
\ cleanup. `snd-open drop  4 to snd-channels  snd-close` destroyed 4 streams
\ and left the other 60 handles in the table.
\
\ Not a memory leak -- the SDL_QuitSubSystem below frees every remaining audio
\ object, and 50 such cycles move RSS by nothing. What it leaves is 60
\ DANGLING handles in a table this word promises to empty, and today SDL
\ happens to reject them (ch-queued reads 0 rather than faulting), which is
\ SDL being defensive about freed memory rather than anything we are owed.
\ The table is fixed-size precisely so this loop can always clear it; the
\ bound has to be the table's, not the caller's.
: snd-close ( -- )
    snd-max-channels 0 ?do
        i cells (ch-streams) + dup @ ?dup if
            1 (SDL_DestroyAudioStream) (ccall) drop  0 swap !
        else drop then
    loop
    (snd-dev) ?dup if 1 (SDL_CloseAudioDevice) (ccall) drop then
    0 to (snd-stream)  0 to (snd-dev)
    (SDL_INIT_AUDIO) 1 (SDL_QuitSubSystem) (ccall) drop ;

\ Create every channel's stream and bind it to the device.
\ dst_spec is NULL -- binding to a device sets the output format for us.
: (ch-build) ( -- flag )
    snd-channels 0 ?do
        (snd-spec) 0 2 (SDL_CreateAudioStream) (ccall)
        dup 0= if drop false unloop exit then          ( stream )
        dup (snd-dev) swap 2 (SDL_BindAudioStream) (ccall) (c-bool) 0= if
            1 (SDL_DestroyAudioStream) (ccall) drop  false unloop exit
        then
        i cells (ch-streams) + !
    loop true ;

\ Is a device open right now? The genuine predicate -- snd-open is the verb.
: snd-ready? ( -- flag )  (snd-dev) 0<> ;

\ Every failure path takes this route: snapshot SDL's reason FIRST, then let
\ snd-close undo whatever got as far as being built (including balancing a
\ successful SDL_Init when the device itself never opened).
: (snd-failed) ( -- ior )  (snd-why!) snd-close 1 ;

\ Open the default playback device. 0 on success, non-zero if the system has
\ no working audio -- an ior, so `snd-open drop` runs soundless and
\ `snd-open abort" ..."` insists, with no 0= in either. The magnitude is
\ opaque (test zero/non-zero); snd-why carries the detail.
\
\ Already open is SUCCESS and does nothing. Re-opening for real would clear
\ every queue, reset every volume and pop the device -- so the accidental
\ second call is free, and the deliberate reopen is spelled
\ snd-close snd-open drop.
\
\ Two channels is the floor: next-ch needs at least one channel that is not
\ the tone channel, and below that its steal scan would count backwards.
: snd-open ( -- ior )
    snd-ready? if 0 exit then
    snd-channels 2 max snd-max-channels min to snd-channels
    (ch-reset)
    \ Init failing is the one exit that must NOT run (snd-failed): there is no
    \ subsystem to quit, and nothing was built. Every later failure has both.
    (SDL_INIT_AUDIO) 1 (SDL_Init) (ccall) (c-bool) 0= if (snd-why!) 1 exit then
    AUDIO_S16LE (snd-spec) l!            \ format: signed 16-bit LE
    1           (snd-spec) 4 + l!        \ channels: mono
    snd-rate    (snd-spec) 8 + l!        \ freq
    (AUDIO_DEFAULT) (snd-spec) 2 (SDL_OpenAudioDevice) (ccall) to (snd-dev)
    (snd-dev) 0= if (snd-failed) exit then
    (ch-build) 0= if (snd-failed) exit then
    (ch-streams) @ to (snd-stream)         \ channel 0 = the tone channel
    \ Resume unconditionally: whether a freshly opened device starts paused is
    \ not documented, and resuming an already-playing device is harmless.
    (snd-dev) 1 (SDL_ResumeAudioDevice) (ccall) (c-bool) 0= if (snd-failed) exit then
    0 (snd-why-len) !                      \ success leaves no stale reason
    0 ;

\ --- handing out a channel ---
\ NOTE: nothing is allocated here, in the `allocate` sense -- next-ch hands out
\ one of the fixed channels, and it needs no release: a channel comes back into
\ rotation on its own once it falls silent. (It was called snd-alloc until
\ 2026-08-07, which promised both a heap and a free that never existed.)
\ ch-claim is the exception, and deliberately a separate word: a subsystem that
\ must KEEP a channel says so, and says when it is done.
\
\ A free channel if there is one, otherwise the least recently handed out.
\ Never returns tone-ch, so sound effects cannot cut a game's tones short.
\
\ The search is round-robin rather than lowest-free, because a channel only
\ becomes busy once audio is queued on it: two next-ch calls in a row, before
\ either has been given samples, would otherwise both hand back channel 1 and
\ the second sound would land on top of the first.
: (ch-cycle) ( -- ch )                 \ next channel in 1..snd-channels-1
    (ch-next) @ 1+  dup snd-channels >= if drop 1 then  dup (ch-next) ! ;

\ A CLAIMED channel belongs to a subsystem for as long as it wants it, and
\ next-ch never hands it out. Without this, "keep a channel" is not something a
\ caller can actually do: next-ch skips a channel only while audio is QUEUED on
\ it, so a channel held for later comes back into rotation the moment it falls
\ silent -- and speech.fs, holding one so phrases never queue behind a sound
\ effect, saw its channel reissued 3 times in 200 next-ch calls.
\ snd-close releases every claim, because (ch-reset) clears the table.
: (ch-owned?) ( ch -- flag )
    dup (ch-ok?) if cells (ch-owned) + @ 0<> else drop false then ;
: ch-claim ( ch -- )
    dup (ch-ok?) if 1 swap cells (ch-owned) + ! else drop then ;
: ch-release ( ch -- )
    dup (ch-ok?) if 0 swap cells (ch-owned) + ! else drop then ;

: (ch-spare?) ( ch -- flag )           \ neither claimed nor playing
    dup (ch-owned?) if drop false exit then  ch-playing? 0= ;

: next-ch ( -- ch )
    (snd-stream) 0= if tone-ch exit then
    snd-channels 1- 0 ?do
        (ch-cycle)
        dup (ch-spare?) if  dup (ch-touch) unloop exit  then
        drop
    loop
    \ All busy: steal the least recently handed out that nobody has CLAIMED.
    \ Stealing a claimed one would drop an effect on top of a phrase, which is
    \ the thing claiming it prevents.
    -1                                    ( oldest-so-far, -1 = none yet )
    snd-channels 1 ?do
        i (ch-owned?) 0= if
            dup 0< if  drop i  else
                i cells (ch-ages) + @  over cells (ch-ages) + @  < if drop i then
            then
        then
    loop
    \ Every channel claimed: there is genuinely nothing to hand out. Answer -1,
    \ which is NOT a channel -- every channel word ignores it, so the sound is
    \ dropped. Falling back to tone-ch would be worse than useless: channel 0 is
    \ reserved exactly so effects cannot cut a game's tones short, and handing
    \ it out here would do that on the one path where the caller has no idea
    \ anything is wrong. (With no device open next-ch still answers tone-ch --
    \ harmless there, because every channel word is already a no-op.)
    dup 0< if drop -1 exit then
    dup (ch-touch) ;

: ch-stop ( ch -- )
    dup (ch-ok?) if dup (ch-fade-cancel) then
    (ch-stream) ?dup if 1 (SDL_ClearAudioStream) (ccall) drop then ;

\ Fade to silence over ms, then stop -- the gentle counterpart to ch-stop,
\ which cuts the waveform wherever it happens to be and can click.
\ The fade is driven by snd-pump, so call that once a frame.
: ch-fade ( ms ch -- )
    dup (ch-ok?) 0= if 2drop exit then
    dup (ch-stream) 0= if 2drop exit then
    ms@ over cells (ch-fade-t0) + !
    swap 1 max swap cells (ch-fade-ms) + ! ;

\ Service the channels. Call once a frame: nothing else moves a fade along,
\ because SDL pulls audio on its own thread and a Forth word cannot be a C
\ callback, so the only clock we have is your loop.
: snd-pump ( -- )
    (snd-stream) 0= if exit then
    snd-channels 0 ?do
        i cells (ch-fade-ms) + @ ?dup if           ( dur )
            ms@ i cells (ch-fade-t0) + @ -         ( dur elapsed )
            2dup <= if
                2drop  i ch-stop                   \ also restores the volume
            else
                over swap -                        ( dur remaining )
                i ch-vol@ swap rot */              \ read the volume EACH time so
                i (ch-gain!)                       \ a mid-fade change is honoured
            then
        then
    loop ;

: snd-stop ( -- )  snd-channels 0 ?do i ch-stop loop ;

\ --- queueing ---
: (ch-put-raw) ( c-addr u ch -- )
    (ch-stream) ?dup 0= if 2drop exit then
    -rot 3 (SDL_PutAudioStreamData) (ccall) (c-bool) 0= if (snd-error) then ;

\ Queue raw samples on a channel, in whatever format the channel was told to
\ expect (ch-format!). Sounds queued on the SAME channel play in sequence;
\ different channels mix. Volume is NOT applied here -- SDL applies the
\ channel's gain as it pulls the audio out -- so WE neither scale nor
\ duplicate the caller's samples, and one sample can go to several channels
\ without a copy per channel. SDL does copy them into the stream, though,
\ which is why tone-on frees its buffer on the line after the ch-put.
: ch-put ( c-addr u ch -- )
    dup (ch-stream) 0= if drop 2drop exit then
    \ A new sound is not the one being faded, so the fade is over. This is the
    \ rule that keeps a fade from reaching forward and silencing something
    \ unrelated: without it, a deadline set for a sound that has already ended
    \ still fires, and stops whatever is playing when it does.
    dup (ch-fade-cancel)
    dup (ch-touch)
    \ Deliberately NOT followed by SDL_FlushAudioStream. Flushing would release
    \ the few bytes a resampling stream holds back -- see (ch-avail), which
    \ solves that a different way -- but it declares end-of-input, and SDL
    \ warns of a gap at the join. That would put a gap between consecutive
    \ sounds on one channel, which is exactly the seamless run of tones that
    \ channel 0 exists to preserve.
    (ch-put-raw) ;

\ --- tone synthesis ---
variable (t-n)      \ samples to generate
variable (t-half)   \ samples per half-cycle
variable (t-buf)    \ heap sample buffer (16-bit samples)

: tone-on ( freq ms ch -- )
    dup (ch-stream) 0= if drop 2drop exit then    \ no device: silent no-op
    dup >r  AUDIO_S16LE 1 snd-rate r@ ch-format!  r> drop
    >r
    snd-rate 1000 */ 0 max (t-n) !                \ ms -> sample count
    (t-n) @ 0= if drop r> drop exit then          \ nothing to play
    1 max  snd-rate swap 2* /                     \ freq -> half-cycle length
    1 max (t-half) !
    (t-n) @ 2* allocate abort" tone: out of memory" (t-buf) !
    (t-n) @ 0 ?do
        i (t-half) @ / 1 and if tone-amp negate else tone-amp then
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
    begin dup ch-playing? while 10 ms repeat drop  50 ms ;

: snd-wait ( -- )
    (snd-stream) 0= if exit then
    snd-channels 0 ?do
        begin i ch-playing? while 10 ms repeat
    loop
    50 ms ;
