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
- [x] C unit test harness (69 tests, both architectures)
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
- [x] Unit tests for LIT (69 tests total)
- [x] Error recovery: errors during compilation reset STATE, restore LATEST/HERE
- [x] Linker flag `ld -N` for RWX segments (dict_space must be executable)
- [x] CHECK_DICT macro — software bounds check before dictionary writes
- [x] Refactored TOS-in-register to pure memory stack (eliminated phantom item bug)
- [x] Hardware guard pages (mprotect PROT_NONE) for stack underflow/overflow
- [x] SIGSEGV signal handler with ucontext register recovery to REPL
- [x] Per-definition rollback (saved_latest/saved_here in forth_colon)
- [x] DROP dummy load to trigger guard page on empty stack
- [x] Error handling documentation (docs/Error_Handling.md)

### 3b. Control Flow

- [ ] BRANCH — unconditional relative jump (compiled)
- [ ] 0BRANCH — conditional relative jump (compiled)
- [ ] IF / ELSE / THEN — conditional compilation
- [ ] BEGIN / UNTIL — post-test loop
- [ ] BEGIN / AGAIN — infinite loop
- [ ] BEGIN / WHILE / REPEAT — pre-test loop
- [ ] DO / LOOP / +LOOP / I / J — counted loops
- [ ] RECURSE — compile call to current definition
- [ ] Unit tests for control flow

### 3c. More ASM Primitives

- [ ] `*` (multiply)
- [ ] `/MOD` (division with remainder)
- [ ] ABS, MIN, MAX
- [ ] 1+, 1-
- [ ] Comparisons: `=`, `<`, `>`, `0=`, `0<`
- [ ] Logic: AND, OR, XOR, INVERT
- [ ] Stack: ROT, NIP, TUCK, 2DUP, 2DROP, DEPTH, ?DUP
- [ ] Return stack: `>R`, `R>`, `R@`
- [ ] Dictionary entries for all new primitives
- [ ] Unit tests for all new primitives

### 3d. Defining Words

- [ ] CONSTANT ( n -- ) — `10 CONSTANT TEN`
- [ ] VARIABLE ( -- ) — `VARIABLE FOO`
- [ ] CREATE — create a header with no behavior
- [ ] DOES> — attach runtime behavior to CREATE'd words
- [ ] ALLOT ( n -- ) — reserve n bytes in dict space
- [ ] `,` (COMMA) — compile a cell into dict space
- [ ] `C,` — compile a byte into dict space
- [ ] HERE as a Forth word (push current HERE value)

### 3e. core.fs Bootstrap

- [ ] File loading: INCLUDE or EVALUATE from a buffer
- [ ] Derived stack words: 2OVER, 2SWAP, PICK
- [ ] Derived arithmetic: CELL+, CELLS, MOD, */
- [ ] String words: TYPE, COUNT, S", ."
- [ ] Formatting: CR, SPACE, SPACES, U., .R
- [ ] Comments: `(` and `\`

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
