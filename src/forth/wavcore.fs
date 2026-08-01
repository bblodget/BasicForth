\ BasicForth wavcore.fs -- decode RIFF/WAVE files into sample objects
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Reads a .wav file into memory and tells you what is in it. Pure Forth --
\ no FFI, no audio device, nothing to open -- so it works anywhere BasicForth
\ runs, including under qemu where there is no libSDL3 to load.
\
\   require wavcore.fs
\   s" blip.wav" wav-load   ( -- sample | 0 )
\
\ A sample is an opaque handle; ask it things:
\
\   dup wav-frames .        \ how many sample frames
\   dup wav-rate .          \ samples per second, as recorded in the file
\   dup wav-loop? .         \ does it carry loop points?
\   wav-free
\
\ On failure wav-load returns 0 and wav-why says what was wrong, so a program
\ can carry on without its sound effect rather than abort.
\
\ Accepts uncompressed 16-bit PCM, mono or stereo -- the format every tool
\ writes by default, and the one that needs no conversion to play. Anything
\ else is refused by name rather than mis-decoded into noise.
\
\ See wav.fs for playing one.

\ --- sample layout (a 56-byte heap block) ---
\   +0  the file image, kept so wav-free can release it
\   +8  pointer to the PCM inside that image (no copy is made)
\  +16  PCM byte count      +24 sample rate      +32 channels
\  +40  loop start, frames (-1 for none)         +48 loop end, frames
56 constant (wv-size)

\ Chunk tags, read as little-endian 32-bit words: "RIFF" is the bytes
\ 52 49 46 46, which load as $46464952 on a little-endian machine.
$46464952 constant (wv-RIFF)
$45564157 constant (wv-WAVE)
$20746D66 constant (wv-fmt)
$61746164 constant (wv-data)
$6C706D73 constant (wv-smpl)

variable (wv-fid)     variable (wv-buf)    variable (wv-len)
variable (wv-p)       variable (wv-id)     variable (wv-sz)
variable (wv-body)    variable (wv-dp)     variable (wv-dn)
variable (wv-rate)    variable (wv-ch)
variable (wv-l0)      variable (wv-l1)     variable (wv-s)
variable (wv-why-a)   variable (wv-why-u)

\ --- failure reporting ---
\ Every refusal names itself. The string literals live in the dictionary, so
\ the address stays valid after the defining word returns.
: (wv-fail) ( c-addr u -- 0 )  (wv-why-u) ! (wv-why-a) ! 0 ;
: wav-why ( -- c-addr u )  (wv-why-a) @ (wv-why-u) @ ;

\ --- accessors ---
: (wv@) ( sample off -- x )  over 0= if 2drop 0 exit then + @ ;
: wav-data   ( sample -- c-addr )   8 (wv@) ;
: wav-bytes  ( sample -- u )       16 (wv@) ;
: wav-rate   ( sample -- n )       24 (wv@) ;
: wav-chans  ( sample -- n )       32 (wv@) ;
: wav-loop-start ( sample -- n )   40 (wv@) ;
: wav-loop-end   ( sample -- n )   48 (wv@) ;

: wav-frames ( sample -- n )
    dup 0= if exit then
    dup wav-bytes swap wav-chans 2* / ;

: wav-loop? ( sample -- flag )
    dup 0= if drop false exit then  wav-loop-start 0 >= ;

: wav-free ( sample -- )
    dup 0= if drop exit then
    dup @ ?dup if free drop then      \ the file image
    free drop ;

\ --- read the whole file ---
\ Slurped in one piece and kept: the sample points into this image rather
\ than copying the PCM out of it.
: (wv-slurp) ( c-addr u -- flag )
    r/o bin open-file if drop false exit then  (wv-fid) !
    (wv-fid) @ file-size                        ( lo hi ior )
    if 2drop (wv-fid) @ close-file drop false exit then
    drop dup (wv-len) !
    dup 0= if drop (wv-fid) @ close-file drop false exit then
    allocate if drop (wv-fid) @ close-file drop false exit then
    (wv-buf) !
    (wv-buf) @ (wv-len) @ (wv-fid) @ read-file  ( u2 ior )
    swap (wv-len) @ <> or
    if (wv-buf) @ free drop (wv-fid) @ close-file drop false exit then
    (wv-fid) @ close-file drop true ;

\ --- chunk walk ---
: (wv-chunk) ( -- )                    \ id/size/body of the chunk at (wv-p)
    (wv-buf) @ (wv-p) @ +
    dup l@ (wv-id) !
    dup 4 + l@ (wv-sz) !
    8 + (wv-body) ! ;

\ fmt: format(2) channels(2) rate(4) byterate(4) align(2) bits(2)
: (wv-do-fmt) ( -- flag )
    (wv-sz) @ 16 < if s" wav: fmt chunk is too short" (wv-fail) drop false exit then
    (wv-body) @ w@ 1 <>
        if s" wav: not uncompressed PCM" (wv-fail) drop false exit then
    (wv-body) @ 2 + w@ (wv-ch) !
    (wv-ch) @ 1 <  (wv-ch) @ 2 >  or
        if s" wav: need mono or stereo" (wv-fail) drop false exit then
    (wv-body) @ 14 + w@ 16 <>
        if s" wav: need 16-bit samples" (wv-fail) drop false exit then
    (wv-body) @ 4 + l@ (wv-rate) !
    (wv-rate) @ 0= if s" wav: sample rate is zero" (wv-fail) drop false exit then
    true ;

\ smpl: 36 bytes of header (loop count at +28), then 24 bytes per loop, with
\ start at +8 and end at +12 inside each. Only the first loop is used.
: (wv-do-smpl) ( -- )
    (wv-sz) @ 60 < if exit then
    (wv-body) @ 28 + l@ 0= if exit then
    (wv-body) @ 44 + l@ (wv-l0) !
    (wv-body) @ 48 + l@ (wv-l1) ! ;

: (wv-walk) ( -- flag )
    12 (wv-p) !
    begin (wv-p) @ 8 + (wv-len) @ <= while
        (wv-chunk)
        (wv-p) @ 8 + (wv-sz) @ + (wv-len) @ >
            if s" wav: a chunk runs past the end of the file" (wv-fail) drop
               false exit then
        (wv-id) @ (wv-fmt)  = if (wv-do-fmt) 0= if false exit then then
        (wv-id) @ (wv-data) = if (wv-body) @ (wv-dp) !  (wv-sz) @ (wv-dn) ! then
        (wv-id) @ (wv-smpl) = if (wv-do-smpl) then
        (wv-p) @ 8 + (wv-sz) @ +  dup 1 and +  (wv-p) !   \ chunks pad to even
    repeat
    true ;

\ Loop points are only kept if they actually describe a range inside the
\ sample; a bogus pair is dropped rather than trusted.
\
\ The smpl chunk's end point is INCLUSIVE -- the spec calls it the last sample
\ that will be played -- so the largest legal end on an n-frame sample is
\ n-1, and `end = n` is already one frame past the audio. Getting this wrong
\ reads off the end of the buffer once per loop, quietly.
\ Rejecting clears BOTH endpoints, not just the start. Leaving the end at the
\ value that was just refused hands a caller the very number that would index
\ past the audio, and "no loop" would report three different ends depending on
\ how the file was wrong. No usable loop means -1 -1, always.
: (wv-no-loop) ( -- )  -1 (wv-l0) !  -1 (wv-l1) ! ;
: (wv-check-loop) ( frames -- )
    (wv-l0) @ 0 < if drop (wv-no-loop) exit then
    (wv-l1) @ (wv-l0) @ <=  if drop (wv-no-loop) exit then
    (wv-l1) @ swap >= if (wv-no-loop) then ;

: (wv-drop-buf) ( -- )  (wv-buf) @ ?dup if free drop then  0 (wv-buf) ! ;

\ --- the loader ---
: wav-load ( c-addr u -- sample|0 )
    s" wav: ok" (wv-fail) drop
    -1 (wv-l0) !  -1 (wv-l1) !  0 (wv-dp) !  0 (wv-dn) !
    0 (wv-rate) !  0 (wv-ch) !  0 (wv-buf) !
    (wv-slurp) 0= if s" wav: cannot read the file" (wv-fail) exit then
    (wv-len) @ 12 <
        if (wv-drop-buf) s" wav: too short to be a RIFF file" (wv-fail) exit then
    (wv-buf) @ l@ (wv-RIFF) <>
        if (wv-drop-buf) s" wav: not a RIFF file" (wv-fail) exit then
    (wv-buf) @ 8 + l@ (wv-WAVE) <>
        if (wv-drop-buf) s" wav: RIFF file is not WAVE" (wv-fail) exit then
    (wv-walk) 0= if (wv-drop-buf) 0 exit then
    (wv-ch) @ 0=
        if (wv-drop-buf) s" wav: no fmt chunk" (wv-fail) exit then
    (wv-dp) @ 0=
        if (wv-drop-buf) s" wav: no data chunk" (wv-fail) exit then
    \ Trim a partial trailing frame rather than playing half a sample.
    (wv-dn) @  (wv-ch) @ 2*  /  (wv-ch) @ 2* *  (wv-dn) !
    (wv-dn) @ 0=
        if (wv-drop-buf) s" wav: no audio in the data chunk" (wv-fail) exit then
    (wv-dn) @ (wv-ch) @ 2* / (wv-check-loop)
    (wv-size) allocate
        if drop (wv-drop-buf) s" wav: out of memory" (wv-fail) exit then
    (wv-s) !
    (wv-buf)  @ (wv-s) @ !
    (wv-dp)   @ (wv-s) @  8 + !
    (wv-dn)   @ (wv-s) @ 16 + !
    (wv-rate) @ (wv-s) @ 24 + !
    (wv-ch)   @ (wv-s) @ 32 + !
    (wv-l0)   @ (wv-s) @ 40 + !
    (wv-l1)   @ (wv-s) @ 48 + !
    (wv-s) @ ;
