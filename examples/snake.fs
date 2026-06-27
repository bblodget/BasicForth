\ BasicForth — Snake Game
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Port of BareMetalForth snake.fs to BasicForth (Linux terminal).
\ Requires: KEY?, MS, MS@, AT-XY, PAGE, SCREEN-WIDTH, SCREEN-HEIGHT,
\           CURSOR-OFF, CURSOR-ON, KEY_UP/DOWN/LEFT/RIGHT, rnd
\
\ Usage: include examples/snake.fs
\        snake

screen-width dup 2 mod - constant WIDTH
screen-height 1 - dup 2 mod - constant HEIGHT

0 constant NO_DIR
1 constant NORTH
2 constant EAST
3 constant SOUTH
4 constant WEST

100 constant MAX_LEN
1   constant YOFFSET
50  constant MIN-FRAME-MS
200 constant INIT-FRAME-MS
10  constant FRAME-DECR-MS

variable frame
variable dir
variable hx
variable hy
variable fx
variable fy
variable done
variable body-head    \ index where next position goes
variable body-len     \ current length of snake body
variable col-char     \ character collided with
variable score
variable frame-ms

: init-vars
    0 frame !
    NO_DIR dir !
    WIDTH 2 / dup 2 mod - hx !
    HEIGHT 2 / hy !
    0 fx !  0 fy !
    false done !
    0 body-head !  0 body-len !
    bl col-char !
    0 score !
    INIT-FRAME-MS frame-ms ! ;

create screen WIDTH HEIGHT * allot
create body-x MAX_LEN allot
create body-y MAX_LEN allot

\ *** Screen access words ***

: screen-pos ( x y -- addr ) WIDTH * + screen + ;
: screen!    ( c x y -- ) screen-pos c! ;
: screen@    ( x y -- c ) screen-pos c@ ;
: reset-screen  screen WIDTH HEIGHT * bl fill ;

\ *** Factored Helper Words ***

: screen-body ( body-char -- )
    body-len @ 0 ?do
        dup
        body-head @ 1- i - dup 0< if MAX_LEN + then
        dup body-x + c@
        swap body-y + c@
        screen!
    loop drop ;

: grow-body  body-len @ 1+ MAX_LEN min body-len ! ;

: inc-speed
    frame-ms @ FRAME-DECR-MS - MIN-FRAME-MS max frame-ms ! ;
: inc-score  score @ 1+ score ! ;

: at-border? ( -- f )
    hx @ 0=   hx @ WIDTH 1- = or
    hy @ 0=   hy @ HEIGHT 1- = or or ;

\ *** Clear Objects Words ***
: clear-head  bl hx @ hy @ screen! ;
: clear-body  bl screen-body ;

\ *** Update position words ***

variable food-ok               \ did update-food find an empty cell?

: update-food
    \ Place food on an empty cell, so it never lands on the snake (or border) --
    \ otherwise food could sit on the tail, and eating there would slip past the
    \ screen-based collision check (the tail has just vacated the cell).
    \ Try random spots (bounded, so a near-full board can't spin forever);
    \ once a spot is found the remaining iterations are no-ops.
    false food-ok !
    100 0 do
        food-ok @ 0= if
            WIDTH 2 - 2 / rnd 2 * 2 + fx !
            HEIGHT 2 - rnd 1+ fy !
            fx @ fy @ screen@ bl = food-ok !
        then
    loop
    \ ...then fall back to a scan for any empty cell if the board is crowded.
    \ Only the reachable cells are scanned: the snake moves in x by +-2 from an
    \ even start, so food goes on even columns 2..WIDTH-2 (col WIDTH-1 is the
    \ border) and rows 1..HEIGHT-2 -- odd/outer columns are unreachable.
    food-ok @ 0= if
        HEIGHT 1- 1 do
            WIDTH 2 do
                food-ok @ 0= if
                    i j screen@ bl = if  i fx !  j fy !  true food-ok !  then
                then
            2 +loop
        loop
    then
    \ ...and if the board is completely full, the player has won: end the game.
    food-ok @ 0= if  true done !  then ;

: update-head
    dir @ case
        NORTH of hy @ 1- 0 max hy ! endof
        EAST  of hx @ 2 + WIDTH 1- min hx ! endof
        SOUTH of hy @ 1+ HEIGHT 1- min hy ! endof
        WEST  of hx @ 2 - 0 max hx ! endof
    endcase ;

: update-body ( -- )
    hx @ body-head @ body-x + c!
    hy @ body-head @ body-y + c!
    body-head @ 1+ MAX_LEN mod body-head ! ;

\ *** Drawing words ***

: draw-screen
    HEIGHT 0 do
        0 i YOFFSET + at-xy
        screen i WIDTH * + WIDTH type
    loop ;

: draw-border
    WIDTH 0 do
        [char] - i 0 screen!
        [char] - i HEIGHT 1- screen!
    loop
    HEIGHT 1- 1 do
        [char] | 0 i screen!
        [char] | WIDTH 1- i screen!
    loop ;

: draw-food  [char] F fx @ fy @ screen! ;
: draw-head  [char] H hx @ hy @ screen! ;
: draw-body  [char] o screen-body ;

\ *** Overlays ***

: overlay-score  2 0 at-xy ." Score: " score @ . ;
: overlays  overlay-score ;

\ *** Main game loop words ***

: frame-delay ( start-ms -- )
    ms@ swap - frame-ms @ swap - dup 0> if ms else drop then
    1 frame +! ;

: get-key
    key? 0<> if key case
        KEY_LEFT  of WEST  dir ! endof
        KEY_DOWN  of SOUTH dir ! endof
        KEY_UP    of NORTH dir ! endof
        KEY_RIGHT of EAST  dir ! endof
        [char] q  of true done ! endof
    endcase then ;

: collision?
    at-border? if true exit then
    hx @ hy @ screen@
    dup col-char !
    case
        [char] o of true endof
        [char] - of true endof
        [char] | of true endof
        false swap
    endcase ;

: ate-food?  hx @ fx @ = hy @ fy @ = and ;

: update-objects  update-body update-head ;

: check-collision
    collision? if
        draw-head draw-screen
        true done !
    then
    ate-food? if
        update-food
        grow-body
        inc-score
        inc-speed
    then ;

: draw-objects
    draw-head
    draw-food
    draw-body
    draw-screen ;

: clear-objects  clear-head clear-body ;

: game-loop
    begin
        ms@
        get-key
        clear-objects
        update-objects
        draw-objects
        check-collision
        overlays
        frame-delay
    done @ until ;

: game-init  init-vars reset-screen draw-border update-food ;

: drain-keys  begin key? while key drop repeat ;

: game-over
    WIDTH 2 / 6 - HEIGHT 2 / at-xy ." GAME OVER!"
    WIDTH 2 / 6 - HEIGHT 2 / 1+ at-xy ." Score: " score @ .
    WIDTH 2 / 9 - HEIGHT 2 / 2 + at-xy ." Press q to quit..."
    drain-keys
    begin key [char] q = until ;

: snake
    page cursor-off
    game-init game-loop game-over
    cursor-on page ;
