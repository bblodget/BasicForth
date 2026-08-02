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

\ One allocation holds both stacks and the context, so one free returns it all.
\ The stacks are FENCED: a PROT_NONE page sits below the data stack, between the
\ two stacks, and above the return stack.
\
\     [guard][ data stack ][guard][ return stack ][guard][ context ]
\
\ Both stacks grow down. Without the fences a worker that overflowed its return
\ stack walked silently into its own data stack, and a data stack popped past
\ empty walked into the return stack -- wrong answers, no crash, nothing to
\ debug. With them every direction hits a dead page and dies loudly: the
\ SIGSEGV handler only recovers faults inside the MAIN thread's guard pages, so
\ any other address re-raises with the default handler and dumps core.
\ The context sits above the top fence, out of reach of both stacks.
4096  constant (t-page)
8192  constant thread-dstack                \ bytes of data stack per worker
65536 constant thread-rstack                \ bytes of return stack per worker

: (t-pgup)  ( a -- a' )  (t-page) 1- + (t-page) negate and ;   \ round up to a page

\ Everything is measured from the first page boundary at or above the handle.
: (t>g0)    ( t -- a )  (t-pgup) ;                      \ fence below the data stack
: (t>dlow)  ( t -- a )  (t>g0) (t-page) + ;
: (t>dtop)  ( t -- a )  (t>dlow) thread-dstack + ;      \ DSP starts here
: (t>g1)    ( t -- a )  (t>dtop) ;                      \ fence between the stacks
: (t>rlow)  ( t -- a )  (t>g1) (t-page) + ;
: (t>rtop)  ( t -- a )  (t>rlow) thread-rstack + ;      \ SP starts here
: (t>g2)    ( t -- a )  (t>rtop) ;                      \ fence above the return stack
: (t>ctx)   ( t -- ctx )  (t>g2) (t-page) + ;
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

\ Fence the three boundary pages, returning 0 or the first errno. Written as
\ its own word because the handle has to survive all three calls -- computing
\ the second and third guard from whatever happened to be under `over` was a
\ bug that fenced the wrong pages and left the stacks open.
: (t-fence) ( t -- ior )
    dup (t>g0) (t-page) (prot-none)          ( t ior )
    over (t>g1) (t-page) (prot-none) or      ( t ior )
    swap (t>g2) (t-page) (prot-none) or ;    ( ior )

: thread ( xt -- t ior )
    (t-page) 4 * thread-dstack + thread-rstack + (t-ctx) + allocate
    if  2drop  0 -59  exit  then            ( xt t )
    dup (t>ctx)                             ( xt t ctx )
    rot over !                              ( t ctx )   \ xt at ctx+0
    over (t>dtop) over (t-dtop) !           ( t ctx )   \ fenced regions
    over (t>rtop) over (t-rtop) !           ( t ctx )
    0 over (t-ior) !
    0 over (t-next) !
    running over (t-state) !                \ before create: the worker may
                                            \   publish `finished` immediately
    over (t-link)
    \ Fence the three boundary pages. If mprotect fails the thread would run
    \ unfenced, which is the very thing this prevents -- so refuse to start it.
    over (t-fence)                          ( t ctx ior )
    ?dup if  >r drop dup (t-unlink) free drop  0 r>  exit  then
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
