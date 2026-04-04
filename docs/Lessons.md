# Building BasicForth: An ARM64 Forth

A step-by-step development journal documenting the creation of BasicForth,
a multi-architecture Forth environment for Linux. No libc, no libraries —
just raw system calls and native assembly (ARM64 and x86-64).

Successor to [BareMetalForth](https://github.com/bblodget/BasicForth),
which targeted bare metal x86. BasicForth builds on Linux instead, supporting
modern hardware — from x86 laptops to ARM64 boards like the Raspberry Pi and
OLogic Pumpkin Genio 510.

## What You'll Learn

- ARM64 assembly programming
- Linux system calls from assembly (no libc)
- Cross-compilation and QEMU emulation
- Forth language implementation from scratch
- Subroutine Threaded Code (STC) on ARM64

---

## Table of Contents

- [Lesson 1: Hello ARM64](#lesson-1-hello-arm64)

---

## Lesson 1: Hello ARM64

Our first goal is simple: write an ARM64 assembly program that prints
"BasicForth" to the terminal and exits. No Forth yet — just prove we can
build and run an ARM64 binary.

This is the equivalent of BasicForth's early lessons on boot sectors and BIOS
interrupts, but instead of bare metal we're targeting Linux. The ARM64 Linux
syscall interface is our foundation — everything BasicForth does will be
built on top of it.

### Why ARM64?

ARM64 (also called AArch64) is the 64-bit ARM architecture. Unlike x86, which
evolved from 8-bit and 16-bit predecessors and carries decades of backward
compatibility, ARM64 was designed as a clean 64-bit architecture from the start.

Some key differences from x86:

| Aspect                    | x86-64                  | ARM64                   |
|---------------------------|-------------------------|-------------------------|
| Design philosophy         | CISC (Complex)          | RISC (Reduced)          |
| Instruction size          | Variable (1-15 bytes)   | Fixed (4 bytes always)  |
| General-purpose registers | 16                      | 31                      |
| Syscall instruction       | `syscall`               | `SVC #0`                |
| Syscall number register   | RAX                     | X8                      |
| Return value register     | RAX                     | X0                      |

The fixed 4-byte instruction size is a big deal for Forth. When we build the
compiler later, every compiled call will be exactly 4 bytes — no variable-length
encoding to worry about.

### ARM64 Registers

ARM64 gives us 31 general-purpose 64-bit registers (X0-X30) plus the stack
pointer (SP) and a zero register (XZR). Each X register has a 32-bit alias
(W0-W30) that accesses the lower 32 bits.

For now, we only need a few:

| Register | Purpose for syscalls               |
|----------|------------------------------------|
| X0       | First argument (and return value)  |
| X1       | Second argument                    |
| X2       | Third argument                     |
| X8       | Syscall number                     |

Compare this with x86-64 where syscall arguments go in RDI, RSI, RDX, R10,
R8, R9 and the syscall number goes in RAX. ARM64's convention is simpler —
arguments just go in X0, X1, X2, etc. in order.

### Linux Syscalls on ARM64

A system call is how a user program asks the kernel to do something — write to
a file, read from the terminal, allocate memory, exit. The mechanism is:

1. Put the syscall number in X8
2. Put arguments in X0, X1, X2, ... (up to 6 arguments in X0-X5)
3. Execute `SVC #0` (Supervisor Call)
4. Kernel handles the request
5. Result comes back in X0 (positive = success, negative = error)

The two syscalls we need:

**write** — send bytes to a file descriptor:
```
Syscall number: 64
X0 = file descriptor (1 = stdout)
X1 = pointer to buffer
X2 = number of bytes
Returns: number of bytes written (in X0)
```

**exit** — terminate the program:
```
Syscall number: 93
X0 = exit code (0 = success)
Does not return
```

Note that the syscall numbers are completely different from x86! On x86-64,
write is 1 and exit is 60. On ARM64, write is 64 and exit is 93. The arguments
have the same meaning, but the numbers are assigned differently. You can find
the full ARM64 syscall table at [arm64.syscall.sh](https://arm64.syscall.sh/).

### Key ARM64 Instructions

For this first program we need just a handful of instructions:

**MOV** — load a constant into a register:
```
MOV X0, #1          // X0 = 1
```

**ADR** — load the address of a label into a register:
```
ADR X1, msg         // X1 = address of msg
```

ADR computes a PC-relative address, meaning "the address of `msg` relative to
where this instruction is." This is important for position-independent code and
avoids needing to know absolute addresses at assembly time.

**SVC #0** — supervisor call (trigger a syscall):
```
SVC #0              // like INT 0x80 or SYSCALL on x86
```

### GNU Assembler Syntax

BasicForth uses the GNU assembler (`as`), which has different syntax from
NASM (used by BasicForth). Key differences:

| Feature          | NASM (x86)       | GNU as (ARM64)                    |
|------------------|------------------|-----------------------------------|
| Comments         | `; comment`      | `// comment` or `/* */`           |
| Constants        | `equ`            | `.equ`                            |
| String data      | `db "text"`      | `.ascii "text"`                   |
| Section          | `section .text`  | `.text` or `.section .rodata`     |
| Entry point      | `global _start`  | `.global _start`                  |
| Immediate values | `mov rax, 1`     | `MOV X0, #1` (note the `#`)      |

The `#` prefix on immediate values is an ARM convention — it makes it visually
clear which operands are constants vs registers.

Both x86 and ARM64 use destination-first order (`inst dst, src`), but ARM64
often has three operands where x86 has two:

```
// x86:   ADD EAX, EBX       // EAX = EAX + EBX  (2 operands, dst is also src)
// ARM64: ADD X0, X1, X2     // X0 = X1 + X2     (3 operands, dst is separate)
```

The three-operand form means you don't destroy either input — a common RISC
advantage over CISC.

### Program Structure

The program needs:

1. A `.text` section with the entry point `_start`
2. Defined constants for the syscall numbers and file descriptors
3. Code to call `write(1, msg, len)` then `exit(0)`
4. A `.rodata` section with the message string
5. A way to compute the string length at assembly time

For the string length, GNU as lets you compute it with `. - msg` where `.`
means "the current address." Define the string, then immediately compute the
distance from the label to get the byte count.

### The Build System

Since we're developing on an x86 laptop but targeting ARM64, we cross-compile:

- `aarch64-linux-gnu-as` — the cross-assembler (assembly → object file)
- `aarch64-linux-gnu-ld` — the cross-linker (object file → ELF executable)
- `qemu-aarch64-static` — ARM64 user-mode emulator (runs the binary on x86)

The workflow is:

```
[source.s] → as → [source.o] → ld → [executable]
                                          ↓
                                  qemu-aarch64-static (test on laptop)
                                          or
                                  scp + ssh (test on real board)
```

The linker produces a static ELF binary with no dynamic dependencies. No libc,
no interpreter, no shared libraries. The kernel loads it, maps its segments into
memory, and jumps to `_start`. That's it.

### Exercise

Write an ARM64 assembly program that:

1. Defines constants for the `write` (64) and `exit` (93) syscall numbers
2. Prints "BasicForth\n" to stdout using the `write` syscall
3. Exits cleanly with status code 0
4. Assembles and links into a static ELF binary
5. Runs under QEMU user-mode emulation

Create a Makefile with targets for `build`, `test` (QEMU), and `deploy`
(copy to board and run via SSH).

The resulting binary should be around 1KB — just an ELF header, a few
instructions, and a string constant.

### Q&A

**Q: Why `SVC #0` and not just `SVC`?**

A: ARM's supervisor call instruction takes an immediate value that the kernel
*could* use to distinguish different call types. Linux always uses 0 and
ignores the immediate — the syscall number comes from X8 instead. But the
assembler requires you to write `SVC #0` explicitly.

**Q: Why `ADR` instead of loading an absolute address?**

A: `ADR` computes a PC-relative address, which means the code works regardless
of where it's loaded in memory. On ARM64, you can't load a full 64-bit address
in a single instruction anyway (instructions are only 32 bits wide). `ADR` can
reach +/- 1MB from the current instruction, which is plenty for our string
constants.

**Q: Why not use GCC with `-nostdlib`?**

A: You can — `gcc -nostdlib -static -o basicforth forth.s` would work. We
use `as` + `ld` separately to make the build steps explicit and educational.
GCC just calls them under the hood anyway. Either approach produces the same
binary.

**Q: How does this compare to BasicForth's starting point?**

A: BasicForth started with a boot sector — 512 bytes of raw machine code loaded
by the BIOS. We start one level up, with a Linux ELF binary. We don't have to
deal with bootloaders, video mode, or real mode, but we also don't have direct
hardware access. Everything goes through the kernel via syscalls. The trade-off
is worth it: we can focus on Forth and ARM64 assembly without getting bogged
down in hardware bring-up.
