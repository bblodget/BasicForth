# Changelog

## Unreleased

### Added: help-system sections (grouped `topics`, labelled `apropos`)
- Each directory in `BASICFORTH_DOCS` is now treated as a named **section** (its
  last path component). `topics` groups its listing under one header per section
  instead of printing a flat list, and `apropos` tags each hit with its section
  (e.g. `Stack (Language-Reference)`). `man` still searches across all sections.
- A section header is printed lazily, so a directory with no `.md` files adds no
  header. New internal word `(basename)` extracts the section name.
- First user-facing docs landed under this scheme: `Language-Reference/Stack.md`
  and `Tutorial/01-Getting-Started.md`.

### Added: interactive help system (`man` / `topics` / `apropos`)
- A docs browser reads the `docs/*.md` files in the colon-separated directories
  named by the `BASICFORTH_DOCS` environment variable (same convention as
  `BASICFORTH_PATH`). `topics` lists the available topics; `man <topic>` finds
  `<topic>.md` (case-insensitive) and pages it a screenful at a time
  (space = next page, q = quit); `apropos <keyword>` lists the topics whose file
  contains the keyword (case-insensitive substring).
- New primitives back the feature: `(getdents)` wraps the `getdents64` syscall
  for directory enumeration, and `(docs-path)` exposes `BASICFORTH_DOCS`. The
  getdents and pager line buffers live on the heap (`allocate`), so the feature
  costs little dictionary space.
- See docs/Help_System.md.

### Fixed: `char` / `[char]` could segfault on missing input
- `parse-word` returns `( 0 0 )` when there is no next word; `char`
  (`parse-word drop c@`) and `[char]` both fetched that `c-addr` *without
  checking the length*, dereferencing a NULL (or, at the end of a page-sized
  included file, an unmapped) address. So `: star char * emit ;` then `star` (a
  misuse — `[char]` is the in-definition form), a bare `char`, or an `[char]` at
  the very end of a file all crashed. Fix: the callers now check `u` before
  fetching — `char` returns 0 when there is no word, and `[char]` compiles 0 —
  so the invalid `c-addr` is never dereferenced. `[char] *` and interpret-time
  `char *` are unchanged.

### Fixed: INCLUDE left the interpreter parsing a freed file mapping
- `forth_included` set `source_addr`/`source_len`/`to_in` to the included file's
  lines but never restored the caller's values, then `munmap`ed the file — so
  after the include the outer interpreter parsed from a freed mapping. It only
  worked when `include` was the last token of a line and the file was fully
  consumed; a leftover token, or a compile-time error inside the file (an
  undefined word inside a `:`), dereferenced the freed page and wedged the REPL
  or segfaulted (with the SAVE capture hooks active). `forth_included` now saves
  and restores the source pointers around the line loop on both architectures.
- Bonus: tokens after `include <file>` on the same line now run correctly, and
  `reload` recovers cleanly from a `session.fs` with an error.

### Session reload — edit/compile/run loop
- `-session ( -- )` forgets everything defined since startup (the session
  definitions and anything entered interactively), keeping `core.fs` and the
  session words. `reload ( -- )` does `-session` then re-`include`s the
  (possibly hand-edited) `session.fs`. Built on a restore point recorded just
  past `core.fs` at startup (`(session-mark!)`/`(session-restore)` primitives,
  both arches), so the file needs no marker header.
- `session.fs` now stays *pure definitions*: capture is forward-only (a marker
  run / `-session` moves `LATEST` backward and is not logged), and `reload`
  suppresses its own line. After a clean reload the in-memory log is re-seeded
  from the file, so a later `save` matches the edited file. If `session.fs` has
  an error, `reload` reports it (`reload: …`), leaves the log untouched (so
  `save` can't persist a broken file), and the REPL keeps running.
- Clarified in TODO: `INCLUDED` from inside a colon word is **not** buggy; it is
  `( c-addr u -- )` per ANS (the earlier "underflow" was a stray `included drop`).

### MARKER — dictionary restore points
- `marker ( "name" -- )` defines a word that, when run, restores `HERE` and
  `LATEST` to their values from just before the marker — forgetting the marker
  and every later definition and reclaiming the dictionary space. The modern
  replacement for `FORGET`; the basis of an edit/compile/run loop and (soon) a
  cleanly reloadable `session.fs`. Markers nest.
- Defined in core.fs with `CREATE ... DOES>`, on two small primitives:
  `(latest@) ( -- a )` and `(restore-dict) ( here latest -- )`, on both
  architectures. New docs/Marker.md.

### Fixed: INCLUDE/INCLUDED of an empty or tiny file
- `forth_included` could close a standard file descriptor when loading a 0-, 1-,
  or 2-byte file: x86 `platform_mmap_file` clobbered the callee-saved `%rbx`
  (which `forth_included` used for the fd), so the subsequent close ran
  `close(file_size)` — `close(0/1/2)` = stdin/stdout/stderr. For larger files it
  closed an unopened fd (a harmless leak), which is why it went unnoticed until
  empty-`session.fs` auto-load hit it. `platform_mmap_file` now leaves `%rbx`
  alone, and `forth_included` treats a 0-byte file as a clean no-op (skips
  `mmap`). Empty/whitespace source files now load correctly.

### Session persistence — SAVE (Phase 4)
- `save ( -- )` writes the words you define interactively to `session.fs` in the
  current directory; an interactive session auto-loads `session.fs` at startup
  (after `core.fs`). `save` writes a temporary file and atomically `rename-file`s
  it into place, so a write failure can never destroy an existing `session.fs`.
- New `rename-file ( c-addr1 u1 c-addr2 u2 -- ior )` (ANS FILE-EXT) and a
  `platform_rename` syscall wrapper (`renameat`) on both architectures.
- `write-file` (and thus `write-line`) now loops over `write(2)` until all bytes
  are written; a short write is no longer reported as success, so output — and
  the temp file `save` renames into place — can never be silently truncated. Persistence is source-replay: it records the *source text*
  of definitions, not a binary image. Capture excludes transient actions (only
  lines that advance the dictionary are kept), handles multi-line definitions,
  and discards a definition that errors partway. `save` is idempotent and
  cumulative, and a no-op when nothing was captured (no empty file).
- Active only in an interactive terminal session (stdin is a TTY, no script
  argument); `BASICFORTH_SESSION=1`/`0` forces it on/off. Scripts and pipes
  never auto-load or capture.
- The capture log is heap-backed (grows via `RESIZE`). The REPL drives three
  `core.fs` hook words — `(session-seed)`, `(capture-line)`, `(capture-reset)` —
  registered via a new `(hook!)` primitive; `session.fs` is loaded in asm by
  `main.s` (like `core.fs`). New docs/Persistence.md.

### Dynamic memory — ANS MEMORY wordset (Phase 4)
- `allocate ( u -- a-addr ior )`, `free ( a-addr -- ior )`, and
  `resize ( a-addr1 u -- a-addr2 ior )` provide a heap separate from the
  dictionary, obtained from the kernel on demand. Backed by anonymous `mmap`
  (one mapping per allocation), data-only (no execute permission). `allocate 0`
  is rejected with a non-zero `ior`; `resize` preserves contents up to the
  smaller of old/new and may move the block. Allocations are page-granular.
- New platform call `platform_mmap_anon` (anonymous `PROT_READ|PROT_WRITE`,
  `MAP_PRIVATE|MAP_ANONYMOUS`) on both architectures; `munmap` reused for
  release. `ALLOCATE`/`FREE`/`RESIZE` live in core.fs on top of the
  `(mmap-anon)`/`(munmap)` primitives, with the length-header bookkeeping and a
  portable allocate-copy-free `RESIZE` in Forth — so the internals can later be
  re-backed by a finer-grained allocator behind the same interface.
- New `examples/tac.fs` — the Unix `tac` (reverse the lines of stdin), the
  heap showcase: stdin's size is unknown, so it slurps into an `ALLOCATE`d
  buffer that doubles with `RESIZE` as it fills, then emits the lines in reverse
  and `FREE`s it. No fixed input limit, unlike the fixed-buffer `sort.fs`.

### `read-line` — line-at-a-time file reading (Phase 4)
- `read-line ( c-addr u1 fileid -- u2 flag ior )` returns exactly one line per
  call. It stores at most u1 characters (u2 <= u1) and consumes the line
  terminator without storing it. The terminator is LF; a CR immediately before
  it is removed, so CRLF files read cleanly. `flag` is false only at end of file
  with nothing read (the loop's stop signal); `ior` is 0 (incl. normal EOF) or a
  positive errno. A line longer than u1 fills the buffer and the rest of that
  line is read and discarded, so the next call starts at the following line
  (truncation, a deliberate choice over ANS "continuation"). No state is kept
  between calls, so reading several files or reused fds is always safe. Defined
  in core.fs on top of `read-file` (one byte per read()); a buffered version can
  replace it later behind the same interface.
- New `examples/cat-lines.fs` — the `cat` program rewritten with
  `read-line`/`write-line`, a line-oriented companion to the byte-exact
  `examples/cat.fs` (it normalizes CRLF to LF).

### File-access words (read & write files) (Phase 4)
- `open-file`/`create-file ( c-addr u fam -- fileid ior )`, `close-file
  ( fileid -- ior )`, `read-file ( c-addr u1 fileid -- u2 ior )`, and
  `file-size ( fileid -- ud ior )`. With `write-file` from the previous slice,
  scripts can now read and write data files. fileid is a raw OS fd; `ior` is 0
  on success else the positive errno.
- Access methods `r/o`/`w/o`/`r/w` (= the OS open flags) and `bin` (a no-op on
  Linux), defined in core.fs.
- Platform layer: new `platform_read_file`; `platform_open_file` split into
  `platform_open_file_mode` (flags + mode) with a read-only wrapper, plus
  `platform_create_file`; `platform_fstat` now returns a negative errno on
  failure so `file-size` can report it. `INCLUDED` is unchanged.
- New `examples/cat.fs` — a Forth `cat` (args → open → read loop → write to
  stdout → close; errors on stderr, non-zero exit on failure).
- New `examples/sort.fs` — sort a file's lines into `<name>_sorted.<ext>`
  (slurp with `read-file`, sort with `compare`, emit with `write-line`).

### Fixed: raw mode no longer corrupts the terminal for piped scripts
- BasicForth entered raw mode (echo off) on *every* startup, even for a
  non-interactive script. With `tool.fs | less`, `less` would start while the
  terminal was raw, save that as its "restore-to" state, and on quit put the
  terminal back into raw mode — leaving the shell with no echo.
- Raw mode is now entered **lazily, on the first interactive input**
  (`KEY`/`KEY?`/`ACCEPT`), and only when **stdin is a terminal**. A program
  that never reads input never touches the terminal; and keying off stdin
  (not stdout) means an interactive session still gets raw mode when its
  stdout is piped or redirected. `platform_restore_term` is a matching no-op
  when raw mode was never entered.

### Script arguments and exit status (Unix `#!` Tier 3)
- Command-line arguments are now exposed to Forth, mirroring gforth:
  - `argc` — variable holding the current argument count
  - `argv` — variable holding a pointer to the argument vector
  - `arg ( u -- c-addr u )` — the uth argument as a string (`0 0` if out of range)
  - `next-arg ( -- c-addr u )` — return the next argument and consume it
  - `shift-args ( -- )` — drop the first argument, decrementing `argc`
  - At startup the auto-loaded script is shifted out, so a script's first
    argument is `arg[1]` / the first `next-arg`.
- `bye-code ( n -- )` — exit with status `n`, silently (no "Goodbye!"), so a
  utility's stdout is not corrupted. Plain `bye` is unchanged.
- The startup banner is now printed only when entering the interactive REPL
  (a script ending in `bye`/`bye-code` exits first) and only when stdout is a
  terminal, so a script used as a Unix utility produces clean stdout whether
  its output goes to a terminal, a pipe, or a file. New platform calls:
  `platform_exit`, `platform_isatty`.
- New `examples/echo.fs` — a Forth `echo` utility (executable `#!` script).
- Fixed three integration tests that had been matching substrings in the
  startup banner (`0` from `v0.5.0`, `64` from `x86-64`) rather than real
  command output; they now assert actual output.

### Scripts exit non-zero on error
- A startup script that errors — an undefined word, a failed parse, a stack
  underflow, `ABORT`/`QUIT` — now prints its diagnostic and exits with a
  non-zero status instead of dropping into the interactive REPL, so a Forth
  utility fails like any other Unix program. Errors while loading `core.fs`
  still drop to the REPL (a broken bootstrap is a development problem).
- Internally: a `script_running` flag scopes this to the user script, and
  `rp0` is now initialized before the startup load so a fault during it
  recovers onto a valid return stack (previously `rp0` was only set on REPL
  entry — a latent bug for faults during startup).

### File-output words (stdout / stderr / fileid) (Phase 4)
- `stdin`/`stdout`/`stderr` push the standard fileids (0/1/2); a fileid is a
  raw OS file descriptor.
- `write-file ( c-addr u fileid -- ior )` and `write-line ( c-addr u fileid --
  ior )` write to any fileid, returning an `ior` (0 on success, else the
  positive `errno`). `write-line` appends a newline. This lets a utility write
  diagnostics to `stderr` without corrupting its stdout.
- `TYPE`/`EMIT` are unchanged (still stdout). Internally `platform_write` was
  split into `platform_write_fd ( fd buf len )` with a stdout wrapper; a single
  `write(2)` is issued (a partial write on a pipe counts as success).
- New `examples/lines.fs` — a utility that writes data to stdout and its count
  to stderr, demonstrating the stdout/stderr split.

### BASICFORTH_PATH multi-directory search
- `BASICFORTH_PATH` now accepts a colon-separated list of directories
  (like `PATH`). On a CWD miss, each directory is searched in order and
  the first match is loaded. Empty segments (leading/trailing/doubled
  `:`) are skipped. Applies to `INCLUDE`, `INCLUDED`, the command-line
  file argument, and the startup `core.fs` load.
- Single-directory and unset behavior are unchanged.

### Nested INCLUDED error reporting fix
- A file that `INCLUDE`d another file could report the wrong filename and
  line number for its own later errors: the nested call clobbered the
  `file_name_addr`/`file_name_len`/`file_line_num` globals and the shared
  path-resolution buffer. `forth_included` now saves and restores those
  globals around each line, and the resolved-path buffer is scratch-only.
- On a `BASICFORTH_PATH` hit, error messages now show the filename as
  typed rather than the resolved path (the trade for correct, nesting-safe
  reporting).

### Unix `#!` script support (Tier 1)
- `forth_included` skips a leading `#!` shebang line, so a Forth file can be
  made executable (`chmod +x foo.fs`) and run directly via
  `#!/usr/bin/env basicforth`. The check matches an exact `#!`, so a leading
  `#` decimal literal is unaffected, and the shebang counts as line 1 so
  error line numbers stay accurate. Scripts currently end with `bye` to exit
  (run-and-exit flag and `ARGC`/`ARGV` are planned follow-ups).
- New `examples/hello.fs` — an executable `#!` script demonstrating the
  feature.

### Bug fixes
- `.(` no longer leaks the parsed text onto the data stack (it pushed one
  cell per character). Redefined as the standard `[char] ) parse type`.

### Testing
- 119 unit tests + 309 integration tests (multi-directory, nested-INCLUDE
  error-context, `#!` script, script-argument/`bye-code`, and bundled-example
  cases)

---

## v0.5.0 — 2026-04-12

Snake game port from BareMetalForth, plus platform and Forth additions
to support interactive games, convenient file loading, and flexible
library search.

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

### BASICFORTH_PATH Environment Variable
- Fallback search directory for `INCLUDE`, `INCLUDED`, and startup core.fs
- `BASICFORTH_PATH=src/forth ./basicforth` finds core.fs from any CWD
- CWD is always tried first (existing behavior unchanged)

### Snake Game
- `examples/snake.fs` — terminal-based snake game
- Adaptive frame timing, score overlay, game-over screen
- Works on both x86-64 and ARM64 (tested on Pumpkin board)

### Testing
- 119 unit tests + 295 integration tests

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
