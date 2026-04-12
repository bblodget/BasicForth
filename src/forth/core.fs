\ BasicForth core.fs -- Forth-defined words
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded automatically at startup. These words build on the
\ ASM primitives in core.s.

\ Output helpers
: CR    10 emit ;
: SPACE 32 emit ;
: BL    32 ;

\ Boolean constants
: TRUE  -1 ;
: FALSE  0 ;

\ Arithmetic helpers
: MOD   /mod drop ;
: /     /mod nip ;

\ Stack helpers
: CELL+ 8 + ;
: CELLS 8 * ;

\ Comparison
: <>    = invert ;
: 0<>   0= invert ;

\ Derived stack words
: -ROT    rot rot ;
: 2OVER   3 pick 3 pick ;
: 2SWAP   rot >r rot r> ;

\ Derived arithmetic
: 2*      1 lshift ;
: */      >r * r> / ;

\ Output helpers
: SPACES  dup 0 > if 0 do space loop else drop then ;

\ String helpers
: COUNT   dup 1+ swap c@ ;

\ Number base
: DECIMAL   #10 base ! ;
: HEX       $10 base ! ;

\ Pictured numeric output
\ Builds strings right-to-left in PAD buffer.
: <#        pad 68 + hld ! ;
: HOLD      hld @ 1- dup hld ! c! ;
: SIGN      0< if 45 hold then ;
: >DIGIT    ( n -- char ) dup 10 < if 48 + else 10 - 65 + then ;
: #         ( ud-lo ud-hi -- qd-lo qd-hi )
            \ Step 1: divide ud-hi by BASE (using 0:ud-hi as double)
            swap >r               ( ud-hi                R: ud-lo )
            0 base @ um/mod       ( rem-hi quot-hi       R: ud-lo )
            \ Step 2: divide (rem-hi:ud-lo) by BASE
            r> swap >r            ( rem-hi ud-lo         R: quot-hi )
            swap base @ um/mod    ( rem quot-lo          R: quot-hi )
            \ rem is the digit, convert and HOLD
            swap >digit hold      ( quot-lo              R: quot-hi )
            r> ;                  ( qd-lo qd-hi )
: #S        begin # 2dup or 0= until ;
: #>        2drop hld @ pad 68 + over - ;

\ Double-cell helpers
: DNEGATE   ( d-lo d-hi -- d-lo' d-hi' )
            invert swap invert 1+ swap over 0= if 1+ then ;
: DABS      ( d-lo d-hi -- d-lo d-hi )
            dup 0< if dnegate then ;

\ Formatted output
: U.        0 <# #S #> type space ;
: .         dup >r s>d dabs <# #S r> sign #> type space ;
: .R        >r dup >r s>d dabs <# #S r> sign #> r> over - spaces type ;

\ Redefine */ using double-width intermediate
: */MOD     >r m* r> fm/mod ;
: */        */mod nip ;

\ Memory operations
: +!        dup @ rot + swap ! ;
: 2!        swap over ! cell+ ! ;
: 2@        dup cell+ @ swap @ ;
: CHAR+     1+ ;
: CHARS     ;
: FILL      ( c-addr u char -- )
            -rot begin dup 0 > while
                >r 2dup c! 1+ r> 1-
            repeat drop 2drop ;
: MOVE      ( addr1 addr2 u -- )
            dup 0 > if
                >r 2dup u< if
                    \ dest < src: copy forward
                    r> 0 do over i + c@ over i + c! loop
                else
                    \ dest >= src: copy backward
                    r> begin dup 0 > while
                        1- >r
                        over r@ + c@    ( src dest byte )
                        over r@ + c!    ( src dest )
                        r>
                    repeat drop
                then 2drop
            else drop 2drop then ;
: ALIGN     here 7 + -8 and here - allot ;
: ALIGNED   7 + -8 and ;

\ Character helpers
: CHAR      parse-word drop c@ ;

\ System words
: ENVIRONMENT?  ( c-addr u -- false ) 2drop false ;

\ Helper: convert char to digit value, or -1 if invalid
: >DIGIT?   ( char -- n true | false )
            dup 48 < if drop false exit then
            dup 58 < if 48 - dup base @ < if true else drop false then exit then
            dup 65 < if drop false exit then
            dup 91 < if 55 - dup base @ < if true else drop false then exit then
            dup 97 < if drop false exit then
            dup 123 < if 87 - dup base @ < if true else drop false then exit then
            drop false ;

\ >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
\ Convert string to number, accumulating into double ud.
\ Stack order: ( ud-lo ud-hi c-addr u ) with u on top.
\ Stops at first non-digit character.
: >NUMBER  ( ud-lo ud-hi c-addr u -- ud-lo' ud-hi' c-addr' u' )
    begin dup 0 > while
        over c@ >digit?
        0= if exit then             ( ud-lo ud-hi c-addr u digit )
        \ Stash c-addr and u on return stack, keep digit on data stack
        swap >r swap >r             ( ud-lo ud-hi digit  R: u c-addr )
        rot rot                     ( digit ud-lo ud-hi )
        swap >r                     ( digit ud-hi  R: u c-addr ud-lo )
        base @ *                    ( digit ud-hi*base )
        r> base @ um*               ( digit ud-hi*base prod-lo prod-hi )
        rot +                       ( digit prod-lo new-ud-hi )
        -rot +                      ( new-ud-hi new-ud-lo )
        swap                        ( new-ud-lo new-ud-hi )
        r> 1+ r> 1-                 ( new-ud-lo new-ud-hi c-addr+1 u-1 )
    repeat ;

\ ABORT" ( flag "ccc" -- )  IMMEDIATE, COMPILE_ONLY
\ If flag is true at runtime, print message and abort.
: ABORT"  postpone if  postpone s"  postpone type  postpone abort  postpone then ; immediate

\ WORD ( char "<chars>ccc<char>" -- c-addr )
\ Parse delimited string, return counted string at HERE.
: WORD
    drop                            \ ignore delimiter (use whitespace)
    parse-word                      ( c-addr u )
    dup here c!                     \ store count at HERE
    here 1+ swap                    ( c-addr here+1 u )
    dup >r                          ( c-addr here+1 u  R: u )
    move                            \ copy string to HERE+1
    r> here 1+ + 0 swap c!         \ null-terminate (optional)
    here ;                          \ return counted string address

\ Core extension words
: 0>        0 > ;
: U>        swap u< ;
: WITHIN    over - >r - r> u< ;
: ERASE     0 fill ;
: U.R       >r 0 <# #S #> r> over - spaces type ;
: HOLDS     begin dup 0 > while 1- 2dup + c@ hold repeat 2drop ;
: .(        \ parse and print until closing paren
            begin
                source >in @ > if
                    source drop >in @ + c@ dup 41 = if
                        drop 1 >in +! exit
                    then
                    emit 1 >in +!
                else exit then
            again ; immediate

\ Defining words
: VARIABLE  create 1 cells allot ;

\ Standard alias for PARSE-WORD
: PARSE-NAME  parse-word ;

\ String words (17)
: /STRING   ( c-addr u n -- c-addr+n u-n ) rot over + -rot - ;
: CMOVE     ( c-addr1 c-addr2 u -- )
            dup 0 > if 0 do over i + c@ over i + c! loop 2drop
            else drop 2drop then ;
: CMOVE>    ( c-addr1 c-addr2 u -- )
            dup 0 > if
                begin dup 0 > while
                    1- >r over r@ + c@ over r@ + c! r>
                repeat drop
            then 2drop ;
: -TRAILING ( c-addr u1 -- c-addr u2 )
            begin dup 0> while
                2dup + 1- c@ 32 <> if exit then
                1-
            repeat ;
: BLANK     ( c-addr u -- ) 32 fill ;
\ COMPARE: use variables to avoid deep stack juggling
variable (cmp-a1)  variable (cmp-u1)
variable (cmp-a2)  variable (cmp-u2)
: COMPARE   ( c-addr1 u1 c-addr2 u2 -- n )
    (cmp-u2) ! (cmp-a2) ! (cmp-u1) ! (cmp-a1) !
    (cmp-u1) @ (cmp-u2) @ min   ( min-len )
    0 ?do
        (cmp-a1) @ i + c@
        (cmp-a2) @ i + c@
        2dup <> if
            < if -1 else 1 then
            unloop exit
        then 2drop
    loop
    (cmp-u1) @ (cmp-u2) @
    2dup = if 2drop 0
    else < if -1 else 1 then then ;

\ Programming-Tools words (15)
: ?     ( a-addr -- ) @ . ;

\ Hex output helpers for DUMP
: H.2   ( u -- ) base @ >r hex
        0 <# # # #> type
        r> base ! ;

: H.ADDR ( u -- ) base @ >r hex
        0 <# # # # # # # # # #> type
        r> base ! ;

\ DUMP uses variables to keep the logic simple
variable (dump-addr)  variable (dump-len)
: DUMP  ( addr u -- )
        (dump-len) ! (dump-addr) !
        begin (dump-len) @ 0 > while
            (dump-addr) @ h.addr ." : "
            (dump-len) @ 16 min   ( n -- bytes this row )
            dup 0 do (dump-addr) @ i + c@ h.2 space loop
            dup 16 < if 16 over - 0 do ."    " loop then
            ."  |"
            dup 0 do
                (dump-addr) @ i + c@ dup 32 < over 126 > or
                if drop 46 then emit
            loop
            ." |" cr
            dup (dump-addr) @ + (dump-addr) !
            negate (dump-len) @ + (dump-len) !
        repeat ;

\ Double-Number words (8)
: D+    ( d1-lo d1-hi d2-lo d2-hi -- d3-lo d3-hi )
        rot + >r              ( d1-lo d2-lo  R: hi-sum )
        over + dup rot u< if r> 1+ else r> then ;
: D-    ( d1 d2 -- d3 ) dnegate d+ ;
: D0=   ( d -- flag ) or 0= ;
: D0<   ( d -- flag ) nip 0< ;
: D=    ( d1 d2 -- flag ) d- d0= ;
: D<    ( d1 d2 -- flag ) d- d0< ;
: D.    ( d -- ) dup >r dabs <# #s r> sign #> type space ;
