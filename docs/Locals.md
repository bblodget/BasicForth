# Locals — Design Note

Status: **stage 2 built (2026-08-12): `{: … :}` compiles, on both
architectures, with open-coded references.** Stage 1 (2026-08-11) was the
runtime frame and its unwind contract. Phase 8 (`docs/TODO.md`, "Threading and Locals").
This note records what the runtime-frame design costs, where it can go wrong,
and what still has to be decided.

## What stage 2 shipped

`{: a b c :}` as an immediate word in `core.fs`, name resolution ahead of the
dictionary in the outer interpreter, and an **open-coded** reference: x86-64
emits 23 bytes (a TLS load, an offset load, and a push), ARM64 24 bytes / six
instructions. Neither calls anything. Frame build and release remain ordinary
calls, since they happen once per invocation rather than once per mention.

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

These are the **testing** surface, not the compiled one. Stage 2 must open-code
the reference, not call `(local@)` — see "The one thing that decides this".

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

## Recommendation

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

Not measured on ARM64: the only ARM64 target here is QEMU, where timings mean
nothing. Worth repeating on the Pumpkin board before committing to the design.

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

## Two edges that need deciding at compile time

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
