\ BasicForth speech.fs -- saying text out loud, synthesized into memory
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Speaks arbitrary text through flite, with no file anywhere:
\
\   require speech.fs
\   snd-open drop  speech-open drop
\   s" hello, commander" say
\   speech-ch ch-wait
\
\ flite synthesizes into memory and the samples go straight onto a channel,
\ so there is nothing to render, nothing to load, and nothing on disk.
\
\ SAY BLOCKS WHILE IT SYNTHESIZES, and that is the whole reason voice.fs
\ exists alongside it. Measured here, cmu_us_slt: "Go!" 7 ms, "Dark Star,
\ ready." 16 ms, a full sentence 38 ms. A 60 Hz frame is 16.7 ms. So say is
\ for the prompt, for menus, and for the pause between levels -- inside a
\ frame loop it drops frames, and a game wants voice.fs's pre-rendered WAVs
\ (help voice). The audio itself plays in the background either way; it is
\ only the synthesis that costs.
\
\ QUALITY. flite is a small formant-ish synthesizer from 2001, and it sounds
\ like one. That is the trade for synthesizing 90x faster than real time in
\ half a megabyte: voice.fs drives a modern neural engine and sounds far
\ better, but takes hundreds of milliseconds and has to write a file. Live
\ and arbitrary here; recorded and good there.
\
\ THE VOICE IS NOT BAKED IN. speech-voice! takes a library and the symbol
\ that registers it, because the two do not follow one pattern -- the indic
\ and grapheme voices are not named cmu_us_<something>, so deriving the
\ symbol from a short name would break for exactly the voices someone would
\ go looking for.
\
\   s" libflite_cmu_us_rms.so.1" s" register_cmu_us_rms" speech-voice!
\
\ The .so.1 matters: a machine with the runtime package has libflite.so.1 and
\ no libflite.so, since the bare name belongs to the -dev package. Naming the
\ soname is what makes this work on a plain install.

require sound.fs

\ --- configuration ---------------------------------------------------------

128 constant (sp-name-max)
create (sp-lib)  (sp-name-max) allot        \ voice library soname
variable (sp-lib#)
create (sp-sym)  (sp-name-max) allot        \ its register_* symbol
variable (sp-sym#)

\ Both names are copied here rather than borrowed: a caller's s" string sits in
\ a transient buffer that the next s" reuses, so keeping the address would work
\ until the second phrase and then not.
: speech-voice! ( lib u sym u -- )
    dup (sp-name-max) > if 2drop 2drop exit then
    dup (sp-sym#) !  (sp-sym) swap cmove
    dup (sp-name-max) > if 2drop exit then
    dup (sp-lib#) !  (sp-lib) swap cmove ;

s" libflite_cmu_us_slt.so.1" (sp-lib) swap dup (sp-lib#) ! cmove
s" register_cmu_us_slt"      (sp-sym) swap dup (sp-sym#) ! cmove

\ --- why ------------------------------------------------------------------

128 constant (sp-why-max)
create (sp-why-buf) (sp-why-max) allot
variable (sp-why-len)
: (sp-why$) ( c-addr u -- )  (sp-why-max) min  dup (sp-why-len) !  (sp-why-buf) swap cmove ;
: speech-why ( -- c-addr u )  (sp-why-buf) (sp-why-len) @ ;

\ --- binding --------------------------------------------------------------

0 value (flite)                              \ libflite.so.1 handle
0 value (fl-text2wave)
0 value (fl-delete)
0 value (fl-voice)                           \ cst_voice* from register_*
-1 value speech-ch                           \ our own channel, -1 = not open
\ Ready means the voice is bound and we still hold a live channel. Speech's
\ claim outlives a snd-close -- claims belong to whoever took them, not to the
\ device -- so the channel is still ours after the device comes back, and only
\ the stream needs checking to know there is a device at all.
: speech-ready? ( -- flag )
    (fl-voice) 0= if false exit then
    speech-ch 0< if false exit then
    speech-ch (ch-stream) 0<> ;

\ The cst_wave flite hands back. Verified by calling it rather than read off a
\ header: type*@0, sample_rate@8 (int), num_samples@12 (int), num_channels@16
\ (int), samples*@24 -- so the two counts are 32-bit fields sharing a cell.
: (wave-rate)   ( w -- n )  8 +  l@ ;
: (wave-count)  ( w -- n )  12 + l@ ;
: (wave-chans)  ( w -- n )  16 + l@ ;
: (wave-data)   ( w -- a )  24 + @ ;

\ (dlopen)/(dlsym) rather than dlopen/dlsym: the parenthesised pair returns 0
\ instead of aborting, which is what lets this whole word promise an ior. Each
\ takes a NUL-terminated address, so every name goes through >z first -- and >z
\ shares one scratch buffer, so each result is consumed before the next call.
: (sp-bind) ( -- ior )
    s" libflite.so.1" >z (dlopen) dup to (flite)  0= if
        s" no libflite.so.1 on this machine" (sp-why$) 1 exit then
    (flite) s" flite_init" >z (dlsym) ?dup 0= if
        s" libflite has no flite_init" (sp-why$) 2 exit then
    0 swap (ccall) drop
    (flite) s" flite_text_to_wave" >z (dlsym) dup to (fl-text2wave) 0= if
        s" libflite has no flite_text_to_wave" (sp-why$) 2 exit then
    (flite) s" delete_wave" >z (dlsym) dup to (fl-delete) 0= if
        s" libflite has no delete_wave" (sp-why$) 2 exit then
    \ The voice lives in its own library and registers itself on demand.
    (sp-lib) (sp-lib#) @ >z (dlopen) ?dup 0= if
        s" no such voice library" (sp-why$) 3 exit then
    ( vlib )  dup (sp-sym) (sp-sym#) @ >z (dlsym) ?dup 0= if
        drop s" voice library has no register symbol" (sp-why$) 4 exit then
    nip                                      ( register-fn )
    0 swap 1 swap (ccall) dup to (fl-voice) 0= if
        s" the voice would not register" (sp-why$) 5 exit then
    0 ;

\ The device check comes FIRST. Testing idempotence first would report success
\ after snd-close, when there is no device to speak through at all.
: speech-open ( -- ior )
    0 (sp-why-len) !
    snd-ready? 0= if
        s" no audio device (snd-open first)" (sp-why$) 6 exit then
    speech-ready? if 0 exit then             \ idempotent, like snd-open
    \ flite stays bound across a snd-close: the library is loaded and the voice
    \ registered, and neither has anything to do with the audio device. Only
    \ the channel has to be taken again.
    (fl-voice) 0= if (sp-bind) ?dup if exit then then
    \ Our own channel: a channel is a sequential queue, so successive says wait
    \ for each other instead of talking over themselves, and speech never
    \ queues up behind a sound effect.
    \ next-ch answers -1 when there is nothing to give, and ch-claim rejects it.
    next-ch ch-claim 0= if
        drop s" no free channel to speak on" (sp-why$) 7 exit then
    to speech-ch
    \ next-ch hands back the least recently used channel WITHOUT clearing it
    \ when everything is busy, so it can arrive with someone else's effect
    \ still queued and the first phrase would play behind it. Taking the
    \ channel means taking it over.
    speech-ch ch-stop
    0 ;

\ Give the channel back. flite stays bound: reopening then only has to take a
\ channel again, and re-registering a voice buys nothing (there is no dlclose
\ here either). Closing speech is about the channel.
\
\ It stops mid-phrase rather than letting one finish. Releasing a channel with
\ audio still on it puts the next caller's sound behind the tail of a phrase --
\ say speech-ch ch-wait first if you want it played out.
: speech-close ( -- )
    speech-ch 0< if exit then                \ idempotent, like snd-close
    speech-ch ch-stop
    speech-ch ch-release
    -1 to speech-ch ;

\ --- speaking -------------------------------------------------------------

\ >z copies into one shared 256-byte scratch buffer and aborts past it. Check
\ here instead, so an over-long phrase reports something about the phrase
\ rather than about a buffer the caller never mentioned.
240 constant say-max

: say ( c-addr u -- )
    speech-ready? 0= if 2drop exit then      \ silent no-op, like tone
    dup say-max > if
        2drop s" phrase too long to say" (sp-why$) exit then
    0 (sp-why-len) !
    >z (fl-voice) 2 (fl-text2wave) (ccall)   ( w )
    ?dup 0= if s" the engine produced nothing" (sp-why$) exit then
    dup (wave-count) 0= if
        dup 1 (fl-delete) (ccall) drop
        drop s" the engine produced no audio" (sp-why$) exit then
    >r                                       \ the wave lives on the return
                                             \ stack only -- keeping a data
                                             \ copy too leaves it behind
    AUDIO_S16LE  r@ (wave-chans)  r@ (wave-rate)  speech-ch ch-format!
    r@ (wave-data)  r@ (wave-count) 2*  speech-ch ch-put
    \ Free immediately: ch-put hands the bytes to SDL, which copies them.
    r> 1 (fl-delete) (ccall) drop ;

: talking? ( -- flag )
    speech-ch 0< if false exit then  speech-ch ch-playing? ;
