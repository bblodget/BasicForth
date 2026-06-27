# BasicForth — TODO

Detailed progress tracker organized by phase. Check items off as they're
completed. See Planning.md for high-level vision and design decisions.

---

## Phase 1: Hello World — COMPLETE

- [x] Minimal static ELF binary (ARM64)
- [x] Write to stdout via SYS_write
- [x] Verified on Genio 510 (native) and QEMU (cross-compile)
- [x] Makefile with as + ld, auto-detects native vs cross

---

## Phase 2: REPL Foundation — COMPLETE

- [x] Terminal raw mode (ioctl TCGETS/TCSETS)
- [x] Platform layer (platform_emit, platform_key, platform_bye, platform_write)
- [x] Data stack (pure memory, DSP points to top item)
- [x] Stack primitives (DUP, DROP, SWAP, OVER)
- [x] Arithmetic (+, -, NEGATE)
- [x] Memory access (@, !, C@, C!)
- [x] KEY, EMIT, ACCEPT (line input with backspace and echo)
- [x] Number parsing (decimal, hex, negative)
- [x] Dictionary structure (DEFWORD macro, linked list, 21 entries)
- [x] FIND (case-insensitive dictionary lookup)
- [x] PARSE-WORD, EXECUTE
- [x] DOT, DOT-S, BYE
- [x] Outer interpreter REPL (PARSE-WORD → FIND → EXECUTE → NUMBER → error)
- [x] Multi-architecture (ARM64 + x86-64) for all of the above
- [x] C unit test harness (both architectures)
- [x] Documentation (Manual, Dictionary, Outer Interpreter, Testing Framework)

---

## Phase 3: Dictionary & Compiler — IN PROGRESS

### 3a. Compiler Foundation — COMPLETE

- [x] STATE variable (0 = interpreting, non-zero = compiling)
- [x] compile_call ( xt -- ) — emit a CALL/BL instruction into dict space
- [x] compile_ret — emit RET (x86) or LDP+RET epilog (ARM64)
- [x] compile_prolog (ARM64) — emit STP to save LR in compiled words
- [x] LIT — push the next inline value onto the stack at runtime
- [x] compile_literal ( n -- ) — compile LIT + value into a definition
- [x] `:` (COLON) — parse name, create dictionary header, switch to compile mode
- [x] `;` (SEMICOLON) — compile RET, link new entry, switch to interpret mode
- [x] Update outer interpreter to check STATE (compile vs interpret)
- [x] IMMEDIATE — mark most recent word as immediate
- [x] `'` (TICK) — parse next word, push its xt
- [x] Unit tests for LIT
- [x] Error recovery: errors during compilation reset STATE, restore LATEST/HERE
- [x] Linker flag `ld -N` for RWX segments (dict_space must be executable)
- [x] CHECK_DICT macro — software bounds check before dictionary writes
- [x] Refactored TOS-in-register to pure memory stack (eliminated phantom item bug)
- [x] Hardware guard pages (mprotect PROT_NONE) for stack underflow/overflow
- [x] SIGSEGV signal handler with ucontext register recovery to REPL
- [x] Per-definition rollback (saved_latest/saved_here in forth_colon)
- [x] DROP dummy load to trigger guard page on empty stack
- [x] Error handling documentation (docs/Error_Handling.md)

### 3b. Control Flow — MOSTLY COMPLETE

- [x] Inline branch compilation (not BRANCH/0BRANCH primitives — true STC)
- [x] compile_0branch, compile_branch, patch_forward (internal helpers)
- [x] IF / ELSE / THEN — conditional compilation
- [x] BEGIN / UNTIL — post-test loop
- [x] BEGIN / AGAIN — infinite loop
- [x] BEGIN / WHILE / REPEAT — pre-test loop
- [x] RECURSE — compile call to current definition
- [x] Control-flow stack tags (CF_ORIG/CF_DEST) for mismatch detection
- [x] Balance check in `;` for unresolved forward references
- [x] Nest-safe longjmp recovery for errors inside EVALUATE/INCLUDED
- [x] FIND flag=2 for IMMEDIATE+COMPILE_ONLY words
- [x] Integration tests for control flow (20 tests)
- [x] Documentation (docs/Conditionals.md)
- [x] DO / LOOP / +LOOP / I / J / UNLOOP — counted loops
- [x] +LOOP boundary-crossing detection (handles non-exact increments)
- [x] LEAVE — exit DO loop early

### 3c. More ASM Primitives — COMPLETE

- [x] `*` (multiply)
- [x] `/MOD` (division with remainder, divide-by-zero and INT64_MIN/-1 safe)
- [x] ABS, MIN, MAX
- [x] 1+, 1-
- [x] Comparisons: `=`, `<`, `>`, `0=`, `0<`
- [x] Logic: AND, OR, XOR, INVERT
- [x] Stack: ROT, NIP, TUCK, 2DUP, 2DROP, DEPTH, ?DUP
- [x] Return stack: `>R`, `R>`, `R@` (F_COMPILE_ONLY)
- [x] Dictionary entries for all new primitives
- [x] Unit tests for all new primitives
- [x] ARM64 I-cache flush (platform_flush_icache, CTR_EL0 cache line detection)

### 3d. Defining Words — MOSTLY COMPLETE

- [x] HERE ( -- addr ) — push dictionary free-space pointer
- [x] ALLOT ( n -- ) — reserve n bytes (bounds-checked both directions)
- [x] `,` (COMMA) — compile a cell into dict space
- [x] `C,` — compile a byte into dict space
- [x] CREATE ( "name" -- ) — compile push-data-address code, aligned data field
- [x] CONSTANT ( x "name" -- ) — compile push-value code
- [x] VARIABLE ( "name" -- ) — defined in core.fs as CREATE 1 CELLS ALLOT
- [x] build_header refactor — shared by :, CREATE, CONSTANT
- [x] DOES> — attach runtime behavior to CREATE'd words

### 3e. core.fs Bootstrap — MOSTLY COMPLETE

- [x] Comments: `(` and `\` (asm, IMMEDIATE)
- [x] EVALUATE ( c-addr u -- ) — interpret a string as Forth
- [x] File I/O: platform_open_file, platform_fstat, platform_mmap_file, platform_munmap, platform_close_file
- [x] INCLUDED ( c-addr u -- ) — load Forth file via mmap, line-by-line
- [x] Startup auto-load of core.fs (silent skip if not found)
- [x] core.fs initial words: CR, SPACE, BL, TRUE, FALSE, MOD, /, CELL+, CELLS, <>, 0<>
- [x] Line-by-line error reporting: filename:line: ? token
- [x] Derived stack words: 2OVER, 2SWAP, PICK
- [x] Derived arithmetic: */
- [x] String words: TYPE, COUNT, S", ."
- [x] SPACES
- [x] Double-cell arithmetic: S>D, UM*, M*, UM/MOD, SM/REM, FM/MOD
- [x] Pictured numeric output: <#, #, #S, #>, HOLD, SIGN, BASE, PAD, HLD
- [x] Formatting: U., .R
- [x] */MOD (redefined with M* FM/MOD), DECIMAL
- [x] Batch 1: LSHIFT, RSHIFT, U<, 2/, +!, 2!, 2@, 2*, CHAR+, CHARS, FILL, MOVE, ALIGN, ALIGNED, CHAR, -ROT
- [x] Batch 2: STATE, [, ], LITERAL, ['], [CHAR], EXIT, POSTPONE, COMPILE,
- [x] Batch 3: >BODY, >IN, SOURCE, ABORT, QUIT, ABORT", >NUMBER, >DIGIT?, WORD, ENVIRONMENT?
- [x] Batch 4: CASE/OF/ENDOF/ENDCASE, UNUSED, 0>, U>, WITHIN, ERASE, U.R, HOLDS, .(
- [x] Batch 5: ?DO, VALUE/TO, :NONAME, PARSE, PARSE-NAME, SOURCE-ID, WORDS
- [x] String words: /STRING, COMPARE, CMOVE, CMOVE>, -TRAILING, BLANK
- [x] Programming-Tools: ?, DUMP, H.2, H.ADDR
- [x] Facility: KEY?, MS, PAGE, AT-XY, SCREEN-WIDTH, SCREEN-HEIGHT (platform layer)
- [x] Double-Number: D+, D-, D., D0=, D0<, D=, D<

---

## Infrastructure — COMPLETE

- [x] GitHub repository (private, github.com/bblodget/BasicForth)
- [x] README.md, LICENSE (GPL-2.0-only)
- [x] Copyright headers (SPDX) on all source files
- [x] Makefile: native arch auto-detection, run/test/clean/help targets
- [x] Makefile: QEMU auto-detection for cross-arch run targets
- [x] deploy_template.sh for remote board deployment
- [x] Startup banner with version from `git describe --tags --dirty`
- [x] Versioning with git tags (see docs/Versioning.md)
- [x] CHANGELOG.md
- [x] EOF handling in platform_key (clean exit on piped input)
- [x] Empty line re-prompts (instead of exiting)
- [x] BYE prints "Goodbye!" before exit
- [x] Integration test suite (shell-based piped I/O)
- [x] Native build and test on Pumpkin board (clone from GitHub)

---

## Phase 4: File System and Storage

- [x] Output handles (step 2): `stdin`/`stdout`/`stderr` (fileid = raw OS fd),
  `write-file`/`write-line ( c-addr u fileid -- ior )`. `platform_write` split
  into `platform_write_fd` with a stdout wrapper; `TYPE`/`EMIT` unchanged.
  Lets a utility write to stderr without corrupting stdout.
- [x] Generic file-access words (step 3): `open-file`, `create-file`,
  `close-file`, `read-file`, `file-size`, and `r/o`/`w/o`/`r/w`/`bin`. fileid =
  raw OS fd, `ior` = 0/positive errno (same model as the output words). New
  `platform_read_file`; `platform_open_file` generalized to
  `platform_open_file_mode` (+ read-only wrapper) and `platform_create_file`;
  `platform_fstat` reports errors. Example `examples/cat.fs`.
- [x] `read-line ( c-addr u1 fileid -- u2 flag ior )` (step 4): one line per
  call — at most u1 chars stored (u2 <= u1), terminator (LF, preceding CR
  stripped) consumed not stored; `flag` false only at EOF with nothing read. A
  line longer than u1 fills the buffer and the rest is discarded so the next
  call starts at the following line (truncation, chosen over ANS continuation);
  no cross-call state, so multiple files / reused fds are always safe. Defined
  in core.fs on top of `read-file` (one byte per read()), so no new asm/platform
  code — a buffered version can replace it later behind the same interface.
- [x] Dynamic memory — ANS MEMORY wordset (`ALLOCATE`/`FREE`/`RESIZE`): a heap
  *separate* from the dictionary, obtained from the kernel on demand via
  anonymous `mmap` (one mapping per allocation, data-only/no-exec). New
  `platform_mmap_anon`; `munmap` reused. `ALLOCATE`/`FREE`/`RESIZE` defined in
  core.fs over `(mmap-anon)`/`(munmap)` primitives, with a one-cell length
  header and a portable allocate-copy-free `RESIZE`, so the internals can be
  re-backed by a finer allocator later. `ALLOCATE 0` returns a non-zero `ior`;
  page-granular, so suited to a few large buffers. This unblocks later ideas
  that need scratch storage (SAVE session log, help text, text-processing lib).
  Still deferred (harder, separate step): *growing the dictionary itself* — a
  `PROT_EXEC` mapping with a movable `HERE` (see WildIdeas / Future-Hardening).
- Block storage / `LOAD` / `LIST` / `THRU` (Forth screens) — **Won't do.** Block
  screens are a historical storage model; BasicForth already loads source from
  files via `INCLUDE`/`INCLUDED`, and the Phase 4 file-access words cover real
  file I/O, so block storage adds little.
- [x] SAVE / persistence of user definitions — source-replay. `save` writes
  interactively-defined words to `session.fs`; an interactive session auto-loads
  it at startup (after core.fs). Capture excludes transient actions (LATEST/STATE
  delta — bare ALLOT/,/C, are not captured), handles multi-line defs, discards
  errored defs; idempotent and
  cumulative. Heap-backed log; REPL hooks `(session-seed)`/`(capture-line)`/
  `(capture-reset)` registered via `(hook!)`; gated to interactive tty sessions
  (`BASICFORTH_SESSION=1`/`0` overrides). See docs/Persistence.md.
  - Known limitation: persists definitions, not runtime state (a `variable`
    reloads uninitialized). Redefinitions accumulate in the file.
- [x] `MARKER` — dictionary restore points (modern replacement for `FORGET`).
  `marker <name>` defines a word that rewinds `HERE`/`LATEST` to before the
  marker, forgetting it and all later definitions. `CREATE ... DOES>` in core.fs
  over `(latest@)`/`(restore-dict)` primitives. See docs/Marker.md. (`FORGET`
  deferred — obsolescent, footgun-prone; BareMetalForth also did marker-only.)
- [x] Session integration for `MARKER`: `-session` forgets the session
  definitions (rewinds to a restore point recorded just past core.fs, so core.fs
  and the session words survive) and `reload` does `-session` + re-`include`
  session.fs — the edit/compile/run loop. session.fs stays *pure definitions*:
  capture is forward-only (a marker run / `-session` moves LATEST backward and is
  not logged) and `reload` sets a one-shot skip flag. Implemented with an
  external restore point (`(session-mark!)`/`(session-restore)` globals) rather
  than a marker-in-the-file, so the file needs no `marker -session` header. See
  docs/Persistence.md.
- [x] `SEE` — source lister. `see <name>` prints a word's definition source
  (exactly as typed; multi-line and comments preserved). Resolves the name and
  matches the live xt, so it shows the definition currently in force and never
  stale source: a redefinition shadows the older one, and a word forgotten by
  `-session`/a marker reports not found. Works for any defining word; no new asm
  primitive. See docs/See.md.
  - [x] **Dictionary source metadata → `see` for *any* word.** Each compiled
    header carries an 8-byte `[SrcId:2][Len:2][Off:4]` record stamped at compile
    time, and a `.bss` source table maps SrcId → absolute file path. `see`
    dispatches on SrcId: `≥1` reads the byte span straight from the source file
    (so `core.fs` and any `include`d file are covered, attributed by *file
    position* not name — no wrong-source edge); `0xFFFF` reports *primitive
    (assembly)*; `0` (typed at the REPL, no file) falls back to the session
    capture log. New primitives `(find-meta)`/`(source-path)`; `platform_getcwd`
    + `make_absolute` keep paths re-openable after a CWD change. This supersedes
    and retired the old post-load seeded text-parser (which recognised
    definitions by defining word and so missed custom-defining-word words and had
    a rare redefinition wrong-source edge — both now gone). See
    docs/See_Metadata.md. Shipped v0.6.0.
- [~] ~~Bug: `INCLUDED` from inside a colon definition underflows the stack~~ —
  **not a bug.** `INCLUDED` is `( c-addr u -- )` per ANS (it leaves nothing on
  the stack; errors are printed, not returned as an ior). The earlier "underflow"
  was an erroneous `included drop` — the `drop` underflowed after the file
  loaded. `: load s" foo.fs" included ;` (no `drop`) works fine, which is what
  `reload` relies on. The SAVE startup still loads session.fs in asm, but that's
  now just a convenience, not a workaround.
- [x] **Fixed: `INCLUDE`/`INCLUDED` left the outer interpreter parsing a freed
  mmap.** `forth_included` overwrote `source_addr`/`source_len`/`to_in` with the
  file's lines but never restored the caller's values, then `munmap`ed the file.
  After the include the outer `forth_interpret_line` parsed from the (now freed)
  mapping. It only "worked" when `include` was the last token of a line *and* the
  file was fully consumed (so `to_in >= source_len` → no deref); any leftover
  token, or a compile-time error inside the file (which leaves `to_in` mid-line),
  dereferenced the freed page — wedging the REPL or **segfaulting** once the SAVE
  capture hooks were active. Fix: `forth_included` now saves the source pointers
  before the line loop and restores them on every loop-exit path (both arches).
  Bonus: tokens after `include <file>` on the same line now run correctly.
- [x] **Help system — docs browser (`man` / `topics` / `apropos`).** Reads the
  `*.md` topics in the colon-separated directories named by `BASICFORTH_DOCS`.
  `topics` lists them, `man <topic>` finds `<topic>.md` (case-insensitive) and
  pages it a screenful at a time, `apropos <keyword>` lists the topics whose file
  contains the keyword. New primitives: `(getdents)` (wraps `getdents64` for
  directory enumeration) and `(docs-path)` (exposes `BASICFORTH_DOCS`); getdents
  and pager buffers are heap-allocated. See Help_System.md. (Per-word
  `help <word>` is deferred to a later "Part A" — see WildIdeas.md.)
- [x] **Interactive tutorial (`tutorial` / `next` / `back`).** Walks a
  `BASICFORTH_DOCS` Markdown file one `## `-heading step at a time, returning to
  the REPL after each step so the reader can type the examples. Reuses the
  docs-browser machinery (file resolution, `read-line`, the pager line-printer).
  See Tutorial_System.md.
- [x] **First tutorial content: "Snake".** `docs/Tutorial/Snake.md` builds a
  playable terminal Snake game step by step, exercising nearly the whole
  language. Finished program in `examples/snake-mini.fs` (load-tested in the
  integration suite). Tutorials are self-contained subjects with descriptive,
  prefix-free names (`tutorial Snake`).
- [x] **Dictionary space raised 64 KB → 256 KB** (`DICT_SPACE_SIZE`, both arches,
  BSS only). The shared dictionary was nearly full once large examples
  (`examples/sort.fs`) loaded alongside `core.fs`; `unused` now reports ~226 KB
  free.

---

## Phase 5: Graphics and Sound

- [ ] Framebuffer (/dev/fb0), DRM/KMS, or SDL2
- [ ] Font rendering
- [ ] Sound output (ALSA or PipeWire)
- [ ] Game demos (snake, sprites)

---

## Phase 6: Robotics

- [ ] GPIO access via /dev/gpiochip (Pumpkin 40-pin header)
- [ ] I2C / SPI sensor communication
- [ ] Real-time control loops

---

## Phase 7: Custom Linux Distribution

- [ ] Minimal Linux image with BasicForth as /sbin/init (PID 1)
- [ ] Boot straight to Forth prompt
- [ ] Built-in editor for standalone development

---

## Phase 8: Threading and Locals

- [ ] Locals word set (section 13) — Gforth-style separate locals stack
  - Separate locals stack (not return stack) to avoid conflicts with >R/R>
  - `{` syntax: `{ a b c -- result }` declares locals, pops from data stack
  - Each local name compiles to a locals-stack-relative fetch
  - TO works with locals (compile a locals-stack-relative store)
  - Reentrant and thread-safe (each thread gets its own locals stack)
  - Required for safe multi-threaded Forth words
- [ ] Threading support (pthreads or clone syscall)
  - Per-thread data stack, return stack, and locals stack
  - Shared dictionary (read-only after compilation)
  - Thread-local state: SOURCE, >IN, STATE, BASE
  - Synchronization primitives (mutex, semaphore)

---

## Future / Usability

- [x] `BASICFORTH_PATH` colon-separated directory search
  - Supports multiple directories separated by `:` (like PATH,
    LD_LIBRARY_PATH).
  - `BASICFORTH_PATH=/path/to/lib:/path/to/examples`
  - Each directory searched in order when a file is not found in CWD;
    first match wins. Empty segments are skipped.
- [x] Fix `incl_path_buf` for nested INCLUDED calls
  - `forth_included` now saves/restores `file_name_addr`, `file_name_len`,
    and `file_line_num` around the `forth_interpret_line` call, so a nested
    INCLUDE no longer corrupts the parent's error context (it was reporting
    the wrong file AND line).
  - `incl_path_buf` is now scratch-only: on a fallback hit the error name
    stays the original (as-typed) filename rather than the resolved path, so
    no error-reporting state depends on the shared buffer.

---

## Shell-Like Words (pwd / cd / ls / cat / more) — NEXT

Navigate and inspect the filesystem from the REPL — hop to another directory
and list or read a file without leaving BasicForth. Most infrastructure already
exists; only `chdir` is a new syscall. See `docs/WildIdeas.md` for the full
write-up. Read-only + navigation first; filesystem mutators (`mkdir`/`rm`/`cp`/
`touch`) are deferred as a separate, riskier class.

- [x] `chdir` platform primitive
  - New syscall wrapper: `SYS_chdir` (80 on x86-64, 49 on ARM64), stubbed in
    both `test_helper_*.s`. Forth bridge `chdir ( c-addr u -- ior )` copies the
    path to a NUL-terminated buffer (over-long → `-ENAMETOOLONG`).
- [x] Capture the startup directory at boot
  - `_start` `getcwd`s into `startup_dir` before `core.fs` loads. `(startup-dir)`
    exposes it. `session.fs` is now pinned to it: `core.fs` builds absolute
    `<startup>/session.fs(.new)` for seed-log / SAVE / RELOAD, so persistence
    never wanders after a `cd`. Regression test guards it.
- [x] `pwd ( -- )` — prints the cwd (← new `(cwd)` primitive over `getcwd`).
- [x] `cd ( "path" -- )` — `chdir` to the parsed token.
  - `cd` with no argument → returns to the startup directory; a failed cd reports
    the offending path.
  - [ ] `cd ~` → `$HOME` (optional `~` expansion via the `HOME` env var) — not
    yet done; needs HOME captured at boot.
- [x] `ls ( "[dir]" -- )` — list a directory (current by default; optional `<dir>`
    arg supported), one entry per line, skipping `.`/`..` (← `(getdents)`).
- [x] `cat ( "file" -- )` — dump a file to stdout (← chunked `read-file`).
- [x] `more ( "file" -- )` — paged file view (← the existing `page-file` pager).
    Named `more` because `page` already means clear-screen.
- [ ] `pushd` / `popd` / `dirs` — a small fixed-depth directory stack.
- [ ] Integration tests + docs (a `docs/Shell_Words.md` page + a short Manual
    section). Limitation to document: `parse-word` path tokens can't contain
    spaces in v1.

---

## Unix `#!` Script Support

Run a Forth file as an executable Unix script:
`chmod +x foo.fs` then `./foo.fs`, where the file begins with a
`#!/usr/bin/env basicforth` line. The kernel-level shebang mechanism and
command-line file loading already work; these tiers fill the gaps.

- [x] Tier 1 — Skip a leading `#!` shebang line
  - `forth_included` skips a leading `#!` first line (exact two-byte `#!`
    check, so a leading `#` decimal literal is unaffected; the shebang
    counts as line 1 so error line numbers stay accurate). Mirrored on
    x86-64 and ARM64.
  - Scripts that end in `bye` work end-to-end; see `examples/hello.fs`.
- [~] Tier 2 — Run-and-exit flag (no implicit REPL) — DECIDED NOT TO DO
  - The idea: a flag (e.g. `basicforth -s file.fs`) loads the file then exits
    instead of dropping into the REPL, so scripts need no explicit `bye`.
    Shebang form would be `#!/usr/bin/env -S basicforth -s`; no flag keeps
    today's "load then REPL" behavior (used by snake.fs).
  - Decision (2026-06): not worth it. GNU Forth (gforth) has no run-and-exit
    flag either — its documented way to exit after processing is to append
    `-e bye`, i.e. the same `bye` convention we already support. Ending a
    script with `bye` (see `examples/hello.fs`) is the mainstream Forth
    answer and is good enough.
  - The only thing a flag would add over the `bye` convention is clean
    exit-on-error with a non-zero exit status (a script that errors before
    `bye` currently drops into the REPL rather than failing).
  - UPDATE (2026-06): that remaining gap is now closed without a flag. A
    `script_running` flag is set around the startup script load; an error
    during it — a line error returned by INCLUDED, or a fault/ABORT/QUIT that
    recovers into repl_loop — exits non-zero instead of entering the REPL.
    (`rp0` is now initialized before the startup load so a fault there recovers
    onto a valid return stack.) core.fs load errors still drop to the REPL.
- [x] Tier 3 — Script arguments and exit codes  (DONE)
  - Enables writing Unix utilities / filters in Forth (read args + stdin,
    return a status). Both invocation forms give the same argv layout:
    `argv[0]`=interpreter, `argv[1]`=auto-loaded script, `argv[2..]`=user args:
    - `basicforth snake.fs level1.txt`
    - `./snake_start.fs level1.txt`  (shebang launcher that includes snake.fs)
  - Capture the full `argv` vector + `argc` at `_start` (we already save
    `argc` and `argv[1]`); this is startup/asm-word work, NOT a syscall — no
    new platform function needed for arg access.
  - Expose to Forth, mirroring gforth (variables + words) for portability:
    - `argc` — VARIABLE holding the current arg count (`argc @`)
    - `argv` — VARIABLE holding a pointer to the arg vector (`argv @` → char**)
    - `arg ( u -- c-addr u )` — uth arg as a string; `0 0` if out of range
    - `next-arg ( -- c-addr u )` — return arg[1] and consume it; `0 0` when empty
    - `shift-args ( -- )` — delete arg[1], shift the rest left, decrement
      `argc` (O(1): copy arg[0] forward, advance `argv`, dec `argc`)
    - At startup the auto-loaded script is shifted out, so `arg[0]` is the
      interpreter and the first user arg is `arg[1]` / first `next-arg`.
  - `bye-code ( n -- )` — exit with status n, silent (no "Goodbye!") so a
    utility's stdout isn't corrupted; plain `bye` keeps its message. This is
    the ONLY real platform-layer addition (an exit-with-status syscall
    wrapper); also closes the Tier 2 exit-on-error gap.
  - Mirror x86-64 and ARM64. Integration tests (args + `$?`); doc + example
    `examples/echo.fs` (a Forth `echo`).
  - Also added (option 2 of the banner decision): the startup banner now
    prints only when stdout is a terminal, so a utility's piped/redirected
    stdout is clean. New platform calls: `platform_exit`, `platform_isatty`.
  - NOTE: an arg gives you the *string*; reading that data file is separate —
    see Phase 4 (expose file-read words).

---

## Future / Hardening

- [ ] Replace `ld -N` with `mprotect` on dict_space at startup
  - Currently we use OMAGIC (`ld -N`) to make all segments RWX so compiled
    code in dict_space can execute.  The proper approach is to keep normal
    segment permissions and call `SYS_mprotect` on just the dict_space pages
    to add PROT_EXEC.  See BareMetalForth Lesson 37 for background.
- [ ] Guard page after dict_space for dictionary overflow detection
  - Currently dict_space uses a software CHECK_DICT macro.  A guard page
    would provide zero-cost hardware detection, consistent with the data
    stack approach.
