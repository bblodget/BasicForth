BasicForth is a modern Forth environment for Linux, inspired by 1980s BASIC —
boot up and start coding. Multi-architecture (ARM64 + x86-64), pure assembly
with minimal library dependencies, targeting video games and robotics.

## Working Style

The way we like to work is: first we make a plan together, once we agree on the
plan and the go-ahead is given, then we execute the plan step by step.

## Documentation

Reference docs live in docs/. Each covers one topic and is kept up to date
as the code evolves:

- Planning.md — vision, phases, design decisions
- Platform_Layer.md — platform API, termios, syscall reference, file I/O
- Core_Primitives.md — ASM primitives, data stack, pure memory stack design
- Forth_Core_Words.md — Forth 2012 standard core vocabulary
- Conditionals.md — control flow compilation, branch encoding, error handling
- Defining_Words.md — CREATE, CONSTANT, VARIABLE, DOES>, dictionary layout
- String_Words.md — TYPE, S", .", COUNT, inline string compilation
- Outer_Interpreter.md — REPL loop, forth_interpret_line, EVALUATE/INCLUDED
- ARM64_Quick_Reference.md — ARM64 instruction and register reference
- x86_Quick_Reference.md — x86-64 AT&T syntax reference

## Development Environment

- Development on x86 Linux laptop using Claude Code
- x86-64: build and run natively on laptop
- ARM64: cross-compile with aarch64-linux-gnu-as + aarch64-linux-gnu-ld
- ARM64 smoke test with qemu-aarch64 (user-mode emulation)
- Deploy and test on Pumpkin Genio 510 board via SSH
- Top-level Makefile dispatches to arch-specific builds

## Architecture

- Multi-arch: src/arch/arm64/ and src/arch/x86/
- Shared Forth source: src/forth/ (future core.fs)
- No libc, no dynamic linker — static ELF binaries
- Subroutine Threaded Code (STC)
- 64-bit cells (native word size on both architectures)
- Linux syscalls (SVC #0 on ARM64, syscall on x86-64)
- Open to minimal libraries for threading, graphics, sound where it makes sense

## Register Allocation

### ARM64
- X19=DSP, X21=HERE, X22=LATEST, SP=return stack
- Pure memory stack: TOS at [X19], no TOS-in-register

### x86-64
- R15=DSP, R13=HERE, R12=LATEST, RSP=return stack
- Pure memory stack: TOS at [R15], no TOS-in-register

## Related Projects

- BareMetalForth: ~/Dev/BareMetalForth/ (original x86-32 bare metal project)
- Pumpkian: ~/Dev/Pumpkian/ (Debian image builder for the target board)
