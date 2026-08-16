# Concurrency

Run a Forth word on a real OS thread, alongside the prompt. Load it first —
threads are not part of the startup image:

    require threads.fs

At a glance:

    thread  ( xt -- t ior )         run xt on a new OS thread; t is its handle
    join    ( t -- result status )  wait for it, free its stacks, report
    threads ( -- )                  list the live threads

## thread ( xt -- t ior )
Start a new OS thread running `xt`. Returns a handle and an `ior` — 0 on
success. The handle is the thread's context block, not the raw thread id,
because `join` has to free the thread's stacks and cannot find them from an id
alone.

    require threads.fs
    variable c
    : work  1000 0 do 1 c +! loop ;
    : go    ['] work thread throw  join throw throw  c @ . ;
    go                \ 1000

`thread throw` rather than `thread drop`: `throw` passes a 0 ior through and
stops on anything else. Dropping it instead means a thread that never started
looks just like one that finished — you get an answer, and it is wrong.

Throwing straight out like that is fine for **one** thread. With several, it is
a trap: a throw on the third `thread` walks away from the two already running,
and nothing is left to join them or free their stacks. Start them all, join
them all, and report afterwards — `tutorial Concurrency` builds that pattern.

A worker runs **already-compiled** words only: no `:`, no `create`, no
interpret-time `s"`, no `save`/`load`. Define first, then run —
`help concurrency` explains why.

## join ( t -- result status )
Wait for the thread to finish, release its stacks, and report. Two values,
because two different things can go wrong:

    status = 0    the join worked; result is the worker's own throw code
                  (0 if it ran to completion)
    status ≠ 0    the join itself failed; result is 0

That split matters. A worker throwing `35` is your program's logic; a join
failing with `EDEADLK 35` is a bug in how you are using threads. One combined
code could not tell them apart.

    : t35   35 throw ;
    : go    ['] t35 thread throw  join . . ;  \ prints status, then result
    go                \ 0 35    — status 0: the join was fine.
                      \           result 35: what the worker threw.

Check `status` first — it is on top — and only read `result` when it is 0.

Status codes follow their source: **positive** values are the system's `errno`
(`EDEADLK` 35, `EINVAL` 22), **negative** ones are BasicForth's. The one you
are likely to meet is `bad-handle`, a spent or unknown handle.

## bad-handle ( -- n )
The `join` status for a handle that is not live — already joined, or never was
a handle. `-60`, but compare by name:

    : try ( t -- )
        join                            ( result status )
        dup bad-handle = if  ." already joined" cr 2drop
        else                 throw  .   ( the worker's throw code )  then ;

    ' w thread throw value t
    t try             \ 0    — ran to completion
    t try             \ already joined

It is the one status you can provoke by mistake rather than by system failure,
since joining twice is an easy slip and the second call must not touch the
memory the first one freed.

Every thread must be joined — nothing else frees its memory — and joined
**exactly once**. A second join is caught and reported as `-60` rather than
touching freed memory.

A failed join frees nothing, because the worker may still be running on the
stacks inside the block, so the memory leaks by design. Do not retry it. The
handle stays registered, though, so if some *other* thread joined it by
mistake, the rightful owner can still reclaim it.

## threads ( -- )
List the threads you have started and not yet joined, newest first.

    threads
    handle        state     result
    77F66C644008  finished  0
    77F66C632008  running   -

`running` means the word is still executing. `finished` means it has returned
and its result is waiting — but the memory is **not** reclaimed until you
`join` it, which is exactly what the listing is for: see what is done, join it,
watch it leave the list.

    threads           \ (no threads)   when nothing is outstanding

Once a thread reads `finished`, its `result` is the real one — the listing and
`join` will agree. (What you cannot rely on is the *timing*: a thread listed as
`running` may finish a moment later.)

## Private stacks, one per worker
A worker does not share the prompt's stacks. It is handed a fresh data stack
and return stack, so `depth` inside a worker starts at 0 and its arithmetic
cannot disturb yours. `BASE` is per-thread too — a worker calling `hex` leaves
the prompt in decimal — and so is `seed`, so `random` and `rnd` give every
worker an independent sequence (`help random`).

**The locals stack is per-thread as well**, which is what makes `{: … :}` safe
to call from several workers at once: each has its own frames, so a `|` local
is genuinely private scratch space where a shared `variable` would race
(`help locals`).

`seed` earns its place there twice over. Shared, it was not merely slow but
**wrong**: `random` reads the cell, mixes, and writes it back, and two threads
doing that without atomicity walk one interleaved sequence and lose each
other's updates — measured, 1707 of one worker's 2000 draws also appeared in
the other's. It was slow as well, because a cache line cannot be written by
two cores at once: four threads ran four times slower than one, with no lock
anywhere in sight.

Those stacks are **fenced**: run off either end — too deep a recursion, or one
`drop` too many — and the thread dies at once rather than quietly reading and
writing its other stack. The whole process goes down with it, which is loud and
obvious; that is the intent. Worker stacks are a fixed size and do not grow.

    : w   hex ;
    : go  ['] w thread throw  join throw throw  base @ . ;
    go                \ 10

## thread-dstack thread-rstack ( -- n )
The size in bytes of a worker's data stack and return stack — 8192 and 65536
as shipped. `constant`s, read when `thread` allocates: they describe what a
worker gets, and changing them is a source edit, not a `to`.

Worth knowing when a worker recurses deeply, since the fence turns an overrun
into an immediate death rather than corruption. The return stack is the larger
of the two because that is the one recursion consumes.

## Errors come back as a value
A worker that throws does not reset the prompt — it ends that thread, and the
code comes back as `join`'s `result`. So a worker failing is something you
handle, not a session you lose.

    : boom  42 throw ;
    : go    ['] boom thread throw  join drop . ;
    go                \ 42

`catch` works normally inside a worker, so a thread can handle its own errors
and only report what it chooses to.

## The rule: the prompt owns the dictionary
Workers run **already-compiled** words. Inside a thread, do not use `:`,
`create`, interpret-time `s"`, `save` or `load` — the dictionary, `here` and
the string buffers are shared and unprotected. Define your words first, then
run them on a thread.

This is a documented rule, not an enforced one — a sharp tool with a stated
grip, like `cmove`'s overlap direction.

## Sharing data
Threads share one address space, so a `variable` is visible to all of them,
which is how the examples above report their results. That also means two
threads writing the same cell race. Keep it simple: give each worker its own
cells to write, and read them after `join`.

## See Also

- `help exceptions` — `catch`/`throw`, which work per-thread here.
- `docs/Threading.md` — the design: trampoline, TLS, and what is still open.
