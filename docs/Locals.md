# Locals — Design Note

Status: **BUILT, stages 1-3 (2026-08-11 to 08-13), on both architectures.**
Stage 1 was the runtime frame and its unwind contract, stage 2 `{: … :}` with
open-coded references, stage 3 assignment (`to`), the shadow note, and the rest
of the Forth 2012 declaration (`|`, `--`). Phase 8 (`docs/TODO.md`, "Threading
and Locals").

The ARM64 timings the note originally called for were taken on a Raspberry Pi
400 on 2026-08-15 and changed two things: the frame stopped being a call (28 ns
→ 0.4), and the day after, so did every `LITERAL` in the engine. See "The frame
was a call, and that was the wrong call", "The literal was fixed too", and "Why
ARM64 still loses", which explains the one performance gap that remains: a
reference costs six instructions on ARM64 to x86's four, because finding LP
takes four instructions there and one on x86. That is measured and accounted
for — a property to know about, not an open question or a defect.

Still open by design: `does>` is refused rather than supported — deliberately,
see below.

This note records what the runtime-frame design costs, where it can go wrong,
and what the building of it corrected.

## What stage 3 shipped

`to <local>`, open-coded like the read (a `to x` in a loop is as hot as reading
`x`); the shadow note when a local hides an existing word; `is` refused on a
local; and the rest of the declaration, `|` and `--`.

`|` needs no new primitive: uninitialised locals got one compiled `0` push
each, immediately before the frame build. The last-declared local sits at the
top of the stack, so the zeros land exactly on those slots — the same trick the
`0 {: n acc :}` workaround used, moved into the compiler where it cannot leak
into the word's stack effect. *(Superseded 2026-08-15: the zeros are now
written straight into their slots by the open-coded frame — see "The frame was
a call, and that was the wrong call" below. Each of those pushes was a
`LITERAL`, which at the time was the most expensive thing the engine did. That
is no longer true of literals themselves — see "The literal was fixed too"
below — but the frame is still better off not pushing anything.)*

The hard part was none of that. It was answering "am I loading a file?", which
took four attempts — `source-id` (answers 0 inside an included file too),
`(ldg-n)` (misses command-line scripts), `cur_source_id` (a 64-entry table that
answers 0 once full, which `redefined` had gated on for months), and finally
`in_load`, a flag the loader sets. Each wrong one passed a test against
`included`; only walking the other paths a file can arrive by separated them.

## What stage 2 shipped

`{: a b c :}` as an immediate word in `core.fs`, name resolution ahead of the
dictionary in the outer interpreter, and an **open-coded** reference: x86-64
emits 23 bytes (a TLS load, an offset load, and a push), ARM64 24 bytes / six
instructions. Neither calls anything. Frame build and release remained ordinary
calls, since they happen once per invocation rather than once per mention —
**which was wrong, and is fixed; see below.**

**The relocations are not hand-encoded.** Both emitters copy a code template
written as real instructions, so the assembler and linker fill in the TLS
offset; x86 then emits the remaining 14 relocation-free bytes directly, and
ARM64 patches one `imm12` field. On a fixed-width architecture where every
instruction is a bitfield, copying and patching one field is the difference
between a mirror and a guess.

**What the frame's shape forced.** The build happens where `{:` appears; the
release happens once, when the definition returns. That pairing is only safe if
the build is unconditional and happens once — so `{:` is refused where the
compile-time stack is non-empty (inside an unclosed `if`/`begin`/`do`/`case`,
or after a `[ … ]` that left a value), and refused a second time in one
definition. Each of those cases leaked 8 bytes of LP per call before the guard
existed. `does>` is refused outright: its body outlives the frame, and read a
dead slot without crashing.

Three of those four defects came from review rather than from the tests, which
were green throughout. The tests only covered the *refused* side of the
placement rule, which let the documented rule drift narrower than the enforced
one — twice — before a test on the permitted side pinned it.

## What stage 1 shipped

The substrate, driven by primitives rather than syntax, so the dangerous half
could be tested before `{: … :}` existed:

| word | effect | |
|---|---|---|
| `(lframe)` | `( x1 .. xn n -- )` | push a frame; `x1` becomes local 0 |
| `(lunframe)` | `( n -- )` | pop a frame of n cells |
| `(local@)` | `( i -- x )` | fetch local i |
| `(local!)` | `( x i -- )` | store to local i |
| `(lp@)` `(lp0@)` | `( -- a )` | the pointer, and this thread's empty mark |
| `(lstack-size)` | `( -- n )` | bytes per locals stack |

These are the **testing** surface, not the compiled one: stage 2 open-coded the
reference rather than calling `(local@)`, which is what "The one thing that
decides this" below insisted on.

Sizes moved to **`src/config.inc`**, included by both architectures, so a
tunable cannot drift between them. `LOCALS_STACK_SIZE` is 16 KB (2048 cells)
for the REPL thread and each worker; `threads.fs` reads it back through
`(lstack-size)` rather than keeping a second copy.

### Three things the design below got wrong

**1. "Every path that reaches `repl_loop` … resets `lp` to `lp0`" is too
strong.** `forth_interpret_line` **nests**: a compiled word holding a frame can
call `EVALUATE`, and an error inside that evaluation unwinds only the *inner*
interpret_line while the caller keeps running. Resetting to `lp0` there hands
the caller freed slots — and because local 0 then sits in the guard page, it
faults. The rule is really *restore `lp` to what it was when **this**
interpret_line began*; at the outermost level that value **is** `lp0`. `lp` is
saved on entry and restored on the error exits (x86 in place of the alignment
padding, ARM64 in the padding slot the `il_sp` push already carried).

**2. The reset sites were miscounted, in both directions.** `interpret_line`
has *three* exits, not one: `.Lil_done`, `.Lil_err_return` (undefined word,
compile-only word) and `.Lcf_longjmp`. The first two are not reachable from
the label the note named, and `.Lil_err_return` was missed on the first pass —
the nesting test caught it. Meanwhile `.Lsemi_unbalanced` stopped being a site
at all when it was routed through `.Lcf_abort` the day before.

**3. `.Lil_done` deliberately does *not* restore.** A balanced line already
left `lp` where it found it, so restoring on the normal path would silently
*repair* a leaked frame rather than let it surface — which would defeat every
test in the section.

### What the guard pages bought immediately

The locals stack is fenced like the data stack, with its own pair of pages and
its own messages (`locals stack overflow`, and `locals stack underflow (engine
bug — please report)`, since no Forth code can cause the latter). That fence
earned itself during stage 1: a draft test stored to a local with **no frame
open**, which faulted cleanly instead of scribbling on the REPL's memory. It
had been passing anyway, on the echoed input — see the vacuous-assertion note
in `docs/TODO.md`.

## The original recommendation (2026-08-10)

*Everything from here down is the pre-build research note, kept because its
reasoning is what the stages were built against. Where building it proved the
note wrong, the correction is marked in place.*

Build it, with a **separate locals stack and a runtime frame**, as the TODO
already sketches. The measurements below say the frame is affordable, and the
risk is smaller than it first appears — but only if one implementation
constraint is respected (see "The one thing that decides this").

## Why locals earn their place here

Three-plus arguments is where Forth's stack notation stops paying, and games
code is full of `x y w h color`. The evidence is in this repository, not in
theory:

- `pad.fs`'s `pad-open` carries `( n handle )` annotations on nearly every
  line, purely to survive review.
- Its `(merge)` needs `>r … r>` around a stack comment (`( neg? pos?   R:
  stick )`) to stay readable. Writing that comment wrong — putting `R: stick`
  outside the parens — cost a debugging round, and the code was correct.
- `(pad-why!)` juggles a C pointer against a loop index across five lines.

None of those words is badly factored. They have three arguments.

It also serves the project's stated aim directly: BASIC-inspired, approachable,
"boot up and start coding". Stack juggling is the first wall a newcomer from
BASIC or C hits.

## Design

Per the existing sketch, unchanged:

    : blit ( src x y w h -- )  {: s x y w h :}
        ... s x y w h referenced by name ...

**Syntax is Forth 2012 section 13's `{: … :}`**, not the `{ … }` the TODO
originally sketched. Decided 2026-08-10: matching the standard costs two
characters and leaves `{` free for something else later.

The whole declaration, not just the arg list: `{: <arg>… [| <val>…]
[-- comment] :}`. **Stage 2 shipped the arg list and claimed conformance on
that alone**; stage 3 added `|` and `--`. Brandon caught the gap by reading a
stack comment that no longer matched its word — the missing `|` had been
worked around by pushing a `0` before `{:`, which silently made the word take
an argument it did not want. Worth remembering that a subset of a standard
syntax is not the standard syntax, and the gap shows up first in the examples.

- **A separate locals stack**, not the return stack. This is the decision that
  removes most of the danger: no interaction with `>r`/`r>`, and none with
  `do`/`loop` control parameters, which live on the return stack.
- **Per-thread**, via the existing `.tdata` TLS block in `core.s` — the same
  place `sp0`, `handler` and `base` already live. Workers get their own copy
  for free from the `.tdata` image, exactly as `is_repl` does.
- **`lp` in TLS, not in a register.** Both arches document a freed register
  (`R14` / `X20`, formerly TOS), but both are in active scratch use — 36 and 16
  references respectively. Reclaiming one is a separate change and not worth
  coupling to this.
- **Pay only if you use it.** Frame setup and teardown are emitted only in
  definitions that declare locals. A word with no locals compiles exactly as it
  does today. The single unconditional cost is one extra cell saved and
  restored by `catch`, which is noise.

## What it costs — measured, x86-64, 30M iterations

Each stack operation is a `call` in STC, so this measures dispatch, which is
what dominates. Baseline `empty` loop subtracted; all four variants verified
stack-neutral before timing.

| variant   | time  | per call |
|-----------|-------|----------|
| `empty`   | 0.02s | —        |
| `lits`    | 0.22s | ~1.1 ns  |
| `juggle`  | 0.33s | ~1.0 ns  |
| `viavars` | 0.71s | ~4–5 ns  |

- **A primitive call costs about 1 ns.** So the `rot over swap` a three-argument
  word does today costs roughly 3 ns each time through.
- **A `variable`-style access costs 4–5 ns** — four times a primitive. That is
  the `create`/`does>` call, not the fetch.

Not measured on ARM64 at the time: the only ARM64 target then was QEMU, where
timings mean nothing. **Measured on a Raspberry Pi 400 on 2026-08-15** — see
below, and `tests/bench-locals.fs`, which is that measurement kept.

## The one thing that decides this

**A local reference must be open-coded, or at worst compile to a single
primitive-class call. It must not be implemented as a `create`/`does>` word.**

The table above is the whole argument. Locals replace ~3 ns of juggling. If a
local reference is open-coded — load at `lp`-relative offset, push — it costs
well under a nanosecond and no dispatch, and locals are a clear win. If it
compiles to one primitive call it is roughly a wash, which is still fine
because the readability is the point. If it is built like `variable`, each
reference costs 4–5 ns and **locals make three-argument words slower than the
juggling they replaced.**

That is the failure mode to design against, and it is invisible to a
correctness test.

## The frame was a call, and that was the wrong call

Measured on a Raspberry Pi 400 (1.8 GHz), 2026-08-15, with `drop` subtracted
where it is shared. This is the ARM64 run the section above says is owed.

| | ARM64 | x86-64 |
|---|---|---|
| local reference, back to back | 0.62 ns | 0.10 ns |
| local reference, in context | ~1.2 ns | — |
| `dup` | 2.24 ns | 0.82 ns |
| colon call | 1.94 ns | 0.80 ns |
| **LITERAL** | **10.6 ns** | **1.68 ns** |
| `variable @` | 15.1 ns | 9.9 ns |
| frame build+release, **before** | 27.8 ns | 7.2 ns |
| frame build+release, **after** | 0.4 ns | 0.4 ns |

*The `LITERAL` row is a record of what it cost on 2026-08-15, and is what made
the frame worth open-coding. It no longer describes the engine — literals were
fixed the next day. See "The literal was fixed too" below for the current
figures. The rest of the table still holds.*

**The open-coding decision holds.** A reference is cheaper than the `dup` it
replaces and cheaper than a call, on both architectures, even at ARM64's six
instructions to x86's four. Had it been a `create`/`does>` word it would have
cost 15 ns and locals would have been a pessimisation, exactly as predicted.

**The frame was the mistake.** "Once per invocation rather than once per
mention" is true and was the wrong conclusion, because it was never the *call*
that cost — it was the `LITERAL` in front of it. The cell count is known while
`{:` is running, yet it was pushed at run time by `forth_lit`, which reaches
its operand through its own return address and returns past it, mispredicting
the return-stack predictor every time. Two per invocation, plus one per
uninitialised val.

**The tell was flatness.** A frame of 1 cost the same 28 ns as a frame of 3.
Frame cost that ignores frame size is not frame work.

`(lframe,)` now emits the build open-coded — read LP, adjust, straight-line
moves into the slots, zeros written directly — and the release likewise. The
primitives `(lframe)`/`(lunframe)` remain, since the unwind tests drive them
directly, but nothing compiles a call to them any more.

**What this cost in space:** a definition using locals grows by roughly 20–40
bytes, because inlining trades one shared copy for a private one, and the copy
loop becomes straight-line moves that scale with the number of locals. It is
paid once per definition against a saving on every call, and a definition with
no locals is still byte-for-byte unchanged. Words with several `|` locals can
come out *smaller*, since each of those used to cost a 13-byte literal and now
costs an 8-byte store.

On ARM64 the whole-word comparison improved from 49.0 ns to 26.0 ns but still
trails the juggled spelling at 19.6 ns; on x86 it went 15.2 → 6.4 ns and now
wins against 8.6 ns. The next section is why, and what was tried.

## The literal was fixed too

Re-measured 2026-08-16, after `LITERAL` stopped being a call (a number now
compiles to an immediate). Raw `tests/bench-locals.fs` PART 1 figures, ps per
access, each carrying the shared `drop` call that the calibration row isolates:

| | ARM64 (Pi 400) | x86-64 |
|---|---|---|
| colon call (calibration) | 1940 | 820 |
| **literal** | **1960** | **880** |
| local reference | 2620 | 900 |
| `dup` | 4300 | 1640 |
| `variable @` | 17040 | 6820 |

**A literal is now indistinguishable from the calibration baseline** — the row
sits within noise of a bare call+ret on both architectures, where it used to
stand at 10.6 ns on ARM64. Subtracting the shared call leaves ~0.02 ns on ARM64
and ~0.06 ns on x86, which is below what this harness can resolve; the honest
statement is that it costs nothing measurable, not that it costs 0.02 ns.

**This does not change any locals conclusion.** The whole-word comparison is
where the decision lives, and it moved by less than the run-to-run spread:

| `(a+b)*(b+c)`, ps/call | ARM64 | x86-64 |
|---|---|---|
| locals | 26000 | 6400 |
| juggled | 20000 | 9000 |

So locals still win on x86 and still lose on ARM64, for the reason the next
section gives. The frame work was worth doing on its own terms — it removed
work rather than making a slow instruction faster — and nothing about it needs
revisiting now that the literal is cheap.

## Why ARM64 still loses, and the experiment that did not fix it

**Counted, not guessed** — including the primitives, which have to be counted
individually rather than averaged: `over`, `>r`, `r>` and `drop` are three
instructions each (`LDR`/`STR`/`RET`), but `+` and `*` are **five**.

| | inline | primitives called | executed |
|---|---|---|---|
| `f-locals` | 196 B / **49** | `+ + *` = 15 | **64** |
| `f-juggle` | 36 B / **9** | `over + >r + r> *` = 24 | **33** |

So the locals spelling runs **1.94× the instructions for 1.35× the time**. It
is not fetch-starved or cache-thrashing; it executes at *better* IPC
(**1.35 vs 0.94** at 1.8 GHz, since it makes half as many calls) and simply has
far more to do.

**Where the instructions are.** A reference is six instructions on ARM64, and
**four of them are spent finding LP**: `MRS TPIDR_EL0`, two `ADD`s for the TLS
offset, then the load. That sequence is identical at every reference in the
word. On x86 the same thing is *one* instruction, `mov %fs:lp@tpoff,%rax` —
which is the whole reason x86 wins this comparison and ARM64 does not. Same
design, four instructions against one.

**The experiment (2026-08-15, branch discarded).** Cache LP in `X20` — which is
documented as available — for the duration of a word that has locals: the frame
build saves the caller's `X20` and the release restores it, ordinary
callee-saved discipline. References then cost **two** instructions instead of
six. Correctness was never the problem; it was verified on Pi hardware across
all four suites, deep recursion, nesting, early `exit`, and a deliberate
locals-stack overflow followed by recovery. Two properties made it cheaper than
it looks: `X20` is only ever live between a build and its matching release, so
**the signal handler needs no change** (after a fault it holds garbage that
nothing reads before the next build overwrites it), and registers are
per-thread already, so threads need nothing either.

Figures below come from the single run that also produced the instruction
counts: `f-locals` 26.4 ns, `f-juggle` 19.6 ns. The section above quotes
`f-locals` as 26.0 ns from an earlier run — run-to-run spread on this board is
~2%, so the two are the same result, and the derived ratios here use the 26.4
pair for consistency with the counts.

| | before | after |
|---|---|---|
| `f-locals` | 26.4 ns | 23.0 ns |
| code size | 196 B / 49 instrs | 144 B / 36 |
| **realistic `acc` loop** | **0.213 s** | **0.214 s** |

**It was rejected on the third row.** 13% on a reference-dense synthetic, 27%
smaller code — and *nothing at all* on a real workload. The `acc` loop
(`{: n | s :}` with `to s` inside `?do`) is dominated by its primitive calls and
loop overhead, so cheaper references dilute to zero. A microbenchmark row that
moves while the workload it stands for does not is the signal to stop.

**What was left on the table**, if this is ever revisited: reserving `X20`
globally rather than per-word would also remove the TLS access from the frame
itself (build 8 instructions → 1, release 8 → 1), predicting ~15 ns — a win
over 19.6, but a modest one, and the same reasoning says it would show up in
synthetics and not in the `acc` loop, since a frame is built once per call and
`acc` calls it once per 100,000 iterations. Against that: a global reservation
must reset `X20` in the signal handler's ucontext (the handler carries a
comment saying LP lives in TLS *"so no ucontext edit needed, but it must be
remembered"*), must change two places that use `X20` as scratch, and fails by
leaking a frame **silently** — surfacing much later as an overflow in unrelated
code, which is the shape of every serious bug this project has had.

**A note on the reasoning, because it was wrong three times.** The residual was
first attributed to I-cache pressure, then to being purely instruction-count
bound; both were refuted by counting. The surviving model — time tracks
instructions, but calls cost more per instruction than inline code — is only
*directional*: it predicted 21.0 ns for the experiment and reality was 23.0.
Treat any further estimate here as an argument for measuring, not as a result.

A fourth slip, caught in review and worth keeping as the reason for the table
above: the first version of this section put the executed counts at **58 and
27** — against the 64 and 33 measured here — by assuming every primitive was
three instructions, having measured only the four that are. `+` and `*` are
five. The direction survived — locals still run more instructions for less
time — but a section whose title is "counted, not guessed" had a guess in it.

A fifth, in the correction itself: it first described the superseded pair as
"58 and 33", pasting in the new f-juggle figure while quoting the old one for
f-locals. Both numbers here now come from `git show` rather than recall, which
is the only reliable way to quote a number you have just finished changing.

**The standing conclusion:** a local reference is cheaper than the `dup` it
replaces on both architectures, and locals are a clear win on x86. On ARM64 a
small, reference-dense word is modestly slower than the same word written with
stack juggling, because finding LP costs four instructions there and one on
x86. That is a property to know about, not a defect to fix — until a real
workload shows it costing something.

## The unwind contract

The frame must be released on every path that leaves a definition. With a
separate stack this is *not* automatic — the return stack unwinds itself, the
locals stack does not.

**The rule, which matters more than the list below:** *every path that reaches
`repl_loop` with a reset return stack must also reset `lp` to `lp0`.* State it
that way and a reset path added later is covered by construction. Enumerating
sites alone is how this gets missed — the first draft of this note listed four
and there are eight.

> **Corrected in stage 1.** The rule above is right for paths that reach
> `repl_loop`, and wrong for `forth_interpret_line`, which **returns to its
> caller** and can be nested inside a word that holds a live frame. Those exits
> restore `lp` to *this* call's entry value, not to `lp0`. See "Three things
> the design below got wrong" at the top.

**Normal return.** `forth_semicolon` and `forth_exit` emit an `lp` restore
before the `RET`, in definitions that declared locals. `compile_ret` has seven
callers, but the other five (`forth_value`, `forth_defer`, `forth_create`,
`forth_constant`, `forth_does`) emit `RET` for compiler-generated stubs that
cannot contain locals.

**Cooperative unwind.** `forth_catch` carries one more cell in its frame
alongside the saved DSP; `forth_throw`'s *caught* path restores `lp` from it.

**Reset-to-REPL paths — all eight, in `src/arch/x86/` and the ARM64 mirror:**

| site | file | what it is |
|---|---|---|
| `.Lthrow_reset` | `core.s` ~4885 | an **uncaught** throw — resets both stacks |
| `forth_quit` | `core.s` ~4919 | `QUIT`, which resets the return stack by definition |
| `dict_full` | `main.s` ~503 | dictionary exhausted |
| `.Lcf_longjmp` | `core.s` ~3123 | the interpret-line error unwind |
| `.Lsig_recover` | `platform_linux.s` ~534 | guard-page SIGSEGV — stack under/overflow |
| recovery anchor | `core.s` ~2288, ~2469 | `colon_dsp`/`saved_latest`/`saved_here` restore |
| REPL re-entry | `main.s` ~507 | fault or ABORT during a startup script |
| thread start | `core.s` ~4732 | each worker gets its own locals stack |

`ABORT` needs no entry of its own: it is `-1 throw`, so it funnels through
either a catch frame or `.Lthrow_reset`.

Two of these deserve singling out. **`.Lcf_longjmp`** restores `%rsp` wholesale
from `il_rsp`, abandoning the return stack without touching anything else — it
already unlinks the `handler` chain by hand, so this is the same shape of fix
in the same place. **`.Lsig_recover`** is the awkward one: it resumes at
`repl_loop` by rewriting RIP/RSP/R15/R12/R13 in the signal `ucontext` rather
than by executing a reset, which is exactly why grepping for the usual
`rp0(%rip), %rsp` idiom does not find it. Because `lp` lives in TLS rather than
a register, the handler can store to it directly — no `ucontext` edit needed —
but it has to be remembered.

This is where the work will actually go wrong. These are abort paths, and abort
paths here have a history: the partial-header bug needed fixing at five
separate ones, and the recovery anchor is global rather than per-definition. A
leaked frame is silent — nothing fails until the locals stack overflows, much
later, in unrelated code.

**Test obligation:** assert `lp` is back at `lp0` after *each* of the eight
paths, not a sample of them — a caught `throw`, an uncaught `throw`, `QUIT`, an
aborted colon definition, a stack underflow (guard page), a stack overflow, a
`dict_full`, and a worker thread exiting. Not "does it work" but "did the frame
go back", which is a different assertion and the only one that fails when a
reset path is missed.

## Scoping: locals shadow, and that is sharper here than elsewhere

A local takes precedence over anything of the same name in the dictionary, for
the rest of the definition, reverting at `;`. That is what every other language
does and what the standard requires.

The difference is that Forth lets you shadow **verbs**, not just data:

    : sum {: i :}  10 0 do i + loop ;   \ `i` is the local, NOT the loop index

`i` and `j` are primitives here, and `i` is about the most natural name a local
could have. `{: dup :}` would be worse. In C, shadowing costs you a variable;
here it can cost you the loop index or an operator, silently.

So: **shadow, but have the compiler print a note when a local's name already
exists in the dictionary.** It stays quiet for `x y w h s n` and speaks up
exactly when a verb is about to disappear. `to` follows the same resolution
order — `to x` stores to the local when one is in scope, to the `value`
otherwise.

## Core, not a library

This cannot be a `require`d `.fs` file, for a concrete reason rather than a
stylistic one: **five of the eight reset paths are in assembly** —
`.Lsig_recover` in `platform_linux.s`, `.Lcf_longjmp` and `forth_quit` in
`core.s`, `dict_full` in `main.s`. A library cannot reach them, so it could
never make the unwind contract hold. Name resolution also has to consult the
locals list *before* the dictionary while compiling, which is the outer
interpreter itself.

The split follows the house pattern: frame primitives and the `lp` resets in
`core.s`, the `{:` parsing word in `core.fs`.

Being in core costs nothing when unused. Frame code is emitted only in
definitions that declare locals; the resolution check is gated on a non-empty
locals list; the `lp` resets sit on error paths, not hot ones.

## Open questions

None blocking. The three that were here are resolved above or below:
assignable (yes), `does>` (reject), `see` (already free — it replays captured
source text rather than decompiling, so `{: s x y w h :}` prints verbatim).

## Two edges that needed deciding at compile time

> **Both decided and shipped.** `does>` is a compile-time error (it did not
> fail loudly — it returned a wrong number from a dead frame). `:noname` takes
> locals and works: `:noname {: a :} a 2 * . ;  21 swap execute` prints 42 with
> LP balanced. The "ninth thing to reset" below was right, and is cleared on
> every path that abandons a definition.

**`does>` must reject local references.** The body after `does>` runs when the
*created* word is executed — long after the defining word returned and its
frame was popped:

    : mk {: v :}  create v ,  does> @ v + ;   \ `v` here reads a dead frame

The name is lexically inside the same definition, but the frame is not live.
This has to be a compile-time error, not a wild read.

**`:noname` should take locals** like any other definition. Worth doing
alongside the open `:noname` bug in `docs/TODO.md`, because they share a root:
a definition abandoned part-way leaves `STATE` compiling, and locals add a
*second* piece of per-definition compile-time state — the list of local names.

That list is a ninth thing the abort paths must reset, and it is not the
runtime `lp`. It belongs wherever `drop_partial_header` is called and `state`
is zeroed (`.Lthrow_reset`, `forth_quit`, `.Lcf_longjmp`). Miss it and the
*next* definition inherits stale local names — which would compile, and be
wrong.

## Deliberately deferred

**Compile-time offset tracking**, where locals resolve to fixed data-stack
offsets and cost nothing at runtime. It needs the compiler to know the exact
data-stack depth at every point in a definition, which this compiler does not
track, and it constrains the feature (assignment and control-flow merges both
get awkward). It is a later optimisation, alongside the peephole inliner
already in the TODO.

The syntax is identical either way, so this can be swapped in later with no
user-visible change. That is what makes deferring it safe.
