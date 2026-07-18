decimal
\ Width and Height of state space
64 constant W
32 constant H

\ ms between generations
100 value tick

\ buffer0 and buffer1 are used for double buffering 
\ the 1-D Cellular Automata state.
\ Each cell holds 0 or 1.  Binary state.
create buffer0 W cells allot
create buffer1 W cells allot

\ Lookup table for the CA rule
create pln0 32 cells allot  \ Lookup table for pln0

\ Pointers to buffer0 and buffer1
\ swaps between generations
variable curr-gen
variable next-gen
variable tmp-gen

\ the neighborhood case being enumerated (5 bits)
variable (config)

\ pseudo-neighbors: bit layout [west2 west1 center east1 east2]
: west2  (config) @ 16 and 0<> 1 and ;
: west1  (config) @  8 and 0<> 1 and ;
: center (config) @  4 and 0<> 1 and ;
: east1  (config) @  2 and 0<> 1 and ;
: east2  (config) @  1 and 0<> 1 and ;

: #neighbors west2 west1 east1 east2 + + + ;
: >pln0  ( value -- )  \ Put the value into pln0 at the index given by (config)
    (config) @ cells pln0 + ! ;

\ *****************
\ Start Rules
\ *****************

: 1d-life
    center if
        #neighbors dup 2 = swap 4 = or  \ survive on 2 or 4
    else
        #neighbors dup 2 = swap 3 = or \ born on 2 or 3
    then 1 and >pln0 ;

: echo
    center >pln0 ;

: parity
    east2 east1 center west1 west2 
    xor xor xor xor >pln0 ;

\ *****************
\ End Rules
\ *****************

\ *****************
\ Start Table generation
\ *****************

: table! ( xt -- )
    32 0 do
        i (config) !
        dup execute
    loop drop ;

: make-table ( "rule" -- )
    parse-name find 0= abort" make-table: no such rule" table! ;

: .table
    32 0 do
        pln0 i cells + @ .
    loop ;

\ *****************
\ End Table generation
\ *****************

\ *****************
\ Start Utils
\ *****************

: pos-ptr ( pos -- curr-gen-ptr )
    cells curr-gen @ +
    ;

: .gen
    W 0 do
        i pos-ptr @ if [char] # else [char] . then emit
    loop cr ;

: wrap ( n -- n' ) W mod W + W mod ;

\ Change to base 2.
\ words decimal and hex already exist
: .bin 2 base ! ;

\ *****************
\ End Utils
\ *****************

\ *****************
\ Start Core
\ *****************

: setup-gen ( -- )
  buffer0 curr-gen !
  buffer1 next-gen ! ;

: window ( i -- w )    \ the 5 cells around i packed into 5 bits
    0
    over 2 - wrap pos-ptr @  16 * +
    over 1 - wrap pos-ptr @   8 * +
    over     wrap pos-ptr @   4 * +
    over 1 + wrap pos-ptr @   2 * +
    swap 2 + wrap pos-ptr @       + ;

: swap-gen ( -- )
  curr-gen @ tmp-gen !   \ tmp-gen = curr-gen
  next-gen @ curr-gen !  \ curr-gen = next-gen
  tmp-gen @ next-gen ! ; \ next-gen = tmp-gen

: update-gen ( -- )
    W 0 do
        i window  cells pln0 + @
        next-gen @ i cells + !
    loop ;

: step ( -- )
    .gen
    update-gen
    swap-gen
    tick ms ;

: steps ( n -- )
    0 do
        step
    loop ;

: go ( -- )
    H steps ;

\ *****************
\ End Core
\ *****************


\ *****************
\ Start patterns
\ *****************

: init-empty
    W 0 do
        0 i pos-ptr !
    loop ;

: init-random  \ Init 1-D life with a random pattern
    W 0 do
        2 rnd i pos-ptr !  \ store a random bit
    loop ;

\ The ZOO
\ Discovered reactions in 1d-life (survive {2,4} / born {2,3}):
\ G = glider, G* = glider reflected
\   G + G*      odd gap   -> face (#######) big bang
\   G + G*      even gap  -> blinker  (period 2)
\   G + blinker even gap  -> hexer    (period 6, glider absorbed)
\   G + blinker odd gap   -> tripler  (period 3, long transient)

: face s" #######" ;
: spider s" ######" ;
: glider-left s" ###.#" ;
: glider-right s" #.###" ;
: third-glider s" #.######" ;
: third-glider2 s" ##.#######" ;
: fifth-glider s" #######.##.##.#.#" ;
: viperine s" #.#..#...####..##..##..##" ;
: blinker s" ##..##" ;
: hexer s" #..#..#" ;
: tripler s" ######.#" ;


: place-pattern ( c-addr u pos -- )
    \ Assume pos is counted from the left
    \ pos is wrapped to stay in bounds
    wrap                        \ wrap the position to be within the width
    swap                        \ c-addr pos u
    0 do                        \ c-addr pos
        over                    \ c-addr pos c-addr
        i + c@                  \ c-addr pos state-chr
        [char] # = 1 and         \ c-addr pos state
        over                    \ c-addr pos state pos
        pos-ptr                 \ c-addr pos state curr-gen-ptr
        !                       \ c-addr pos
        1+                      \ c-addr pos-next
        wrap                    \ c-addr pos-next-wrapped
    loop drop drop ;

: init-pattern ( c-addr u -- )
    dup W > abort" pattern wider than W"
    init-empty
    W 2 / over 2 / - place-pattern ;

\ *****************
\ End patterns
\ *****************

\ *****************
\ Start Demos
\ *****************

: spider-run ( -- )
    init-empty
    5 0 do
        spider i 6 * place-pattern
        7 steps 
        \ spider is a 7-gen diehard, so clear for next loop
    loop ;

: collide ( gap -- )
    init-empty
    glider-right 0 place-pattern
    glider-left        \ gap c-addr u
    rot                \ c-addr u gap
    5 +                \ c-addr u gap+5
    place-pattern go ;


\ *****************
\ End Demos
\ *****************

\ *****************
\ Start Main
\ *****************


: start
    ['] 1d-life table!
    setup-gen
    init-random
    ;


start

