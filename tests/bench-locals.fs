\ BasicForth — what a local reference costs, against what it replaces
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Locals were built on one performance claim: a REFERENCE is open-coded, not a
\ call, because a call would make locals slower than the stack juggling they
\ exist to replace -- and nothing about that failure would be visible to a
\ correctness test. The claim was verified by disassembly on both arches but
\ TIMED only on x86, where a reference is 4 instructions to ARM64's 6.
\
\ TWO measurements, because neither alone answers it.
\
\ PART 1 is per-primitive. Every row is ten (ACCESS + drop) pairs, so each
\ carries one `drop` call it cannot shed -- an access has to be consumed by
\ something, and everything that consumes is a call. Rows are therefore
\ comparable TO EACH OTHER, and none is an absolute cost. The `nop` row is a
\ bare call+ret with no drop, which calibrates what that shared suffix costs.
\ Reading a row as an absolute is the mistake this comment exists to prevent.
\
\ PART 2 is the one that settles the design question: the SAME function written
\ both ways, timed end to end, frame build and release included. Locals only
\ have to beat juggling in a whole word -- that is the only place the choice is
\ ever made. The two are checked for equal output before either is timed.
\
\   run

5000000 constant REPS
variable base-ms
variable gv

: nop ;

: .res ( ms -- )                        \ subtract the empty loop, print per-access
    base-ms @ -  dup 5 .r ."  ms "
    1000000000 REPS 10 * */  6 .r ."  ps/access" cr ;

: .res1 ( ms -- )                       \ PART 2: one call per iteration, not ten
    base-ms @ -  dup 5 .r ."  ms "
    1000000000 REPS */  6 .r ."  ps/call" cr ;

\ ---------------------------------------------------------------- PART 1
: b-empty ( -- ms )
    ms@ REPS 0 ?do loop ms@ swap - ;

: b-local ( n -- ms )
    {: a :} ms@
    REPS 0 ?do  a drop a drop a drop a drop a drop
                a drop a drop a drop a drop a drop  loop
    ms@ swap - ;

: b-dup ( n -- ms )
    ms@ swap
    REPS 0 ?do  dup drop dup drop dup drop dup drop dup drop
                dup drop dup drop dup drop dup drop dup drop  loop
    drop ms@ swap - ;

: b-over ( n -- ms )
    ms@ swap 99
    REPS 0 ?do  over drop over drop over drop over drop over drop
                over drop over drop over drop over drop over drop  loop
    2drop ms@ swap - ;

: b-var ( -- ms )                       \ a global: a create/does>-class word, then @
    ms@
    REPS 0 ?do  gv @ drop gv @ drop gv @ drop gv @ drop gv @ drop
                gv @ drop gv @ drop gv @ drop gv @ drop gv @ drop  loop
    ms@ swap - ;

: b-call ( -- ms )                      \ calibration: call+ret, NO drop
    ms@
    REPS 0 ?do  nop nop nop nop nop nop nop nop nop nop  loop
    ms@ swap - ;

: b-lit ( -- ms )                       \ a LITERAL, which the frame compiles twice
    ms@
    REPS 0 ?do  3 drop 3 drop 3 drop 3 drop 3 drop
                3 drop 3 drop 3 drop 3 drop 3 drop  loop
    ms@ swap - ;

: b-refstore ( n -- ms )                \ ten (reference + store), NO drop: both open-coded
    {: a :} ms@
    REPS 0 ?do  a to a  a to a  a to a  a to a  a to a
                a to a  a to a  a to a  a to a  a to a  loop
    ms@ swap - ;

\ ---------------------------------------------------------------- PART 2
\ (a+b)*(b+c) -- b is needed twice, which is what forces the juggling.
: f-locals ( a b c -- n )  {: a b c :} a b + b c + * ;
: f-juggle ( a b c -- n )  over + >r + r> * ;

\ The loop prefix `i dup dup` is identical in both drivers, so it cancels.
: d-locals ( -- ms )
    ms@ REPS 0 ?do i dup dup f-locals drop loop ms@ swap - ;

: d-juggle ( -- ms )
    ms@ REPS 0 ?do i dup dup f-juggle drop loop ms@ swap - ;

: same? ( -- f )                        \ never time two different computations
    2 3 4 f-locals  2 3 4 f-juggle  =
    7 11 13 f-locals  7 11 13 f-juggle  =  and ;

\ ---------------------------------------------------------------- PART 3
\ If PART 2 goes against locals, this says where the time went: the frame is
\ built and released once per CALL, and the count reaches (lframe)/(lunframe)
\ as a LITERAL each time. A frame of 1 costing the same as a frame of 3 is the
\ tell that the fixed part dominates the copying.
: p-nop   ( a b c -- )  drop drop drop ;
: p-f1    ( a -- )      {: a :} ;
: p-f3    ( a b c -- )  {: a b c :} ;
: p-f3r4  ( a b c -- )  {: a b c :} a b + b c + * drop ;

: e-args ( -- ms ) ms@ REPS 0 ?do i dup dup drop drop drop loop ms@ swap - ;
: d-nop  ( -- ms ) ms@ REPS 0 ?do i dup dup p-nop loop ms@ swap - ;
: d-f1   ( -- ms ) ms@ REPS 0 ?do i dup dup drop drop p-f1 loop ms@ swap - ;
: d-f3   ( -- ms ) ms@ REPS 0 ?do i dup dup p-f3 loop ms@ swap - ;
: d-f3r4 ( -- ms ) ms@ REPS 0 ?do i dup dup p-f3r4 loop ms@ swap - ;

: run ( -- )
    cr ." REPS " REPS . cr
    same? 0= if ." f-locals and f-juggle DISAGREE -- timings withheld" cr exit then
    ." the two spellings agree (" 2 3 4 f-locals . ." for 2 3 4)" cr cr

    b-empty dup base-ms !
    ." PART 1 -- ten (access + drop) per iteration; rows compare to each other" cr
    ." empty loop   " 5 .r ."  ms  (subtracted below)" cr
    ." local ref    " 7 b-local .res
    ." dup          " 7 b-dup   .res
    ." over         " 7 b-over  .res
    ." variable @   "   b-var   .res
    ." literal      "   b-lit   .res
    cr ." calibration -- no drop in these two" cr
    ." colon call   "   b-call     .res
    ." ref + store  " 7 b-refstore .res

    cr ." PART 2 -- (a+b)*(b+c), one call per iteration, frame included" cr
    ." f-locals     "   d-locals .res1
    ." f-juggle     "   d-juggle .res1

    cr ." PART 3 -- where a locals call spends its time" cr
    e-args dup base-ms !
    ." loop + args  " 5 .r ."  ms  (subtracted below)" cr
    ." 3 drops      " d-nop  .res1
    ." frame of 1   " d-f1   .res1
    ." frame of 3   " d-f3   .res1
    ." frame3 + 4refs" d-f3r4 .res1
    cr ;
