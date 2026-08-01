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
    : go    ['] work thread drop join 2drop  c @ . ;
    go                \ 1000

A worker runs **already-compiled** words only: no `:`, no `create`, no
interpret-time `s"`, no `save`/`load`. Define first, then run — `help
concurrency` explains why.

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
    : go    ['] t35 thread drop join . . ;   \ prints status, then result
    go                \ 0 35    — status 0: the join was fine.
                      \           result 35: what the worker threw.

Check `status` first — it is on top — and only read `result` when it is 0.

Status codes follow their source: **positive** values are the system's `errno`
(`EDEADLK` 35, `EINVAL` 22), **negative** ones are BasicForth's. The one you
are likely to meet is `-60`, a spent or unknown handle.

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
the prompt in decimal.

Those stacks are **fenced**: run off either end — too deep a recursion, or one
`drop` too many — and the thread dies at once rather than quietly reading and
writing its other stack. The whole process goes down with it, which is loud and
obvious; that is the intent. Worker stacks are a fixed size and do not grow.

    : w   hex ;
    : go  ['] w thread drop join 2drop  base @ . ;
    go                \ 10

## Errors come back as a value
A worker that throws does not reset the prompt — it ends that thread, and the
code comes back as `join`'s `result`. So a worker failing is something you
handle, not a session you lose.

    : boom  42 throw ;
    : go    ['] boom thread drop join drop . ;
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
