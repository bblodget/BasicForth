# BasicForth — Testing Framework

## Overview

BasicForth uses a layered testing strategy that mirrors the three-layer
architecture. Each layer gets the testing approach that fits it best.

## Test Layers

### 1. Unit Tests — Core Primitives (C Harness)

**What:** Test individual assembly primitives in isolation — stack operations,
arithmetic, number parsing, etc.

**How:** A C program links directly against the assembled `core.o` and calls
primitives as functions. A small per-architecture `test_helper.s` provides
bridge functions to get/set engine registers (TOS, DSP) from C.

**Why C:**
- No external dependencies (no Python, no scripting runtime)
- Same toolchain we already use (gcc + as + ld)
- Cross-compiles for ARM64 just like the main binary
- Direct access to the data stack for precise verification

**Structure:**
```
tests/
  test_basicforth.c       Shared C test harness (both architectures)
  test_helper_x86.s       get/set TOS (R14), DSP (R15) for x86-64
  test_helper_arm64.s     get/set TOS (X20), DSP (X19) for ARM64
```

**Build:** Each architecture's Makefile provides a `make test` target that
builds and runs the test binary.

**Linking:** `gcc -nostartfiles` or standard `gcc` with `main()`. The test
binary links `core.o` + `test_helper.o` + `test_basicforth.c`. Platform
functions (`platform_emit`, `platform_key`) are stubbed or linked as needed.

**Example test flow:**
1. Initialize DSP to `data_stack_top`
2. Push values onto the stack via `set_tos()` and DSP manipulation
3. Call a primitive (e.g., `forth_add`)
4. Read TOS and DSP to verify the result
5. Report pass/fail

### 2. Integration Tests — Full Binary (Future, Phase 2-3)

**What:** Launch the full BasicForth binary, send input via stdin, verify
output. Tests the complete stack: platform layer + core primitives +
interactive behavior.

**How:** A script or program that starts the BasicForth process, pipes
commands, and checks output against expected patterns.

**Tests things like:**
- Terminal setup and teardown
- Line input with backspace editing
- Number parsing and display in the interactive prompt
- Error messages for invalid input
- Clean exit on empty line

### 3. Forth Tests — Self-Hosted (Future, Phase 3+)

**What:** Test Forth words written in Forth, using Forth itself.

**How:** A Forth source file (`test.fs` or block-based) that defines test
words and runs them. Similar to BareMetalForth's `vi_tb.fs` testbench.

**Tests things like:**
- Derived words (2DUP, ROT, NIP, etc.)
- Control flow (IF/ELSE/THEN, BEGIN/UNTIL, DO/LOOP)
- User-defined words and the compiler
- String handling

This is the most natural way to test Forth code — the test suite runs
inside the system it's testing.

## Summary

| Layer              | Approach          | Phase   | Status  |
|--------------------|-------------------|---------|---------|
| `core.s`           | C harness (unit)  | Phase 2 | Planned |
| `platform_linux.s` | Integration tests | Phase 3 | Future  |
| `core.fs`          | Forth testbench   | Phase 3 | Future  |
