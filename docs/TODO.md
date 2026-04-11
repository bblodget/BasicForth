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

### 3e. core.fs Bootstrap — IN PROGRESS

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

- [ ] Block storage (file-backed) or file-based source loading
- [ ] LOAD, LIST, THRU (or INCLUDE for file-based)
- [ ] SAVE / persistence of user definitions

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
