\ BasicForth threads.fs -- OS threads via pthreads (require threads.fs)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded on demand, NOT at startup. See docs/Threading.md for the design.
\
\   thread  ( xt -- t ior )        run xt in a new OS thread; t is its handle
\   join    ( t -- result status ) wait for it, free its stacks, report
\   threads ( -- )                 list the live threads
\
\ The handle t is the thread's context block, not the raw pthread id: join has
\ to free the stacks, and it cannot find them from a bare tid.
\
\ THE RULE: the REPL thread owns the dictionary. A worker runs already-compiled
\ words -- no `:`, no `create`, no interpret-time `s"`, no `save`/`load`. It
\ computes, does I/O on file descriptors it owns, and talks to the main thread
\ through shared memory. BASE, depth/.s and catch/throw are per-thread and work
\ normally (see the TLS block in core.s).

require ffi.fs

s" libc.so.6" dlopen value (libc)
(libc) s" pthread_create" dlsym value (pthread-create)
(libc) s" pthread_join"   dlsym value (pthread-join)

\ --- context block: layout MUST match forth_thread_tramp in core.s ---
\   0 xt   8 dtop   16 rtop   24 ior   32 tid   40 state   48 next
64 constant (t-ctx)                         \ bytes of context block

\ One allocation holds both stacks and the context, so one free returns it all,
\ laid out deliberately:
\
\     [ data stack ][ return stack ][ context ]
\      t          dtop            rtop/ctx
\
\ Both stacks grow DOWN, so they grow away from the context. That matters
\ because the context carries the tid join needs; if the context sat below a
\ stack, an overflowing worker would corrupt it. (The trampoline keeps its
\ return path in TLS for the same reason.) A worker that overflows its data
\ stack instead walks down past the allocation base into unmapped memory and
\ faults. Sizes are fixed in v1 and there are still no guard pages -- those
\ need a thread-aware SIGSEGV handler, which is its own step.
8192  constant thread-dstack                \ bytes of data stack per worker
65536 constant thread-rstack                \ bytes of return stack per worker

\ The context sits above both stacks, 16-aligned; the return stack top is the
\ same address, so the C ABI's 16-byte alignment holds on entry.
: (t>ctx)   ( t -- ctx )  thread-dstack + thread-rstack + 15 + -16 and ;
: (t-dtop)  ( ctx -- a )   8 + ;
: (t-rtop)  ( ctx -- a )  16 + ;
: (t-ior)   ( ctx -- a )  24 + ;
: (t-tid)   ( ctx -- a )  32 + ;
: (t-state) ( ctx -- a )  40 + ;
: (t-next)  ( ctx -- a )  48 + ;

1 constant running                          \ ctx.state values; the trampoline
2 constant finished                         \   publishes `finished` itself

\ --- the registry -------------------------------------------------------
\ Live handles, newest first, linked through the context blocks themselves so
\ there is nothing extra to allocate or free. `thread` links, `join` unlinks.
\
\ No mutex: the list is mutated only by the REPL thread. That extends the rule
\ this file already states -- the REPL owns the dictionary, and it owns the
\ thread registry too. (A worker calling `thread` or `join` is outside the
\ rules.) The state cell is different: a worker writes it and the REPL reads
\ it, so it is a single aligned cell, written with release semantics by the
\ trampoline. See docs/Threading.md.
variable (t-head)

: (t-link) ( t -- )                         \ push onto the registry
    dup (t>ctx) (t-next)  (t-head) @ swap !
    (t-head) ! ;

: (t-known?) ( t -- f )                     \ is this handle live? guards join
    (t-head) @
    begin  dup while                        ( t p )
        2dup = if  2drop true exit  then
        (t>ctx) (t-next) @
    repeat  2drop false ;

: (t-unlink) ( t -- )                       \ drop it from the registry
    (t-head) @ over = if                    ( t )
        dup (t>ctx) (t-next) @ (t-head) !  drop exit  then
    (t-head) @                              ( t p )
    begin  dup while
        2dup (t>ctx) (t-next) @ = if        \ p's successor is t
            dup (t>ctx) (t-next)            ( t p a )
            rot (t>ctx) (t-next) @ swap !   ( p )
            drop exit  then
        (t>ctx) (t-next) @
    repeat  2drop ;

: thread ( xt -- t ior )
    thread-dstack thread-rstack + (t-ctx) + 16 + allocate
    if  2drop  0 -59  exit  then            ( xt t )
    dup (t>ctx)                             ( xt t ctx )
    rot over !                              ( t ctx )   \ xt at ctx+0
    over thread-dstack + over (t-dtop) !    ( t ctx )   \ data stack top
    dup over (t-rtop) !                     ( t ctx )   \ return stack top = ctx
    0 over (t-ior) !
    0 over (t-next) !
    running over (t-state) !                \ before create: the worker may
                                            \   publish `finished` immediately
    over (t-link)
    dup (t-tid)  0  (thread-tramp)  3 pick  4 (pthread-create) (ccall)  ( t ctx ior )
    ?dup if                                 \ create failed: unlink, no leak
        nip  over (t-unlink)  swap free drop  0 swap  exit  then
    drop 0 ;                                ( t 0 )

\ JOIN ( t -- result status )
\   status 0  -- the join worked; result is the worker's own throw code, 0 if
\                it ran to completion
\   status /=0 -- the join itself failed; result is 0
\ The two are separate because they mean different things: a worker throwing 35
\ is your program's logic, while a join failing with EDEADLK 35 is a bug in how
\ the threads are being used. A single ior could not tell them apart.
\
\ Join exactly once per handle. A successful join frees the block, so the
\ handle is dead afterwards -- and the registry lookup below is what turns a
\ second join from a crash into an honest error.
\ Status codes: 0 is success, a POSITIVE value is the system's errno straight
\ from pthread (EDEADLK 35, EINVAL 22, ...), and a NEGATIVE value is ours. The
\ sign tells you which layer complained.
-60 constant bad-handle                     \ not a live handle: spent, or never was

: join ( t -- result status )
    dup (t-known?) 0= if  drop 0 bad-handle exit  then
    dup (t>ctx)                             ( t ctx )
    dup (t-tid) @  0  2 (pthread-join) (ccall)         ( t ctx status )
    ?dup if                                 ( t ctx status )
        \ The join FAILED. Do not free: the worker may still be running and its
        \ stacks are inside this very block, so freeing would unmap memory a
        \ live thread is executing on. A leak is recoverable; a use-after-free
        \ is not.
        \
        \ Not freeing is NOT the same as the handle still being good. Only
        \ EDEADLK (a thread joining itself) guarantees the block is alive.
        \ EINVAL usually means someone else is already joining -- their join
        \ will free it -- and after ESRCH the tid may have been recycled onto an
        \ unrelated thread. So a failed join leaks by design and the caller that
        \ failed must not retry.
        \
        \ The handle stays IN the registry, though. The realistic failure is
        \ EDEADLK -- some thread joined the wrong handle, its own -- and the
        \ rightful owner still has to be able to join and reclaim. Unlinking
        \ here would turn one caller's mistake into a thread nobody can ever
        \ join.
        >r  2drop  0 r>  exit  then         ( t ctx )
    (t-ior) @                               ( t result )
    over (t-unlink)
    swap free drop                          ( result )
    0 ;                                     ( result 0 )

\ THREADS ( -- )  list the live threads, newest first.
\ The state is read with (acq@), an ACQUIRE load, pairing with the store-release
\ the trampoline uses to publish it. Both halves matter: with a plain fetch here
\ ARM64 could hoist the result load above the state load and print the initial 0
\ for a worker that actually threw. With the pair, `finished` implies the result
\ beside it is the real one.
: (.handle) ( t -- )                        \ addresses read as hex, whatever
    base @ >r  hex  12 u.0r  r> base ! ;    \   base the user is working in

: threads ( -- )
    (t-head) @ 0= if  ." (no threads)" cr  exit  then
    ." handle        state     result" cr
    (t-head) @
    begin  dup while                        ( p )
        dup (.handle)  ."   "
        dup (t>ctx) (t-state) (acq@) finished = if
            ." finished  "  dup (t>ctx) (t-ior) @ .
        else
            ." running   -"
        then  cr
        (t>ctx) (t-next) @
    repeat  drop ;
