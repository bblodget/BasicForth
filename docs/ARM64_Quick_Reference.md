# ARM64 Quick Reference

Quick reference for ARM64 (AArch64) registers, instructions, and Linux syscalls.

## Common Instructions Quick Reference

| Instruction          | Description                          | Example                     |
|----------------------|--------------------------------------|-----------------------------|
| `MOV`                | Move/copy data                       | `MOV X0, X1`               |
| `MOV`                | Load immediate                       | `MOV X0, #42`              |
| `ADD`                | Add                                  | `ADD X0, X1, X2`           |
| `SUB`                | Subtract                             | `SUB X0, X1, #5`           |
| `MUL`                | Multiply                             | `MUL X0, X1, X2`           |
| `SDIV`               | Signed divide                        | `SDIV X0, X1, X2`          |
| `UDIV`               | Unsigned divide                      | `UDIV X0, X1, X2`          |
| `MSUB`               | Multiply-subtract (for remainder)    | `MSUB X0, X1, X2, X3`     |
| `NEG`                | Negate (two's complement)            | `NEG X0, X1`               |
| `AND`                | Bitwise AND                          | `AND X0, X1, #0xFF`        |
| `ORR`                | Bitwise OR                           | `ORR X0, X1, #1`           |
| `EOR`                | Bitwise XOR                          | `EOR X0, X1, X2`           |
| `MVN`                | Bitwise NOT (move inverted)          | `MVN X0, X1`               |
| `LSL`                | Logical shift left                   | `LSL X0, X1, #4`           |
| `LSR`                | Logical shift right (unsigned)       | `LSR X0, X1, #1`           |
| `ASR`                | Arithmetic shift right (signed)      | `ASR X0, X1, #1`           |
| `CMP`                | Compare (sets flags, no result)      | `CMP X0, #10`              |
| `TST`                | Bitwise AND test (sets flags)        | `TST X0, #1`               |
| `LDR`                | Load from memory (64-bit)            | `LDR X0, [X1]`             |
| `LDRB`               | Load byte from memory                | `LDRB W0, [X1]`            |
| `STR`                | Store to memory (64-bit)             | `STR X0, [X1]`             |
| `STRB`               | Store byte to memory                 | `STRB W0, [X1]`            |
| `STP`                | Store pair (push two registers)      | `STP X29, X30, [SP, #-16]!` |
| `LDP`                | Load pair (pop two registers)        | `LDP X29, X30, [SP], #16`  |
| `ADR`                | Load PC-relative address             | `ADR X0, label`            |
| `ADRP`               | Load PC-relative page address        | `ADRP X0, label`           |
| `BL`                 | Branch with link (call)              | `BL my_func`               |
| `RET`                | Return (branch to X30)               | `RET`                       |
| `B`                  | Unconditional branch                 | `B .loop`                   |
| `B.EQ`               | Branch if equal (ZF=1)               | `B.EQ .done`               |
| `B.NE`               | Branch if not equal (ZF=0)           | `B.NE .loop`               |
| `B.LT`               | Branch if less than (signed)         | `B.LT .negative`           |
| `B.GT`               | Branch if greater than (signed)      | `B.GT .positive`           |
| `B.LO`               | Branch if lower (unsigned <)         | `B.LO .smaller`            |
| `B.HI`               | Branch if higher (unsigned >)        | `B.HI .larger`             |
| `CBZ`                | Compare and branch if zero           | `CBZ X0, .done`            |
| `CBNZ`               | Compare and branch if not zero       | `CBNZ X0, .loop`           |
| `SVC #0`             | Supervisor call (syscall)            | `SVC #0`                    |

## General-Purpose Registers

### Register Views (Same Physical Register)

```
64-bit    32-bit    Description
─────────────────────────────────────────
X0        W0        Argument / return value
X1        W1        Argument
X2        W2        Argument
...       ...
X7        W7        Argument
X8        W8        Syscall number (Linux)
X9        W9        Scratch (caller-saved)
...       ...
X15       W15       Scratch (caller-saved)
X16       W16       IP0 — intra-procedure scratch (avoid)
X17       W17       IP1 — intra-procedure scratch (avoid)
X18       W18       Platform register (avoid — reserved on some OSes)
X19       W19       Callee-saved
...       ...
X28       W28       Callee-saved
X29       W29       Frame pointer (FP)
X30       W30       Link register (LR) — return address
SP        WSP       Stack pointer (must be 16-byte aligned)
XZR       WZR       Zero register (reads as 0, writes discarded)
```

Writing to a W register zeroes the upper 32 bits of the corresponding X register.

### Common Uses

| Register  | Name            | Typical Use                                  |
|-----------|-----------------|----------------------------------------------|
| **X0-X7** | Arguments       | Function args, X0 is also return value       |
| **X8**    | Syscall number  | Linux syscall dispatch                       |
| **X9-X15**| Temporaries     | Scratch within functions (caller-saved)      |
| **X16-X17**| IP0/IP1        | Linker veneers — avoid using                 |
| **X18**   | Platform        | Reserved on some platforms — avoid            |
| **X19-X28**| Callee-saved   | Preserved across calls — ideal for engine state |
| **X29**   | Frame pointer   | FP (optional, we don't use stack frames)     |
| **X30**   | Link register   | Return address from BL — save before nesting |
| **SP**    | Stack pointer   | Return stack — must stay 16-byte aligned     |
| **XZR**   | Zero register   | Constant 0 — useful for comparisons/clears   |

### BasicForth Register Allocation

```
X19 = Data stack pointer (DSP)     — callee-saved, persistent
X20 = HERE pointer                 — dictionary free space
X21 = LATEST pointer               — most recent dictionary entry
X22-X28 = Available for STATE, BASE, etc.
SP  = Return stack                 — hardware stack
X30 = Link register                — saved/restored by BL/RET
```

## Key Differences from x86

| Aspect                | x86                              | ARM64                              |
|-----------------------|----------------------------------|------------------------------------|
| Instruction size      | Variable (1-15 bytes)            | Fixed (4 bytes always)             |
| Operand count         | 2 (dst = dst op src)             | 3 (dst = src1 op src2)            |
| Immediate prefix      | None (`mov eax, 1`)             | `#` prefix (`MOV X0, #1`)         |
| Zero a register       | `xor eax, eax`                  | `MOV X0, XZR` or `MOV X0, #0`    |
| Subroutine call       | `CALL` (pushes return to stack)  | `BL` (saves return in X30)        |
| Subroutine return     | `RET` (pops from stack)          | `RET` (branches to X30)           |
| Push/pop              | `PUSH EAX` / `POP EAX`          | `STP`/`LDP` pairs (no single push)|
| Syscall instruction   | `SYSCALL` or `INT 0x80`         | `SVC #0`                           |
| Syscall number in     | RAX (64-bit) / EAX (32-bit)    | X8                                 |
| Division              | `DIV` uses EDX:EAX              | `SDIV X0, X1, X2` (clean 3-op)   |
| Remainder             | `DIV` gives remainder in EDX    | Needs `MSUB` after `SDIV`         |
| No-op                 | `NOP`                            | `NOP`                              |

## Arithmetic

### Division and Remainder

ARM64 has clean divide instructions but no built-in remainder. Compute it
with multiply-subtract:

```asm
// X0 = X1 / X2 (signed)
SDIV X0, X1, X2

// X3 = X1 % X2 (signed remainder)
SDIV X0, X1, X2         // X0 = quotient
MSUB X3, X0, X2, X1     // X3 = X1 - (quotient * X2) = remainder

// Forth /MOD: ( n1 n2 -- remainder quotient )
SDIV X10, X9, X11       // quotient
MSUB X12, X10, X11, X9  // remainder
// Push X12 (remainder) then X10 (quotient)
```

### Shift Instructions

| Instruction | Name                     | Operation                    |
|-------------|--------------------------|------------------------------|
| `LSL`       | Logical Shift Left       | Bits shift left, 0s fill     |
| `LSR`       | Logical Shift Right      | Bits shift right, 0s fill    |
| `ASR`       | Arithmetic Shift Right   | Bits shift right, sign fills |
| `ROR`       | Rotate Right             | Bits wrap around             |

```asm
LSL X0, X1, #3          // X0 = X1 * 8 (shift left by 3)
LSR X0, X1, #1          // X0 = X1 / 2 (unsigned)
ASR X0, X1, #1          // X0 = X1 / 2 (signed, preserves sign)
LSL X0, X1, #3          // X0 = X1 * 8 (CELLS in BasicForth: 8 bytes)
```

## Memory Access

ARM64 is a load/store architecture — arithmetic only operates on registers.
All memory access goes through `LDR`/`STR` and variants.

### Addressing Modes

```asm
// Base register
LDR X0, [X1]              // X0 = mem[X1]
STR X0, [X1]              // mem[X1] = X0

// Base + immediate offset
LDR X0, [X1, #8]          // X0 = mem[X1 + 8]
STR X0, [X1, #-8]         // mem[X1 - 8] = X0

// Pre-index (update base BEFORE access) — like push
STR X0, [X1, #-8]!        // X1 -= 8, then mem[X1] = X0

// Post-index (update base AFTER access) — like pop
LDR X0, [X1], #8          // X0 = mem[X1], then X1 += 8

// Base + register offset
LDR X0, [X1, X2]          // X0 = mem[X1 + X2]

// Base + scaled register (useful for array indexing)
LDR X0, [X1, X2, LSL #3]  // X0 = mem[X1 + X2*8]
```

### Data Sizes

| Instruction | Size    | Register | Notes                         |
|-------------|---------|----------|-------------------------------|
| `LDR X0`   | 64-bit  | X0       | Full 64-bit load              |
| `LDR W0`   | 32-bit  | W0       | Zeroes upper 32 bits of X0    |
| `LDRH W0`  | 16-bit  | W0       | Zero-extends to 32 bits       |
| `LDRB W0`  | 8-bit   | W0       | Zero-extends to 32 bits       |
| `LDRSW X0` | 32-bit  | X0       | Sign-extends to 64 bits       |
| `LDRSH X0` | 16-bit  | X0       | Sign-extends to 64 bits       |
| `LDRSB X0` | 8-bit   | X0       | Sign-extends to 64 bits       |

### Stack Operations (Pair Load/Store)

ARM64 has no single `PUSH`/`POP`. Use `STP`/`LDP` to save/restore in pairs:

```asm
// Push two registers (pre-decrement SP by 16)
STP X29, X30, [SP, #-16]!

// Pop two registers (post-increment SP by 16)
LDP X29, X30, [SP], #16

// Push a single register (still must keep 16-byte alignment)
STR X0, [SP, #-16]!       // Wastes 8 bytes but keeps alignment
LDR X0, [SP], #16
```

## Condition Flags (NZCV)

ARM64 has four condition flags in the PSTATE register:

| Flag | Name      | Set When                                     |
|------|-----------|----------------------------------------------|
| **N** | Negative | Result bit 63 is 1 (result is negative)      |
| **Z** | Zero     | Result is zero                                |
| **C** | Carry    | Unsigned overflow (ADD) or no borrow (SUB)   |
| **V** | Overflow | Signed overflow                               |

### How CMP and TST Set Flags

**CMP** — computes `Xn - Xm` without storing result:

```asm
CMP X0, #10             // Sets flags based on X0 - 10
B.EQ .equal              // Z=1: X0 == 10
B.LT .less               // N!=V: X0 < 10 (signed)
B.GT .greater             // Z=0 and N==V: X0 > 10 (signed)
```

**TST** — computes `Xn AND Xm` without storing result:

```asm
TST X0, #1              // Test if bit 0 is set
B.NE .is_odd             // Z=0: bit was set

TST X0, X0              // Test if X0 is zero
B.EQ .is_zero            // Z=1: X0 was zero
```

### Conditional Branches

#### Signed Comparisons (use after CMP)

| Instruction | Meaning                  | Flags           |
|-------------|--------------------------|-----------------|
| `B.LT`     | Less than                | N != V          |
| `B.LE`     | Less than or equal       | Z=1 OR N!=V     |
| `B.GT`     | Greater than             | Z=0 AND N==V    |
| `B.GE`     | Greater than or equal    | N == V          |

#### Unsigned Comparisons (use after CMP)

| Instruction | Meaning                  | Flags           |
|-------------|--------------------------|-----------------|
| `B.LO`     | Lower (unsigned <)       | C == 0          |
| `B.LS`     | Lower or same            | C=0 OR Z=1      |
| `B.HI`     | Higher (unsigned >)      | C=1 AND Z=0     |
| `B.HS`     | Higher or same           | C == 1          |

#### Equality (works for both signed and unsigned)

| Instruction | Meaning                  | Flags           |
|-------------|--------------------------|-----------------|
| `B.EQ`     | Equal / zero             | Z == 1          |
| `B.NE`     | Not equal / not zero     | Z == 0          |

#### Compare and Branch (no CMP needed)

| Instruction | Meaning                              |
|-------------|--------------------------------------|
| `CBZ Xn`   | Branch if Xn == 0                    |
| `CBNZ Xn`  | Branch if Xn != 0                    |
| `TBZ Xn, #bit` | Branch if bit is 0 (test bit)    |
| `TBNZ Xn, #bit` | Branch if bit is 1 (test bit)   |

```asm
CBZ X0, .is_zero         // No CMP needed — cleaner than CMP + B.EQ
TBNZ X0, #31, .negative  // Test sign bit directly
```

## Caller-Save vs Callee-Save

| Caller-Save (may be clobbered)     | Callee-Save (must preserve)        |
|------------------------------------|------------------------------------|
| X0-X15, X16-X17                    | X19-X28, X29 (FP), SP             |

X30 (LR) is technically caller-saved — `BL` overwrites it.

### Practical Example

```asm
// Function that uses callee-saved registers
my_function:
    STP X29, X30, [SP, #-16]!   // Save FP and return address
    STP X19, X20, [SP, #-16]!   // Save callee-saved regs we'll use

    // ... function body — X19, X20 are safe to use ...

    LDP X19, X20, [SP], #16     // Restore callee-saved regs
    LDP X29, X30, [SP], #16     // Restore FP and return address
    RET
```

For BasicForth primitives, X19-X21 are our engine registers (DSP, HERE,
LATEST) — they persist across all calls because they're callee-saved.

## Linux Syscall ABI (ARM64)

```
Syscall number:  X8
Arguments:       X0, X1, X2, X3, X4, X5
Invoke:          SVC #0
Return value:    X0 (positive = success, negative = -errno)
Clobbered:       X0-X7 may be clobbered
```

### Common Syscalls

| Syscall         | ARM64 # | x86-64 # | Signature                                  |
|-----------------|---------|----------|--------------------------------------------|
| read            |      63 |        0 | (fd, buf, count)                           |
| write           |      64 |        1 | (fd, buf, count)                           |
| close           |      57 |        3 | (fd)                                       |
| lseek           |      62 |        8 | (fd, offset, whence)                       |
| ioctl           |      29 |       16 | (fd, cmd, arg)                             |
| openat          |      56 |      257 | (dirfd, pathname, flags, mode)             |
| exit            |      93 |       60 | (status)                                   |
| mmap            |     222 |        9 | (addr, len, prot, flags, fd, offset)       |
| munmap          |     215 |       11 | (addr, len)                                |
| mprotect        |     226 |       10 | (addr, len, prot)                          |
| clock_gettime   |     113 |      228 | (clk_id, timespec)                         |
| nanosleep       |     101 |       35 | (req, rem)                                 |

### Syscall Example

```asm
// write(1, msg, 12) — print "Hello World\n"
MOV X0, #1              // fd = stdout
ADR X1, msg             // buf = address of string
MOV X2, #12             // count = 12 bytes
MOV X8, #64             // syscall number = write
SVC #0                  // invoke kernel
// X0 = bytes written (or negative error)
```

## GNU Assembler (as) Syntax

### Directives

| Directive          | Description                        | Example                    |
|--------------------|------------------------------------|----------------------------|
| `.global`          | Export symbol                       | `.global _start`           |
| `.equ`             | Define constant                    | `.equ SYS_write, 64`      |
| `.text`            | Code section                       | `.text`                    |
| `.section .rodata` | Read-only data section             | `.section .rodata`         |
| `.data`            | Read-write data section            | `.data`                    |
| `.bss`             | Uninitialized data section         | `.bss`                     |
| `.ascii`           | String (no null terminator)        | `.ascii "hello"`           |
| `.asciz`           | String (with null terminator)      | `.asciz "hello"`           |
| `.byte`            | 8-bit value                        | `.byte 0xFF`               |
| `.hword`           | 16-bit value                       | `.hword 0x1234`            |
| `.word`            | 32-bit value                       | `.word 0x12345678`         |
| `.quad`            | 64-bit value                       | `.quad 0x123456789ABCDEF0` |
| `.space`           | Reserve N bytes (filled with 0)    | `.space 1024`              |
| `.align`           | Align to boundary                  | `.align 4`                 |
| `.include`         | Include another source file        | `.include "defs.s"`        |
| `.macro`/`.endm`   | Define macro                       | `.macro push reg` ...      |

### Comments

```asm
// C-style line comment (preferred)
/* C-style block comment */
@ Legacy ARM comment (also works)
```

### Labels

```asm
my_function:             // Global label
    ...
1:                       // Local numeric label
    B 1b                 // Branch to previous '1:' label (b = backward)
    B 1f                 // Branch to next '1:' label (f = forward)
.L_local:                // Local label (convention: .L prefix)
```
