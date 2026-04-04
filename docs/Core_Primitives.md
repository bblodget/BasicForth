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

The data stack is a region of memory in .bss, managed by a dedicated
register. It grows downward (toward lower addresses), matching the
hardware stack convention.

### Layout

```
                    Low addresses
                    ┊
                    ├── data_stack_bottom (start of .bss allocation)
                    │
                    │   ... unused space ...
                    │
          DSP ───► ├── top of stack (most recently pushed value)
                    ├── second item
                    ├── third item
                    ┊
                    ├── data_stack_top (initial DSP value)
                    High addresses
```

`data_stack_top` is a label at the *end* of the allocated region. The DSP
starts here (empty stack) and decrements as values are pushed.

### Configuration

| Parameter       | Value     | Notes                                |
|-----------------|-----------|--------------------------------------|
| CELL            | 8 bytes   | 64-bit cells, native word size       |
| DATA_STACK_SIZE | 4096      | 512 cells (4096 / 8)                 |
| Alignment       | 8 (x86) or 16 (arm64) | .align directive in .bss  |

### Register Allocation

| Register | ARM64 | x86-64 | Notes                                        |
|----------|-------|--------|----------------------------------------------|
| DSP      | X19   | R15    | Data stack pointer                           |
| HERE     | X20   | R14    | Dictionary free-space pointer (future)       |
| LATEST   | X21   | R13    | Most recent dictionary entry (future)        |
| RSP      | SP    | RSP    | Return stack (hardware stack)                |

All engine registers are **callee-saved** in their respective ABIs
(AAPCS64 for ARM64, System V AMD64 for x86-64). This means:

- C library functions won't clobber them
- Nested calls within BasicForth preserve them automatically
- Future C interop works without special save/restore code

### Push and Pop

**ARM64** uses macros defined in core.s:

```asm
.macro dpush reg
    STR \reg, [X19, #-CELL]!    // pre-decrement: X19 -= 8, then store
.endm

.macro dpop reg
    LDR \reg, [X19], #CELL      // post-increment: load, then X19 += 8
.endm
```

These use ARM64's pre-decrement and post-increment addressing modes, which
do the pointer arithmetic and memory access in a single instruction.

**x86-64** uses inline instructions (no macros needed — the idiom is short):

```asm
sub $CELL, %r15              # push: make room
mov %rax, (%r15)             # push: store value

mov (%r15), %rax             # pop: load value
add $CELL, %r15              # pop: reclaim space
```

x86 doesn't have pre-decrement/post-increment addressing modes, so push
and pop are always two instructions.

## Current Primitives

### Stack Operations

#### DUP ( a -- a a )

Duplicate the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`                | `mov (%r15), %rax`             |
| `dpush X9`                     | `sub $CELL, %r15`              |
|                                 | `mov %rax, (%r15)`             |

Peek at the top value, then push a copy. Does not pop the original.

#### DROP ( a -- )

Discard the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `ADD X19, X19, #CELL`          | `add $CELL, %r15`              |

Simply advances the stack pointer. The old value remains in memory but is
effectively gone — the next push will overwrite it.

#### SWAP ( a b -- b a )

Exchange the top two stack items.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`                | `mov (%r15), %rax`             |
| `LDR X10, [X19, #CELL]`       | `mov CELL(%r15), %rdx`         |
| `STR X9, [X19, #CELL]`        | `mov %rax, CELL(%r15)`         |
| `STR X10, [X19]`              | `mov %rdx, (%r15)`             |

Load both values into registers, store them back in swapped positions.
The stack pointer doesn't move.

#### OVER ( a b -- a b a )

Copy the second item to the top.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19, #CELL]`        | `mov CELL(%r15), %rax`         |
| `dpush X9`                     | `sub $CELL, %r15`              |
|                                 | `mov %rax, (%r15)`             |

Peek at the second item (one CELL below the top), push a copy.

### Arithmetic

#### + ( a b -- a+b )

Add the top two items.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `dpop X9`                      | `mov (%r15), %rax`             |
| `LDR X10, [X19]`              | `add $CELL, %r15`              |
| `ADD X10, X10, X9`            | `add %rax, (%r15)`             |
| `STR X10, [X19]`              |                                 |

Pop b, add to a in place. The x86 version is more compact — `add %rax, (%r15)`
does the memory read-modify-write in one instruction.

#### - ( a b -- a-b )

Subtract b from a.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `dpop X9`                      | `mov (%r15), %rax`             |
| `LDR X10, [X19]`              | `add $CELL, %r15`              |
| `SUB X10, X10, X9`            | `sub %rax, (%r15)`             |
| `STR X10, [X19]`              |                                 |

Same pattern as +. Note the operand order: a is second on stack, b is top.
Result is a - b.

#### NEGATE ( a -- -a )

Negate the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`               | `negq (%r15)`                  |
| `NEG X9, X9`                  |                                 |
| `STR X9, [X19]`               |                                 |

ARM64 requires load-modify-store. x86 can negate directly in memory.

### I/O Wrappers

These primitives bridge the data stack to the platform layer. They pop or
push values on the Forth data stack and pass them via registers to the
platform functions.

#### forth_emit ( char -- )

Pop a character from the data stack, call `platform_emit`.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `STR X30, [SP, #-16]!`        | `mov (%r15), %rdi`             |
| `dpop X0`                     | `add $CELL, %r15`              |
| `BL platform_emit`            | `jmp platform_emit`            |
| `LDR X30, [SP], #16`          |                                 |
| `RET`                          |                                 |

ARM64 must save/restore the link register (X30) because BL overwrites it.
x86 uses a tail call (`jmp`) — since forth_emit's return address is already
on the hardware stack, platform_emit's `ret` returns directly to the caller.

#### forth_key ( -- char )

Call `platform_key`, push the result onto the data stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `STR X30, [SP, #-16]!`        | `call platform_key`            |
| `BL platform_key`             | `sub $CELL, %r15`              |
| `dpush X0`                    | `mov %rdi, (%r15)`             |
| `LDR X30, [SP], #16`          | `ret`                          |
| `RET`                          |                                 |

platform_key returns the character in X0 (ARM64) or RDI (x86-64).

## Data Stack Memory

Allocated in the .bss section (zero-initialized, no space in the binary):

```asm
.bss
.align 4                        # ARM64: 16-byte aligned
data_stack_bottom:              #        (or .align 8 on x86: 256-byte)
    .space DATA_STACK_SIZE      # 4096 bytes = 512 cells
.global data_stack_top
data_stack_top:                 # DSP starts here (empty stack)
```

`data_stack_top` is exported as a global symbol so that main.s can
initialize the DSP register:

```asm
# ARM64:                          # x86-64:
ADR X19, data_stack_top           lea data_stack_top(%rip), %r15
```

## Future Primitives

Words to be added as BasicForth grows. All will have identical stack effects
on both architectures.

### Stack

| Word  | Stack effect         | Notes                             |
|-------|----------------------|-----------------------------------|
| >R    | ( a -- ) (R: -- a )  | Move to return stack              |
| R>    | ( -- a ) (R: a -- )  | Move from return stack            |
| R@    | ( -- a ) (R: a -- a) | Copy from return stack            |

### Arithmetic

| Word  | Stack effect         | Notes                             |
|-------|----------------------|-----------------------------------|
| *     | ( a b -- a*b )       | Multiply                          |
| /MOD  | ( a b -- rem quot )  | Divide with remainder             |

### Logic

| Word    | Stack effect         | Notes                           |
|---------|----------------------|---------------------------------|
| AND     | ( a b -- a&b )       | Bitwise AND                     |
| OR      | ( a b -- a\|b )      | Bitwise OR                      |
| XOR     | ( a b -- a^b )       | Bitwise XOR                     |
| INVERT  | ( a -- ~a )          | Bitwise NOT                     |

### Comparison

| Word | Stack effect         | Notes                            |
|------|----------------------|----------------------------------|
| 0=   | ( a -- flag )        | True if a == 0                   |
| 0<   | ( a -- flag )        | True if a < 0                    |

### Memory

| Word | Stack effect         | Notes                            |
|------|----------------------|----------------------------------|
| @    | ( addr -- x )        | Fetch cell from memory           |
| !    | ( x addr -- )        | Store cell to memory             |
| C@   | ( addr -- byte )     | Fetch byte from memory           |
| C!   | ( byte addr -- )     | Store byte to memory             |

### Compiler

| Word      | Stack effect          | Notes                           |
|-----------|-----------------------|---------------------------------|
| LIT       | ( -- x )              | Push inline literal             |
| ,         | ( x -- )              | Compile cell to dictionary      |
| EXECUTE   | ( xt -- )             | Call execution token            |
| BRANCH    | ( -- )                | Unconditional branch            |
| 0BRANCH   | ( flag -- )           | Branch if false                 |
| EXIT      | ( -- )                | Return from word                |
