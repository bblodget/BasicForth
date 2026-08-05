#!/usr/bin/env basicforth
\ BasicForth — dice, a threaded Monte Carlo simulation
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Throw a 4-sided die 231 times and count how many 1s come up. That is one
\ "battle". Run a billion battles and ask: what is the most 1s you ever saw?
\
\ The answer is around 100 (the mean is 57.75, so ~6.5 standard deviations
\ out), and finding it is pure brute force — which makes it a good showcase
\ for threads, and a good lesson in what makes threaded code fast or slow.
\
\ Usage (interactive):
\
\   require dice.fs
\   1000000000 to BATTLES     \ how many battles in total
\   16 doit                   \ split them across 16 workers, time it, report
\   roll .                    \ a single throw, at the prompt
\
\ `doit ( #threads -- )` divides BATTLES between the workers, so every thread
\ count does the same work and the wall times compare directly.
\
\ Three things make this fast, in descending order of how much they matter:
\
\   1. Every worker owns its random seed, in memory it allocated itself. One
\      shared seed made 4 threads run 4x SLOWER than 1 — not from locking,
\      there is none, but because a single cache line cannot be written by
\      two cores at once. Results go in one cache line per worker for the
\      same reason, and each is written exactly once, at the end.
\   2. A d4 needs 2 bits, so one 64-bit random value holds 32 throws. We
\      never want the throws themselves, only how many were 1s, and `popcount`
\      answers that for all 32 at once. Worth ~20x.
\   3. Threads, worth ~11x on 8 cores — the least of the three, and the only
\      one most people would think of.
\
\ It is also a lesson in verifying a fast version. Batching 32 throws out of
\ one xorshift64 value passed every check — bit-exact against a naive counter,
\ correct mean, correct standard deviation — and was still wrong, because
\ xorshift64 is F2-linear and those 32 fields are not independent. Only the
\ far tail suffered, by ~50% at 85+, which is the sole region this program
\ cares about. splitmix64 mixes its output and fixes it. `battle-slow` is
\ kept below as the reference the fast one is checked against.

require threads.fs

64 constant LINE                    \ bytes per cache line
16 constant #w                      \ most workers we can start (= nproc here)
231 constant ROLLS                  \ throws per battle

1000000000 value BATTLES            \ battles in total, across all workers
0 value BATTLES_PER_THREAD          \ doit divides BATTLES by the worker count

\ ---------------------------------------------------------------- results
\ One cache line per worker. Two workers sharing a line would trade it back
\ and forth on every write and cost more than the whole simulation.
create num_ones  #w LINE * allot
: nth ( i -- addr )  LINE * num_ones + ;
: .nth ( i -- )      nth @ . ;
: clear_nth ( -- )   #w 0 do  0 i nth !  loop ;
: .some ( n -- )        0 do  i .nth    loop ;
: .n ( -- )          #w .some ;
: best ( n -- max )  0 swap 0 do  i nth @ max  loop ;

\ ---------------------------------------------------------------- the die
\ splitmix64 on whatever cell the caller hands it, so each worker can own its
\ seed. Sharing one seed made 4 threads run 4x SLOWER than 1 — every roll
\ fought for the same cache line.
\
\ This was xorshift64, which is F2-linear: the 64 bits of one output are
\ linear combinations of each other. That is invisible while you use two bits
\ per value, and fatal once you slice one value into 32 rolls — the mean and
\ sd stayed right while the far tail came out ~50% too heavy at 85+, which is
\ the only region this program cares about. splitmix64 advances by a constant
\ and then MIXES, so the bits within one output stand on their own.
\ `$` literals, not [ hex ] … [ decimal ] — the bracket form would leave BASE
\ decimal for whoever loaded this file, whatever base they were working in.
: (mix) ( z -- z' )
    dup 30 rshift xor  $BF58476D1CE4E5B9 *
    dup 27 rshift xor  $94D049BB133111EB *
    dup 31 rshift xor ;
: (next) ( sa -- n )
    dup @  $9E3779B97F4A7C15 +  dup rot !  (mix) ;

: 4roll ( sa -- 1..4 )  (next) 4 mod abs 1+ ;

\ ------------------------------------------------------------- 32 at a time
\ A d4 needs 2 bits, so one 64-bit value holds 32 rolls and we were throwing
\ 62 bits away per roll. We never want the rolls themselves, only how many
\ came up 1 — and a 2-bit field is a 1 exactly when it is 00. So OR each field
\ with itself shifted down, invert, keep the low bit of each field, and count
\ the bits that survive. 231 rolls = 7 whole cells + 7 leftover fields.
: (ones-in) ( x -- n )  dup 1 rshift or invert  $5555555555555555 and  popcount ;

ROLLS 32 /   constant (full)        \ whole cells per battle
ROLLS 32 mod constant (rem)         \ rolls left over
: (mk-mask) ( k -- m )  0 swap 0 do  1 i 2* lshift or  loop ;
(rem) (mk-mask) constant (maskr)
: (ones-r) ( x -- n )  dup 1 rshift or invert (maskr) and popcount ;

\ ---------------------------------------------------------------- seeding
\ Ask the kernel once, at load: read(2) on /dev/urandom. Worker seeds are
\ derived from it, so a run is unpredictable but reproducible — fix SEED with
\ `to SEED` and every worker replays exactly.
create (seedbuf) 8 allot
: os-random ( -- u )
    s" /dev/urandom" r/o bin open-file throw   ( fid )
    >r  (seedbuf) 8 r@ read-file throw         ( u2 )
    8 <> abort" short read from /dev/urandom"
    r> close-file throw
    (seedbuf) @ ;

os-random value SEED
: seed-for ( i -- u )  2654435761 * SEED +  1 or ;

\ Each run moves SEED on, so repeated runs explore new battles instead of
\ replaying the same ones. Setting SEED by hand still replays exactly: the
\ next run is a pure function of the value you put there.
: (bump-seed) ( -- )
    SEED 6364136223846793005 *  1442695040888963407 +  to SEED ;

\ a seed of our own so `roll` works at the prompt, with no worker involved
create seed0  1 cells allot
#w seed-for seed0 !
: roll ( -- 1..4 )  seed0 4roll ;

\ ---------------------------------------------------------------- the work
\ one roll at a time — kept so the fast one has something to be checked against
: battle-slow ( sa -- n )
    0 swap
    ROLLS 0 do  dup 4roll 1 = if swap 1+ swap then  loop
    drop ;

: battle ( sa -- n )
    0 swap
    (full) 0 ?do  dup (next) (ones-in) rot + swap  loop
    (rem) if  (next) (ones-r) +  else  drop  then ;

\ The running max rides this thread's own stack, and num_ones is written once
\ at the very end. Reading the result back each round would put every worker
\ on the same line again.
: escape ( idx -- )
    8 allocate throw                       ( idx sa )
    over seed-for  over !                  ( idx sa )
    0                                      ( idx sa max )
    BATTLES_PER_THREAD 0 do  over battle  max  loop
    rot nth !                              ( sa )
    free throw ;

\ A thread starts with nothing on its stack, so each worker needs its index
\ baked in. Sixteen one-liners, and a table of their xts for doit to pick from.
: 0e   0 escape ;   : 1e   1 escape ;   : 2e   2 escape ;   : 3e   3 escape ;
: 4e   4 escape ;   : 5e   5 escape ;   : 6e   6 escape ;   : 7e   7 escape ;
: 8e   8 escape ;   : 9e   9 escape ;   : 10e 10 escape ;   : 11e 11 escape ;
: 12e 12 escape ;   : 13e 13 escape ;   : 14e 14 escape ;   : 15e 15 escape ;

create workers
    ' 0e ,  ' 1e ,  ' 2e ,  ' 3e ,  ' 4e ,  ' 5e ,  ' 6e ,  ' 7e ,
    ' 8e ,  ' 9e , ' 10e , ' 11e , ' 12e , ' 13e , ' 14e , ' 15e ,
: worker ( i -- xt )  cells workers + @ ;

create handles #w cells allot
: hn ( i -- addr )  cells handles + ;

\ ---------------------------------------------------------------- run it
\ doit does its own timing: `time` parses one word name, so `time 4 doit`
\ would try to time a word called `4`.
: .secs ( ms -- )  s>d <# # # # [char] . hold #s #> type ."  s" ;

\ `thread` returns a handle AND an ior; `join` a result AND a status. Dropping
\ either is how a benchmark lies to you: a worker that never started leaves its
\ slot 0, so the run reports a lower best and a faster time, and looks fine.
\ Start everything, join everything, report at the end — never bail on the
\ first error, or the threads already running are left with nobody to free
\ them. This is the pattern `tutorial Concurrency` builds step by step.
0 value failed
: (note) ( ior -- )   failed if drop exit then  to failed ;
: (wait) ( t -- )     dup 0= if drop exit then  join (note) (note) ;

: (spawn-join) ( #threads -- )
    0 to failed
    dup 0 do  i worker thread (note)  i hn !  loop
        0 do  i hn @ (wait)              loop ;

: doit ( #threads -- )
    dup 1 #w 1+ within 0= abort" doit: worker count must be 1..#w"
    BATTLES over /  to BATTLES_PER_THREAD
    clear_nth
    dup . ." workers, " BATTLES_PER_THREAD . ." battles each ("
    dup BATTLES_PER_THREAD * . ." total)" cr
    dup >r  ms@ >r
    (spawn-join)
    ms@ r> -                       ( ms )
    failed throw                   \ a broken run reports no numbers at all
    ."   " .secs cr
    (bump-seed)                    \ safe here: every worker has been joined
    ."   " r> dup .some cr
    best ." Best: " . ;

\ ---------------------------------------------------------------- demo
\ A small run when this file is executed. Raise BATTLES for a real hunt:
\ a billion battles takes about 40 seconds on 8 cores.
\ No `bye`: run it as a script and you land at the prompt with everything
\ loaded, ready to type a bigger run; `require dice.fs` from a session behaves
\ the same way instead of ending it.
1000000 to BATTLES
cr ." 231 throws of a d4; how many 1s at best?" cr
4 doit
cr ." Now try:  1000000000 to BATTLES   16 doit" cr
