# Performance — what BasicForth costs, and why

BasicForth compiles to native code, so "how fast is it" has an answer you
can measure at the prompt and then *read*: `time` gives you the number,
`dis` gives you the machine code behind it. This page does both for one
benchmark — counting to a billion — and draws out the two lessons hiding
in the numbers.

Everything here is a measurement, not an aspiration. Where we lose, it
says so.

## The measurements

Laptop: AMD Ryzen 9 8945HS, Linux, 2026-07-24. Every row runs the same
work — a loop of 10^9 iterations — timed as wall clock including process
startup (BasicForth's startup is below `time(1)`'s resolution, so wall
clock is loop time), best of five runs. Compared against g++ 11.4 at
`-O0`, gforth 0.7.3, and CPython 3.10.

The `begin`/`until` row was re-measured on 2026-08-15, same machine and same
best-of-five method, after literals stopped compiling to a call: it was 3.66 s
before that change. Every other row is untouched by it — `do`/`loop` evaluates
its bounds once at entry, so its literals never sat in the loop.

    C++ -O0, counter only                       0.36 s
    BasicForth   do loop (empty)                0.41 s
    C++ -O0, accumulator (two increments)       0.47 s
    gforth-fast  do loop                        0.99 s
    BasicForth   do 1+ loop                     1.02 s
    gforth       do loop                        1.24 s
    gforth-fast  do 1+ loop                     1.28 s
    gforth       do 1+ loop                     1.58 s
    BasicForth   begin 1+ dup <n> = until       2.90 s
    Python       while n += 1                  45.3  s

Two honesty notes on the C++ rows. First, they are `-O0` on purpose: at
`-O2` the optimizer proves the loop's result and deletes it, and the
benchmark reports `0.00 s`. Unoptimized C is the fair reference because it
compiles the loop you actually wrote, which is what BasicForth does too.
Second, the two C++ rows exist because the loops differ in real work: our
empty `do loop` increments one counter, so it belongs next to C's
counter-only loop; `do 1+ loop` increments two, so it belongs next to C's
accumulator version.

Read that way: **an empty counted loop runs at unoptimized-C speed** (0.41
vs 0.36 s), and adding one word to the body costs us more than it should
(1.02 vs 0.47 s). Both facts come straight out of the compiled code.

## Why counted loops are fast

`do`/`loop` compiles fully inline — no calls at all:

    require disasm.fs
    : b1 1000000000 0 do loop ;
    dis b1

    b1: 62 bytes at 0044DE04 (dictionary)
      44de04:  49 83 ef 08           sub    $0x8,%r15        \ push the limit
      44de08:  49 c7 07 00 ca 9a 3b  movq   $0x3b9aca00,(%r15)
      44de0f:  49 83 ef 08           sub    $0x8,%r15        \ push the start
      44de13:  49 c7 07 00 00 00 00  movq   $0x0,(%r15)
      44de1a:  49 8b 07              mov    (%r15),%rax      \ DO: pop limit
      44de1d:  49 8b 57 08           mov    0x8(%r15),%rdx   \     and index
      44de21:  49 83 c7 10           add    $0x10,%r15
      44de25:  48 39 c2              cmp    %rax,%rdx        \ zero-trip check
      44de28:  0f 84 13 00 00 00     je     0x44de41
      44de2e:  52                    push   %rdx             \ park them on the
      44de2f:  50                    push   %rax             \  return stack
      44de30:  58                    pop    %rax             \ LOOP: take them back
      44de31:  5a                    pop    %rdx
      44de32:  48 ff c0              inc    %rax             \ index+1
      44de35:  48 39 c2              cmp    %rax,%rdx        \ reached the limit?
      44de38:  74 07                 je     0x44de41
      44de3a:  52                    push   %rdx
      44de3b:  50                    push   %rax
      44de3c:  e9 ef ff ff ff        jmp    0x44de30
      44de41:  c3                    ret

The two bounds are built straight into instructions and run once, at entry —
no call, no inline data to fetch (before 2026-08-15 each was a `call lit`
plus eight bytes of payload, and cost about five times a plain call because
`lit` returns past its own operand and mispredicts). The loop itself is the
eight instructions from `44de30` to `44de3c`: index and limit live on the
hardware return stack (`push`/`pop`, which is what makes `i` work inside
the body), the compare and branch are inline machine instructions, and
**nothing in the loop is a subroutine call**. That is the whole
explanation for 0.41 s.

It is also why we beat gforth here by 2.5×: a threaded-code system pays an
indirect dispatch per loop iteration, and we pay none.

## What a body word costs

Now put one word in the body:

    : b2 0 1000000000 0 do 1+ loop . ;
    dis b2

      ...
      43e84f:  52                    push   %rdx
      43e850:  50                    push   %rax
      43e851:  e8 11 31 fc ff        call   0x401967  \ 1+     <-- new
      43e856:  58                    pop    %rax
      43e857:  5a                    pop    %rdx
      43e858:  48 ff c0              inc    %rax
      ...

One instruction was added — a `call`. And here is what it reaches:

    dis 1+

    1+: primitive at 00401967 (in the binary)
    0000000000401967 <forth_one_plus>:
      401967:  49 83 07 01           addq   $0x1,(%r15)
      40196b:  c3                    ret

**A four-byte body behind a five-byte call.** The work `1+` does is one
instruction; the call and return that wrap it are pure overhead, and the
overhead is bigger than the payload. Under subroutine-threaded code every
word in a hot loop pays this.

How much? Grow the body with `1+ 1-` pairs and measure the slope, against
gforth-fast doing the same:

    body words     BasicForth    gforth-fast
        0            0.40 s        1.03 s
        1            1.01 s        1.32 s
        2            1.82 s        1.57 s
        4            3.53 s        2.85 s
        8            6.90 s        4.49 s

Per added word: **0.84 ns for us, 0.45 ns for gforth-fast.** Our loop
overhead is far lower, but our per-word cost is nearly double, so the two
lines cross between one and two body words: empty loops and one-word
bodies are ours, and from two words on gforth-fast pulls ahead with the
gap widening as the body grows.

The reason is the flip side of the design. gforth-fast's dispatch is
dearer, but it keeps the top of stack in a register, so `1+` is a register
increment. We dispatch with a plain `call` — cheap, and it is why the loop
itself is fast — but our data stack is pure memory, so `1+` is a
read-modify-write at `(%r15)`, and it cannot be folded into the caller.

## Why `begin`/`until` is 7× the cost

Same count, different loop structure:

    : b3 0 begin 1+ dup 1000000000 = until . ;
    dis b3

      44de0f:  e8 e0 3a fb ff        call   0x4018f4  \ 1+
      44de14:  e8 69 38 fb ff        call   0x401682  \ dup
      44de19:  49 83 ef 08           sub    $0x8,%r15       \ the limit, inline
      44de1d:  49 c7 07 00 ca 9a 3b  movq   $0x3b9aca00,(%r15)
      44de24:  e8 04 3b fb ff        call   0x40192d  \ =
      44de29:  49 8b 07              mov    (%r15),%rax     \ UNTIL: pop flag
      44de2c:  49 83 c7 08           add    $0x8,%r15
      44de30:  48 85 c0              test   %rax,%rax
      44de33:  0f 84 d6 ff ff ff     je     0x44de0f

Three calls per iteration instead of zero — the counter bump, the copy and
the comparison are all words here, while `do`/`loop` does the equivalent
compare inline and keeps the counter off the data stack entirely. 2.90 s
versus 0.41 s.

It was 3.66 s until 2026-08-15, when the limit stopped being a `call lit`
plus eight bytes of payload and became the two inline instructions above.
That one change is the whole 0.75 s: a literal used to cost about five
times a plain call, because `lit` reaches its operand through its own
return address and returns past it, mispredicting every time.

**This is the biggest lever in the language.** Same algorithm, same
machine, same compiler: choosing the right loop structure is worth 7×. No
amount of cleverness inside the body recovers what the wrong loop shape
costs.

## Storing into a `value` vs a `variable`

Measured 2026-07-29, same laptop, 20×10^6 iterations, three runs each
(spread under 15%). The loop body is one store or one read:

    read a value      ( : rval 0 do n drop loop ; )      0.55 s   ~11 ns
    read a variable   ( : rvar 0 do v @ drop loop ; )     0.59 s   ~12 ns
    write a value     ( : wval 0 do i to n loop ; )       0.05 s   ~2 ns
    write a variable  ( : wvar 0 do i v ! loop ; )        0.56 s   ~28 ns

Reads are within a few percent. **Writes are 12× apart**, and not for the
reason you would guess: both compile to *three* calls, and the `to` version
is the bigger code (32 bytes against 24), because `to` compiles the address
as an inline literal where `v` is a call.

    : wval  7 to n ;      lit 7 | lit <addr> | !        \ 32 bytes
    : wvar  7 v ! ;       lit 7 | call v    | !        \ 24 bytes

What differs is *where the store lands relative to code being executed*.
`v !` calls `v`'s push-the-address stub and then stores into the cell
sitting immediately next to that stub — in a dictionary that is RWX with
code and data interleaved. That is the pattern a CPU treats as
self-modifying code, and it pays for it with pipeline machine clears.
`to n` inlines the address, so the loop never executes code adjacent to
the cell it writes.

Supporting evidence, and its limit: pointing the store at a **heap** cell
instead (via `allocate`) took it from 0.56 s to 0.21 s — most of the gap,
which confirms the store's location matters. It does not account for the
remaining 4× against `to`, so treat the mechanism as well-supported rather
than settled.

Two things follow. For a hot per-frame scalar, `value` + `to` is the
faster shape as well as the safer one (`help defining-words` covers when
you need a `variable` anyway — anything that must have an address). And
this is a performance argument for the hardening item that would replace
`ld -N` (OMAGIC, all segments RWX) with `mprotect` on just the dictionary:
separating code from data pages is exactly what would remove the effect.

Below a tight loop this is noise. 28 ns is nothing against a frame.

## `<=` as a primitive, versus spelling it `> 0=`

The standard comparison set stops at `<` and `>`, so a Forth without `<=`
makes you write `> 0=`. That is correct, and it is also two words where the
processor already had the answer: the compare sets the flags, and `> 0=`
throws away the one it wanted, materialises a flag in memory, then loads it
back to invert it.

Measured 2026-07-30, same laptop, 20×10^6 iterations, three runs each
(spread under 5%). Each body is `5 6 <op> drop`; `base` is the same loop
with `2drop` in place of the comparison, so the last column is the
comparison alone:

    base    ( 5 6 2drop )                   0.074 s      --
    <=      ( 5 6 <= drop )                 0.105 s    ~1.6 ns
    > 0=    ( 5 6 > 0= drop )               0.133 s    ~3.0 ns
    : le3 > 0= ;                            0.142 s    ~3.4 ns

**The primitive is about half the cost of the sequence it replaces**, and
the difference is exactly what the call structure predicts: one call
instead of two, three if you wrap it in a colon definition. It tracks the
0.84 ns-per-word slope measured above.

The primitive itself is free to provide. `forth_le` is `forth_less` with
one condition code changed — `jg` for `jge` on x86, `CSETM LE` for `LT` on
ARM64 — so `<=` costs exactly what `<` costs. Same for `>=`, `u<=`, `u>=`.

The tempting shortcut is worth naming so nobody re-derives it: `: <= 1+ < ;`
is **wrong**, because `1+` wraps when `n2` is the largest cell value. If you
are on a Forth without these words, `> 0=` is the correct slow spelling.

As always, scale matters: 1.4 ns is nothing outside a hot loop. This is a
free win, not a reason to rewrite working code.

## Practical guidance

- **Use `do`/`loop` for hot counted loops.** It is the one construct that
  compiles with zero calls per iteration.
- **In a hot body, prefer fewer, fatter words.** Each word in the inner
  loop is a call/return you pay 10^9 times. A body that would be five
  words is often better as one definition doing the same work with locals
  on the return stack — or, honestly, as one more primitive.
- **Measure before you tune.** `time` is built in:

        : bench 1000000000 0 do loop ;
        time bench           \ 0.419 s

  It leaves the stack as it found it, so a word that takes arguments works
  (`50000000 time spin`) and results still come back. Resolution is one
  millisecond, so run fast things in a loop.
- **Then read the code.** `require disasm.fs` and `dis <name>` shows what
  the compiler actually emitted, with every call annotated by name. Timing
  tells you *that* something is slow; `dis` tells you *why*, and it is the
  same two-step you just watched on this page.

## Known limits, and what is planned

- **The per-word call/return tax is the big one.** A **peephole inliner**
  would open-code short primitives at the call site — `call 1+` becoming
  `incq (%r15)`, which as shown above is *smaller* than the call it
  replaces. That drives the 0.84 ns/word slope toward zero and would put
  us ahead at every body length, not just the first word or two.
- **`loop` parks index and limit on the return stack every iteration**
  solely so `i` works in the body. When the body never touches `i` or the
  return stack, they could stay in registers and the loop becomes
  inc/cmp/jne — which *is* the C `-O0` loop. Worth roughly 0.41 → 0.38 s
  on the empty benchmark.

Both are open items in docs/TODO.md ("Performance / Optimizer") — and both
are **deliberately deferred** as of 2026-07-25. The base they would sit on
is still moving, and an optimizer that miscompiles surfaces as "this new
feature is broken", which sends you hunting in the wrong layer. They get
reopened when the interface has settled *and* a profile of a real program —
a game, a control loop, not a microbenchmark — shows word dispatch among
the top costs. Everything on this page measures an empty loop, which is the
one case where dispatch dominates because nothing else is happening.

When they do land, the numbers here change and this page gets re-measured.

## Reproducing this

The benchmark is five lines. With the binary built:

    \ bench.fs
    : b1 1000000000 0 do loop ;                    \ empty counted loop
    : b2 0 1000000000 0 do 1+ loop drop ;          \ one body word
    : b3 0 begin 1+ dup 1000000000 = until drop ;  \ the other loop shape
    time b1  time b2  time b3
    bye

For the body-word scaling table, add `1+ 1-` pairs to `b2`'s body. For the
disassembly, `require disasm.fs` first, then `dis b1` and friends.

Numbers are **x86-64 only**. ARM64 figures wait on real hardware: the
cross-build runs under qemu user-mode emulation on this laptop, which
measures qemu's translation cost, not the board's.

## See Also

- docs/Disassembler.md — how `dis` decodes and annotates machine code.
- docs/Core_Primitives.md — the pure-memory data stack these costs come from.
- docs/Conditionals.md — how `do`/`loop` and `begin`/`until` are compiled.
- `help tools` — the reference entries for `time`, `dis`, and `see`.
- docs/TODO.md, "Performance / Optimizer" — the open optimizer work.
- docs/TODO.md, "Future / Hardening" — the `ld -N` → `mprotect` item, which
  the `variable`-store measurement above turns into a performance question
  as well as a hygiene one.
- `help defining-words` — `value` vs `variable` semantics, and when only a
  variable will do (anything that needs an address).
