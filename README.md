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

**v0.16.0** — **Names instead of juggling, and a number that is just a number.**
**Local variables** arrive (Forth 2012 section 13): `{: a b c :}` names a word's
arguments, so three or four of them stop being an exercise in `rot swap over`.
`| t` adds a zeroed scratch value the caller never supplies, `TO` writes one,
and a trailing `-- comment` lets the declaration carry its own stack comment.
The point was never the syntax — a reference and the frame are **open-coded**,
a load rather than a call, because locals that cost a call would be slower than
the juggling they replace. Measured on a Raspberry Pi 400: 0.62 ns a reference
against 2.24 ns for the `dup` it stands in for.

Chasing that led somewhere better. **A number now compiles to an immediate**
instead of a call to `lit` with eight bytes of payload behind it. The old form
reached its operand through its own return address and returned past it, so
every literal mispredicted the return-stack predictor — the most expensive step
in the engine. A loop containing one constant is **2.6x faster on ARM64**, 1.6x
on x86-64, and usually smaller too. The call form is deliberately kept wherever
the inline cell is *storage* someone reads or patches later, which is what let
the two cases be separated instead of traded off.

A file can now **say what it needs from the machine**, and you can ask before
you load it. `NEEDS-CMD` and `NEEDS-LIB` stop a load that cannot work, with a
message naming the file and what to do about it; `WANTS-CMD` and `WANTS-LIB`
declare what a file runs degraded without, which is why `disasm.fs`, `speech.fs`
and `voice.fs` finally have a dep block without giving up their retry-and-report
behaviour. `DEPS <file>` reports the lot against this machine without running a
line — following `require` into the files named there, because "found" is no
comfort when the file underneath it cannot load. And **speech needs no file at
all** now: `say` synthesizes through flite straight onto a channel.

This is also the first release exercised on **real ARM64 hardware** rather than
under emulation, which is where the boot-time `SIGILL` fix came from — a
cache-maintenance bug every QEMU suite had passed, because QEMU models neither
an incoherent instruction cache nor weak memory ordering. Builds on v0.15.0.
123 unit tests + 1180 integration tests + 36 PTY tests + 32 lesson replays.
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
- Locals (Forth 2012 section 13): `{: a b c :}` names a word's arguments so
  three of them stop being an exercise in `rot swap over`; `| t` adds a
  zeroed scratch value the caller never supplies, `TO` writes one, and a
  trailing `-- comment` lets the declaration carry its own stack comment.
  References and the frame are open-coded — a load, never a call — and the
  locals stack is per-thread
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
  settable command template, so nothing here is tied to one — and `SAY`
  speaks arbitrary text on the spot through flite, synthesized into memory
  with no file at all (`speech.fs`)
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
- Dependencies: a file states what it needs at the top — `NEEDS-CMD` and
  `NEEDS-LIB` stop the load with an actionable message rather than half-loading,
  `WANTS-CMD`/`WANTS-LIB` declare what it can run degraded without, and
  `DEPS <file>` reports the lot against this machine without loading a line
- Integer literals (decimal, `$hex`, `%binary`, `#decimal`)
- Guard pages catch stack overflow/underflow with clean recovery
- Control-flow safety: tag mismatch and balance checking

What's next: a GPU backend (SDL_GPU) behind the surface API and sockets —
plus the rest of the package registry and more games. (Threading shipped in
v0.14.0; rendering speech to a file in v0.15.0, and in v0.16.0 both `say`, so
speech at the prompt needs no file at all, and the locals word set.)

## Building

The whole thing, on a current Debian or Ubuntu:

```sh
sudo apt install git binutils gcc make
git clone https://github.com/bblodget/BasicForth.git
cd BasicForth
make
. ./setup.sh
sudo apt install libsdl3-dev libflite1    # graphics, sound, gamepads, say
basicforth
```

The last `apt` line is the optional half: skip it and everything still builds
and runs, without a window or a sound. SDL3 and flite are `dlopen`ed on
demand, so a missing one costs exactly its own feature and nothing else. If
`apt` reports no `libsdl3-dev`, your distribution predates SDL3 and builds it
from source instead.

See **[docs/Guides/Install.md](docs/Guides/Install.md)** for that, the ARM64
cross-compile, rendering speech to WAV files, and what `setup.sh` does — or
`help install` at the prompt, which is the same page.

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
    Guides/                 Task pages, readable at the prompt (help install)
    Tutorials/              Interactive tutorials (tutorial Snake)
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
