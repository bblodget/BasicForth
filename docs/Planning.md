# BasicForth — Planning Document

A modern Forth environment for Linux, inspired by 1980s BASIC. Boot up and
start coding — games, robots, whatever you want. Multi-architecture
(ARM64 + x86-64), pure assembly core with minimal library dependencies.

Successor to [BareMetalForth](../../../BareMetalForth/) (x86-32), which
targeted bare metal. BasicForth builds on Linux instead, making it practical
to support modern hardware without drowning in driver work.

## Project Goals

1. **BASIC for modern computers** — an interactive development environment
   you can boot directly into, with everything you need to write and run code
2. **Multi-architecture** — native on x86-64 and ARM64, same Forth source
3. **Learn assembly and Linux internals** — direct syscalls, no libc
4. **Low-level but practical** — syscalls by default, minimal libraries where
   it makes sense (graphics, sound, threading)
5. **Target applications** — video games and robotics
6. **Educational documentation** — lesson series for each architecture

## Target Platforms

### x86-64: Development Laptop
- Native build and test, fastest iteration cycle
- Any x86-64 Linux system

### ARM64: OLogic Pumpkin Genio 510-EVK
- MediaTek Genio 510 (MT8370), 6nm
- 2x Cortex-A78 @ 2.2GHz + 4x Cortex-A55 @ 2.0GHz (big.LITTLE)
- Mali G57 MC2 GPU
- Raspberry Pi-compatible 40-pin GPIO header
- Primary robotics platform

### ARM64: Raspberry Pi 3/4/5
- Widely available, well-documented
- Same ARM64 Linux syscall ABI

### Future
- Apple Silicon (Linux VM)
- Qualcomm Snapdragon X (WSL)
- Cloud ARM64 instances (AWS Graviton, etc.)

## Design Decisions

### Linux First

Linux handles hardware — USB, display, storage, networking. We own everything
above the syscall boundary. This is the key lesson from BareMetalForth: bare
metal is fascinating but impractical for supporting modern peripherals.

For the "bare metal feel": a custom Linux image with BasicForth as init (PID 1).
Boot straight to a Forth prompt, no distractions.

The platform layer is still isolated — `platform_linux.s` could be swapped for
`platform_baremetal.s` without changing the Forth core, but that's not the
primary goal.

### Minimal Library Dependencies

The default is raw syscalls: no libc, no dynamic linker, static ELF binary
linked with `ld` directly.

However, we're open to minimal libraries where going direct would be
unreasonably painful:

| Domain     | Syscall approach         | Library option           | Decision    |
|------------|--------------------------|--------------------------|-------------|
| Terminal   | ioctl TCGETS/TCSETS      | —                        | Syscalls    |
| Memory     | mmap                     | —                        | Syscalls    |
| Files      | open/read/write/lseek    | —                        | Syscalls    |
| Graphics   | /dev/fb0 or DRM/KMS ioctl | SDL2                    | TBD         |
| Sound      | ALSA ioctl               | libasound or PipeWire    | TBD         |
| Threading  | clone() syscall          | pthread                  | TBD         |

When we do use a library, switch from `ld` to `gcc -nostartfiles` to get
dynamic linking while keeping our own `_start`.

### Editor Strategy

Rather than writing a vi.fs from scratch (as in BareMetalForth), call out to
the user's `$EDITOR` via fork/exec. This gives syntax highlighting, undo, etc.
for free. A minimal in-Forth editor can be written later for the PID 1 scenario.

### GNU Assembler (as)

Both architectures use GNU as (`.s` files). Comment style differs:
- ARM64: `//` line comments (also `/* */`)
- x86-64: `#` line comments (also `/* */`)

## Source Tree

```
src/
  arch/
    arm64/
      main.s              _start, test harness
      core.s              ASM primitives (DUP, DROP, +, EMIT, KEY, ...)
      platform_linux.s    Linux syscalls, terminal raw mode
      Makefile            Cross-compile or native ARM64 build
    x86/
      main.s              _start, test harness
      core.s              ASM primitives (same words, x86-64 instructions)
      platform_linux.s    Linux syscalls, terminal raw mode
      Makefile            Native x86-64 build
  forth/                  Shared Forth source (future core.fs)
Makefile                  Top-level dispatcher
docs/
  Planning.md             This file
  Platform_Layer.md       Platform API reference
  Core_Primitives.md      ASM primitives reference
  Forth_Core_Words.md     Forth vocabulary reference
  ARM64_Quick_Reference.md
  x86_Quick_Reference.md
```

## Register Allocation

### ARM64

| Register | Convention            | BasicForth Use                    |
|----------|-----------------------|-----------------------------------|
| X0-X7    | Args / return values  | Syscall args, scratch             |
| X8       | Syscall number        | Linux syscall dispatch            |
| X9-X15   | Caller-saved temps    | Scratch within primitives         |
| X16-X18  | Platform / linker     | Avoid                             |
| X19      | Callee-saved          | Data stack pointer (DSP)          |
| X20      | Callee-saved          | Scratch (available)               |
| X21      | Callee-saved          | HERE pointer                      |
| X22      | Callee-saved          | LATEST pointer                    |
| X23-X28  | Callee-saved          | Engine state (STATE, BASE, etc.)  |
| X29      | Frame pointer         | Available                         |
| X30      | Link register         | Return address (saved by BL)      |
| SP       | Stack pointer         | Return stack                      |

### x86-64

| Register | Convention            | BasicForth Use                    |
|----------|-----------------------|-----------------------------------|
| RAX      | Return value          | Syscall number, scratch           |
| RDI-R9   | Args                  | Syscall args, scratch             |
| RCX, R11 | Clobbered by syscall  | Scratch                           |
| R10      | 4th syscall arg       | Scratch                           |
| R12      | Callee-saved          | LATEST pointer                    |
| R13      | Callee-saved          | HERE pointer                      |
| R14      | Callee-saved          | Scratch (available)               |
| R15      | Callee-saved          | Data stack pointer (DSP)          |
| RSP      | Stack pointer         | Return stack                      |

Both use callee-saved registers for engine state, ensuring compatibility
with the platform's C calling convention (AAPCS64 on ARM64, System V AMD64
on x86-64). This keeps the door open for linking with C/C++ libraries.

## STC (Subroutine Threaded Code)

Both architectures use STC — compiled words are sequences of native call
instructions:

```
ARM64:                    x86-64:
  BL forth_dup              call forth_dup
  BL forth_add              call forth_add
  RET                       ret
```

ARM64 advantage: every instruction is exactly 4 bytes (fixed-width encoding).
x86-64: CALL is 5 bytes (1-byte opcode + 4-byte relative offset).

### compile_call

ARM64 encodes the offset in the BL instruction itself (26-bit word offset,
+/- 128MB range). x86-64 uses a 32-bit relative offset (+/- 2GB range).

## Software Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────┐
│  core.fs          (pure Forth words)        │  Portable across all architectures
├─────────────────────────────────────────────┤
│  core.s           (asm primitives)          │  Per-architecture, platform-independent
├─────────────────────────────────────────────┤
│  platform_linux.s (Linux syscalls)          │  Per-architecture, platform-specific
└─────────────────────────────────────────────┘
```

### platform_linux.s — Platform Layer

The only file that knows about Linux. Per-architecture, since syscall numbers
and calling conventions differ.

- `platform_emit` — write(stdout, &char, 1)
- `platform_key` — read(stdin, &char, 1)
- `platform_bye` — restore terminal, exit
- `platform_raw_mode` — ioctl TCGETS/TCSETS (disable ECHO, ICANON, IXON; set VMIN=1)
- `platform_restore_term` — ioctl TCSETS with saved original termios
- Future: mmap, open/read/write/lseek, clone

### core.s — Minimal ASM Primitives (~30-35 words)

Per-architecture, platform-independent. The goal is to minimize this layer —
only what *must* be asm for performance or because it can't be expressed
in Forth.

**Stack:**       `DUP`, `DROP`, `SWAP`, `OVER`, `>R`, `R>`
**Arithmetic:**  `+`, `-`, `*`, `/MOD`, `NEGATE`
**Logic:**       `AND`, `OR`, `XOR`, `INVERT`
**Comparison:**  `0=`, `0<`
**Memory:**      `@`, `!`, `C@`, `C!`
**I/O:**         `EMIT`, `KEY` (wrappers around platform layer)
**Compiler:**    `LIT`, `:`, `;`, `BRANCH`, `0BRANCH`, `,`, `EXECUTE`, `IMMEDIATE`, `'`
**System:**      `HERE`, `LATEST`, `STATE`, `EXIT`
**Engine:**      Outer interpreter, number parsing, dictionary search

### core.fs — Forth-Level Words

Pure Forth, shared across all architectures. Built from the asm primitives.

**Derived stack:**       `2DUP`, `2DROP`, `ROT`, `NIP`, `TUCK`, `?DUP`
**Derived arithmetic:**  `1+`, `1-`, `CELL+`, `CELLS`, `ABS`, `MOD`, `*/`
**Comparisons:**         `=`, `<>`, `<`, `>`, `MIN`, `MAX`, `WITHIN`
**Control flow:**        `IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`, `WHILE`, `REPEAT`, `DO`, `LOOP`
**Formatting:**          `.`, `CR`, `SPACE`, `SPACES`, `.S`, `U.`
**Strings:**             `TYPE`, `COUNT`, `S"`

### Inspiration: seedForth

The layered approach is inspired by Ulrich Hoffmann's seedForth/preForth,
which bootstraps a full Forth from just 13 asm primitives. We use more
primitives (~30-35) for a pragmatic balance between minimalism and
usability, but the principle is the same: define the minimum in asm,
build the rest in the language itself.

## C/C++ Interoperability

BasicForth's register usage follows each platform's C calling convention,
keeping the door open for linking with C and C++ libraries.

On both architectures, our engine registers (DSP, HERE, LATEST) live in
callee-saved registers. This means C functions won't clobber them, and we
preserve them if C calls into Forth.

To call a C library function from Forth:
1. Move Forth stack arguments into the platform's argument registers
2. Call the C function (engine registers survive)
3. Push the return value onto the Forth data stack

To call Forth from C:
1. Save the caller's callee-saved registers
2. Load BasicForth engine registers from a context structure
3. Execute Forth code
4. Store engine registers back, restore caller's registers

This is a later-phase feature. For now we link with `ld` directly (no libc).
When needed, switch to `gcc -nostartfiles` to get access to shared libraries
while still providing our own `_start`.

## Concurrency (OS Threads)

BasicForth will support concurrency via Linux OS threads (clone() syscall
or pthread).

Per-thread state: data stack pointer, return stack (SP/RSP), engine registers.
Shared state: dictionary (read-only once compiled), block buffers (need sync).

The register-based design supports this naturally:
- Engine state lives in registers — context switch is save/restore ~10 registers
- No global variables for stack pointers — registers are per-core by nature
- Dictionary is immutable once compiled — safe for concurrent read access

This is a later-phase feature, but the register-based design is chosen now to
keep the path open.

## Project Phases

### Phase 1: Hello World — COMPLETE
- Minimal static ELF binary for ARM64 Linux
- Write "Hello World" to stdout via write syscall
- Verified on Genio 510 (native) and QEMU aarch64 (cross-compile)
- Build system: Makefile with `as` + `ld`, auto-detects native vs cross

### Phase 2: REPL Foundation — COMPLETE
- Terminal raw mode (ioctl TCGETS/TCSETS)
- Data stack with 50+ primitives (arithmetic, stack, logic, comparison, memory)
- KEY, EMIT, ACCEPT (line input with backspace and echo)
- Number parsing (decimal, hex, binary, negative)
- Outer interpreter loop (PARSE-WORD, FIND, EXECUTE, NUMBER)
- Multi-architecture build system (ARM64 + x86-64)

### Phase 3: Dictionary and Compiler — IN PROGRESS
- Dictionary structure with case-insensitive lookup — done
- `:` and `;` — compile call sequences (STC) — done
- Control flow: IF/ELSE/THEN, BEGIN/UNTIL/AGAIN, WHILE/REPEAT, RECURSE — done
- EVALUATE, INCLUDED, core.fs bootstrap — done
- Comments: `(` and `\` — done
- Remaining: `CONSTANT`, `VARIABLE`, `CREATE/DOES>`, DO/LOOP

### Phase 4: File System and Storage
- File-based source loading (INCLUDED) — done
- Remaining: SAVE / persistence of user definitions

### Phase 5: Graphics and Sound
- Linux framebuffer (/dev/fb0), DRM/KMS, or SDL2
- Font rendering
- Sound output (ALSA or PipeWire)
- Game demos (snake, sprites)

### Phase 6: Robotics
- GPIO access via /dev/gpiochip (Pumpkin 40-pin header)
- I2C/SPI sensor communication
- Real-time control loops

### Phase 7: Custom Linux Distribution
- Minimal Linux image with BasicForth as /sbin/init (PID 1)
- Boot straight to Forth prompt
- Built-in editor for standalone development
- Targets: Pumpkin Genio 510, Raspberry Pi, x86 systems

## Resolved Questions

1. **Architecture?** Both ARM64 and x86-64, developed in parallel.
2. **Native or cross-compile?** Both. ARM64 Makefile auto-detects host.
   x86-64 builds natively on the laptop.
3. **QEMU for testing?** Yes. `qemu-aarch64-static` user-mode works well for
   syscall-based programs. Won't work for framebuffer/GPU.
4. **64-bit cells.** Native word size on both architectures. Forth source
   that uses `CELL+` and `CELLS` instead of hardcoded sizes ports cleanly.
5. **Comment style?** ARM64 uses `//`, x86 uses `#`. Both support `/* */`.
6. **Editor?** Call out to `$EDITOR` via fork/exec rather than writing vi.fs.

## Open Questions

1. **License?** GPL v2 (same as BareMetalForth)?
2. **Graphics approach?** Raw framebuffer, DRM/KMS, or SDL2?
3. **Threading?** Raw clone() or pthread?

## References

- [ARM64 Instruction Set Overview](https://developer.arm.com/documentation/ddi0596/latest)
- [Linux ARM64 Syscall Table](https://arm64.syscall.sh/)
- [Linux x86-64 Syscall Table](https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/)
- [ARM64 Calling Convention (AAPCS64)](https://developer.arm.com/documentation/den0024/latest)
- [System V AMD64 ABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
- [MediaTek Genio 510 Specs](https://www.mediatek.com/products/iot/genio-iot/genio-510)
