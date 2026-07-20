# BasicForth — TODO

Detailed progress tracker organized by phase. Check items off as they're
completed. See Planning.md for high-level vision and design decisions.

---

## Known Bugs

- [x] **`MOVE` (core.fs) copied the wrong direction on overlap.** `MOVE
  ( addr1 addr2 u )` must be overlap-safe (memmove semantics), but the original
  definition picked the copy direction backwards: `src < dest` (shift right)
  copied low→high and `src > dest` (shift left) copied high→low — both clobbered
  the overlap, producing a byte "smear". Latent because non-overlapping copies
  and `u <= 1` were unaffected, which covered every caller at the time. Found
  2026-06 while building the line editor. Fixed on the `fix-move-cmove` branch
  (swap the two branches; overlap unit test).
- [x] **`CMOVE>` (core.fs) unbalanced the stack when `u = 0`.** The zero-length
  path ran only `2drop`, but the stack still held `( c-addr1 c-addr2 u )` (3
  cells), leaving `c-addr1` behind. (`CMOVE` handled `u = 0` correctly.) Latent
  because no caller passed `u = 0`. Found 2026-06 (same investigation). Fixed on
  the `fix-move-cmove` branch (drop all three cells; `0 CMOVE>` / `0 CMOVE`
  depth tests).
- [x] **`include <directory>` segfaulted.** `open(2)` succeeds on a directory;
  the raw `mmap` syscall then fails returning -errno (-19, ENODEV), but
  `INCLUDED` checked for exactly -1 — so the error code became the file base
  address. Also, an `fstat` error fell into the "empty file → success" path.
  Both checks now route any negative return to the existing cannot-open error
  path. Found 2026-07-06 (a test bug passed a directory to `include`), fixed
  2026-07-10 on the `include-dir-segfault` branch (both architectures;
  integration tests: error message + session survives).
- [x] **`include` of a missing file silently prints ` ok`.** `forth_included`
  deliberately returns success on ENOENT (after the BASICFORTH_PATH search)
  because startup uses the same path for optional files — `main.s` tells the
  cases apart via the `incl_opened` flag. But at the REPL it swallows typos:
  `include exmaples/bounce.fs` says ` ok` and defines nothing (found 2026-07-11
  during the sound review). Fixed 2026-07-19 on the `require` branch, exactly
  as planned: `(inc-opened?)` exposes `incl_opened`; core.fs wrappers over
  `include`/`included` report `cannot open <name>`; the startup loads call the
  assembly entry directly and keep the silent-skip. Integration tests for
  both `include` and `require` of a missing file.

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
  - Persists definitions and direct `to`/`is` assignments (see below), but not
    other runtime state: a `variable`'s contents reload uninitialized, and
    assignments made *indirectly* (a `to`/`is` inside a called word) are not
    saved. Redefinitions accumulate in the file.
  - [x] Persist direct `to`/`is` assignments across `save`/reload. `forth_to`
    (shared by `to` and `is`) sets a one-shot flag in its interpret-mode store
    path; `(capture-line)` reads it via the new `(assign?)` primitive and logs
    the line even though no new word was defined (no SEE record), and
    `(capture-reset)` clears a stale flag from an errored line. A `to`/`is`
    *inside* a called word compiles a store (not `forth_to`), so calling it is
    not over-captured. Still not persisted: indirectly-set state, and `redo`'s
    recompilation (the record is repointed in place; source-replay order doesn't
    encode the rebuild) — both documented in docs/Deferred_Words.md, docs/Redo.md.
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

See docs/Planning.md "Graphics Direction" for the philosophy/roadmap and
docs/Graphics.md for the API.

- [x] Direct device gateway: `(ioctl)` / `(mmap-dev)` primitives
  (`platform_ioctl` / `platform_mmap_dev`), plus `w@`/`w!`/`l@`/`l!` 16/32-bit
  memory access. (step 1b-i)
- [x] Backend-agnostic 2D surface + primitives in `graphics.fs` (`set-surface`,
  `pixel`, `fill-rect`, `clear`, named colors); 32bpp. (step 1a)
- [x] `fill32` fast block-fill primitive; `fill-rect` clips once and fills each
  row in one burst (full-screen `clear` is instant).
- [x] ~~DRM/KMS software-2D backend~~ — built and hardware-validated in v0.8.0,
  **removed** in the SDL pivot (a desktop compositor owns the display, so DRM
  could never show a window; SDL's KMSDRM driver covers the console case).
  In git history: `src/forth/drm.fs`, `tools/drmoff.c`.
- [x] FFI: dynamic-link build (`gcc -nostartfiles`, dictionary mprotect'd RWX),
  `(dlopen)` / `(dlsym)` / `(ccall)` primitives (up to 6 integer/pointer args),
  `ffi.fs` wrappers, libc-based integration tests, docs/FFI.md + `man ffi`.
  Deferred: float args/returns, >6 args, C-to-Forth callbacks.
- [x] `sdl3.fs`: init/window/renderer/streaming-texture bindings; lock-texture →
  `set-surface`; vsync'd present (`sdl-frame` / `sdl-show`); poll-event
  decoding (`sdl-poll`/`sdl-event-type`/`sdl-key`); `tools/sdl3off.c` verifies
  constants/offsets. Dummy-driver integration test (headless).
- [x] Animation demo: `examples/bounce.fs` — bouncing square at the display
  refresh rate (vsync), ESC/q/close to quit
- [x] Interpreted `s"` and `."` (ANS transient-buffer semantics) — STATE-smart
  redefinitions in core.fs; two alternating 256-byte buffers; compile path
  delegates to the ASM primitives so compiled code is unchanged
- [ ] SDL3 in the Pumpkian board image (build from source; bookworm has no
  libsdl3 package) — done in the Pumpkian repo
- [x] More primitives: `line` (Bresenham), `rect`, `circle`/`fill-circle`
  (midpoint), `blit`/`blit-key`/`grab` sprites (packed 32bpp, color-key
  transparency); `sdl-scale` pixel size (320×180 at 4× = 1280×720 window,
  nearest-neighbor GPU stretch); bounce.fs demo updated
- [ ] Font / text rendering (show characters on the framebuffer)
- [x] Sound output via SDL3 audio: `sound.fs` — `snd-open`/`snd-open?`/
  `snd-close`, `tone` (queued integer square wave, S16 mono 44100), `beep`,
  `snd-wait`, `snd-vol`; no-ops when the device isn't open (games degrade to
  soundless via `snd-open? drop`); wall blips in bounce.fs; dummy-driver
  integration tests; docs/Sound.md + `man sound`
- [ ] SDL_GPU 3D backend behind the surface API (SDL3-only API; see Planning.md)
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

- [ ] **`dis` — disassemble a word via `objdump`** (Linux dev module,
  `require disasm.fs`). Fills the gap `see` leaves for primitives (today it
  punts to `help`). Shell out to binutils **`objdump`** — already a build
  dependency, and it decodes **x86-64 AND aarch64** (and any future arch), so
  no hand-rolled per-arch decompiler like BareMetalForth's x86 subset. Two
  paths, because BasicForth code lives in two places:
  - compiled `:` words live in the RWX dictionary mmap → write the word's byte
    range to a temp file, `objdump -D -b binary -m <arch> --adjust-vma=<addr>`;
  - primitives live in the binary's `.text` → `objdump --disassemble=<sym>
    /proc/self/exe` (no temp file; objdump bounds it by symbol).

  Capture output via `open-pipe`. **Payoff (STC-specific):** reverse-lookup each
  `call <addr>` target in the dictionary and annotate it with the word name —
  turning raw disassembly into a readable decompile (`call DUP` / `call +` /
  `ret`), the half no external tool can do. On-demand module (fits the
  native-core/`sh`-escape-hatch model), graceful when objdump is absent, and
  never loaded on the appliance — where a native subset decompiler would be the
  answer instead. Hard parts: bounding a `:` word's byte length in dict space;
  the primitive path needs an **unstripped** binary; the address→name annotator
  (map relative call targets from the real VMA back through the dictionary).
  `see <primitive>` could point at `dis`.
- [x] **Include guards + dependency includes (`require`)** — done 2026-07-19
  (`require` branch): `require`/`required` load a file only if not already
  loaded; the ledger is a dictionary sentinel `(inc:<basename>)` defined
  after each successful load (self-heals across `marker`/`new`/`load` — a
  forgotten library is require-able again; no `[defined]`/`[if]` needed).
  Libraries declare their own dependencies (sdl3.fs → ffi+graphics,
  sound.fs → ffi, bounce.fs → sdl3+sound), so one `require sdl3.fs` or
  `include bounce.fs` brings up the whole stack. A second
  `require sdl3.fs` under a live window preserves `sdl-win`/`sdl-scale`
  (tested). Missing files now error — see the Known Bugs entry above.
  One new primitive: `(inc-opened?)`; everything else pure core.fs.
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

## Shell-Like Words (pwd / cd / ls / cat / more) — COMPLETE

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
  - [x] `cd ~` → `$HOME` (`~` / `~/sub` expansion). HOME is captured at boot
    (`(home-dir)`); a leading `~` is expanded in `cd`. HOME unset → `cannot access ~`.
- [x] `ls ( "[dir]" -- )` — list a directory (current by default; optional `<dir>`
    arg supported), one entry per line, skipping `.`/`..` (← `(getdents)`).
- [x] `cat ( "file" -- )` — dump a file to stdout (← chunked `read-file`).
- [x] `more ( "file" -- )` — paged file view (← the existing `page-file` pager).
    Named `more` because `page` already means clear-screen.
- [x] `pushd` / `popd` / `dirs` — a fixed-depth (16) directory stack. `pushd <dir>`
    saves the current dir (absolute) and cd's; `popd` returns to it; `dirs` lists
    current + saved (top first). Stack buffer is heap-allocated lazily.
- [x] Integration tests + docs: `docs/Shell_Words.md` + a "Shell-Like Words"
    Manual section; `platform_chdir`/`platform_getcwd` added to Platform_Layer.md;
    Persistence.md updated for the session.fs startup-dir pin. Documented limit:
    `parse-word` path tokens can't contain spaces in v1.
- [ ] **Design note — rewrite over `sh`, or remove? (2026-07-20)** Question:
    now that `sh` exists, should ls/cat/pwd/cd/etc. shell out to the system
    tools, or be dropped entirely (use `sh` directly)? **Leaning KEEP-NATIVE.**
    These are raw-syscall (getdents/getcwd/chdir/read), so they work with **no
    `/bin/sh` and no coreutils** — exactly what the Phase-7 boot-to-Forth
    appliance (PID 1 / bare metal) needs, where there's no shell to exec. Both
    alternatives couple core navigation to external binaries and move the wrong
    way for that goal. Right model: native words for the core navigation you
    always want; `sh` as the escape hatch to the long tail (grep/sed/find/git)
    the system happens to provide — the two roles don't overlap. Only reconsider
    a word that is BOTH rarely-used AND expensive to maintain. If pursued: audit
    the set against that test, drop any dead weight, document the division in
    Shell_Words.md.

---

## Module System / Forth-as-Shell

The vision: BasicForth as a *shell* with Forth as the shell language — `cd`
around, `load` a module, interact with it live (`.module`, `see`/`edit`/run
words, `save` back). Shipped across v0.9.0 (2026-07-04) and the merges since;
see docs/Persistence.md, Line_Editor.md, Deferred_Words.md, Shelling_Out.md.

### Shipped

- [x] Named modules replace the magic `session.fs`: `save <name>` / bare
  `save`, `load`, `new`, `reload`, `-session`; `.session` renamed `.module`;
  capture turns on with a file argument.
- [x] `uses <word>` — whole-token, case-insensitive reference search across
  the module's sources (capture log or file), the "what do I touch if I
  rename this?" tool.
- [x] Modal `edit <word>`: spawns `$VISUAL`/`$EDITOR`/`vi` on a temp file via
  the new `(system)` primitive (fork/execve/wait4; clone on ARM64), so
  multi-line formatting survives; on save it recompiles the word and
  **propagates** to every transitive caller (STC bakes call targets).
- [x] `sh <command>` — run a shell line from the REPL (transient, not
  captured); `(system)` is the underlying primitive.
- [x] `compact <name>` — deduped, dependency-ordered, definitions-only
  snapshot written next to the append-only `save` file; final `is`/`to`
  bindings preserved.
- [x] Dirty-guard: `new`/`load`/`bye` prompt "save first? (y/n)" when the
  module has unsaved changes.
- [x] Typed dictionary headers (Flags2 byte: code/defer/value/noname);
  type-checked `is`/`to`; `defer@`/`action-of`; `see` reports a deferred
  word's current binding.
- [x] `:noname` headers — anonymous definitions carry real source metadata
  (empty name, unfindable by construction), so `see`/`compact`/`edit` handle
  `:noname`-bound defers exactly (multi-line included); fixed the multi-line
  group re-evaluation segfault.
- [x] `uses` + edit-propagation treat `:noname` actions first-class: live
  groups reported as `(:noname is <name>)` and re-run on propagation, with a
  guard so superseded groups are never re-fired.
- [x] Tutorial UX: steps clear the screen; `tutorial <name> [step]` and
  `step [n]` jump/replay (a `value` works as a bookmark argument);
  `end-tutorial`; tty-only pager pause; Chase tutorial (24 steps) and
  `examples/game-template.fs`.
- [x] Robustness fixes found by live use: xorshift64 `rnd` (the old LCG's
  low bit alternated), tabs count as whitespace in the tokenizer, `edit`
  with an untouched file is a no-op (vi `:q!` exits 0).

### Next: the editing-workflow arc (planned 2026-07-08)

Motivating find: a plain interactive redefinition (`: helper 200 ;`) does NOT
propagate — callers silently keep the old code (STC bakes call targets; only
`edit` recompiles callers). Worse, it makes the three persistence views
disagree: live behavior and `save`/`reload` keep callers on the old code,
but `compact` emits the latest source at the word's original position, so
callers would bind the NEW code. `:e` closes the gap and becomes the taught
way to redefine. The full symmetry grid:

|                        | inline | $EDITOR         |
|------------------------|--------|-----------------|
| new word               | `:`    | `define <word>` |
| redefine + propagate   | `:e <word>` | `edit <word>` |

- [x] **Step 1a: `define <word>`** — open `$EDITOR` on a template
  (`: word\n    ;`), evaluate + log on exit, exactly the modal-`edit`
  machinery minus the source lookup. Refuse an existing word ("already
  defined — use edit"), symmetric with `edit`'s errors.
- [x] **Step 1b: bare `edit`** (no argument) — open the *current module
  file* in `$EDITOR`; on exit, if the file changed, `reload` it (unchanged →
  no-op, reuse the `(s=)` compare). Dirty-guard first: unsaved captured
  changes would be lost by the reload, so prompt "save first? (y/n)" like
  `load`/`new`. Requires a current module.

Building Step 1b surfaced a simpler model — reload-based editing makes
propagation correct by construction and stops the save file from
accumulating redefinitions. The original Steps 2–4 were re-planned as the
**file-canonical model, AGREED 2026-07-10 in docs/Module_Architecture.md**
(that doc has the full rationale and hard cases). The staged roadmap:

- [x] **Stage 1: splice machinery** — `save` honors bind vs mutate (the
  hyper-static principle, added to Module_Architecture.md during this
  stage): file text and `:` rebindings kept verbatim in order
  (replay-faithful), `edit`-originated mutations (tagged at capture)
  spliced over the binding they edited; `compact` deprecated.
- [x] **Stage 2: `edit <word>` v2** — temp-file UX + splice + reload
  (replaces propagation). The edit targets the word's newest definition in
  the module file, verifies the span still holds the expected text before
  rewriting (atomic .new+rename), and reloads; the dirty-guard runs before
  any reload (non-interactive sessions refuse instead of discarding).
  Deviation from plan: the temp path is module-adjacent (`<module>.edit`,
  removed after) rather than pid-suffixed — no new syscall, and collisions
  then require two sessions editing the SAME module, which is already a
  conflict. Propagation is now uncalled (deleted in Stage 4).
- [x] **Stage 3: `:e <word>`** — inline redefine + splice + reload.
  Mechanism: `:e` validates the target, arms a one-shot completion hook,
  and EVALUATEs ": <name>" so the rest of the input compiles as a normal
  definition; on completion the group (":e" rewritten to ":") splices the
  file and reloads. Splice failure falls back to a plain unsaved binding.
- [x] **Stage 4: cleanup pass** (2026-07-11) — deleted the propagation body
  (`(propagate)`, `(prop-*)`, `(pmd-*)`; `(eval+log)` survives as `define`'s
  back end with its own `(el-src)` scratch), `compact` + helpers, and the
  whole mutation-tag path: with mutations splicing the file directly, no
  capture group is ever tagged, so `(dir-tags)`/`(cap-tag)` and the entire
  splice-save patch machinery (`(sv-*)`) were dead — `save` is now literally
  "write the log verbatim" (the log = seeded file text + appended bindings),
  and the `(save-impl)` indirection and seed-extent records went with it.
  Dropped the 3 compact tests; fixed the stale ?DO-vs-DO asm comments (both
  arches emit identical code — equal bounds zero-trip for both).
- [ ] **Stage 5: `module <file>` + ownership** — `.module` filters by
  SrcId, foreign-word refusal with a hint, dependency edits splice into
  their own file (one reload propagates through the `include` chain).
- [ ] **Stage 6 (gated on use testing): auto-sync** — the file stays in
  sync as you type; explicit `save` and the dirty-guard retire;
  rollback-on-broken-reload if the fix loop proves insufficient.
  Checkpointing convention meanwhile: **git through `sh`**.

### Use-testing queue (Brandon's v0.10.0 notes, 2026-07-13)

- [x] Quick wins (one branch): edit temp file is `<module>.edit.fs` (editors
  filetype-detect Forth); `list` pages the current module file (BASIC's
  LIST, with a dirty-session note); `cancel;` abandons the definition being
  typed (immediate; disarms a pending `:e` — before this, the only cancel
  was typing an undefined word to force an error).
- [x] **Investigated + fixed: session broken after a stack underflow +
  aborted reload** (2026-07-13). Root cause: guard-fault recovery jumps to
  the REPL loop, abandoning whatever multi-step word was in flight.
  Cascade: (open-module) reseeded the log AFTER evaluating, so a faulted
  reload left the log holding the PREVIOUS module — a later `save`
  silently reverted the file, wiping on-disk edits (the reported data
  loss; the repeated "stack underflow" was each bare-edit quit re-running
  the same faulting reload until a save reverted the bad line away along
  with the user's work). Fixed: (1) (open-module) seeds the log BEFORE
  evaluating — save is always file-faithful; (2) `;` and (restore-dict)
  re-anchor the recovery snapshot (both arches), so a fault keeps every
  definition completed before the bad line and a fault after a forget
  can't resurrect forgotten words. Deferred (bounded, needs a fault-time
  cleanup registry): a faulted include leaks its open fd and read
  buffers.
- [x] **Language Reference coverage audit** — entries written (branch
  reference-gaps, 2026-07-18: all 79 gaps closed; survivors are 8 internals:
  hld lit >digit >digit? fill32 einval page-file chdir — the test's
  exclusion list). DONE (branch help-system, 2026-07-18): the regression
  test lives in test_integration.sh ("every word has a Language-Reference
  entry" — live `words` vs `## ` heading tokens), and `binary` is defined
  beside decimal/hex (name `bin` is taken by the file-access modifier).
- [x] **`help` / `tutorials` interface** (design agreed 2026-07-18; SHIPPED
  2026-07-18, branch help-system — all points below as specified, `man` and
  `topics` retired, docs swept, integration tests for all three behaviors):
  - Bare `help`: list every BASICFORTH_DOCS section except Tutorial (which
    gets a "type tutorials" pointer), topics **aligned in ~3 columns**
    (pad names to a fixed field width — the lister already sorts into a
    buffer), plus a 2-line footer: `help <topic>`, `help <word>`.
  - `help <name>`: exact topic match first → print the page **preamble**
    (top of file to the first `## ` heading — title, short intro,
    at-a-glance table); else scan `## ` heading tokens across the
    reference pages → print just that word's entry block (heading to the
    next `## `). Pages are already written to this convention.
  - Topic match folds case AND hyphen/underscore (fixes the old
    `man help-system` cross-reference bug below).
  - New `tutorials` word lists tutorials ("start one with: tutorial <name>").
  - Retire `man` and `topics`; keep `apropos`. Sweep remaining `man <topic>`
    references in docs/ root pages + Manual when the words land
    (Language-Reference already says `help ...`).
- [x] **Markdown-aware pager** (branch markdown-pager, 2026-07-19) — help
  pages and tutorials render on a terminal: headings bold (hashes
  stripped), indented blocks + `` `code` `` cyan, `**bold**` bold,
  `--more--` bar reverse video. Two layers, as planned:
  - *Platform*: one call `platform_text_attr` (semantic codes: 0-15 =
    VGA/QBasic color — full 16, unlike BareMetalForth's 6 — 16 bold,
    17 reverse, 18 reset), ANSI on Linux, self-gated on isatty(stdout);
    `platform_exit` resets attributes. Forth words: `color`/`bold`/
    `reverse`/`normal` (+ `(attr!)` primitive).
  - *Forth*: render pass `(mk-line)` in the `(pg-line)` choke point, gated
    on the new `(otty?)` (stdout tty — NOT `(tty?)`/stdin, so
    `script <in >tty` still renders and `tty> | pipe` never does) and on
    `(mk?)` (help/tutorial pages opt in; `more`/`list` page Forth source
    and stay plain). Piped output byte-identical, enforced by tests both
    ways (pipe suite: no ESC bytes; PTY suite: rendering present).
- [ ] **`list` should page the capture log, not the file** (found 2026-07-19
  walking the Arrays lesson): `list` shows the module *file*, so a word
  defined since the last `save` is missing — surprising next to bare
  `edit`, whose dirty-guard save makes it look always-current. Since the
  file-canonical model, the log IS "the file's text plus the lines added
  since", so listing the log shows the always-current view with no
  fidelity loss and retires the `(unsaved changes - save to include
  them)` note. Implementation note: the log lives on the heap, and
  `list` pages a fileid through `page-file` — either give the pager a
  page-from-memory entry point or list the log line-by-line through
  `(pg-line)` directly.
- [ ] **`:e`/`edit` dependency re-ordering** (the warning is proving
  annoying): move the fix's later-defined dependencies up to just before
  the edited word; move-to-end when the word has no callers. Design in
  Module_Architecture.md ("Forward references from a mutation").
- [x] **Topic lessons** (branch arrays-lesson, 2026-07-19) — decided lessons
  are just tutorials: same engine, same `tutorial` command, a shorter
  writing style (one idea + one thing to type per step) rather than a new
  word. First lesson: `tutorial Arrays` (`create`/`allot`/`cells`, the
  `nth` idiom, `,`-tables, `erase`, byte arrays — `allot`'s narrative
  home). `tutorials` listing upgraded to show each file's
  `# Name — description` title line, so lessons and projects distinguish
  themselves by description, not by category machinery. More lessons as
  needed: strings, files, defer/is, modules.
- [x] **`.s` ignores BASE** (found 2026-07-16 debugging 1d-life; fixed
  2026-07-19, branch markdown-pager): redefined base-aware in core.fs over
  `depth`/`pick`/`u.r`, same `<3> 1 2 3 ` format (the depth tag follows
  BASE too). Sibling audit: `u. .r u.r` already BASE-aware; `dump`/`h.2`/
  `h.addr` intentionally hex (and save/restore BASE); asm error-message
  line numbers deliberately decimal.
- Rejected: shelling out to the real `man` (our docs are markdown; the
  board may not have man/less; our pager works everywhere).

### Open threads

- [x] **Pipes / output capture** — `open-pipe ( c-addr u fam -- fileid ior )`
  / `close-pipe ( fileid -- wretval wior )` (gforth-compatible) run a command
  with a pipe over its stdout (`r/o`) or stdin (`w/o`); the fileid works with
  the ordinary `read-line`/`write-line`, and `close-pipe` reaps the child and
  returns its exit status. `platform_popen`/`platform_pclose` +
  `(popen)`/`(pclose)`, both arches. Unlocks `history | grep`-style words and
  fzf pickers for `edit`/`load` (still to build, module arc). See
  docs/Shelling_Out.md.
- [ ] Ctrl-D exits without the dirty-guard prompt (EOF exits inside
  `platform_key`), so unsaved work can be lost silently.
- [x] ~~`man` doesn't map hyphens↔underscores~~ — obsolete: `man` was retired
  in v0.11.0 and its replacement `help <topic>` folds case AND `-`/`_`.

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
