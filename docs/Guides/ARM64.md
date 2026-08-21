# ARM64 registers and machine code

What you are looking at when `dis` prints a listing. BasicForth compiles
straight to machine code, so a definition is not a thread of tokens to be
decoded — it is AArch64, and `objdump` will show you every byte of it. The
vocabulary is small: four reserved registers, and about six instruction
shapes the compiler ever emits.

This is the reading guide, not an assembler tutorial. For the instruction
set itself see `docs/ARM64_Quick_Reference.md` in the source tree, and
`help dis` for the disassembler's own behaviour.

At a glance:

    X19    DSP      data stack pointer — the top item is [X19]
    X21    HERE     next free byte of dictionary space
    X22    LATEST   most recent dictionary entry
    SP     return stack — the hardware stack, used as Forth's
    X30    LR, the link register — written by every BL

    [X19]              top of stack       [X19, #8]   second item
    str x9,[x19,#-8]!  push               ldr x9,[x19],#8   pop
    bl <addr>  \ name  a Forth word
    stp x29,x30,[sp,#-16]!   /   ldp x29,x30,[sp],#16
                       the prologue and epilogue of a definition

**Destination first**, then the sources: `add x19, x19, #8` is
`x19 = x19 + 8`. Note this is the opposite of x86's AT&T syntax, where the
destination comes last — the single easiest thing to trip over when reading
both. See `help x86-order`.

The sections — each of these is `help <topic>`:

    arm64-reserved  the four registers holding engine state
    arm64-frame     the stp/ldp prologue, and why x86 has no equivalent
    arm64-regs      the whole register file, and what each one is for
    arm64-stack     push, pop and top-of-stack as instruction shapes
    arm64-literal   numbers, strings, and data embedded in the code
    arm64-calls     calling a word, control flow, and `does>` patching
    arm64-abi       the C and syscall conventions, for FFI and platform code
    arm64-worked    a whole definition read end to end
    arm64-see-also  related pages

## arm64-reserved

Four registers carry engine state, and they hold it across every call:

| Register | Holds                       | Notes                              |
|----------|-----------------------------|------------------------------------|
| `X19`      | DSP, the data stack pointer | Points **at** the top item             |
| `X21`      | HERE, dictionary free space | Where the next compiled byte lands |
| `X22`      | LATEST, newest dict entry   | Head of the chain `find` walks       |
| `SP`       | The return stack            | The machine stack, used as Forth's |

All four are **callee-saved** in the AAPCS64 ABI, and that is the whole
reason they were chosen. A C function reached through the FFI — an SDL
call, `dlopen`, anything — is obliged to give them back untouched, so the
Forth engine survives arbitrary foreign code without saving and restoring
state around every call.

The corollary matters if you write inline machine code: **clobber one of
these and you corrupt the interpreter**, usually not at the instruction
that did it. If your word needs a register, use a scratch one, or save and
restore the callee-saved register you borrow.

**Everything else is scratch, including the registers that look spare.**
`X9`–`X15` are caller-saved temporaries and used freely. `X20` and
`X23`–`X28` are callee-saved but *not* reserved: they are in live scratch
use throughout `core.s`, borrowed by whichever primitive needs them and
saved on entry — `X23`/`X24` are pushed as a pair at 32 sites. X20 in
particular is often described as free, and it is free only on paper; the
locals pointer lives in thread-local storage rather than in X20 for exactly
that reason.

`X16` and `X17` are linker veneer scratch and `X18` is platform-reserved:
avoid all three. `SP` must stay 16-byte aligned.

## arm64-frame

**This is the difference that will confuse you first.** Every colon
definition opens and closes with a pair of instructions that have no x86
counterpart:

    stp x29, x30, [sp, #-16]!      // prologue: save frame pointer and LR
    ...
    ldp x29, x30, [sp], #16        // epilogue: restore them
    ret

x86's `call` pushes the return address to memory, so a definition can begin
with its first real instruction. ARM64's `BL` instead writes the return
address into **X30, the link register** — a register, not the stack. That
is faster for a leaf function and fatal for a nested one: the moment a
definition calls another word, that `BL` overwrites X30 and the way home is
gone.

So every definition that calls anything must spill X30 before its first
`BL` and restore it before its `ret`. BasicForth spills X29 alongside it to
keep SP 16-byte aligned, which the ABI requires.

Two practical consequences when reading a listing:

- The first and last instructions are bookkeeping. **The word's actual
  behaviour starts on line two.** An ARM64 definition is always four bytes
  of prologue and eight of epilogue larger than its x86 twin, which is why
  the same source compiles to 32 bytes here and 27 there.
- **Primitives usually have no prologue.** `dis dup` is three instructions
  with no `stp`, because it calls nothing and never disturbs X30. A `stp`
  at the top of a primitive means it makes a call.

## arm64-regs

The whole register file, and what each one means here. ARM64 has thirty-one
general-purpose registers — nearly twice x86's — which is why primitives
here rarely spill anything.

| Register | 32-bit view | Role in BasicForth                               |
|----------|-------------|--------------------------------------------------|
| `X0`–`X7`    | `W0`–`W7`       | Scratch. C arguments 1–8; `X0` returns             |
| `X8`       | `W8`          | Scratch. **Syscall number**; AAPCS indirect          |
| `X9`–`X15`   | `W9`–`W15`      | Caller-saved temporaries — the workhorses here   |
| `X16` `X17`  | `W16` `W17`     | IP0/IP1, linker veneer scratch — **avoid**           |
| `X18`      | `W18`         | Platform register — **avoid**                        |
| `X19`      | `W19`         | **Reserved: DSP**                                    |
| `X20`      | `W20`         | Callee-saved scratch — holds `ctx` in workers      |
| `X21`      | `W21`         | **Reserved: HERE**                                   |
| `X22`      | `W22`         | **Reserved: LATEST**                                 |
| `X23`–`X28`  | `W23`–`W28`     | Callee-saved scratch — save what you borrow      |
| `X29`      | `W29`         | Frame pointer; spilled for SP alignment          |
| `X30`      | `W30`         | **LR** — written by every `BL`; see below              |
| `SP`       | `WSP`         | **Reserved: the return stack**, 16-byte aligned      |
| `XZR`      | `WZR`         | Reads as 0, writes are discarded                 |
| `PC`       | —           | Not addressable; reach it via `ADR`/`ADRP`           |
| `V0`–`V31`   | `Bn`…`Qn`       | FP/SIMD — see below                              |
| `NZCV`     | —           | Condition flags — set only by the `S` forms (`ADDS`) |

`Wn` is the bottom half of `Xn`, and **writing `Wn` zeroes the top half** —
there is no way to write just 32 bits and keep the rest, unlike x86's `%ax`
and `%al`.

**There is no register 31.** That encoding means `XZR` in most instructions
and `SP` in a few (`ADD`, `SUB`, and the load/store base), decided by the
instruction rather than by the operand. So `MOV X9, SP` and `MOV X9, XZR`
are genuinely different instructions that look nearly identical in the
encoding — worth remembering when a listing seems to move the stack pointer
somewhere surprising.

The SIMD file is a separate bank: `V0`'s low 64 bits are `D0`, its low 32
are `S0`, and `FMOV` is how a value crosses between `Xn` and that bank
without going through memory. Two things use it. The FFI passes float
arguments in `V0`–`V7` and takes a float return from `V0`, counted in their
own sequence independently of the integer arguments. And `popcount` borrows
`V0` for a trick with no integer equivalent: `FMOV` the cell across, `CNT`
counts the bits in all eight bytes at once, and `ADDV` sums those eight
per-byte counts into one.

## arm64-stack

The data stack is a plain array of 8-byte cells that grows **downward**,
with `X19` pointing at the top item. There is no top-of-stack register:
every operation goes through memory. That costs a little speed and buys a
great deal of simplicity, because no primitive has to agree with any other
about what is cached where.

**Square brackets mean "the memory at"**, the way parentheses do in AT&T —
`X19` is the address, `[X19]` is what is stored there. Unlike x86 there is
no exception to learn: brackets appear only on `LDR`/`STR` and their kin,
because arithmetic here never touches memory. To get an address without
loading from it, use `ADR`/`ADRP` rather than a `lea`-style trick.

ARM64's indexed addressing modes make push and pop single instructions —
the pointer update rides along with the memory access:

    ldr x9, [x19]              // read top of stack (does not pop)
    ldr x10, [x19, #8]         // read second item

    str x9, [x19, #-8]!        // push: pre-index — decrement, then store
    ldr x9, [x19], #8          // pop:  post-index — load, then increment

The `!` is the tell. `[x19, #-8]!` writes X19 back *before* the access;
`[x19], #8` writes it back *after*. Read those two lines as "push" and
"pop" and most listings read themselves.

**Why `drop` loads a value it never uses.** `dis drop` shows this:

    ldr x9, [x19]
    add x19, x19, #0x8
    ret

The load looks dead, and it isn't. The stack is bracketed by two
`PROT_NONE` guard pages, so overflow and underflow arrive as a SIGSEGV the
handler turns into a Forth error. But *moving* a pointer never faults —
only touching memory does. Without that read, `drop` on an empty stack
would walk X19 quietly into the guard page and the fault would surface
later, inside some unrelated word. Touching the cell first makes the error
land on the word that caused it. (Note it is a plain `ldr` plus `add`, not
the post-index pop: the point is to touch the cell, and the two-instruction
form makes that explicit.)

## arm64-literal

A number compiles to an **immediate** — the value is built into the
instruction, with no call and no inline data:

    mov x9, #0x3               // #3
    str x9, [x19, #-8]!        // push it

Two instructions, and `objdump` helpfully prints the decimal value in the
margin. That is the common case and it needs no annotation.

The older shape — a `bl lit` followed by an 8-byte cell — survives only
where the cell is **storage** that something reads or patches later: a
`constant`, a `value`, a `create` body, a deferred word, and `[']`. `dis`
knows the shape and prints the cell as data rather than decoding it as
instructions:

    bl  0x401958  \ lit
    2a 00 00 00 00 00 00 00      \ literal: 42

Strings are the other embedded shape — a call to the string runtime, an
8-byte length, then the characters, **padded to a 4-byte boundary** so the
next instruction stays aligned:

    bl  0x4048d0  \ (s")
    02 00 00 00 00 00 00 00 68 69 00 00   \ s" hi"
    bl  0x4048a0  \ type

Those two trailing zeros are the padding, not part of the string. ARM64
instructions are always four bytes at a four-byte boundary, so unlike x86 a
misaligned resume would not merely decode wrongly — it could not decode at
all.

## arm64-calls

Under Subroutine Threaded Code, calling a Forth word is calling a
subroutine. There is no inner interpreter and no dispatch loop:

    bl  0x400b38  \ dup

The `\ dup` is `dis` reverse-mapping the target through the dictionary —
`objdump` supplies the address, BasicForth supplies the name.

Control flow compiles to ordinary branches over the same stack idioms.
`if` pops a flag and tests it, usually with `cbz`, which compares against
zero and branches in one instruction:

    ldr x9, [x19], #8          // pop the flag
    cbz x9, 0x45c858           // ...to the else branch

`do`/`loop` keeps the limit and index on the return stack as a pair, which
is why `i` reads through `SP`:

    stp x9, x10, [sp, #-16]!   // index and limit
    ldr x9, [sp]               // i
    ...
    add x9, x9, #0x1
    cmp x9, x10
    b.eq 0x45c97c              // done

Locals reach their frame through a TLS slot, so they are per-thread. This
is the one place ARM64 is conspicuously wordier:

    mrs x9, tpidr_el0          // thread pointer
    add x9, x9, #0x0, lsl #12  // ...plus the module offset
    add x9, x9, #0x38          // ...plus this variable's slot
    ldr x9, [x9]               // the locals pointer at last

Four instructions where x86 needs one `mov %fs:...`. A definition using
locals repeats that sequence per access, which is why a listing with locals
looks so much longer than the source suggests. The cost has been measured;
it is real but small, and an attempt to cache the pointer in X20 showed no
improvement on a real workload and was discarded.

**A `b` where you expect a `ret`** means `does>`. `create` compiles a
literal and a `ret`; attaching a `does>` overwrites that `ret` with a
branch to the behaviour:

    bl   0x401958  \ lit
    f0 c8 45 00 00 00 00 00      \ literal: 0x45c8f0
    b    0x45c89c

No padding is involved, because a `B` and a `RET` are both exactly four
bytes. (The x86 build has to reserve four `nop`s after its `ret` to make
room for a five-byte `jmp` — see `help x86-calls`. Fixed-width instructions
pay off here.)

## arm64-abi

Everything above concerns Forth code calling Forth code. Two other calling
conventions show up in listings — in `dis` of a platform word, and any time
you read FFI or inline assembly.

**AAPCS64, for C calls:**

| Category            | Registers                                     |
|---------------------|-----------------------------------------------|
| Arguments, in order | `X0`–`X7`                                         |
| Return value        | `X0` (and `X1` for 128-bit)                       |
| Caller-saved        | `X0`–`X15` (X9–X15 are the pure temporaries)      |
| Callee-saved        | `X19`–`X28`                                       |
| Special             | `X16`/`X17` veneers, `X18` platform, `X29` FP, `X30` LR |

`SP` must be 16-byte aligned at all times, not merely at a call — a stricter
rule than x86's. Forth's return stack is deliberately *not* ABI-aligned, so
a C call cannot simply be made from Forth code; see `docs/Core_Primitives.md`
for how the boundary is crossed.

**Linux syscalls**, which the platform layer uses instead of libc:

|                |                         |
|----------------|-------------------------|
| Syscall number | `X8`                      |
| Arguments      | `X0`–`X5`                   |
| Instruction    | `svc #0`                  |
| Return         | `X0`, negative for `-errno` |

The number goes in X8 rather than X0 precisely so the arguments can stay in
the ordinary argument registers. A listing that loads X8 with a constant and
executes `svc` is talking to the kernel.

## arm64-worked

A whole definition, end to end:

    > : sq dup 3 * + ;
    > dis sq
    sq: 32 bytes at 0045C83C (dictionary)
      45c83c:  a9bf7bfd  stp  x29, x30, [sp, #-16]!
      45c840:  97fe90be  bl   0x400b38  \ dup
      45c844:  d2800069  mov  x9, #0x3
      45c848:  f81f8e69  str  x9, [x19, #-8]!
      45c84c:  97fe9107  bl   0x400c68  \ *
      45c850:  97fe90f8  bl   0x400c30  \ +
      45c854:  a8c17bfd  ldp  x29, x30, [sp], #16
      45c858:  d65f03c0  ret

Line by line: save the link register; call `dup`; build the literal 3 and
push it; call `*`; call `+`; restore the link register; return. Five source
words, five pieces of machine code, in order, wrapped in the frame that
keeps the way home. Note every instruction is exactly four bytes — the
addresses climb by four all the way down, which is a useful sanity check
that you are looking at code and not at data.

The header line tells you which of the two worlds you are in.
`(dictionary)` means the code lives in the RWX dictionary mapping, compiled
at runtime. The other case is a primitive, which lives in the binary's
`.text` and comes with a real symbol:

    > dis dup
    dup: primitive at 00400B38 (in the binary)
    0000000000400b38 <forth_dup>:
      400b38:  f9400269  ldr  x9, [x19]
      400b3c:  f81f8e69  str  x9, [x19, #-8]!
      400b40:  d65f03c0  ret

Read TOS, push it back. No prologue, because `dup` calls nothing. `dup` is
three instructions.

## arm64-see-also

- `help dis` — the disassembler word itself, and what it needs installed.
- `help x86` — the same guide for the other architecture.
- `docs/ARM64_Quick_Reference.md` — the instruction set and syntax.
- `docs/Core_Primitives.md` — the stack layout, guard pages, and the C
  boundary.
