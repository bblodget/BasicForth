PumpkinForth is an educational Forth implementation for ARM64 Linux, sister
project to BasicForth (x86). Pure ARM64 assembly, no libc, raw syscalls,
subroutine threaded code.

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
4. The lesson style should match BasicForth's docs/Lessons.md.

## Development Environment

- Development on x86 Linux laptop using Claude Code
- Cross-compile with aarch64-linux-gnu-as + aarch64-linux-gnu-ld
- Smoke test with qemu-aarch64 (user-mode emulation)
- Deploy and test on Pumpkin Genio 510 board (Pumpkian Debian) via SSH
- Makefile targets: build, test (QEMU), deploy (scp + ssh to board)

## Architecture

- Pure ARM64 assembly (GNU as)
- No libc, no dynamic linker — static ELF binary
- Subroutine Threaded Code (STC) using BL/RET
- 64-bit cells (native word size)
- Register allocation: X19=DSP, X20=HERE, X21=LATEST, SP=return stack
- Linux syscalls via SVC #0

## Related Projects

- BasicForth: ~/Dev/BasicForth/ (x86 sister project)
- Pumpkian: ~/Dev/Pumpkian/ (Debian image builder for the target board)
