# BasicForth

A "basic" Forth system written in pure assembly for ARM64 and x86-64 Linux.

Inspired by 1980s BASIC — boot up and start coding. No libc, no dynamic
linker, just static ELF binaries built from assembly source. Subroutine
Threaded Code (STC) with 64-bit cells.

## Status

**v0.3.0** — Full ANS Forth core word set. All 133 required core words
implemented, plus many useful core extension words.
119 unit tests + 236 integration tests.

What works today:

- **ANS Forth core word set** — all 133 required words from section 6.1
- Interactive REPL with line editing (backspace, Ctrl+C)
- Colon definitions (`: square dup * ;`)
- Defining words: `CREATE`, `CONSTANT`, `VARIABLE`, `DOES>`
- Control flow: `IF ELSE THEN`, `BEGIN UNTIL AGAIN WHILE REPEAT`
- Counted loops: `DO LOOP +LOOP I J UNLOOP LEAVE`
- Multi-way branching: `CASE OF ENDOF ENDCASE`
- Compiler words: `LITERAL`, `POSTPONE`, `[']`, `[CHAR]`, `EXIT`, `STATE`, `[ ]`
- Double-cell arithmetic: `S>D`, `UM*`, `M*`, `UM/MOD`, `SM/REM`, `FM/MOD`
- Pictured numeric output: `<# # #S #> HOLD SIGN`, `BASE`, `HEX`, `DECIMAL`
- Formatted output: `.` (base-aware), `U.`, `.R`, `U.R`
- String words: `TYPE`, `S"`, `."`, `COUNT`, `CHAR`, `PICK`
- System: `ABORT`, `ABORT"`, `QUIT`, `>NUMBER`, `SOURCE`, `>IN`, `EVALUATE`, `INCLUDED`
- File loading: auto-load `core.fs` at startup
- Integer literals (decimal, `$hex`, `%binary`, `#decimal`)
- Guard pages catch stack overflow/underflow with clean recovery
- Control-flow safety: tag mismatch and balance checking
- Core extension words: `0>`, `U>`, `WITHIN`, `ERASE`, `UNUSED`, `.(`, `HOLDS`, `COMPILE,`, `NIP`, `TUCK`, and more

What's next: remaining core extensions (?DO, VALUE/TO, :NONAME), Phase 4
file system and storage.

## Building

### Prerequisites

**x86-64** (native):
- GNU assembler (`as`)
- GNU linker (`ld`)
- GCC (for unit tests)

**ARM64** (cross-compile from x86-64):
- `aarch64-linux-gnu-as`, `aarch64-linux-gnu-ld`
- `aarch64-linux-gnu-gcc` (for unit tests)
- `qemu-aarch64-static` (optional, for local smoke testing)

On Debian/Ubuntu: `apt install binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu qemu-user-static`

### Build Commands

```sh
make              # Build for native architecture
make all          # Build all architectures
make x86          # Build x86-64 binary
make arm64        # Build ARM64 binary (cross-compile or native)
make clean        # Remove build artifacts
```

### Running

```sh
make run-x86      # Run x86-64 binary
make run-arm64    # Run ARM64 binary (native or via QEMU)

# Or directly:
src/arch/x86/basicforth
```

### Unit Tests

```sh
make run-test-x86     # Run x86-64 tests
make run-test-arm64   # Run ARM64 tests
```

### Deploy to ARM64 Board

For deploying to a remote ARM64 board, see
`src/arch/arm64/deploy_template.sh`.

## Example Session

```
> 6 7 * .
42  ok
> : square dup * ;
 ok
> 9 square .
81  ok
> : fact  1 swap 1+ 1 do i * loop ;
 ok
> 6 fact .
720  ok
> hex FF . decimal
FF  ok
> : describe  case
    1 of ." one"   endof
    2 of ." two"   endof
    3 of ." three" endof
    ." other"
  endcase ;
 ok
> 2 describe
two ok
> : make-adder  create ,  does> @ + ;
 ok
> 5 make-adder add5
 ok
> 10 add5 .
15  ok
```

## Architecture

BasicForth uses a three-layer design:

```
+---------------------------------------------+
|  core.fs          (pure Forth words)        |  Portable across all platforms
+---------------------------------------------+
|  core.s           (asm primitives)          |  Per-arch, platform-independent
+---------------------------------------------+
|  platform_linux.s (Linux syscalls)          |  OS-specific
+---------------------------------------------+
```

- **Subroutine Threaded Code (STC)**: compiled words are native CALL/RET
  (x86) or BL/RET (ARM64) sequences. No interpreter overhead.
- **Pure memory stack**: data stack top is always in memory at `[DSP]`,
  not cached in a register. Simpler, easier to debug.
- **64-bit cells**: native word size on both architectures.
- **No libc**: direct Linux syscalls via `syscall` (x86) / `SVC #0` (ARM64).

### Register Allocation

| Register | ARM64 | x86-64 | Purpose            |
|----------|-------|--------|--------------------|
| DSP      | X19   | R15    | Data stack pointer |
| HERE     | X21   | R13    | Dictionary pointer |
| LATEST   | X22   | R12    | Latest dict entry  |
| RSP      | SP    | RSP    | Return stack       |

## Project Structure

```
BasicForth/
  Makefile                  Top-level build (dispatches to arch dirs)
  src/
    arch/
      arm64/
        main.s              Outer interpreter
        core.s              Assembly primitives + dictionary
        platform_linux.s    Linux syscalls, guard pages, I-cache flush
        Makefile
      x86/
        main.s              Outer interpreter
        core.s              Assembly primitives + dictionary
        platform_linux.s    Linux syscalls, guard pages
        Makefile
    forth/
      core.fs               Forth-defined words (loaded at startup)
  tests/
    test_basicforth.c       Unit test harness (119 tests)
    test_integration.sh     Integration tests (236 tests, piped I/O)
    test_helper_arm64.s     ARM64 test bridge
    test_helper_x86.s       x86-64 test bridge
  docs/                     Design documentation
```

## Target Hardware

- **Development**: x86-64 Linux laptop
- **ARM64 board**: any ARM64 Linux board (Raspberry Pi 4/5, etc.)
  running a 64-bit OS

## License

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version. See [LICENSE](LICENSE) for details.
