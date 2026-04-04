# Pumpkin Forth — Planning Document

An educational Forth implementation for ARM64 Linux, sister project to
[BasicForth](https://github.com/your-repo/BasicForth).

## Project Goals

1. **Learn ARM64 assembly** by building a complete Forth from scratch
2. **Learn Linux internals** through direct syscalls (no libc, no libraries)
3. **Portable across ARM64 boards** — same binary runs on Genio 510, RPi, etc.
4. **Share Forth-level code with BasicForth** — core.fs, vi.fs, examples all reuse
5. **Educational documentation** — lesson series contrasting ARM64 with x86

## Target Hardware

### Primary: OLogic Pumpkin Genio 510-EVK
- MediaTek Genio 510 (MT8370), 6nm
- 2x Cortex-A78 @ 2.2GHz + 4x Cortex-A55 @ 2.0GHz (big.LITTLE)
- Mali G57 MC2 GPU
- Raspberry Pi-compatible 40-pin GPIO header
- USB-C serial debug, MIPI-DSI display
- Runs IoT Yocto Linux

### Secondary: Raspberry Pi 3/4/5
- Broadcom ARM64 SoC
- Widely available, well-documented
- Same ARM64 Linux syscall ABI

### Future: Any ARM64 Linux system
- Apple Silicon (Linux VM)
- Qualcomm Snapdragon X (Windows Subsystem for Linux)
- Cloud ARM64 instances (AWS Graviton, etc.)

## Design Decisions

### Linux First (Platform Abstraction)
- Linux kernel handles hardware (USB, display, storage, networking)
- We still own everything above the syscall boundary
- For "bare metal feel": custom Yocto image with PumpkinForth as init (PID 1)
- Platform layer is isolated — swap `platform_linux.s` for `platform_baremetal.s`
  to port to bare metal without changing the Forth core
- Focus stays on Forth and ARM64 assembly, not hardware bring-up

### No Library Dependencies
- No libc, no libm, no dynamic linker
- Static ELF binary linked with `ld` directly (or `gcc -nostdlib`)
- All OS interaction through raw `svc #0` syscalls
- Terminal control via raw `ioctl` (TCGETS/TCSETS for raw mode)
- Memory via `mmap` (anonymous for buffers, file-backed for blocks)
- This is the approach BasicForth uses on x86 Linux — proven pattern

### GNU Assembler (as)
- Ships with ARM64 toolchain (native or cross-compile)
- `.s` files, ARM64 assembly syntax
- Supports macros, conditional assembly, includes
- Alternative considered: FASMARM (FASM for ARM) — less mainstream

## ARM64 Architecture Overview

### Registers

| Register | Convention                      | PumpkinForth Use                       |
|----------|---------------------------------|----------------------------------------|
| X0-X7   | Arguments / return values       | Syscall args, scratch                  |
| X8       | Syscall number                  | Linux syscall dispatch                 |
| X9-X15   | Caller-saved temporaries        | Scratch within primitives              |
| X16-X17  | Intra-procedure call (IP0/IP1)  | Avoid (linker may use)                 |
| X18      | Platform register               | Avoid (reserved on some OSes)          |
| X19-X28  | Callee-saved                    | Forth engine registers                 |
| X29      | Frame pointer (FP)              | Available if we don't use frames       |
| X30      | Link register (LR)             | Return address (like x86 stack)        |
| SP       | Stack pointer                   | Return stack                           |
| XZR/WZR  | Zero register                   | Constant zero (reads as 0)             |

### Suggested Register Allocation

```
X19 = Data stack pointer     (EBP equivalent in BasicForth)
X20 = HERE pointer           (dictionary free space)
X21 = LATEST pointer         (most recent dictionary entry)
X22-X28 = Available for engine state (STATE, BASE, etc.)
SP  = Return stack           (same as x86)
X30 = Link register          (return address, saved/restored by BL/RET)
```

Key difference from x86: ARM64 has 31 GP registers vs x86's 8. We can keep
more engine state in registers instead of memory, which is both faster and
more educational (exposes the register-rich vs register-starved tradeoff).

### Key Instructions

```asm
// Subroutine call and return (STC basis)
BL label        // Branch with Link — like x86 CALL (saves return addr in X30)
RET             // Return — branches to X30 (like x86 RET but from register)

// Stack operations (for return stack)
STP X29, X30, [SP, #-16]!  // Push pair (pre-decrement)
LDP X29, X30, [SP], #16    // Pop pair (post-increment)

// Load/store (memory access)
LDR X0, [X1]           // Load 64-bit from address in X1
STR X0, [X1]           // Store 64-bit to address in X1
LDR W0, [X1]           // Load 32-bit (W = lower 32 bits)
LDRB W0, [X1]          // Load byte

// Arithmetic
ADD X0, X1, X2         // X0 = X1 + X2
SUB X0, X1, X2         // X0 = X1 - X2
MUL X0, X1, X2         // X0 = X1 * X2
SDIV X0, X1, X2        // X0 = X1 / X2 (signed)

// Compare and branch
CMP X0, X1             // Compare (sets flags)
B.EQ label             // Branch if equal
B.LT label             // Branch if less than (signed)
CBZ X0, label          // Compare and Branch if Zero (no CMP needed!)
CBNZ X0, label         // Compare and Branch if Not Zero

// Syscall
MOV X8, #64            // syscall number (write = 64 on ARM64)
SVC #0                 // Supervisor Call — like x86 INT 0x80
```

### Linux Syscall ABI (ARM64)

```
Arguments:  X0, X1, X2, X3, X4, X5
Syscall #:  X8
Invoke:     SVC #0
Return:     X0 (result or negative errno)
Clobbered:  X0-X7 may be clobbered (save if needed)
```

Common syscalls (numbers differ from x86!):

| Syscall       | ARM64 # | x86-32 # | Signature                         |
|---------------|---------|----------|-----------------------------------|
| read          |      63 |        3 | (fd, buf, count)                  |
| write         |      64 |        4 | (fd, buf, count)                  |
| close         |      57 |        6 | (fd)                              |
| exit          |      93 |        1 | (status)                          |
| ioctl         |      29 |       54 | (fd, cmd, arg)                    |
| mmap          |     222 |   90/192 | (addr, len, prot, flags, fd, off) |
| clock_gettime |     113 |      265 | (clk_id, timespec)                |
| nanosleep     |     101 |      162 | (req, rem)                        |

## Cell Size Decision

**64-bit cells** (8 bytes each). Reasons:
- ARM64 native word size is 64 bits
- Pointers are 64-bit (can't fit in 32 bits)
- `LDR`/`STR` naturally operate on 64-bit values
- Stack alignment: ARM64 requires 16-byte SP alignment
- Trade-off: uses more memory per cell, but memory is abundant

This means `CELL+` adds 8, `CELLS` multiplies by 8, and all stack entries
are 8 bytes wide. BasicForth uses 32-bit cells — Forth source that assumes
cell size (e.g., hardcoded `4 +` instead of `CELL+`) won't port cleanly.

## STC on ARM64

Subroutine Threaded Code works naturally:

```asm
// x86 STC (BasicForth):       // ARM64 STC (PumpkinForth):
// call forth_dup               BL forth_dup
// call forth_multiply          BL forth_multiply
// ret                          RET
```

`BL` (Branch with Link) saves the return address in X30 (Link Register).
`RET` branches back to X30. This is simpler than x86 where `CALL` pushes
to the stack and `RET` pops from it.

**Caveat**: Nested calls clobber X30. A primitive that calls another function
must save X30 first (push to stack or save in a callee-saved register). Same
concept as x86, different mechanism.

### Compiling User Words

The `:` compiler generates BL instructions:

```asm
// : double  dup + ;
// Compiles to:
double:
    BL forth_dup        // 4 bytes (fixed width!)
    BL forth_add        // 4 bytes
    RET                 // 4 bytes
```

ARM64 advantage: every instruction is exactly 4 bytes. No variable-length
encoding like x86. This simplifies the compiler — every compiled call is
4 bytes, always.

**BL range limit**: BL can reach +/- 128MB from the current instruction.
For our purposes this is effectively unlimited (dictionary won't be that large).

### compile_call on ARM64

```asm
// Compile a BL instruction to target address
// Input: X0 = target address
compile_call:
    LDR X1, [X20]          // X1 = HERE
    SUB X2, X0, X1         // X2 = offset = target - HERE
    ASR X2, X2, #2         // Shift right 2 (BL encodes word offset)
    AND X2, X2, #0x3FFFFFF // Mask to 26 bits
    ORR X2, X2, #0x94000000 // BL opcode
    STR W2, [X1]           // Store 32-bit instruction at HERE
    ADD X1, X1, #4         // Advance HERE
    STR X1, [X20]          // Update HERE
    RET
```

## Software Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────┐
│  core.fs          (pure Forth words)        │  Portable across all platforms
├─────────────────────────────────────────────┤
│  core.s           (asm primitives)          │  ARM64-specific, platform-independent
├─────────────────────────────────────────────┤
│  platform_linux.s (Linux syscalls)          │  Platform-specific I/O
└─────────────────────────────────────────────┘
```

### platform_linux.s — Platform Layer

The only file that knows about Linux. Swap this to port to bare metal.

- `EMIT` — write(stdout, &char, 1)
- `KEY` — read(stdin, &char, 1)
- `BYE` — exit syscall
- Terminal raw mode — ioctl TCGETS/TCSETS
- Memory allocation — mmap (anonymous)
- Block I/O — open/read/write/lseek

### core.s — Minimal ASM Primitives (~30-35 words)

Platform-independent ARM64 assembly. The goal is to minimize this layer —
only what *must* be asm for performance or because it can't be expressed
in Forth.

**Stack:**       `DUP`, `DROP`, `SWAP`, `OVER`, `>R`, `R>`
**Arithmetic:**  `+`, `-`, `*`, `/MOD`, `NEGATE`
**Logic:**       `AND`, `OR`, `XOR`, `INVERT`
**Comparison:**  `0=`, `0<`
**Memory:**      `@`, `!`, `C@`, `C!`
**Compiler:**    `LIT`, `:`, `;`, `BRANCH`, `0BRANCH`, `,`, `EXECUTE`, `IMMEDIATE`, `'`
**System:**      `HERE`, `LATEST`, `STATE`, `EXIT`
**Engine:**      Outer interpreter, number parsing, dictionary search

### core.fs — Forth-Level Words

Pure Forth, portable across all PumpkinForth ports (and potentially
shareable with BasicForth). Built from the asm primitives above.

**Derived stack:**       `2DUP`, `2DROP`, `ROT`, `NIP`, `TUCK`, `?DUP`
**Derived arithmetic:**  `1+`, `1-`, `CELL+`, `CELLS`, `ABS`, `MOD`, `*/`
**Comparisons:**         `=`, `<>`, `<`, `>`, `MIN`, `MAX`, `WITHIN`
**Control flow:**        `IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`, `WHILE`, `REPEAT`, `DO`, `LOOP`
**Formatting:**          `.`, `CR`, `SPACE`, `SPACES`, `.S`, `U.`
**Strings:**             `TYPE`, `COUNT`, `S"`

This is a significant departure from BasicForth, where nearly all words
were implemented in assembly. By defining the minimum asm core and building
the rest in Forth, we bring the system up faster and keep more code portable.
Words can be moved back down to asm later if performance requires it.

### Inspiration: seedForth

The layered approach is inspired by Ulrich Hoffmann's seedForth/preForth,
which bootstraps a full Forth from just 13 asm primitives. We use more
primitives (~30-35) for a pragmatic balance between minimalism and
usability, but the principle is the same: define the minimum in asm,
build the rest in the language itself.

### C/C++ Interoperability

PumpkinForth's register usage follows the ARM64 calling convention (AAPCS64),
keeping the door open for linking with C and C++ libraries.

Key compatibility points:
- X19-X28 (our engine registers) are callee-saved in AAPCS64 — C functions
  won't clobber them, and we preserve them if C calls into Forth
- SP is kept 16-byte aligned — required by AAPCS64
- X0-X7 for arguments, X0 for return values — same as our syscall convention
- X29 (FP) and X30 (LR) saved/restored with standard prologue/epilogue

To call a C library function from Forth, a wrapper word would:
1. Move Forth stack arguments into X0-X7
2. BL to the C function (engine registers survive because they're callee-saved)
3. Push X0 (return value) onto the Forth data stack

To call Forth from C, an entry point would:
1. Save caller's X19-X28 (AAPCS64 requires this)
2. Load PumpkinForth engine registers from a context structure
3. Execute Forth code
4. Store engine registers back, restore caller's X19-X28

C++ uses the same AAPCS64 ABI — use `extern "C"` on the C++ side to
avoid name mangling.

This is a later-phase feature. For now we link with `ld` directly (no libc).
When needed, switch to `gcc -nostartfiles` to get access to shared libraries
while still providing our own `_start`.

### Future: Concurrency (OS Threads)

PumpkinForth will support concurrency via Linux OS threads (clone() syscall).
Each thread gets its own data stack and return stack, enabling true multi-core
parallelism on the Genio 510's big.LITTLE cores.

Per-thread state: data stack (X19), return stack (SP), engine registers (X20-X28).
Shared state: dictionary (read-only once compiled), block buffers (need synchronization).

Architectural decisions to support this:
- Engine state lives in registers (X19-X28) — context switch is just save/restore ~10 registers
- No global variables for stack pointers — registers are per-core by nature
- Dictionary is immutable once compiled — safe for concurrent read access
- Platform layer (platform_linux.s) will provide thread creation and synchronization primitives

This is a later-phase feature, but the register-based design is chosen now to
keep the path open.

## Project Phases

### Phase 1: Hello World ✓ COMPLETE
- Minimal static ELF binary for ARM64 Linux
- Write "Hello World" to stdout via write syscall
- Verified on Genio 510 (native) and QEMU aarch64 (cross-compile)
- Build system: Makefile with `as` + `ld`, auto-detects native vs cross
- Cross-compile on x86 laptop, deploy to board via SSH

### Phase 2: REPL Foundation
- Terminal raw mode (ioctl TCGETS/TCSETS) — in platform_linux.s
- Line input with backspace and echo
- Number parsing (decimal, hex)
- Data stack (X19 as stack pointer)
- Basic asm primitives: DUP, DROP, SWAP, +, -, ., CR
- Outer interpreter loop

### Phase 3: Dictionary and Compiler
- Dictionary structure (same layout as BasicForth)
- Word lookup (case-insensitive)
- `:` and `;` — compile BL sequences (STC)
- `CONSTANT`, `VARIABLE`, `CREATE`
- Control flow: IF/ELSE/THEN, BEGIN/UNTIL, DO/LOOP
- core.fs — derived words in Forth

### Phase 4: Block System and Libraries
- Block storage (file-backed, same format as BasicForth)
- LOAD, LIST, THRU
- Port core.fs from BasicForth (or write PumpkinForth-specific version)
- Port vi.fs (should work unchanged)

### Phase 5: Framebuffer and Graphics
- Linux framebuffer via /dev/fb0 or DRM/KMS
- Font rendering (reuse Terminus font from BasicForth)
- Shadow buffer + blit
- Port snake.fs, sprite demos

### Phase 6: Yocto Integration
- Custom Yocto layer for PumpkinForth
- PumpkinForth as /sbin/init (PID 1)
- Boot straight to Forth prompt
- GPIO access via /dev/gpiochip (for the 40-pin header)

## Shared Code with BasicForth

These files can be copied (or symlinked) directly:

| File                   | Notes                                        |
|------------------------|----------------------------------------------|
| `lib/core.fs`          | All pure Forth — works unchanged             |
| `lib/vi.fs`            | All pure Forth — works unchanged             |
| `examples/snake.fs`    | Works unchanged                              |
| `examples/wumpus.fs`   | Works unchanged (once ported for BasicForth) |
| `tools/fs_to_blocks.c` | C tool — architecture independent            |
| `tools/blocks_to_fs.c` | C tool — architecture independent            |

Files that need rewriting from scratch:

| File                   | Notes                                                  |
|------------------------|--------------------------------------------------------|
| `src/core.s`           | ARM64 asm primitives (~30-35 words)                    |
| `src/platform_linux.s` | ARM64 Linux syscalls (EMIT, KEY, BYE, raw mode, mmap) |
| `src/core.fs`          | Derived Forth words built from asm primitives          |
| `src/Makefile`         | ARM64 assembler + linker                               |

## Resolved Questions

1. **Native or cross-compile?** Both. Makefile auto-detects host architecture.
   Cross-compile on x86 laptop with QEMU for quick iteration, deploy to board
   via SSH for real hardware testing.

2. **QEMU for testing?** Yes. `qemu-aarch64-static` user-mode works well for
   syscall-based programs. Won't work for framebuffer (Phase 5).

3. **64-bit cells.** Native word size, pointers fit naturally. Forth source
   that uses `CELL+` and `CELLS` instead of hardcoded sizes will port fine.

4. **Lesson format?** Separate `docs/Lessons.md` for PumpkinForth, written
   after each implementation milestone. Same teaching style as BasicForth.

## Open Questions

1. **License?** Same GPL v2 as BasicForth?

## References

- [ARM64 Instruction Set Overview](https://developer.arm.com/documentation/ddi0596/latest)
- [Linux ARM64 Syscall Table](https://arm64.syscall.sh/)
- [ARM64 Calling Convention (AAPCS64)](https://developer.arm.com/documentation/den0024/latest)
- [MediaTek Genio 510 Specs](https://www.mediatek.com/products/iot/genio-iot/genio-510)
- [Pumpkin Genio 510 Board Guide](https://ologic.gitlab.io/aiot-dev-guide-pumpkin/qsg/pumpkin_genio_510/board_reference_guide.html)
