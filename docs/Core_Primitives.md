# BasicForth — Core ASM Primitives

The core primitives layer is the middle layer of BasicForth's three-layer
architecture. It contains the minimum set of operations that must be
written in assembly — either because they directly manipulate the data
stack, or because they can't be expressed in Forth.

```
┌─────────────────────────────────────────────┐
│  core.fs          (pure Forth words)        │  Portable across all platforms
├─────────────────────────────────────────────┤
│  core.s           (asm primitives)     ◄──  │  THIS LAYER
├─────────────────────────────────────────────┤
│  platform_linux.s (Linux syscalls)          │  Per-arch, platform-specific
└─────────────────────────────────────────────┘
```

## Design Philosophy

- **Per-architecture, platform-independent.** Each architecture has its own
  core.s, but none of them reference the OS. They only call platform_linux.s
  functions for I/O.
- **Minimize this layer.** Anything that can be written in Forth should be
  in core.fs instead (see [Forth_Core_Words.md](Forth_Core_Words.md)). Only what *must* be asm belongs here.
- **Identical stack effects.** Every primitive has the same Forth-level
  behavior on both architectures. The assembly differs, the semantics don't.

## Data Stack

The data stack holds Forth values. All items live in a memory region in
.bss. The data stack pointer (DSP) always points to the **top item** on
the stack (or equals `sp0` when the stack is empty).

```
                    Low addresses
                    ┊
  guard_page_overflow   4096 bytes   PROT_NONE
  ──────────────────────────────────────────────
  data_stack_bottom     page-aligned
                    │
                    │   ... unused space ...
                    │
          DSP ───► ├── top item
                    ├── second item
                    ┊
  data_stack_top ──► ├── bottom item
  ──────────────────────────────────────────────
  guard_page_underflow  4096 bytes   PROT_NONE
                    High addresses
```

The stack grows **downward**. Pushing decrements DSP, popping increments
it. When the stack is empty, DSP equals `sp0` (which points to
`data_stack_top`). Stack depth is `(sp0 - DSP) / CELL`.

### Guard Pages

The data stack is bracketed by two 4096-byte guard pages marked
`PROT_NONE` via `mprotect` at startup. Any access to a guard page
triggers a SIGSEGV, which our signal handler catches and recovers from.
See [Error_Handling.md](Error_Handling.md) for details.

- **Underflow**: reading past `sp0` touches the underflow guard page.
- **Overflow**: pushing past `data_stack_bottom` touches the overflow
  guard page.

This provides zero-cost bounds checking — the CPU's MMU does the work as
part of normal memory access, with no extra instructions in the normal case.

### Configuration

| Parameter       | Value                   | Notes                        |
|-----------------|-------------------------|------------------------------|
| CELL            | 8 bytes                 | 64-bit cells, native word    |
| DATA_STACK_SIZE | 4096                    | 512 cells (4096 / 8)         |
| Alignment       | page-aligned            | Required for guard pages     |

### Register Allocation

| Register | ARM64 | x86-64 | Notes                                        |
|----------|-------|--------|----------------------------------------------|
| DSP      | X19   | R15    | Data stack pointer (top item)                |
| HERE     | X21   | R13    | Dictionary free-space pointer                |
| LATEST   | X22   | R12    | Most recent dictionary entry                 |
| RSP      | SP    | RSP    | Return stack (hardware stack)                |

All engine registers are **callee-saved** in their respective ABIs
(AAPCS64 for ARM64, System V AMD64 for x86-64). This means:

- C library functions won't clobber them
- Nested calls within BasicForth preserve them automatically
- Future C interop works without special save/restore code

### Push and Pop

**Push a new value onto the stack:**
1. Decrement DSP by CELL
2. Store the value at the new DSP

**Pop a value off the stack:**
1. Load the value from DSP
2. Increment DSP by CELL

**ARM64:**

```asm
// Push value in X9 onto the stack
STR X9, [X19, #-CELL]!         // pre-decrement: X19 -= 8, store X9

// Pop top of stack into X9
LDR X9, [X19], #CELL           // post-increment: load, X19 += 8
```

ARM64's pre-decrement and post-increment addressing modes combine the
pointer arithmetic and memory access in a single instruction.

**x86-64:**

```asm
# Push value in %rax onto the stack
sub $CELL, %r15                 # make room
mov %rax, (%r15)               # store value

# Pop top of stack into %rax
mov (%r15), %rax               # load value
add $CELL, %r15                # reclaim space
```

x86 doesn't have pre-decrement/post-increment addressing modes, so push
and pop are each two instructions.

## Current Primitives

### Stack Operations

#### DUP ( a -- a a )

Duplicate the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`               | `mov (%r15), %rax`             |
| `STR X9, [X19, #-CELL]!`      | `sub $CELL, %r15`              |
|                                 | `mov %rax, (%r15)`             |

Load the top item, then push a copy. ARM64's pre-decrement store does
the push in one instruction.

#### DROP ( a -- )

Discard the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`               | `mov (%r15), %rax`             |
| `ADD X19, X19, #CELL`          | `add $CELL, %r15`              |

The dummy load (`LDR` / `mov`) reads from the current top before
incrementing DSP. This is essential: without it, DROP on an empty stack
would silently move DSP into the guard page without faulting. The load
ensures the guard page triggers immediately.

#### SWAP ( a b -- b a )

Exchange the top two stack items.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`               | `mov (%r15), %rax`             |
| `LDR X10, [X19, #CELL]`       | `mov CELL(%r15), %rcx`         |
| `STR X10, [X19]`              | `mov %rcx, (%r15)`             |
| `STR X9, [X19, #CELL]`        | `mov %rax, CELL(%r15)`         |

Load both items into registers, write them back in swapped positions.
DSP doesn't move.

#### OVER ( a b -- a b a )

Copy the second item to the top.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19, #CELL]`        | `mov CELL(%r15), %rax`         |
| `STR X9, [X19, #-CELL]!`      | `sub $CELL, %r15`              |
|                                 | `mov %rax, (%r15)`             |

Load the second item (at DSP+CELL), push it onto the stack.

### Arithmetic

#### + ( a b -- a+b )

Add the top two items.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19], #CELL`        | `mov (%r15), %rax`             |
| `LDR X10, [X19]`              | `add $CELL, %r15`              |
| `ADD X10, X10, X9`            | `add %rax, (%r15)`             |
| `STR X10, [X19]`              |                                 |

Pop b, add to a in place. x86's `add %rax, (%r15)` adds a register
directly to memory, making this compact.

#### - ( a b -- a-b )

Subtract b from a.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19], #CELL`        | `mov (%r15), %rax`             |
| `LDR X10, [X19]`              | `add $CELL, %r15`              |
| `SUB X10, X10, X9`            | `sub %rax, (%r15)`             |
| `STR X10, [X19]`              |                                 |

Pop b, subtract from a in place. x86's `sub %rax, (%r15)` computes
`[r15] - rax` and stores back, which is exactly `a - b`.

#### NEGATE ( a -- -a )

Negate the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`               | `negq (%r15)`                  |
| `NEG X9, X9`                  |                                 |
| `STR X9, [X19]`               |                                 |

ARM64 requires a load-negate-store sequence since NEG operates on
registers. x86's `negq` operates directly on memory in one instruction.

### I/O Wrappers

These primitives bridge the data stack to the platform layer. They move
values between the stack and the platform's argument/return registers.

#### forth_emit ( char -- )

Pop a character from the stack and write it to stdout.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X0, [X19], #CELL`        | `mov (%r15), %rdi`             |
| `B platform_emit`              | `add $CELL, %r15`              |
|                                 | `jmp platform_emit`            |

Pop the character into the platform's first argument register (X0 or
RDI) and tail-call `platform_emit`. Since there's nothing to do after
the platform call returns, the tail call lets `platform_emit`'s RET
return directly to the original caller.

#### forth_key ( -- char )

Read one character from stdin and push it onto the stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `STP X29, X30, [SP, #-16]!`   | `call platform_key`            |
| `BL platform_key`              | `sub $CELL, %r15`              |
| `STR X0, [X19, #-CELL]!`      | `mov %rdi, (%r15)`             |
| `LDP X29, X30, [SP], #16`     | `ret`                          |
| `RET`                           |                                 |

Call `platform_key`, push the returned character. KEY cannot use a tail
call because we need to push the return value after the platform call.
ARM64 must save/restore X30 (link register) since BL overwrites it.

`platform_key` returns the character in X0 (ARM64) or RDI (x86-64).

## Data Stack Memory

Allocated in the .bss section with page-aligned guard pages:

```asm
.bss
.balign 4096
guard_page_overflow:                # mprotect PROT_NONE at startup
    .space 4096
.balign 4096
data_stack_bottom:
    .space DATA_STACK_SIZE          # 4096 bytes = 512 cells
.global data_stack_top
data_stack_top:                     # DSP starts here (empty stack)
.balign 4096
guard_page_underflow:               # mprotect PROT_NONE at startup
    .space 4096
```

`data_stack_top` is exported as a global symbol so that main.s can
initialize the DSP register:

```asm
# ARM64:                          # x86-64:
ADR X19, data_stack_top           lea data_stack_top(%rip), %r15
```

On an empty stack, DSP equals `sp0` and no items exist in memory.

## Additional Primitives (since initial documentation)

The following primitives have been added to core.s on both architectures.
See [Forth_Core_Words.md](Forth_Core_Words.md) for the full vocabulary.

### Stack (all in asm)

ROT, NIP, TUCK, 2DUP, 2DROP, DEPTH, ?DUP, >R, R>, R@

### Arithmetic (all in asm)

\*, /MOD (divide-by-zero safe), 1+, 1-, ABS, MIN, MAX

### Logic and Comparison (all in asm)

AND, OR, XOR, INVERT, =, <, >, 0=, 0<

### Interpreter and Compiler

| Word              | Stack effect          | Notes                              |
|-------------------|-----------------------|------------------------------------|
| LIT               | ( -- x )              | Push inline literal (hidden)       |
| EXECUTE           | ( xt -- )             | Call execution token               |
| :                 | ( "name" -- )         | Begin colon definition             |
| ;                 | ( -- )                | End definition (IMMEDIATE)         |
| IMMEDIATE         | ( -- )                | Mark word as immediate             |
| '                 | ( "name" -- xt )      | Find xt (IMMEDIATE)                |
| (                 | ( "ccc)" -- )         | Paren comment (IMMEDIATE)          |
| \                 | ( "ccc" -- )          | Line comment (IMMEDIATE)           |
| EVALUATE          | ( c-addr u -- )       | Interpret string as Forth          |
| INCLUDED          | ( c-addr u -- )       | Load and interpret a source file   |
| INTERPRET-LINE    | ( -- )                | Internal: interpret current source |

### Future Primitives

| Word      | Stack effect          | Notes                           |
|-----------|-----------------------|---------------------------------|
| BRANCH    | ( -- )                | Unconditional branch            |
| 0BRANCH   | ( flag -- )           | Branch if false                 |
| EXIT      | ( -- )                | Return from word (RET)          |
| ,         | ( x -- )              | Compile cell to dictionary      |
| HERE      | ( -- addr )           | Push HERE register              |
