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

\ Move monster i by one step on an axis, clamped to the arena. Terminal cells
\ are ~2x taller than wide, so x moves in 2-COLUMN STRIDES (same trick as
\ snake.fs) and every x stays on the even grid — collisions match exactly.
: nudge-x ( i step -- )  2 *  over mx@ + 2 max W min swap mx! ;
: nudge-y ( i step -- )        over my@ + 1 max H min swap my! ;

\ ---- Brains: each takes a monster index ( i -- ) and moves that monster ----
\ A pursuer must never be faster than the player: the player moves one axis
\ per frame, so a brain does too — it picks an AIM POINT and closes the longer
\ axis by one. And no brain is perfect: each frame it takes the smart step
\ only pct% of the time, otherwise a random WOBBLE — those fumbles are the
\ player's chance. A brain's personality is where it aims and how sharp it is.
variable tx  variable ty                          \ where the current brain aims
: aim! ( x y -- )  ty !  tx ! ;
: step-toward ( i -- )                            \ one step toward (tx,ty)
    dup mx@ tx @ - abs  over my@ ty @ - abs  > if
        dup dup mx@ tx @ toward nudge-x           \ farther in x: close x
    else
        dup dup my@ ty @ toward nudge-y           \ else close y
    then drop ;
: wobble ( i -- )                                 \ one random one-axis step
    2 rnd if  dup 3 rnd 1- nudge-x  else  dup 3 rnd 1- nudge-y  then  drop ;
: pursue ( i pct -- )                             \ pct%: smart step, else wobble
    100 rnd > if  step-toward  else  wobble  then ;

: hunt ( i -- )                                   \ sharp: aims at the player
    px @ py @ aim!  50 pursue ;

: ambush ( i -- )                                 \ aims 3 cells ahead of player
    px @ pdx @ 3 * +  py @ pdy @ 3 * +  aim!  40 pursue ;

: drift ( i -- )                                  \ wanders; occasionally lunges
    px @ py @ aim!  15 pursue ;

\ ---- Setup ----
: spawn-gold   W 2 / rnd 1+ 2 *  gx !  H rnd 1+ gy ! ;   \ even column

: place-monster ( i -- )                          \ scatter to a corner (even x)
    dup 2 mod if W 2 - else 2 then  over mx!
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
: input                                           \ drain the queue; last key wins
    begin key? while
        key case
            KEY_UP    of  0 -1 go endof
            KEY_DOWN  of  0  1 go endof
            KEY_LEFT  of -1  0 go endof
            KEY_RIGHT of  1  0 go endof
            [char] q  of  true caught ! endof
        endcase
    repeat ;

: step-player
    px @ pdx @ 2 * +  2 max W min  px !           \ 2-column stride
    py @ pdy @ +      1 max H min  py ! ;

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
