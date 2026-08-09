# Concurrency — Put the Other Cores to Work

Your machine has more than one core. So far BasicForth has used exactly one of
them. This lesson takes a job that takes a while, splits it across threads, and
times both — so you can see the difference rather than take it on faith. About
fifteen minutes, typing as you go.

This is a *lesson*: short steps, one idea each. After each step you're back at
the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## A job worth splitting

Threads are only worth it when there's real work to divide. Counting primes by
trial division suits us perfectly: lots of arithmetic, and each number can be
tested without knowing anything about the others.

    require threads.fs
    200000 value LIMIT

Threads are not in the startup image — `require` loads them. Type `next`.

## Is it prime?

    : prime? ( n -- f )
        dup 2 <  if drop false exit then
        dup 2 =  if drop true  exit then
        dup 1 and 0= if drop false exit then
        3
        begin  dup dup * 2 pick <=
        while  2dup mod 0= if 2drop false exit then
               2 +
        repeat 2drop true ;

    7 prime? .        \ -1  (true)
    9 prime? .        \ 0   (false)

It divides by odd numbers until the divisor squared passes `n`. Note the third
line: even numbers are thrown out immediately, without dividing by anything.
That detail comes back to bite us later.

## Count them, one core at a time

One counting word serves the whole lesson. It walks from `start` in steps of
`step`, counting primes below `LIMIT`:

    : (count) ( start step -- n )
        >r  0 swap
        begin  dup LIMIT < while
            dup prime? if  swap 1+ swap  then
            r@ +
        repeat  drop  r> drop ;

The count rides on the **stack**, not in a variable — that matters later.

## Count them, and time it

Counting every odd number from 3 gives every prime except 2, which we leave
out to keep the splitting tidy:

    : serial ( -- n )  3 2 (count) ;
    serial .          \ 17983

    : s  serial drop ;
    time s

You'll see something like `0.050 s`. Note your number — everything from here
is measured against it.

If yours is much faster or slower, that's fine; only the *ratio* matters —
we'll make the job bigger at the end and check that the ratio survives.

## Two workers

Each worker needs its own counter and its own place to start. Name them with
`value` so we can re-aim them without rewriting the workers:

    2 value stride
    3 value n0    4 value n1
    0 value c0    0 value c1
    0 value t0    0 value t1
    : w0  n0 stride (count) to c0 ;
    : w1  n1 stride (count) to c1 ;

A `value` says what it holds from the moment it exists — the workers are aimed
at every second number already. Reading one takes no `@`, and `to` sets it.

Each worker writes **its own** counter, exactly once, at the end. Type `next`.

## Don't drop the errors

`thread` hands back a handle **and** an ior. `join` hands back the worker's
result **and** a status. Throw those away and a thread that never started
looks exactly like one that finished: you still get a total, and it is wrong.

The tempting fix is to stop at the first error. Don't — by then the other
threads are already running, and abandoning them leaves them running with
nothing left to free them.

**Start everything, join everything, and report at the end.** Type `next`.

## Helpers that remember

    0 value failed
    : (note) ( ior -- )  failed if drop exit then  to failed ;
    : spawn  ( xt -- t )  thread (note) ;
    : wait   ( t -- )     dup 0= if drop exit then  join (note) (note) ;

`(note)` keeps the *first* error and ignores the rest. `spawn` keeps the
handle and remembers the ior. `wait` skips a handle of 0 — a thread that never
started — and checks both halves of what `join` gives back.

## Start two, join two

Now the driver. Every start is matched by a wait, and only then do we look at
whether anything went wrong:

    : run2 ( -- n )
        0 to failed
        ' w0 spawn to t0   ' w1 spawn to t1
        t0 wait   t1 wait
        failed throw
        c0 c1 + ;

    run2 .        \ 17983

It runs right now, because the workers were aimed the moment they were
defined.

## Deal the numbers out

The obvious split: one worker takes every second number starting at 3, the
other every second number starting at 4. That is the deal the values already
hold; naming it lets us put it back later.

    : naive2  3 to n0  4 to n1  2 to stride ;
    naive2  run2 .        \ 17983

Same answer as `serial` — the split is correct. Now time it:

    : p2  run2 drop ;
    time p2

## Correct, and no faster

Two threads, and the clock barely moved. The work was split; the *effort* was
not.

Look again at what each worker got. `n0` starts at 3 and steps by 2 — every
odd number. `n1` starts at 4 and steps by 2 — every **even** number. And
`prime?` throws an even number out on its second line, before dividing by
anything.

So one worker did all the real work and the other raced through nothing. Two
threads, one core's worth of effort. Type `next`.

## Deal only the odd numbers

Give each worker odd numbers by stepping over the evens entirely: start at 3
and 5, step by 4.

    : odds2  3 to n0  5 to n1  4 to stride ;
    odds2  run2 .         \ 17983
    time p2

Same answer, about half the time. The lesson generalises past primes: an even
split of the *input* is not an even split of the *work*.

## Two more workers

Same shape again — each with its own start, its own counter, its own handle:

    0 value n2    0 value n3
    0 value c2    0 value c3
    0 value t2    0 value t3
    : w2  n2 stride (count) to c2 ;
    : w3  n3 stride (count) to c3 ;

Nothing here is shared between workers. That is the whole trick. Type `next`.

## Run all four

    : run4 ( -- n )
        0 to failed
        ' w0 spawn to t0   ' w1 spawn to t1
        ' w2 spawn to t2   ' w3 spawn to t3
        t0 wait  t1 wait  t2 wait  t3 wait
        failed throw
        c0 c1 + c2 + c3 + ;

Starts 3, 5, 7, 9 stepping by 8 — four interleaved runs of odd numbers:

    : odds4  3 to n0  5 to n1  7 to n2  9 to n3  8 to stride ;
    : p4  run4 drop ;
    odds4  run4 .         \ 17983
    time p4

## What just happened

Four threads, roughly a quarter of the time — the same answer, sooner. On the
machine this lesson was written on, counting to two million:

    \ 1 thread   1.157 s
    \ 2 threads  0.596 s   1.94x
    \ 4 threads  0.305 s   3.79x
    \ 8 threads  0.163 s   7.10x

Two things made that possible, and both were choices:

- every worker had **its own counter**, so no two threads ever wrote the same
  cell
- every worker accumulated **on its own stack** and stored once at the end

Both of those come back in a moment. First, does it hold at scale? Type `next`.

## Make the job bigger

`LIMIT` is a `value`, so it can change without recompiling anything —
`(count)` reads it afresh every time round the loop:

    2000000 to LIMIT
    time s
    time p4

Ten times the work. The serial run grows to about a second, the four-thread
run to about a quarter of that — the **ratio holds**, and thread setup matters
even less than before. Bigger jobs parallelise better, which is the whole
reason to reach for threads at all.

## Sharing, and how to get it wrong

Threads share all of memory. One `value` — or one `variable` — is visible to
every thread, which is how the counters come back.

That also means two threads writing the same one will lose data. Adding to a
shared total is the classic way to get bitten, because *add* is not one step:
it reads, adds, and writes, and another thread can slip in between the read
and the write. Both spellings have the flaw:

    \ DON'T: two workers, one total
    \ : w0  ... total +! ;          \ variable
    \ : w1  ... 1 +to total ;       \ value — same race, fewer clues

`+to` is the more dangerous of the two only because it looks like a single
act. Neither is atomic; nothing in Forth makes them so.

Counts vanish, and never the same ones twice. Give each worker its own cell
and add them up after `join`, as we did. Channels will make sharing safe
later; until then, one writer per cell.

## The other rule

A worker runs words that are **already compiled**. Inside a thread, don't use
`:`, `create`, `save`, or an interpret-time `s"` — the dictionary is shared
and unprotected. Define first, then run:

    threads

That lists any threads you started and haven't joined yet. Ours are all
joined, so it should say `(no threads)`. If you ever drop a handle, `threads`
is how you get it back — nothing else can free that thread's stacks.

## Where to go next

Try more workers than four. `nproc` tells you how many hardware threads you
have — but `lscpu -e` shows which of them share a physical core, and that is
where the gains stop. Past your real core count the curve flattens.

- `help concurrency` — `thread`, `join`, `threads` in full
- `help exceptions` — a worker's `throw` comes back as `join`'s result
- `docs/Threading.md` — how a Forth word gets onto an OS thread at all

Type `end-tutorial` to finish. Your definitions stay.
