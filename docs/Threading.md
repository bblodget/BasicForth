# Threading — Design Notes

Status: **design only, nothing implemented** (2026-07-22). Real concurrency
for BasicForth: audio feeders, robot control loops at fixed Hz, socket
readers — the Phase 8 item, given a concrete shape. Supersedes the
"pthreads or clone?" question in TODO Phase 8: **pthreads, via the FFI.**

## Decision: FFI + pthreads (not raw clone)

- The binary is already dynamically linked for the FFI, and since glibc
  2.34 `pthread_create` lives in libc itself — the dependency is already
  on board.
- Raw `clone` means hand-rolling child stack setup, thread exit, and
  futex-based join on two architectures — weeks of subtle bugs to avoid a
  library we already load. pthreads brings create/join/mutex/cond for free.
- SDL already spawns threads inside this process (see the `SYS_exit_group`
  fix — `bye` uses exit_group precisely so all threads die), so the
  runtime demonstrably tolerates being multi-threaded.
- This is the "leverage Linux, use select libraries" philosophy applied to
  concurrency. Bare metal is not a live constraint.

## The real work: the trampoline

`pthread_create` starts the new thread as a **C function on a C stack**,
with none of the Forth machine state — no DSP register, no data stack, no
return-stack convention. So the heart of the feature is a small per-arch
assembly trampoline (~20 instructions):

1. receive a context pointer (the `arg` C hands through),
2. load the thread's pre-allocated data stack into the DSP register
   (X19 / R15) and switch SP to its return stack,
3. `EXECUTE` the xt from the context,
4. on return, `pthread_exit(0)`.

Stacks are `allocate`d by the parent at `thread` time and recorded in the
context block, freed at `join`.

Forth-level API (names unsettled):

    thread ( xt -- tid ior )     run xt in a new thread, own stacks
    join   ( tid -- ior )        wait for it; frees its stacks
    \ later: detach, mutex/cond wrappers if channels aren't enough

## The v1 rule: workers run compiled words only

One dictionary, one `HERE`, one `LATEST`, one `BASE`, one pair of `s"`
transient buffers, one capture log. None of it is thread-safe, and making
it all thread-safe is a remodel, not a feature. So v1 draws a loud, honest
line — the classic Forth answer:

> **The REPL thread owns the dictionary.** Worker threads run
> already-compiled words: no `:`, no `create`, no interpret-time `s"`, no
> `save`/`load`, and treat `BASE` as read-only. They compute, they do I/O
> on fds they own, and they talk to the main thread through channels.

Documented as a rule, enforced by nothing (v1) — like `cmove`'s overlap
direction, it's a sharp tool with a stated grip.

## Channels: the one blessed way to communicate

Shared-memory mutation between threads is where the bugs live. v1 ships
**channels** — a fixed-size ring buffer of cells with a mutex + condvar
(pthreads, via FFI) — as the intended communication path:

    chan  ( capacity -- ch )     make a channel (heap)
    ch!   ( x ch -- )            put, blocks when full
    ch@   ( ch -- x )            take, blocks when empty
    ch?   ( ch -- x true | false )   non-blocking take (REPL side)

Message-passing over shared mutation: teachable, testable, and exactly
what the real use cases need (a socket reader draining lines into a
channel the prompt-peek drains; a control loop receiving setpoints).

## Interactions to settle (the honest list)

- **`catch`/`throw`'s handler chain is a single global.** A worker calling
  `catch` would splice into the REPL's chain — corruption. The handler
  slot must become per-thread. This is one instance of the general
  question below.
- **Per-thread state ("user area").** Classic Forth gives each task its
  own copy of `BASE`, `handler`, etc. via USER variables. Options: a
  per-thread context block whose address rides in a reserved register or
  below the data-stack base; or pthread TLS via FFI. v1 can defer almost
  all of it by the workers-don't-interpret rule — but `handler` at minimum
  must be settled if workers may `catch` (or v1 forbids `catch` in
  workers, and says so).
- **Fault recovery is process-wide.** The guard-page/segfault machinery is
  built around signals and one REPL. A worker that faults needs a decided
  story — likely: kill that thread, report at the next prompt, leak its
  stacks (v1). Signal handlers are shared; the handler must check which
  thread it's on.
- **`bye`** already uses `SYS_exit_group` (all threads die) — the SDL
  sound work paid this cost in advance. No change needed.
- **Locals (Phase 8 sibling)**: the planned locals stack must be
  per-thread from day one — one more slot in the thread context.
- **Stack sizing**: data/return stack sizes for workers (the main thread's
  generous defaults are overkill × N threads). Constants in v1.

## Sequencing

1. Trampoline + `thread`/`join` on both arches; a worker that computes and
   `join`s. Unit tests via the C harness (needs test_helper stubs — see
   the unit-test convention), integration via deterministic join tests.
2. Channels (`chan`/`ch!`/`ch@`/`ch?`) + the worker rule documented in the
   Language Reference and a Threading topic page.
3. Per-thread `handler` (or an explicit no-catch-in-workers rule), fault
   story, then the wider user-area question only when something needs it.

Chat needs none of this (docs/Sockets.md — non-blocking + poll); threading
is its own arc with its own payoffs.
