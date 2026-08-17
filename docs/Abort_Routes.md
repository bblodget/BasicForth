# Abort Routes

Every way an error reaches `forth_interpret_line`'s error exit, and what each
one does to an open definition on the way.

This exists because the `EVALUATE` propagation work has "enumerate every abort
route and commit that list before changing code" written into its TODO entry.
The area has produced seven wedges so far, three of them found in error paths
during the 2026-08-16 `STATE` sweep, and `recovery-anchor-is-global` records an
obvious-looking fix here that segfaulted. The list is the point: a fix that
handles the route in front of it and misses the other eight is the failure mode
this file is meant to prevent.

Line numbers are omitted deliberately — they rot. Labels are stable and
greppable, and both architectures use the same ones.

**One global is spelled differently per arch**: x86 calls it `il_rsp`, ARM64
calls it `il_sp`. This file writes `il_rsp` for both; grep for `il_sp` on
ARM64.


## The three callers of `forth_interpret_line`

It returns a status: **0 = success, 1 = error**. Every caller reads it.

| Caller | File | What it does with the status |
|---|---|---|
| `repl_loop` | `main.s` | Non-zero → `repl_error`: print `? <token>`, next prompt |
| `forth_evaluate` | `core.s` | Restores source context, **returns it in RAX/X0** |
| `forth_included` | `core.s` | Non-zero → `.Lincl_error`: report `file:line: ? token`, stop the load |

`forth_evaluate` and `forth_included` both nest: either can be reached from
inside a line the other is already interpreting. That nesting is what the whole
problem is about.


## Two mechanisms reach the error exit

**A — ordinary return.** Errors raised in `forth_interpret_line`'s own token
loop fall through to `.Lil_err_return`, which sets the status to 1 and runs the
epilogue normally.

**B — longjmp.** Errors raised *inside a called word*, at arbitrary call depth,
jump to `.Lcf_longjmp`. It resets the stack pointer to `il_rsp` and then runs
the same epilogue. This is why the nesting level cannot be tracked with a
counter: the longjmp path unwinds without any intervening frame running its own
epilogue, so a counter would never be decremented. The depth is *derived* from
the saved `il_rsp` chain instead.

Before unwinding, `.Lcf_longjmp` unlinks any exception frame **inside** the
region it abandons (return-stack address below `il_rsp`). A `CATCH` established
*outside* this nest stays armed and is reached cooperatively by the error
return. Getting this backwards would either leave dangling handler frames or
disarm a `CATCH` that should still fire.

Both mechanisms converge on one epilogue, which also restores `LP` to the value
saved at *entry* — not `lp0`. At the outermost level those are the same; at any
nesting depth they are not, and resetting to `lp0` would free a caller's live
locals frame and let it keep running against freed slots.


## The abort decision

`.Lil_err_maybe_abort` is the shared decision point — every error exit that may
have an open definition behind it routes through it. It is three-way:

| STATE | `F_HIDDEN` on LATEST | Nesting | Result |
|---|---|---|---|
| non-zero | — | **not consulted** | Abort: roll back to the global anchor |
| 0 | clear | — | Return 1, no rollback |
| 0 | set | outermost only | Abort |
| 0 | set | nested | Return 1, no rollback |

The middle rows are the `STATE`-is-not-definition-open lesson: `[` interprets
*inside* an open definition, so `STATE` alone answers "am I compiling", never
"is a definition open". The pair is `STATE` **or** `F_HIDDEN` at LATEST+8.

The first row is the older, still-unfixed bug. On the compiling arm the abort
is not gated by nesting at all, so an error inside a nested evaluation rolls
back to the *global* anchor and takes the enclosing definition with it.
**Gating it is not the fix** — skipping the abort there would leave a hidden
header with `STATE` still set, wedging the session harder than the bug avoided.

"Outermost" is read as *previous `il_rsp` == 0*, and **the offset differs by
architecture**: x86 pushes previous-`il_rsp` and then LP, putting previous at
`+8`; ARM64's `STP X10, X11` stores the first operand first, putting it at
`+0`. Reading x86's offset on ARM64 tests LP, which is never zero, so the gate
silently never fires. Mirrored asm that looks identical is exactly how this
one hides.


## The sites

**Into `.Lcf_abort`** (roll back, then longjmp) — seven, and both architectures
carry the same seven in the same order:

| Label | Raised by |
|---|---|
| `.Lbh_open_raise` | `:` while a definition is already open |
| `.Lsemi_ub_say` | `;` with unbalanced control flow |
| `.Lto_is_local` | `is <local>` — refused; it wrote the shadowed global |
| `.Lto_not_found` | `to` / `is` naming an unknown word |
| `forth_does` | `does>` in a definition with locals — refused |
| `.Lpostpone_not_found` | `postpone` naming an unknown word |
| `.Lsq_no_close` | `s"` with no closing quote |

**Into `.Lcf_mismatch` → `.Lcf_abort`** — three ways in, and only the first
goes through `cf_check_tag`:

- **`cf_check_tag`**, called by `then`, `else`, `until`, `again`, `while`,
  `repeat` (twice), `endof`, `loop` (three times) and `+loop` (three times).
  One decision, fourteen call sites.
- **`forth_endcase`** does *not* use it. It walks the compile-time stack
  itself, bounded by `colon_dsp`, and jumps to `.Lcf_mismatch` from
  `.Lendcase_bad` — popping its own frame first, since it is jumping out of a
  call rather than returning from one.
- **`forth_leave`** jumps there directly when it is not inside a `DO` loop.

Worth stating because "the closers all funnel through `cf_check_tag`" is the
obvious summary and it is wrong: two of the sites bypass it, and a change made
to `cf_check_tag` alone would miss them.

**Into `.Lil_err_maybe_abort`** from `forth_interpret_line`'s own loop:

- `.Lil_not_found` — the token is neither a word nor a number
- `.Lil_compile_only` — a compile-only word used while interpreting

**Gated separately**: `.Ltick_not_found` (`'` failing to find a name) runs its
own copy of the outermost test before choosing `.Lcf_abort` or `.Lcf_longjmp`.
It was assumed exempt — "it cannot be inside brackets" — and that comment was
simply wrong; `: foo [ ' nosuchword` reaches it with `STATE` 0 and a definition
open. A stale comment asserting an exemption is why the second regression in
the `STATE` sweep was missed.


## Resets that bypass `interpret_line` entirely

These do not return a status to anyone. They rewrite the machine state and
resume at `repl_loop`, abandoning every nesting level at once — but they do
*not* all reset the same things:

| Route | Trigger | Data stack |
|---|---|---|
| `forth_quit` | `QUIT` | **preserved** |
| `.Lthrow_uncaught` → `.Lthrow_reset` | `THROW`/`ABORT` with no handler | emptied |
| `dict_full` (`main.s`) | Dictionary exhausted | emptied |
| `sigsegv_handler` (`platform_linux.s`) | Guard-page hit on either stack | emptied |

`QUIT` is the exception and reads like it is not: it sits beside the others in
the source and resets the return stack and LP the same way, but neither arch's
`forth_quit` writes DSP. That is Forth 2012 — `QUIT` empties the return stack,
`ABORT` is what empties the data stack.

The signal handler is the awkward one: it recovers by **rewriting the ucontext**
(RIP/RSP/DSP) rather than by executing a reset, so grepping for the usual reset
idiom does not find it. `LP` lives in TLS, so it stores that directly.

None of these are propagation candidates — they already abort everything. They
matter here because they are the four places that must stay correct if the
recovery anchor or the loader flag changes meaning.


## Where the status is lost

`forth_evaluate` computes the right answer and hands it back. Nothing consumes
it.

`EVALUATE` is dispatched as an ordinary Forth word through its `DEFWORD` entry.
`forth_execute` is a **tail-call** (`jmp *%rax` / `BR X9`), so the status
register actually survives back to `.Lil_found_execute` in the enclosing
`interpret_line` — which drops it and jumps straight to `.Lil_loop`.

So for a *directly interpreted* `evaluate` the value is sitting right there at
the call site, unread.

**The bug is wider than the TODO entry describes.** It is filed against the
bracketed form, but brackets and definitions have nothing to do with it — the
minimal reproduction is one line at the prompt (all verified against
`v0.16.0-14-gbad2f78`):

    > s" nosuchword" evaluate            \ prints ` ok`. No error at all.
    > s" nosuchword" evaluate 7 .        \ prints `7  ok` — the outer line runs on
    > : q s" nosuchword" evaluate 42 . ;  q     \ prints `42  ok`
    > : z 1 [ s" nosuchword" evaluate ] 2 + . ;  z    \ prints `3  ok`

The third line is the one that matters for the fix: `evaluate` **compiled into
a definition and run later** is just as silent, and there the status register is
long gone. Any fix validated only at the prompt will look complete and cover
half the cases.

**`INCLUDED` behaves differently, and better.** Because `forth_included` reads
the status, a load error *is* reported:

    > include t.fs
    t.fs:2: ? nosuchword
     ok
    > 7 .
    7  ok

It names the file and line and stops the load. **It also returns 1** — the
status is correct and always was; `.Lincl_err_tail` sets it explicitly. The
outer line carries on anyway.

That is the crux, and it locates the **defect** precisely: **both
`forth_evaluate` and `forth_included` already compute the right status. It is
dropped at a single call site** — `.Lil_found_execute`, which calls the word and
jumps straight back to `.Lil_loop` without looking at the result. Nothing is
missing upstream.

Locating the defect in one place is not the same as the fix being in one place,
and the difference is the whole trap here. Two consequences:

- A **Forth-level wrapper cannot help.** `core.fs` redefines `included`, but a
  register return is invisible to Forth code, which communicates on the data
  stack. The status can only be consulted by an assembly caller.
- The single call site **cannot be the whole fix**, because it only sees words
  the *outer interpreter* executes directly. A compiled `evaluate` runs from
  inside a definition's body, where there is no such site and the register is
  overwritten by the next call.

So `INCLUDED` already does the reporting half and skips the propagating half,
while `EVALUATE` does neither. Whatever channel gets added should let
`INCLUDED` keep its own reporting rather than replacing it — the `file:line:`
prefix is the part a load error is actually worth.

**But the register is not a general channel.** When `evaluate` is compiled into
a definition and that definition runs later, the status is destroyed by the
calls that follow it in the body. Any fix that reads RAX/X0 at
`.Lil_found_execute` fixes the interpreted case and leaves the compiled one
exactly as broken — while looking, from the prompt, like it worked. That is a
vacuous-fix trap of the kind `verify-fixes-against-broken-build` catalogues, and
it needs a test in the compiled form specifically.


## Constraints on any fix

Recorded so the next attempt does not rediscover them:

1. **The recovery anchor is global.** `saved_latest` / `saved_here` /
   `colon_dsp` are one anchor that `;` moves forward, not a per-nesting
   snapshot. Saving and restoring them per level segfaults — DSP came back as 0
   across a `core.fs` load.
2. **`INCLUDED` must keep reporting `file:line`.** An error that throws past
   `forth_included` loses the frame that knows which file and line it was on,
   which is most of what a load error is worth.
3. **An outer `CATCH` must still intercept.** Whatever channel is used has to
   respect the handler chain the way `.Lcf_longjmp`'s unlink already does.
4. **The compiling arm cannot simply be gated** (see the abort-decision table).
5. **Both arches, and the `il_rsp` offset is not the same on both.**
6. **`LP` restores to entry, never `lp0`,** at any nesting depth.


## The pins, and why one of them is not an acceptance test

`tests/test_integration.sh` has four assertions in this cluster. The TODO entry
says two get flipped, which is right about the count and wrong about which
signal to trust. Each probes whether `foo` survived:

| Assertion | Today | After propagation | Use as acceptance? |
|---|---|---|---|
| a nested error while compiling still takes the outer definition | `MISSING` | `MISSING` | **No** |
| a failed tick inside a nested `EVALUATE` does not abandon it either | `EXISTS` | `MISSING` | Yes |
| an error inside a nested `EVALUATE` does not abandon the outer definition | `EXISTS` | `MISSING` | Yes |
| a failed tick inside `[ ]` DOES abandon at the top level | `3` | `3` | Unaffected — a control |

The first one **passes in both worlds**. Today `foo` is missing because a
nested error while compiling wrongly rolls back to the global anchor; after the
fix `foo` is missing because the line correctly aborted. Same observation,
opposite mechanism — the exact shape `verify-fixes-against-broken-build`
catalogues, and it would read as confirmation.

That points at what the acceptance test actually has to check. **The bug is not
that `foo` survives — it is that the failure is silent.** All four assertions
watch the dictionary; none watches the output, and the defining symptom is
` ok` printed where `? nosuchword` belongs.

**Reporting is only half of it.** An error that prints and then lets the line
finish is still not propagated — `INCLUDED` does exactly that today. So the
criteria have to cover both halves, plus the two behaviours that must *not*
change. All baselines below measured against `v0.16.0-14-gbad2f78`:

| # | Probe | Today | Required after |
|---|---|---|---|
| 1 | `s" nosuchword" evaluate` | ` ok` | reports `? nosuchword` |
| 2 | `s" nosuchword" evaluate 7 .` | `7  ok` | reports; **`7` does not print** |
| 3 | `: q s" nosuchword" evaluate 42 . ;  q` | `42  ok` | reports; **`42` does not print** |
| 4 | `: z 1 [ s" nosuchword" evaluate ] 2 + . ;  z` | `3  ok` | reports; `z` not defined |
| 5 | `: bad s" nosuchword" evaluate ;  ' bad catch .` | `0` | **non-zero** throw code |
| 6 | `include <bad.fs> 7 .` | `file:1: ? nosuchword` then `7  ok` | keeps `file:1:`; **`7` does not print** |
| 7 | `1 2 nosuchword` then `.s` | `<2> 1 2` | unchanged — a typo must not clear the stack |

Rows 2, 3 and 6 are the propagation half and none of the four existing pins
covers them. Row 3 is the one that cannot be satisfied by reading a status
register at `.Lil_found_execute`. Row 5 says the channel has to reach `CATCH`,
which is the strongest single check here — it is the difference between "the
error was announced" and "the error happened". Rows 6 and 7 are regression
guards: 6 protects `INCLUDED`'s `file:line:` prefix, 7 protects the deliberate
decision that interpret-mode errors leave the data stack alone.

Both architectures, per the usual rule for hand-mirrored asm — and `il_rsp` is
spelled `il_sp` on ARM64, at a different offset.


## Choosing the channel

Written 2026-08-16, before any code. Four candidate mechanisms, scored against
the seven rows above. **Three of them fail, each on a different row**, and the
rows they fail on are the reason the table is worth having.

### A — read the status register at `.Lil_found_execute`

The value is already sitting there (`forth_execute` tail-calls, so the word's
return lands in the interpreter's own frame). One `test`/`jnz` after the call.

**Fails row 3.** A compiled `evaluate` runs from inside a definition's body,
where there is no `.Lil_found_execute` at all and the register is overwritten by
the next call in the body. This candidate cannot see the case that matters, and
— worse — it *looks* complete from the prompt, where rows 1, 2 and 4 all pass.

### B — a pending-error global, checked at token boundaries

`forth_evaluate` sets `pending_err`; `interpret_line` checks it after each word
it executes and routes to the shared error exit.

**Fails row 3 differently, and row 5.** The flag is set mid-body of `q`, but
nothing consults it until `q` *returns* — by which time `42 .` has already run.
That is reporting without propagation, which is precisely the half-fix
`INCLUDED` already ships. And a flag is not a throw, so `' bad catch .` still
answers 0.

### C — re-longjmp to the outer `interpret_line`

Reuse `.Lcf_longjmp`. Once the inner level's epilogue has restored `il_rsp`, a
jump there unwinds to the *outer* frame and returns error 1 from it — which
does abandon the rest of `q`'s body, so row 3 passes.

**Fails row 5**, and instructively. `.Lcf_longjmp` deliberately unlinks every
exception frame whose address is below `il_rsp`. The frame established by
`' bad catch` sits inside the current `interpret_line`, so it is *dropped* on
the way past. The line aborts instead of `catch` returning non-zero — the error
is handled by the interpreter rather than by the program that asked to handle
it. Making this candidate work means teaching it about the handler chain, at
which point it has become candidate D with more steps.

### D — THROW  (recommended)

Let a nested `interpret_line` error raise an exception.

All seven rows pass. Row 3 works because a throw unwinds the return stack
through `q`'s frame; row 5 works because that is what `CATCH` is for; rows 6 and
7 are untouched because `INCLUDED` still prints before it throws, and the
top-level path never throws at all.

The strongest argument is one the code makes on its own: **`CATCH`'s frame
already snapshots exactly the state `EVALUATE` and `INCLUDED` bracket by hand** —
`source_addr`, `source_len`, `to_in`, `source_id`, **`il_rsp`**, `file_name_*`,
`file_line_num`, `cur_source_id`, `cur_line_off`. Ten cells, restored by
`THROW`. That set was not chosen with this bug in mind, and it is the set this
bug needs. A mechanism whose recovery state already matches the problem is
usually the intended one.

### Sub-decisions inside D

**1. Throw from the callers, not from `interpret_line`.** `interpret_line`
keeps returning its status — `repl_loop` still needs it, and `INCLUDED` needs it
to print `file:line:` first. Each caller then decides. The practical
consequence is the point: **the change does not touch `interpret_line`'s abort
decision at all**, which is where seven of the wedges have been, and where
`recovery-anchor-is-global` records a fix that segfaulted. `forth_evaluate` and
`forth_included` are the whole edit.

**2. Nested only.** Gate on the same *previous `il_rsp` == 0* predicate the
abort decision already uses — already written, already debugged, and already
carrying the per-arch offset trap. Throwing at the top level too would make a
plain typo clear the data stack, breaking row 7 and a deliberate documented
behaviour. The asymmetry is real and wants a comment: at the top level there is
no outer computation to protect, so a status return is enough.

**3. A new silent throw code, not `-2`.** Uncaught, `-1` and `-2` print
nothing (the thrower already spoke); everything else prints `uncaught
exception: N`. Since `EVALUATE` and `INCLUDED` will have reported already, the
code must join the silent set. Reusing `-2` would work but overloads `ABORT"`,
and a program that wants to tell "the user's `abort"` fired" from "the text I
evaluated was broken" has a fair claim to both. Add one code to the silent list.

**4. Restore the error wording *before* throwing.** `CATCH`'s ten cells do
**not** include `err_pfx_addr`/`err_pfx_len`; `forth_evaluate` brackets those
itself, on the return stack a throw would skip. Restore the context first, then
throw at the end of the routine — otherwise an error raised later in the same
outer token inherits the inner string's wording, which is the exact regression
`a nested evaluate does not leak its error wording` already pins.

### What this does *not* fix

The compiling-arm bug (`STATE != 0`, nested error rolls back to the global
anchor and takes the enclosing definition) is **not repaired** by this — it is
made unobservable. The rollback still happens at the nested level; the outer
line then aborts anyway, so the definition was forfeit either way and the
visible outcome becomes correct. Worth stating plainly so nobody later reads a
passing test as evidence that the anchor behaviour changed. It did not.
