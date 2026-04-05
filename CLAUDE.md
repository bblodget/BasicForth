BasicForth is a modern Forth environment for Linux, inspired by 1980s BASIC —
boot up and start coding. Multi-architecture (ARM64 + x86-64), pure assembly
with minimal library dependencies, targeting video games and robotics.

## Working Style

The way we like to work is: first we make a plan together, once we agree on the
plan and the go-ahead is given, then we execute the plan step by step.

## Lessons and Documentation

We document the journey in docs/Lessons.md. The format is a series of
"lessons" followed by a Q&A section. Each lesson is basically a chapter.

The process:
1. Plan and implement a step/milestone together.
2. After the implementation is working, write the lesson in docs/Lessons.md.
3. The lesson should be written so a third-party reader can understand the
   concepts, algorithms (pseudocode), and data structures — but the assembly
   implementation is left as an exercise for the reader. Assembly hints are
   fine, but not the full code.

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
- X19=DSP, X20=TOS, X21=HERE, X22=LATEST, SP=return stack

### x86-64
- R15=DSP, R14=TOS, R13=HERE, R12=LATEST, RSP=return stack

## Related Projects

- BareMetalForth: ~/Dev/BareMetalForth/ (original x86-32 bare metal project)
- Pumpkian: ~/Dev/Pumpkian/ (Debian image builder for the target board)
