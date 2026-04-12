# Changelog

## Unreleased (snake-game branch)

Snake game port from BareMetalForth, plus platform and Forth additions
to support interactive games.

### Platform Layer
- `platform_key`: ANSI escape sequence parsing — arrow keys (ESC[A/B/C/D)
  return abstract key codes 129-132, standalone ESC returns 27
- `platform_ms_get`: monotonic millisecond timestamp via clock_gettime
- `platform_cursor_off`, `platform_cursor_on`: ANSI cursor visibility

### New Forth Words (asm)
- `MS@` ( -- u ) — monotonic millisecond timestamp
- `CURSOR-OFF` ( -- ) — hide terminal cursor
- `CURSOR-ON` ( -- ) — show terminal cursor
- `INCLUDE` ( "name" -- ) — parse filename and load it (convenience wrapper for INCLUDED)

### New Forth Words (core.fs)
- Key constants: `KEY_ESCAPE` (27), `KEY_UP` (129), `KEY_DOWN` (130),
  `KEY_RIGHT` (131), `KEY_LEFT` (132)
- `random` ( -- n ) — LCG random number generator, seeded from MS@
- `rnd` ( n -- 0..n-1 ) — random number in range

### Command-Line File Loading
- `./basicforth filename.fs` loads a Forth file at startup before the REPL
- Saves argc/argv[1] at `_start`, loads after core.fs

### Snake Game
- `examples/snake.fs` — terminal-based snake game
- Adaptive frame timing, score overlay, game-over screen
- Works on both x86-64 and ARM64 (tested on Pumpkin board)

### Testing
- 119 unit tests + 294 integration tests

---

## v0.4.0 — 2026-04-12

Core extensions complete, plus words from four additional standard word
sets: Programming-Tools, String, Facility, and Double-Number. Platform
layer extended with terminal query and timing functions, enabling games
and interactive applications.

### Core Extension Words (completing section 6.2)
- `?DO` — skip-if-equal counted loop
- `VALUE`, `TO` — named mutable values with interpret/compile dual behavior
- `:NONAME` — anonymous colon definitions (pushes xt)
- `PARSE` — parse with arbitrary delimiter character
- `PARSE-NAME` — standard alias for PARSE-WORD
- `SOURCE-ID` — input source identifier (0=keyboard, -1=EVALUATE)

### Programming-Tools Words (section 15)
- `WORDS` — list all dictionary words
- `DUMP` — hex+ASCII memory dump
- `?` — fetch and print shorthand

### String Words (section 17)
- `/STRING` — adjust string address and length
- `COMPARE` — lexicographic string comparison
- `CMOVE`, `CMOVE>` — forward and backward byte copy
- `-TRAILING` — remove trailing spaces
- `BLANK` — fill with spaces

### Facility Words (section 10)
- `KEY?` — non-blocking input check
- `MS` — millisecond delay
- `PAGE` — clear screen (ANSI)
- `AT-XY` — cursor positioning (ANSI)
- `SCREEN-WIDTH`, `SCREEN-HEIGHT` — terminal size query

### Double-Number Words (section 8)
- `D+`, `D-` — double-cell addition and subtraction
- `D.` — print signed double-cell number
- `D0=`, `D0<` — double-cell zero tests
- `D=`, `D<` — double-cell comparison

### Platform Layer
- 6 new platform functions: `platform_key_ready`, `platform_ms`,
  `platform_page`, `platform_at_xy`, `platform_screen_width`,
  `platform_screen_height`
- Linux: FIONREAD ioctl, nanosleep, TIOCGWINSZ ioctl, ANSI escapes
- Clean abstraction for future Windows/bare-metal ports

### Testing
- 119 unit tests (C harness)
- 280 integration tests (shell-based, piped I/O)

---

## v0.3.0 — 2026-04-11

Full ANS Forth core word set (section 6.1). All 133 required core words
are now implemented, plus many useful core extension words. BasicForth
is a standards-compliant Forth environment.

### Defining Words
- `CREATE`, `CONSTANT`, `VARIABLE`, `DOES>`, `>BODY`
- `HERE`, `ALLOT`, `,`, `C,`

### Counted Loops
- `DO`, `LOOP`, `+LOOP`, `I`, `J`, `UNLOOP`, `LEAVE`

### Multi-Way Branching
- `CASE`, `OF`, `ENDOF`, `ENDCASE`

### Double-Cell Arithmetic
- `S>D`, `UM*`, `M*`, `UM/MOD`, `SM/REM`, `FM/MOD`
- `DNEGATE`, `DABS` (helpers in core.fs)

### Pictured Numeric Output
- `<#`, `#`, `#S`, `#>`, `HOLD`, `HOLDS`, `SIGN`
- `BASE`, `PAD`, `HLD`, `DECIMAL`, `HEX`
- `.` redefined using pictured output (respects BASE)
- `U.`, `.R`, `U.R`, `*/MOD`, `*/`

### Compiler Words
- `STATE`, `[`, `]`, `LITERAL`, `POSTPONE`, `COMPILE,`
- `[']`, `[CHAR]`, `EXIT`

### System Words
- `>IN`, `SOURCE`, `>NUMBER`, `WORD`, `ENVIRONMENT?`
- `ABORT`, `ABORT"`, `QUIT`

### String Words
- `TYPE`, `S"`, `."`, `COUNT`, `CHAR`, `PICK`
- Unterminated string error detection

### Simple Core Words
- Arithmetic: `LSHIFT`, `RSHIFT`, `2*`, `2/`, `+!`
- Memory: `2!`, `2@`, `FILL`, `MOVE`, `ALIGN`, `ALIGNED`, `CHAR+`, `CHARS`
- Comparison: `U<`
- Stack: `-ROT`

### Core Extension Words
- `0>`, `U>`, `WITHIN`, `ERASE`, `UNUSED`
- `.(` (immediate print)

### Bug Fixes
- ARM64 `+LOOP` off-by-one branch offset (TBNZ +2 → +3)
- `LEAVE` outside DO now detected at compile time
- Stale compiler state (do_depth, leave_count) reset on error
- Unknown-word compile abort restores DSP
- `compile_s_quote` bounds check and unterminated string detection
- `.R` signed-number handling with double-cell DABS
- `.` handles INT64_MIN correctly via DNEGATE
- Missing `.global forth_one_plus` on ARM64

### Architecture
- Per-test timing in integration tests with slow-test threshold
- ARM64 software 128/64-bit division for UM/MOD
- DOES> patching: x86 RET+NOPs → JMP rel32, ARM64 RET → B
- POSTPONE handles both IMMEDIATE and non-IMMEDIATE words

### Documentation
- docs/Defining_Words.md — dictionary layout, CREATE, DOES>
- docs/String_Words.md — inline string compilation
- docs/Pictured_Numeric_Output.md — number formatting, double-cell math
- Updated Core_Primitives.md, Conditionals.md, Forth_Core_Words.md

### Testing
- 119 unit tests (C harness)
- 236 integration tests (shell-based, piped I/O)

---

## v0.2.0 — 2026-04-09

Control flow, file loading, and the core.fs bootstrap. BasicForth can now
load Forth source files and compile definitions with conditionals, loops,
and recursion.

### Features
- Control flow: `IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`, `AGAIN`, `WHILE`, `REPEAT`
- Recursion: `RECURSE` (compile call to current definition)
- Comments: `(` paren comments, `\` line comments
- `EVALUATE` — interpret a string as Forth source
- `INCLUDED` — load and interpret a Forth source file (via mmap)
- Startup auto-load of `core.fs` (silent skip if not found)
- core.fs words: `CR`, `SPACE`, `BL`, `TRUE`, `FALSE`, `MOD`, `/`, `CELL+`, `CELLS`, `<>`, `0<>`
- Control-flow safety: tag checking detects mismatched pairs (e.g., `BEGIN...THEN`)
- Unresolved control flow detected by `;` with clean rollback
- File error reporting with filename and line number

### Architecture
- Inline native branches (not BRANCH/0BRANCH primitives) — true STC
- x86-64: `JZ`/`JMP` rel32 with forward-reference patching
- ARM64: `CBZ`/`B` with bitfield offset encoding and I-cache flush
- Nest-safe longjmp recovery for errors inside EVALUATE/INCLUDED
- FIND returns flag=2 for IMMEDIATE+COMPILE_ONLY words
- Platform file I/O: `open`, `fstat`, `mmap`, `munmap`, `close` syscalls

### Testing
- 119 unit tests (C harness)
- 113 integration tests (shell-based, piped I/O)

---

## v0.1.0 — 2026-04-08

Initial tagged release. Interactive REPL with compiler on ARM64 and x86-64.

### Features
- Interactive REPL with line editing (backspace, Ctrl+C)
- Colon definitions (`: square dup * ;`)
- Integer literals: decimal, `$hex`, `%binary`, `#decimal`, negative
- Arithmetic: `+ - * /MOD ABS MIN MAX NEGATE 1+ 1-`
- Comparisons: `= < > 0= 0<`
- Logic: `AND OR XOR INVERT`
- Stack: `DUP DROP SWAP OVER ROT NIP TUCK 2DUP 2DROP DEPTH ?DUP`
- Return stack: `>R R> R@` (compile-only)
- Memory: `@ ! C@ C!`
- I/O: `EMIT KEY . .S`
- Dictionary: `FIND WORDS IMMEDIATE '`
- Guard pages catch stack overflow/underflow with clean recovery
- ARM64 I-cache flush for compiled code
- Startup banner with version from git tags
- EOF handling for piped input
- BYE word prints "Goodbye!" and exits

### Testing
- 113 unit tests (C harness)
- 75 integration tests (shell-based, piped I/O)

### Build System
- Native architecture auto-detection (`make` builds for host)
- Cross-compile ARM64 from x86 with QEMU support
- Targets: `make`, `make run`, `make test`, `make run-test`, `make run-integration`
