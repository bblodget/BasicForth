\ BasicForth wav.fs -- play loaded WAV samples on mixing channels
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Joins the two halves: wavcore.fs turns a .wav file into a sample, sound.fs
\ owns the device and the channels, and this plays one on the other.
\
\   require wav.fs
\   snd-open drop
\   s" blip.wav" wav-load value blip
\   blip wav-play drop            \ on a channel of its own choosing
\   snd-wait  snd-close
\
\ A sound plays on a channel; sounds on different channels play together. The
\ sample's own rate and format are handed to the channel, so a 48 kHz stereo
\ file and a 16 kHz mono one can be playing at the same moment -- SDL converts
\ each to whatever the hardware wants.
\
\ Loading is separate from playing on purpose: load once, play many times.
\ The same sample can be playing on several channels at once: none of these
\ words copies or alters it, and SDL takes its own copy of the bytes as they
\ are queued.

require wavcore.fs
require sound.fs

\ Which SDL format the sample's bytes already are. 8, 16 and 32-bit go to the
\ device untouched; 24-bit never reaches here, because wavcore widens it to
\ 32-bit at load (SDL has no 24-bit format at all).
: (wav-fmt) ( sample -- format )
    dup wav-float? if drop AUDIO_F32LE exit then
    wav-bits
    dup 8  = if drop AUDIO_U8    exit then
    dup 32 = if drop AUDIO_S32LE exit then
    drop AUDIO_S16LE ;

\ Play a sample on a channel you choose, telling the channel what is coming.
\ Whatever was already queued there plays first.
: wav-play-on ( sample ch -- )
    over 0= if 2drop exit then
    over (wav-fmt)                  ( sample ch format )
    2 pick wav-chans                ( sample ch format channels )
    3 pick wav-rate                 ( sample ch format channels rate )
    3 pick ch-format!               ( sample ch )
    swap dup wav-data swap wav-bytes rot ch-put ;

\ Play on a channel of the system's choosing -- a free one, or the least
\ recently used. Returns the channel so you can stop or fade it; -1 for a
\ sample that failed to load, which every ch- word treats as no channel.
: wav-play ( sample -- ch )
    dup 0= if drop -1 exit then
    next-ch tuck wav-play-on ;

\ How long a sample runs, in milliseconds -- useful for scheduling without
\ polling ch-playing?.
: wav-ms ( sample -- n )
    dup 0= if exit then
    dup wav-frames 1000 rot wav-rate ?dup if */ else drop drop 0 then ;
