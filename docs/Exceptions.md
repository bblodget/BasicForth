# Exceptions — CATCH and THROW

The Forth 2012 exception wordset: `catch ( xt -- 0 | n )` runs a word while
trapping any `throw ( n -- )` raised inside it, restoring the stacks and
returning the thrown code instead of losing control to the REPL. Before this,
the only unwind was `abort` — "throw to top level" — so every library that
could fail needed a non-aborting `?`-variant (`snd-open?`); `catch` is the
general case, and `allocate throw` / cleanup-then-rethrow become natural
idioms.

```forth
: game   ['] play catch          \ run the game, trapping any error
         snd-close sdl-close     \ cleanup happens on BOTH paths
         throw ;                 \ re-raise a real error; 0 throw is a no-op
```

## Semantics

- `catch` pops the xt and runs it like `execute`. Normal completion returns
  0 on top of whatever the word left. A `throw n` (n non-zero) anywhere below
  returns n instead, with **both stack pointers restored** to their values at
  `catch` time — the cells the xt consumed are still counted but their
  contents are unspecified (the usual idiom drops them).
- `0 throw` does nothing; an ior of 0 means "fine".
- Uncaught non-zero `throw` behaves like `abort` always has (clear stacks,
  reset to the prompt), first reporting `uncaught exception: n` — except for
  the standard codes -1 (`abort`) and -2 (`abort"`), which stay silent
  because any message was already printed.
- `abort` **is** `-1 throw` and `abort"` throws `-2` (Forth 2012), so
  `catch` traps every `abort" ..."` guard in core.fs and the libraries.
  Deviation from the standard: our `abort"` prints its message at throw
  time and does not pass it to the handler, consistent with "errors are
  printed, not returned".
- Per the standard, `throw` also restores the **input source specification**
  in use at the `catch` — so throwing across `evaluate` or `included` leaves
  the interpreter parsing the right buffer (see below).
- `catch` restores the *stacks*, not the world: files, devices, heap blocks,
  and dictionary changes made before the throw stay as they are. Cleanup is
  the catcher's job (the `game` pattern above). A throw across a `marker`
  run does not un-run the marker.

## How it works (core.s, both architectures)

A `handler` global holds the return-stack address of the innermost live
exception frame (0 = none). `catch` pushes a frame on the return stack and
links it: the previous handler (chain link), the data-stack pointer, and the
interpreter's input-source + file-error context (`source_addr`/`source_len`/
`>in`/`source-id`, `il_rsp`/`il_sp`, and the INCLUDED error-reporting
globals) — exactly the state `evaluate` and `included` save in their own
frames and restore cooperatively on normal return, which a throw unwinds
past. `throw` sets the return-stack pointer to `handler`, pops the frame
back into the globals, and returns — landing in `catch`'s caller.

Because a stale handler pointing into an abandoned return stack would be
memory corruption, every path that abandons the return stack maintains it:

- `repl_loop` zeroes `handler` at the top of every line (this also covers
  the guard-page fault recovery and `dict_full`, which resume there);
  `quit` and the uncaught-throw reset zero it directly.
- The compile-error longjmp (`.Lcf_abort`) unwinds only to the innermost
  `forth_interpret_line`, so it *walks the chain*, unlinking just the frames
  inside the abandoned region — a `catch` armed outside an `evaluate`
  survives an undefined word inside it.

Frames are pushed with `STP` pairs on ARM64, keeping SP 16-byte aligned.

## Interactions and limits

- **Guard faults are not throws.** A stack underflow/overflow or SIGSEGV
  inside a caught word still recovers to the REPL (the fault handler cannot
  unwind to a Forth frame safely); the `catch` never returns. The session
  survives either way.
- **Interpreter errors are not throws** (v1): an undefined word inside an
  `evaluate` reports `? word` and makes `evaluate` return normally, as
  before — the outer `catch` sees 0.
- A throw out of an `included` file stops the load; the file's mmap and fd
  are not cleaned up (same class as the fault-time include leak already on
  the books — a fault-time cleanup registry would fix both).
- Codes: use positive numbers (or -1/-2 via `abort`/`abort"`) for your own
  errors; the standard reserves the rest of the negative range.

## Testing

Unit tests (both arches): clean catch returns 0, thrown code returned, depth
restored on throw, `0 throw` no-op — via `test_throw*` xt wrappers in the
test helpers. Integration tests (`CATCH / THROW` section): uncaught-throw
report + session survival, silent uncaught `abort`, `abort"` trapped as -2,
nested catch with rethrow, throw across `evaluate` and across `included`
(input source restored — the rest of the line runs), and an error inside a
caught `evaluate` leaving the outer handler armed.

## Scope / next

- Retiring `?`-variants (`snd-open?`) in favor of `catch` is deliberately
  deferred — the lessons teach them and they cost nothing.
- Converting interpreter errors and guard faults into standard throw codes
  (-4 stack underflow, -13 undefined word, ...) would let programs trap
  those too; revisit if a real need appears.
