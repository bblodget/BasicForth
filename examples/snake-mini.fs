\ BasicForth — Minimal Snake (companion to the "Snake" tutorial)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ The finished program built step by step in the Snake tutorial
\ (tutorial Snake). A deliberately small Snake: a bordered board, a snake
\ that grows when it eats, arrow-key steering, and a timed frame loop.
\ For a fuller version (score, speed-up) see examples/snake.fs.
\
\ Requires: at-xy, page, cursor-off, cursor-on, key?, key, ms, ms@,
\           KEY_UP/DOWN/LEFT/RIGHT, rnd  (all built in).
\
\ Usage:  include examples/snake-mini.fs
\         snake            \ arrow keys to steer, q to quit

22 constant W            \ inner board width  (play area is columns 1..W)
16 constant H            \ inner board height (play area is rows 1..H)
150 constant FRAME       \ milliseconds per frame
300 constant MAXLEN      \ longest the snake can get

variable dx  variable dy        \ current direction (each -1, 0, or 1)
variable hx  variable hy        \ head position
variable nx  variable ny        \ where the head is about to move
variable fx  variable fy        \ food position
variable len                    \ current snake length
variable hd                     \ ring-buffer index of the head
variable gameover

create bx MAXLEN cells allot     \ body x positions (ring buffer)
create by MAXLEN cells allot     \ body y positions (ring buffer)

: bx! ( x idx -- )  cells bx + ! ;
: by! ( y idx -- )  cells by + ! ;
: bx@ ( idx -- x )  cells bx + @ ;
: by@ ( idx -- y )  cells by + @ ;

: tail-i ( -- idx )  hd @ len @ 1- - MAXLEN + MAXLEN mod ;

: draw ( x y char -- )  >r at-xy r> emit ;

: place-food
    W rnd 1+ fx !  H rnd 1+ fy !
    fx @ fy @ [char] F draw ;

: draw-border
    W 2 + 0 do  i 0 [char] # draw   i H 1+ [char] # draw  loop
    H 2 + 0 do  0 i [char] # draw   W 1+ i [char] # draw  loop ;

: init-snake
    W 2 / hx !  H 2 / hy !
    1 dx !  0 dy !
    3 len !  2 hd !  false gameover !
    hx @ 2 - 0 bx!  hy @ 0 by!
    hx @ 1 - 1 bx!  hy @ 1 by!
    hx @     2 bx!  hy @ 2 by! ;

: go ( dx dy -- )  dy !  dx ! ;
: input
    key? if
        key case
            KEY_UP    of  0 -1 go endof
            KEY_DOWN  of  0  1 go endof
            KEY_LEFT  of -1  0 go endof
            KEY_RIGHT of  1  0 go endof
            [char] q  of  true gameover ! endof
        endcase
    then ;

: ahead   hx @ dx @ + nx !   hy @ dy @ + ny ! ;

: wall? ( -- f )
    nx @ 1 <  nx @ W >  or
    ny @ 1 <  ny @ H >  or  or ;

: hits-body? ( -- f )
    false
    len @ 0 ?do
        hd @ i - MAXLEN + MAXLEN mod
        dup bx@ nx @ =  swap by@ ny @ =  and
        or
    loop ;

: advance-head
    hd @ 1+ MAXLEN mod hd !
    nx @ hd @ bx!   ny @ hd @ by!
    nx @ hx !  ny @ hy ! ;

: tick
    ahead
    wall? hits-body? or if  true gameover !  exit  then
    nx @ fx @ =  ny @ fy @ =  and
    if    len @ 1+ MAXLEN min len !  place-food
    else  tail-i dup bx@ swap by@ bl draw
    then
    advance-head
    nx @ ny @ [char] O draw ;

: draw-snake
    len @ 0 ?do
        hd @ i - MAXLEN + MAXLEN mod
        dup bx@ swap by@ [char] O draw
    loop ;

: frame-wait ( t0 -- )
    ms@ swap -  FRAME swap -  dup 0> if ms else drop then ;

: setup
    page cursor-off
    init-snake  draw-border  draw-snake  place-food ;

: play
    begin
        ms@
        input
        tick
        frame-wait
        gameover @
    until ;

: finish
    cursor-on
    0 H 3 + at-xy
    ." Game over!  Score: "  len @ 3 - .  cr ;

: snake   setup play finish ;
