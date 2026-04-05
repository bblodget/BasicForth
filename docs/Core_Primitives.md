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

The data stack holds Forth values. It consists of two parts: a dedicated
**TOS register** that always holds the top value, and a **memory region**
in .bss that holds the remaining items. This TOS-in-register design
eliminates a memory access on most operations.

### TOS-in-Register Invariant

A dedicated register always holds the top of the data stack:

- **ARM64:** X20 = TOS
- **x86-64:** R14 = TOS

The data stack pointer (DSP) points to the **second** item on the stack,
not the top. This is the key invariant that every primitive must maintain.

```
  TOS register ──► top value (always in X20 / R14)

         DSP ───► ├── second item     (in memory)
                   ├── third item
                   ┊
                   ├── data_stack_top  (initial DSP value)
                   High addresses
```

### Why TOS-in-Register?

Many Forth primitives operate on the top of stack. With TOS in a register:

| Operation      | Memory TOS (old)       | Register TOS (current)    |
|----------------|------------------------|---------------------------|
| DUP            | load + store           | store only (TOS stays)    |
| DROP           | adjust pointer         | load next into TOS        |
| NEGATE         | load + negate + store  | negate register           |
| EMIT           | pop from memory + call | pass register + tail call |
| Compare to 'q' | load from memory + CMP | CMP register directly     |

The tradeoff: every primitive must maintain the invariant that TOS is in the
register and DSP points to the second item. This adds complexity to each
word's implementation, but the performance benefit compounds across the
entire system.

### Layout

```
                    Low addresses
                    ┊
                    ├── data_stack_bottom (start of .bss allocation)
                    │
                    │   ... unused space ...
                    │
          DSP ───► ├── second item (next below TOS)
                    ├── third item
                    ┊
                    ├── data_stack_top (initial DSP value)
                    High addresses

          TOS ───► (in register, not in memory)
```

`data_stack_top` is a label at the *end* of the allocated region. DSP
starts here (empty stack) and decrements as values are pushed to memory.

### Configuration

| Parameter       | Value                   | Notes                        |
|-----------------|-------------------------|------------------------------|
| CELL            | 8 bytes                 | 64-bit cells, native word    |
| DATA_STACK_SIZE | 4096                    | 512 cells (4096 / 8)        |
| Alignment       | 8 (x86) or 16 (arm64)  | .align directive in .bss     |

### Register Allocation

| Register | ARM64 | x86-64 | Notes                                        |
|----------|-------|--------|----------------------------------------------|
| DSP      | X19   | R15    | Data stack pointer (second item)             |
| TOS      | X20   | R14    | Top of stack value                           |
| HERE     | X21   | R13    | Dictionary free-space pointer (future)       |
| LATEST   | X22   | R12    | Most recent dictionary entry (future)        |
| RSP      | SP    | RSP    | Return stack (hardware stack)                |

All engine registers are **callee-saved** in their respective ABIs
(AAPCS64 for ARM64, System V AMD64 for x86-64). This means:

- C library functions won't clobber them
- Nested calls within BasicForth preserve them automatically
- Future C interop works without special save/restore code

### Push and Pop

With TOS in a register, "push" and "pop" have specific meanings:

**Push a new value onto the stack:**
1. Store current TOS to memory (DSP decrements)
2. Set TOS register to the new value

**Pop a value off the stack:**
1. Read TOS register (that's the value)
2. Load next value from memory into TOS (DSP increments)

**ARM64:**

```asm
// Push: save TOS to memory, set new TOS
STR X20, [X19, #-CELL]!        // pre-decrement: X19 -= 8, store X20
MOV X20, <new_value>

// Pop: use TOS, load next
MOV <dest>, X20                 // read current TOS
LDR X20, [X19], #CELL          // post-increment: load, X19 += 8
```

ARM64's pre-decrement and post-increment addressing modes combine the
pointer arithmetic and memory access in a single instruction.

**x86-64:**

```asm
# Push: save TOS to memory, set new TOS
sub $CELL, %r15                 # make room
mov %r14, (%r15)               # store TOS
mov <new_value>, %r14          # set new TOS

# Pop: use TOS, load next
mov %r14, <dest>               # read current TOS
mov (%r15), %r14               # load next
add $CELL, %r15                # reclaim space
```

x86 doesn't have pre-decrement/post-increment addressing modes, so push
and pop are each two instructions for the memory portion.

## Current Primitives

### Stack Operations

#### DUP ( a -- a a )

Duplicate the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `STR X20, [X19, #-CELL]!`     | `sub $CELL, %r15`              |
|                                 | `mov %r14, (%r15)`             |

Push TOS to memory. TOS register is unchanged — it already holds the
value we want on top. One of the simplest benefits of TOS-in-register.

#### DROP ( a -- )

Discard the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X20, [X19], #CELL`       | `mov (%r15), %r14`             |
|                                 | `add $CELL, %r15`              |

Load the next value from memory into the TOS register. The old TOS value
is simply abandoned — no need to write it anywhere.

#### SWAP ( a b -- b a )

Exchange the top two stack items.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19]`               | `mov (%r15), %rax`             |
| `STR X20, [X19]`              | `mov %r14, (%r15)`             |
| `MOV X20, X9`                 | `mov %rax, %r14`              |

Exchange TOS register with the value in memory at DSP. Only one memory
location is touched (the second item). DSP doesn't move.

#### OVER ( a b -- a b a )

Copy the second item to the top.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `STR X20, [X19, #-CELL]!`     | `sub $CELL, %r15`              |
| `LDR X20, [X19, #CELL]`       | `mov %r14, (%r15)`             |
|                                 | `mov CELL(%r15), %r14`         |

Push current TOS (b) to memory, then load the second item (a) into TOS.
After the push, a is at DSP+CELL (one cell below the newly stored b).

### Arithmetic

#### + ( a b -- a+b )

Add the top two items.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19], #CELL`        | `add (%r15), %r14`             |
| `ADD X20, X9, X20`            | `add $CELL, %r15`              |

Pop second item (a) from memory, add to TOS (b). x86 is particularly
compact — `add (%r15), %r14` adds memory directly to the TOS register.

#### - ( a b -- a-b )

Subtract b from a.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `LDR X9, [X19], #CELL`        | `mov (%r15), %rax`             |
| `SUB X20, X9, X20`            | `sub %r14, %rax`               |
|                                 | `mov %rax, %r14`               |
|                                 | `add $CELL, %r15`              |

Pop a from memory, compute a - b. ARM64 handles this in two instructions
since SUB can place the result directly in X20. x86 needs a temporary
because `sub` computes dest - src, and we need [DSP] - R14, not R14 - [DSP].

#### NEGATE ( a -- -a )

Negate the top of stack.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `NEG X20, X20`                 | `neg %r14`                     |

One instruction on both architectures. No memory access needed — TOS is
already in a register. This is a clear win over the old memory-TOS approach,
which required load-negate-store (3 instructions on ARM64).

### I/O Wrappers

These primitives bridge the data stack to the platform layer. They move
values between the TOS register and the platform's argument/return registers.

#### forth_emit ( char -- )

Pass TOS to `platform_emit`, pop new TOS from memory.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `MOV X0, X20`                 | `mov %r14, %rdi`               |
| `LDR X20, [X19], #CELL`      | `mov (%r15), %r14`             |
| `B platform_emit`             | `add $CELL, %r15`              |
|                                 | `jmp platform_emit`            |

Both use a **tail call** (ARM64: `B`, x86: `jmp`). Since forth_emit has
nothing to do after platform_emit returns, it jumps directly — platform_emit's
return goes straight back to the original caller. On ARM64, this means no
X30 save/restore is needed, unlike the old approach which required
`STR X30`/`BL`/`LDR X30`/`RET`.

The argument passes directly from TOS register to the platform's argument
register (X0 or RDI) — no memory round-trip.

#### forth_key ( -- char )

Push old TOS to memory, call `platform_key`, set TOS to result.

| ARM64                           | x86-64                         |
|---------------------------------|--------------------------------|
| `STR X30, [SP, #-16]!`        | `sub $CELL, %r15`              |
| `STR X20, [X19, #-CELL]!`    | `mov %r14, (%r15)`             |
| `BL platform_key`             | `call platform_key`            |
| `MOV X20, X0`                 | `mov %rdi, %r14`              |
| `LDR X30, [SP], #16`          | `ret`                          |
| `RET`                          |                                 |

KEY cannot use a tail call because we need to move the return value into
TOS after platform_key returns. ARM64 must save/restore X30 since BL
overwrites it.

platform_key returns the character in X0 (ARM64) or RDI (x86-64).

## Data Stack Memory

Allocated in the .bss section (zero-initialized, no space in the binary):

```asm
.bss
.align 4                        # ARM64: .align 4 = 2^4 = 16-byte aligned
data_stack_bottom:              #        (x86: .align 8 = 8-byte aligned)
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

TOS (X20 / R14) is undefined on an empty stack. The first push stores the
undefined value to memory (harmless — it's never accessed) and sets TOS to
the pushed value.

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
