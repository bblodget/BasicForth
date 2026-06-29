# BasicForth

A "basic" Forth system written in pure assembly for ARM64 and x86-64 Linux.

Inspired by 1980s BASIC — boot up and start coding. No libc, no dynamic
linker, just static ELF binaries built from assembly source. Subroutine
Threaded Code (STC) with 64-bit cells.

Goal:  Fun, retro-inspired Forth environment for graphics, sounds, games
and robotics on modern ARM64 and x86-64 hardware.

## Philosophy

BasicForth grows out of my earlier bare-metal x86-32 Forth project. The
guiding ideas:

- **BASIC for modern computers** — an interactive environment you can boot
  straight into and start coding, the way 1980s home computers dropped you at a
  prompt. The eventual target is a minimal Linux image with BasicForth as PID 1,
  booting directly to a Forth prompt.
- **Linux first** — let the kernel handle the hard parts (USB, display, storage,
  networking) and own everything above the syscall boundary. Bare metal is
  fascinating but impractical for supporting modern peripherals; the platform
  layer stays isolated so a bare-metal or other-OS backend remains possible.
- **Low-level but practical** — raw syscalls by default (no libc, no dynamic
  linker, static ELF), but open to minimal libraries where going direct would be
  unreasonably painful (graphics, sound, threading). Engine registers follow each
  platform's C calling convention, keeping the door open to linking C/C++ later.
- **Target applications** — video games and robotics on real ARM64 and x86-64
  hardware.

See [docs/Planning.md](docs/Planning.md) for the full vision, design decisions,
and project phases.

## Status

**v0.8.0** — Library-free 2D graphics over DRM/KMS (Phase 5), `edit <word>` to
recall and re-edit a definition (with horizontal scrolling and a continuation
prompt), and `.session` to list this session's words. Builds on v0.7.0's
interactive line editor, shell-like words (`cd`/`ls`/`cat`/`pushd`/…), session
persistence (`save`/`reload`), built-in help (`man`/`topics`/`apropos`),
tutorials, source viewing (`see`), file access, and dynamic memory.
119 unit tests + 510 integration tests.
See [CHANGELOG.md](CHANGELOG.md) for the full history.

What works today:

- **ANS Forth core word set** — all 133 required words from section 6.1
- **Complete core extensions** — all commonly useful section 6.2 words
- Interactive REPL with a full line editor: arrow-key cursor movement,
  Ctrl-A/Ctrl-E, insert/delete anywhere, up/down command history, horizontal
  scrolling for long lines, and a `...` continuation prompt for open definitions
- `EDIT <word>` recalls a definition onto the prompt, pre-filled and editable
- Colon definitions (`: square dup * ;`) and anonymous (`:NONAME`)
- Defining words: `CREATE`, `CONSTANT`, `VARIABLE`, `VALUE`/`TO`, `DOES>`
- Late binding & redefinition: `DEFER`/`IS` (vectored words), `REDO`
- Control flow: `IF ELSE THEN`, `BEGIN UNTIL AGAIN WHILE REPEAT`
- Counted loops: `DO LOOP +LOOP I J UNLOOP LEAVE`, `?DO` (skip-if-equal)
- Multi-way branching: `CASE OF ENDOF ENDCASE`
- Compiler words: `LITERAL`, `POSTPONE`, `[']`, `[CHAR]`, `EXIT`, `STATE`, `[ ]`
- Double-cell arithmetic: `S>D`, `UM*`, `M*`, `UM/MOD`, `SM/REM`, `FM/MOD`, `D+`, `D-`, `D.`
- Pictured numeric output: `<# # #S #> HOLD SIGN`, `BASE`, `HEX`, `DECIMAL`
- Formatted output: `.` (base-aware), `U.`, `.R`, `U.R`
- String words: `TYPE`, `S"`, `."`, `COUNT`, `COMPARE`, `CMOVE`, `/STRING`, `-TRAILING`
- System: `ABORT`, `ABORT"`, `QUIT`, `>NUMBER`, `SOURCE`, `>IN`, `EVALUATE`, `INCLUDED`, `INCLUDE`
- Facility: `KEY?`, `MS`, `MS@`, `PAGE`, `AT-XY`, `CURSOR-OFF`, `CURSOR-ON`, `SCREEN-WIDTH`, `SCREEN-HEIGHT`
- File access: `OPEN-FILE`, `CREATE-FILE`, `CLOSE-FILE`, `READ-FILE`, `READ-LINE`,
  `WRITE-FILE`, `WRITE-LINE`, `FILE-SIZE`, `RENAME-FILE` (methods `R/O W/O R/W BIN`)
- Dynamic memory (ANS MEMORY): `ALLOCATE`, `FREE`, `RESIZE`
- Session persistence: `SAVE`/`RELOAD`/`-SESSION` (source-replay to `session.fs`)
  and `MARKER` dictionary restore points
- Help system: `MAN`, `TOPICS`, `APROPOS`, interactive `TUTORIAL`/`NEXT`/`BACK`,
  and `SEE` (show a word's source via dictionary metadata)
- Shell-like words: `PWD`, `CD`, `LS`, `CAT`, `MORE`, `PUSHD`, `POPD`, `DIRS`
- Graphics (Phase 5): library-free software 2D over DRM/KMS — `set-surface`,
  `pixel`, `fill-rect`, `clear`, named colors (`graphics.fs`); `drm-open`/
  `drm-show`/`drm-close` scan out to a real display with no libdrm/X/Wayland
- Tools: `WORDS`, `.SESSION` (list this session's words), `DUMP`, `.S`,
  `VERSION` (also `basicforth -v`)
- Unix integration: `#!` shebang scripts, `ARGC`/`ARGV`/`ARG`/`NEXT-ARG`/`SHIFT-ARGS`,
  `BYE-CODE` (exit status), clean stdout for use as a pipe/utility
- Game support: arrow key parsing, key constants, random number generator
- Examples: Snake (`snake.fs`, `snake-mini.fs`) plus Unix-style utilities
  (`cat.fs`, `sort.fs`, `tac.fs`, `echo.fs`, `lines.fs`) — x86-64 and ARM64
- File loading: auto-load `core.fs` (and `session.fs`) at startup;
  `BASICFORTH_PATH` multi-directory search
- Integer literals (decimal, `$hex`, `%binary`, `#decimal`)
- Guard pages catch stack overflow/underflow with clean recovery
- Control-flow safety: tag mismatch and balance checking

What's next: more Phase 5 — sound, a GPU (Vulkan) backend behind the surface
API, font rendering — plus locals word set, threading, and more games.

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
src/arch/x86/basicforth examples/snake.fs   # load a file at startup
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
      graphics.fs           Software 2D surface API (on-demand)
      drm.fs                DRM/KMS display backend (on-demand)
  tests/
    test_basicforth.c       Unit test harness (119 tests)
    test_integration.sh     Integration tests (510 tests, piped I/O)
    test_line_editor_pty.py Line-editor tests under a pseudo-terminal
    test_helper_arm64.s     ARM64 test bridge
    test_helper_x86.s       x86-64 test bridge
  examples/
    snake.fs                Snake game (full version)
    snake-mini.fs           Snake game (tutorial answer key)
    cat.fs / cat-lines.fs   Unix `cat` (byte-exact / line-oriented)
    sort.fs / tac.fs        Sort lines / reverse lines (heap demo)
    echo.fs / hello.fs      `#!` script utilities
    lines.fs                stdout/stderr split demo
  docs/                     Design documentation
    Tutorial/               Interactive tutorials (tutorial Snake)
    Language-Reference/     Per-topic reference (man Stack, …)
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
