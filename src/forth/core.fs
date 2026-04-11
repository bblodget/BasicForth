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

\ Defining words
: VARIABLE  create 1 cells allot ;
