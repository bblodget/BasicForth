# Threading — Design Notes

Status: **step 0 done** (2026-07-31) — the per-thread variables now live in
TLS. No threads yet: the trampoline, `thread`/`join` and channels are still
ahead. Real concurrency for BasicForth: audio feeders, robot control loops at
fixed Hz, socket readers — the Phase 8 item, given a concrete shape.
Supersedes the "pthreads or clone?" question in TODO Phase 8: **pthreads, via
the FFI.**

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

## Per-thread state: native TLS (done, 2026-07-31)

Some globals must read differently in each thread. `sp0` is the obvious one —
`depth` is `(sp0 - DSP)/CELL`, so a worker measuring against the REPL's `sp0`
gets nonsense — and `handler`, the head of the `catch` chain, is the dangerous
one: a worker splicing into the REPL's chain corrupts it.

The mechanism is **native thread-local storage**, not a reserved register and
not `pthread_getspecific`. Every thread already has a thread pointer the kernel
and glibc maintain (`%fs` on x86-64, `TPIDR_EL0` on ARM64); the linker assigns
each TLS variable an offset, and the address is thread-pointer + offset:

    x86-64      mov %fs:sp0@tpoff, %rax          # one instruction, as before
    ARM64       TLS_ADDR X9, sp0                 # macro: MRS + two ADDs

Why not the alternatives: a reserved register means auditing 31 scratch uses of
`%r14` (and the ARM64 equivalent) for no gain; `pthread_getspecific` puts a
function call inside `depth`. TLS costs nothing at runtime and glibc allocates
each thread's copy inside `pthread_create` automatically.

Three variables moved: `base`, `sp0`, `handler` — about a dozen sites per arch,
plus `__thread` on the C unit-test harness's `extern` declarations or the link
fails on a TLS/non-TLS mismatch. Both arches land on an identical 24-byte TLS
block (`base` 0, `sp0` 8, `handler` 16). Verified: local-exec TLS works in a
`-nostartfiles -no-pie` dynamically linked binary on x86-64 and ARM64, each
thread getting its own copy.

A quiet bonus: a new thread's TLS block is initialised from the image in
`.tdata`, so a worker starts with `BASE` decimal and no live `CATCH` frame
without the trampoline doing anything. Only `sp0` needs filling in.

**What this settles, precisely.** `BASE` no longer needs to be read-only: a
worker doing `hex` cannot disturb the REPL. `depth`/`.s` will work in workers
once the trampoline sets that thread's `sp0`. And the `catch` *chain* is now
per-thread, so a worker can no longer splice into the REPL's chain.

**What it does not settle: `catch`/`throw` is still not thread-safe.** Besides
the chain link, a `CATCH` frame snapshots ten further globals — the input
source (`source_addr`, `source_len`, `to_in`, `source_id`) and the file-error
context (`il_rsp`/`il_sp`, `file_name_addr`, `file_name_len`, `file_line_num`,
`cur_source_id`, `cur_line_off`) — and `THROW` writes all ten *back* while
unwinding. Those are still plain globals, so a worker's `throw` would restore
its snapshot over whatever line the REPL is parsing. Per-thread `handler` is
necessary but not sufficient; **workers must not `catch` until this is fixed.**

The cheap fix is not to move all ten into TLS — that is ~280 sites across both
arches, in parser hot paths. The snapshot exists to restore the *interpreter's*
input source across a throw, and a worker has no input source: it never
interprets (see the dictionary rule below). So `catch`/`throw` should skip the
snapshot and restore entirely when not on the REPL thread, gated on one
per-thread flag in the TLS block. Roughly ten lines per arch, and testable the
moment the trampoline exists — hence step 1, not step 0.

## The v1 rule: workers run compiled words only

One dictionary, one `HERE`, one `LATEST`, one `BASE`, one pair of `s"`
transient buffers, one capture log. None of it is thread-safe, and making
it all thread-safe is a remodel, not a feature. So v1 draws a loud, honest
line — the classic Forth answer:

> **The REPL thread owns the dictionary.** Worker threads run
> already-compiled words: no `:`, no `create`, no interpret-time `s"`, no
> `save`/`load`. They compute, they do I/O
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

- **`catch`/`throw` is not thread-safe yet.** The chain head (`handler`) is
  per-thread as of step 0, but a `CATCH` frame also snapshots ten shared
  globals that `THROW` writes back — see the TLS section above. Fix: skip the
  snapshot when not on the REPL thread, gated on a per-thread flag. Until
  then, **workers must not `catch`.**
- ~~Per-thread state ("user area").~~ **Settled by TLS** (above) for `base`,
  `sp0`, `handler`. Adding another per-thread variable is now a one-line
  change — move it into the `.tdata` block. `HERE`/`LATEST`/the `s"` buffers
  deliberately stay shared, guarded by the dictionary rule.
- **An uncaught `throw` in a worker.** Today `throw` with no handler resets
  to the REPL, which is wrong from a worker thread. Intended shape: the
  trampoline installs the worker's outermost `catch`, so an uncaught throw
  ends *that thread* and surfaces as the `ior` from `join`. Cheap now that
  the handler chain is per-thread.
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

0. **Per-thread `base`/`sp0`/`handler` via TLS — DONE 2026-07-31.** No
   threads involved; behaviour identical, covered by the existing suites.
1. Trampoline + `thread`/`join` on both arches; a worker that computes and
   `join`s. Unit tests via the C harness (needs test_helper stubs — see
   the unit-test convention), integration via deterministic join tests.
   Proof tests: `depth` reads 0 inside a worker, and a `throw` in a worker
   surfaces through `join`.
2. Channels (`chan`/`ch!`/`ch@`/`ch?`) + the worker rule documented in the
   Language Reference and a Threading topic page.
3. Worker stack guard pages and a thread-aware SIGSEGV handler — the one
   genuinely open design question. TLS helps: the handler can tell which
   thread it is on.

Chat needs none of this (docs/Sockets.md — non-blocking + poll); threading
is its own arc with its own payoffs.
