# BasicForth

A "basic" Forth system written in pure assembly for ARM64 and x86-64 Linux.

Inspired by 1980s BASIC — boot up and start coding. Raw Linux syscalls, no
runtime written in C — pure assembly source, plus an FFI that can call into
any C library (SDL3 for graphics). Subroutine
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
- **Low-level but practical** — raw syscalls by default (the platform layer
  never calls libc), plus an FFI (`dlopen`/`dlsym`/`(ccall)`) for the few
  capabilities sealed behind libraries (graphics, sound). Engine registers
  follow each platform's C calling convention, which is what lets Forth call
  straight into C libraries.
- **Target applications** — video games and robotics on real ARM64 and x86-64
  hardware.

See [docs/Planning.md](docs/Planning.md) for the full vision, design decisions,
and project phases.

## Status

**v0.15.0** — **Give it a voice and a controller.** `voice-render` turns text
into a WAV file through whatever text-to-speech engine the machine has — the
engine is a **command template**, so nothing here is tied to one, and a game
renders its phrases once at build time rather than paying synthesis in the
frame loop. **Game controllers** arrive with `pad.fs`: four slots, compass
button names, hot-plug handled where SDL actually reports it. A program can
**read its environment** now (`getenv`), which is how `voice.fs` finds its
engine, and startup's own five lookups go through the same platform call
instead of five hand-written copies per architecture.

The random generator is **seeded from the kernel** rather than the clock:
`ms@` gave two processes started in the same millisecond an identical stream —
200 parallel launches produced 87 distinct first values, now 200 of 200 — and
`0 seed !`, the obvious thing to type for a repeatable run, used to kill the
generator dead. Both fixed. The sound API also lost its odd corners:
`snd-open` returns an `ior` like `open-file`, `snd-alloc` is `next-ch`, and
`snd-vol` is `tone-amp` — named for what it is, since it is not a volume.

And BasicForth **runs Forth on OS threads** — `thread`, `join`, `threads`, with
`BASE`, `sp0` and the exception handler moved into thread-local storage and
worker stacks fenced by guard pages. Plus `<=`, `>=`, `u<=`, `u>=` as
primitives; a compile-only word now aborts the line and names itself instead of
letting the rest of it run; and a child process no longer prints onto the
command line you typed. Builds on v0.13.0.
123 unit tests + 951 integration tests + 36 PTY tests + 26 lesson replays.
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
- Pictured numeric output: `<# # #S #> HOLD SIGN`, `BASE`, `HEX`, `DECIMAL`, `BINARY`
- Formatted output: `.` (base-aware), `U.`, `.R`, `U.R`, `U.0R` (zero-padded)
- String words: `TYPE`, `S"`, `."`, `COUNT`, `COMPARE`, `CMOVE`, `/STRING`, `-TRAILING`
- Exceptions: `CATCH`, `THROW` (Forth 2012) — `ABORT`/`ABORT"` are catchable
- System: `ABORT`, `ABORT"`, `QUIT`, `>NUMBER`, `SOURCE`, `>IN`, `EVALUATE`, `INCLUDED`, `INCLUDE`
- Facility: `KEY?`, `MS`, `MS@`, `PAGE`, `AT-XY`, `CURSOR-OFF`, `CURSOR-ON`, `SCREEN-WIDTH`, `SCREEN-HEIGHT`
- File access: `OPEN-FILE`, `CREATE-FILE`, `CLOSE-FILE`, `READ-FILE`, `READ-LINE`,
  `WRITE-FILE`, `WRITE-LINE`, `FILE-SIZE`, `RENAME-FILE` (methods `R/O W/O R/W BIN`)
- Dynamic memory (ANS MEMORY): `ALLOCATE`, `FREE`, `RESIZE`
- Modules: `SAVE <name>` / `LOAD <name>` / `NEW` / `RELOAD` / `USES`
  (named source-replay files) and `MARKER` dictionary restore points;
  `ON-START`/`ON-STOP` hand a held resource across a reload, `KEEP` records
  a setup line that defined nothing, `BOOTING?` tells a start from a restart,
  `LIST` pages the whole program, and `DELETE <name>` removes a definition
- Editing: `EDIT <word>` / `:E <word>` / `DEFINE <word>` / bare `EDIT` —
  fix a definition in `$EDITOR` or at the prompt, draft a new one, or open
  the whole module; mutations splice the module file and reload it
- Help system: `HELP` (topic list / topic summary / per-word entry),
  `TUTORIALS`, `APROPOS`, interactive `TUTORIAL`/`NEXT`/`BACK`,
  and `SEE` (show a word's source via dictionary metadata)
- Shell-like words: `PWD`, `CD`, `LS`, `CAT`, `MORE`, `PUSHD`, `POPD`, `DIRS`
- Graphics (Phase 5): software 2D on a backend-agnostic surface — `set-surface`,
  `pixel`, `fill-rect`, `clear`, `fill32`, named colors (`graphics.fs`) —
  plus lines, rects and circles, full-color sprites (`GRAB`/`BLIT`/`BLIT-KEY`)
  and 1-bit sprites colored at draw time (`STAMP`/`ROW,`) — presented in a
  desktop window via the SDL3 backend (`sdl3.fs`): timer-paced frames
  (`SDL-FPS`), `SDL-SCALE` chunky pixels, `SDL-TITLE`, keyboard/quit events;
  try `examples/bounce.fs`
- Text: `TEXT`/`GLYPH` draw strings and characters on the surface, rendered
  through `STAMP` so text is any color and clips like a sprite. Two bundled
  CP437 faces — Terminus 8×16 (SIL OFL 1.1) and the IBM PC 8×8 (public
  domain) — load together and switch by name; `FONT-SCALE` magnifies them as
  `STAMP-SCALE` does sprites, and `>XY` turns a character cell into its pixel
  corner with the scale folded in, so a layout survives both a font switch
  and a scale change
- Sound: mixing channels through SDL3's playback device (`sound.fs`) —
  `SND-OPEN`, `TONE`, `BEEP`, `TONE-ON`, `SND-WAIT`. Sounds on different
  channels play together, sounds queued on one play in turn; `CH-VOL!` is
  SDL's own gain so it reaches audio already playing, and `CH-FADE` +
  `SND-PUMP` take a channel down gently
- Samples: `WAV-LOAD` reads a `.wav` (8/16/32-bit integer and 32-bit float,
  mono or stereo, 24-bit widened losslessly), `WAV-FROM` decodes one already
  in memory, and `WAV-PLAY` puts it on a channel (`wavcore.fs`, `wav.fs`)
- Speech: `VOICE-RENDER` speaks text into a WAV file through whatever
  text-to-speech engine the machine has (`voice.fs`) — the engine is a
  settable command template, so nothing here is tied to one
- Threads: `THREAD` runs a Forth word on an OS thread, `JOIN` waits for it,
  `THREADS` lists them — `BASE`, `sp0` and the exception handler are
  thread-local, and worker stacks are fenced with guard pages
- FFI: `dlopen`/`dlsym`/`(ccall)` call any C library directly from Forth
  (`ffi.fs`) — SDL3 is bound this way, with zero C glue code. `(CCALLF)` and
  `>F32` pass float arguments, which integer-only cells otherwise cannot
- Tools: `WORDS`, `.MODULE` (list the module's words), `DUMP`, `.S`,
  `VERSION` (also `basicforth -v`), and `DIS` — disassemble any word, your
  own or a primitive, with call targets named (`disasm.fs`)
- Unix integration: `#!` shebang scripts, `ARGC`/`ARGV`/`ARG`/`NEXT-ARG`/`SHIFT-ARGS`,
  `GETENV`, `BYE-CODE` (exit status), clean stdout for use as a pipe/utility
- Game controllers: `PAD-OPEN` claims one of four player slots (`pad.fs`),
  reporting an `ior` rather than aborting, with buttons named
  by **position** (`PAD-SOUTH`/`PAD-EAST`/`PAD-WEST`/`PAD-NORTH`) rather than
  by a letter that moves between Xbox, Nintendo and PlayStation, plus sticks,
  triggers, and a d-pad that wins over the analog stick when both are pushed
- Game support: arrow key parsing, key constants, and a random number generator
  seeded from the kernel (`RANDOM`, `RND`, `ENTROPY`)
- Examples: Snake (`snake.fs`, `snake-mini.fs`) plus Unix-style utilities
  (`cat.fs`, `sort.fs`, `tac.fs`, `echo.fs`, `lines.fs`) — x86-64 and ARM64
- File loading: auto-load `core.fs` (and `session.fs`) at startup;
  `BASICFORTH_PATH` multi-directory search
- Integer literals (decimal, `$hex`, `%binary`, `#decimal`)
- Guard pages catch stack overflow/underflow with clean recovery
- Control-flow safety: tag mismatch and balance checking

What's next: a GPU backend (SDL_GPU) behind the surface API and sockets —
plus a package registry, the locals word set, live speech at the prompt, and
more games. (Threading shipped in v0.14.0; rendering speech to a file, in
v0.15.0 — what is left is saying a phrase without writing it down first.)

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
- **Raw syscalls**: all OS work goes through `syscall` (x86) / `SVC #0`
  (ARM64) in the platform layer — never through libc. The binary is
  dynamically linked only so the FFI can `dlopen` C libraries (SDL3);
  libc is bypassed except `dlopen`/`dlsym`.

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
      ffi.fs                dlopen/dlsym wrappers for C libraries (on-demand)
      sdl3.fs               SDL3 display backend (on-demand)
      sound.fs              SDL3 audio backend (on-demand)
  tests/
    test_basicforth.c       Unit test harness (119 tests)
    test_integration.sh     Integration tests (610 tests, piped I/O)
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
    Language-Reference/     Per-topic reference (help stack, …)
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
