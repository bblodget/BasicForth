\ BasicForth — Chase (companion to the "Chase" tutorial)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ The finished program from the "Chase" tutorial (tutorial Chase), which
\ teaches TOP-DOWN design: sketch the whole game first, name the seams, then
\ fill them in. You are @, you collect gold $, and monsters M hunt you.
\
\ The tutorial builds this with deferred seams (defer/is) so the skeleton runs
\ before the parts exist, then "bakes" the settled design into the direct
\ definitions you see here. What stays is the per-monster BRAIN TABLE: each
\ monster carries its own execution token, dispatched with EXECUTE — so every
\ ghost can have a different mind (hunt, ambush, drift), Pac-Man style.
\
\ Requires: at-xy, page, cursor-off, cursor-on, key?, key, ms, ms@,
\           KEY_UP/DOWN/LEFT/RIGHT, rnd, '  (all built in).
\
\ Usage:  include examples/chase.fs
\         chase            \ arrow keys to move, q to quit

40 constant W            \ inner board width  (play area is columns 1..W)
20 constant H            \ inner board height (play area is rows 1..H)
120 constant FRAME       \ milliseconds per frame
8  constant MAXM         \ most monsters the table can hold

\ --- player ---
variable px  variable py         \ player position
variable pdx variable pdy        \ player heading (each -1, 0, or 1)
\ --- gold ---
variable gx  variable gy         \ gold position
variable score
\ --- monsters (a table: position + brain per monster) ---
variable mcount                  \ how many monsters are in play
create mxs    MAXM cells allot   \ x position of each monster
create mys    MAXM cells allot   \ y position of each monster
create mbrain MAXM cells allot   \ execution token (xt) of each monster's brain
\ --- game ---
variable caught                  \ true => game over

\ Per-monster accessors (idx -> the i-th slot)
: mx@ ( i -- x )    cells mxs + @ ;
: my@ ( i -- y )    cells mys + @ ;
: mx! ( x i -- )    cells mxs + ! ;
: my! ( y i -- )    cells mys + ! ;
: brain@ ( i -- xt ) cells mbrain + @ ;
: brain! ( xt i -- ) cells mbrain + ! ;

\ Small helpers
: sgn ( n -- -1|0|1 )  dup 0> if drop 1 else 0< if -1 else 0 then then ;
: toward ( cur target -- step )  swap - sgn ;     \ sign(target - cur)
: draw ( x y char -- )  >r at-xy r> emit ;

\ Move monster i by one step on each axis, clamped to the arena.
: nudge-x ( i step -- )  over mx@ + 1 max W min swap mx! ;
: nudge-y ( i step -- )  over my@ + 1 max H min swap my! ;

\ ---- Brains: each takes a monster index ( i -- ) and moves that monster ----
: hunt ( i -- )                                   \ greedy: step toward player
    dup dup mx@ px @ toward nudge-x
    dup my@ py @ toward nudge-y ;

: ambush ( i -- )                                 \ aim 3 cells ahead of player
    dup dup mx@  px @ pdx @ 3 * +  toward nudge-x
    dup my@  py @ pdy @ 3 * +  toward nudge-y ;

: drift ( i -- )                                  \ random wander
    dup 3 rnd 1- nudge-x
    3 rnd 1- nudge-y ;

\ ---- Setup ----
: spawn-gold   W rnd 1+ gx !  H rnd 1+ gy ! ;

: place-monster ( i -- )                          \ scatter to a corner
    dup 2 mod if W 1- else 2 then  over mx!
    dup 2 / 2 mod if H 1- else 2 then  swap my! ;

: install-brains                                  \ each ghost its own mind
    ' hunt 0 brain!
    ' ambush 1 brain!
    ' drift 2 brain! ;

: init-game
    W 2 / px !  H 2 / py !  0 pdx !  0 pdy !
    0 score !  false caught !
    3 mcount !
    mcount @ 0 ?do i place-monster loop
    install-brains
    spawn-gold ;

\ ---- Drawing ----
: draw-border
    W 2 + 0 do  i 0 [char] # draw   i H 1+ [char] # draw  loop
    H 2 + 0 do  0 i [char] # draw   W 1+ i [char] # draw  loop ;
: draw-gold      gx @ gy @ [char] $ draw ;
: draw-player    px @ py @ [char] @ draw ;
: draw-monsters  mcount @ 0 ?do i mx@ i my@ [char] M draw loop ;

: erase-actors
    px @ py @ bl draw
    mcount @ 0 ?do i mx@ i my@ bl draw loop ;
: draw-actors  draw-gold draw-player draw-monsters ;

\ ---- One turn ----
: go ( dx dy -- )  pdy !  pdx ! ;
: input
    key? if
        key case
            KEY_UP    of  0 -1 go endof
            KEY_DOWN  of  0  1 go endof
            KEY_LEFT  of -1  0 go endof
            KEY_RIGHT of  1  0 go endof
            [char] q  of  true caught ! endof
        endcase
    then ;

: step-player
    px @ pdx @ + 1 max W min px !
    py @ pdy @ + 1 max H min py ! ;

: step-monsters                                   \ run each monster's own brain
    mcount @ 0 ?do  i  i brain@  execute  loop ;

: eat?
    px @ gx @ =  py @ gy @ =  and
    if  1 score +!  spawn-gold  then ;

: collide?
    mcount @ 0 ?do
        px @ i mx@ =  py @ i my@ =  and
        if true caught ! then
    loop ;

: update   step-player  step-monsters  eat?  collide? ;

: frame-wait ( t0 -- )
    ms@ swap -  FRAME swap -  dup 0> if ms else drop then ;

\ ---- The game ----
: setup
    page cursor-off
    init-game
    draw-border draw-actors ;

: play
    begin
        ms@  input  erase-actors  update  draw-actors  frame-wait
        caught @
    until ;

: finish
    cursor-on
    0 H 3 + at-xy
    ." Caught!  Score: " score @ . cr ;

: chase   setup play finish ;
