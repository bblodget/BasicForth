#!/usr/bin/env basicforth
\ BasicForth — dice, a threaded Monte Carlo simulation
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Throw a 4-sided die 231 times and count how many 1s come up. That is one
\ "battle". Run a billion battles and ask: what is the most 1s you ever saw?
\
\ ---------------------------------------------------------------------------
\ Where this comes from: Pokémon soft-lock picking. A run can strand itself
\ with no way forward except a specific string of luck in one long battle —
\ 231 turns, and the escape needs 177 of them to go your way, each a 1-in-4
\ chance. The question the video asks is whether brute force can find it, with
\ a Python script that rolls 231 d4s a million times and reports its best:
\
\     while numbers[0] < 177 and rolls < 1000000:   \ it never gets there
\
\ It never gets there, and neither will this. P(177 or better) is 1.2e-60 —
\ one battle in 8.3e59. This program manages 3.5e7 battles a second on 8 cores,
\ so expecting a single hit takes 7.5e44 years, about 5e34 times the age of
\ the universe. The script's million battles typically peak around 91.
\
\ That is the honest answer to the challenge, and it is what makes this a good
\ benchmark rather than a good search: the target is unreachable, the work is
\ embarrassingly parallel, and every core you add buys real throughput against
\ a number that will not move. The mean is 57.75 and a standard deviation is
\ 6.58, so ~100 is already 6.5 sigma out; 100x the battles buys about 3 more.
\
\ The video reports a billion battles taking the Python script about 8 DAYS.
\ This does a billion in 28 seconds on a laptop — 8 cores, 16 threads. All
\ measured, on the same size of job:
\
\     python, per the video      1,447 battles/s
\     one worker here        2,824,021 battles/s      1,950x
\     16 workers            35,335,689 battles/s     24,400x
\
\ Note where that comes from. Threads are worth 12.5x of it — good scaling
\ for 8 cores, since SMT is real but not a second core. The other 1,950x is
\ one worker against one Python process: compiled Forth instead of an
\ interpreter, and the two tricks below, of which packing 32 rolls into one
\ draw is worth ~20x on its own for three lines of code.
\
\ Which is the lesson. Threading is the multiplier everyone reaches for first
\ and the smallest one here.
\
\ Video: https://www.youtube.com/watch?v=M8C8dHQE2Ro
\ ---------------------------------------------------------------------------
\
\ What `Best` should come out as. Exact binomial(231, 1/4), so it is what the
\ program is supposed to find, not a measurement of this one:
\
\     BATTLES        typical   usual     look into it outside
\     100 thousand      88     86–90            84–97
\     1 million         91     89–94            88–100
\     10 million        94     93–97            91–102
\     100 million       97     96–100           94–105
\     1 billion        100     99–102           97–107
\     10 billion       103     101–105          100–109
\
\ `Best` is a maximum, so it jumps around. Landing outside the "usual" column
\ is UNREMARKABLE — it happens somewhere between 1 run in 6 and 1 run in 17,
\ depending on the row (`Best` is a whole number, so these bands snap outward
\ to integers and are wider than the 80% they are built from). Only the last
\ column is diagnostic: chance puts a run outside it about once in a thousand.
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
\ Three things make it fast, in descending order of how much they matter:
\
\   1. Nothing is shared between workers. Each has its own `seed` (thread-local
\      already) and its own cache line for the result, written once at the end.
\      Sharing one seed made 4 threads run 4x SLOWER than 1 — no locking
\      involved, just one cache line two cores both wanted.
\   2. A d4 needs 2 bits, so one 64-bit `random` holds 32 throws, and
\      `popcount` counts the 1s in all 32 at once. Worth ~20x.
\   3. Threads, worth 12.5x on 8 cores (16 threads) — the least of the three,
\      and the only one most people would think of.
\
\ `battle-slow` is kept as the obvious version the fast one is checked against.

require threads.fs

64 constant LINE                    \ bytes per cache line
16 constant #w                      \ most workers we can start. nproc counts
                                    \ LOGICAL cpus, so this is 8 cores x SMT --
                                    \ 16 workers really is the useful maximum
                                    \ here, but they are not 16 cores' worth
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
\ `random` is splitmix64 and `seed` is thread-local, so a worker just calls it:
\ its own stream, its own cell, nothing to allocate. This file used to carry
\ its own splitmix64 because the built-in was xorshift64 -- F2-linear, and so
\ wrong for the trick below of slicing one value into 32 rolls. That moved
\ into the core (see `help random`), and ~20 lines left this file with it.
: roll ( -- 1..4 )  4 rnd 1+ ;

\ ------------------------------------------------------------- 32 at a time
\ A d4 needs 2 bits, so one 64-bit value holds 32 rolls and we were throwing
\ 62 bits away per roll. We never want the rolls themselves, only how many
\ came up 1 — and a 2-bit field is a 1 exactly when it is 00. So OR each field
\ with itself shifted down, invert, keep the low bit of each field, and count
\ the bits that survive. 231 rolls = 7 whole cells + 7 leftover fields.
: (ones-in) ( x -- n )
    dup 1 rshift or invert  $5555555555555555 and  popcount ;

ROLLS 32 /   constant (full)        \ whole cells per battle
ROLLS 32 mod constant (rem)         \ rolls left over
: (mk-mask) ( k -- m )  0 swap 0 do  1 i 2* lshift or  loop ;
(rem) (mk-mask) constant (maskr)
: (ones-r) ( x -- n )  dup 1 rshift or invert (maskr) and popcount ;

\ ---------------------------------------------------------------- seeding
\ One number from the kernel at load; every worker's seed is derived from it,
\ so a run is unpredictable but reproducible — `to RUN-SEED` and every worker
\ replays exactly. `entropy` is the whole of what used to be a dozen lines of
\ open/read/close on /dev/urandom.
\
\ Named RUN-SEED, not SEED, because the dictionary is CASE-INSENSITIVE: a
\ `value SEED` here would silently redefine the core `seed` (this file did
\ exactly that for months, harmlessly, until it started using it). Loading
\ from a file prints no warning — the redefinition notice is interactive-only.
: os-random ( -- u )  entropy if drop ms@ then ;
os-random value RUN-SEED
: seed-for ( i -- u )  2654435761 * RUN-SEED + ;

\ Each run moves RUN-SEED on, so repeated runs explore new battles instead of
\ replaying the same ones. Setting RUN-SEED by hand still replays exactly: the
\ next run is a pure function of the value you put there.
: (bump-seed) ( -- )
    RUN-SEED 6364136223846793005 *  1442695040888963407 +  to RUN-SEED ;

\ ---------------------------------------------------------------- the work
\ one roll at a time — kept so the fast one has something to be checked against
: battle-slow ( -- n )
    0  ROLLS 0 do  roll 1 = if 1+ then  loop ;

: battle ( -- n )
    0  (full) 0 ?do  random (ones-in) +  loop
    (rem) if  random (ones-r) +  then ;

\ The running max rides this thread's own stack, and num_ones is written once
\ at the very end. Reading the result back each round would put every worker
\ on the same line again.
\
\ Setting this thread's own `seed` from the index is what makes a run
\ reproducible — every worker starts kernel-seeded and unpredictable
\ otherwise, which is right for a game and wrong for a benchmark you want to
\ repeat.
: escape ( idx -- )
    dup seed-for  seed !                   ( idx )
    0                                      ( idx max )
    BATTLES_PER_THREAD 0 do  battle max  loop
    swap nth ! ;

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
\ a billion battles takes about 28 seconds on 8 cores (16 threads).
\ No `bye`: run it as a script and you land at the prompt with everything
\ loaded, ready to type a bigger run; `require dice.fs` from a session behaves
\ the same way instead of ending it.
1000000 to BATTLES
cr ." 231 throws of a d4; how many 1s at best?" cr
4 doit
cr ." Now try:  1000000000 to BATTLES   16 doit" cr
