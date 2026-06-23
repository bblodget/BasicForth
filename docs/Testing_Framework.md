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
bridge functions to get/set engine registers (DSP, HERE, LATEST) from C.

**Why C:**
- No external dependencies (no Python, no scripting runtime)
- Same toolchain we already use (gcc + as + ld)
- Cross-compiles for ARM64 just like the main binary
- Direct access to the data stack for precise verification

**Structure:**
```
tests/
  test_basicforth.c       Shared C test harness (both architectures)
  test_helper_x86.s       get/set DSP (R15) for x86-64
  test_helper_arm64.s     get/set DSP (X19) for ARM64
```

**Build:** Each architecture's Makefile provides a `make test` target that
builds and runs the test binary.

**Linking:** `gcc -nostartfiles` or standard `gcc` with `main()`. The test
binary links `core.o` + `test_helper.o` + `test_basicforth.c`. Platform
functions (`platform_emit`, `platform_key`) are stubbed or linked as needed.

**Example test flow:**
1. Initialize DSP to `data_stack_top`
2. Push values onto the stack via DSP manipulation
3. Call a primitive (e.g., `forth_add`)
4. Read DSP and stack contents to verify the result
5. Report pass/fail

### 2. Integration Tests — Full Binary

**What:** Launch the full BasicForth binary, send input via stdin, verify
output. Tests the complete stack: platform layer + core primitives +
interactive behavior.

**How:** `tests/test_integration.sh` pipes Forth commands to the binary
with a 2-second timeout and checks output via substring matching.

**Tests things like:**
- Arithmetic, stack operations, comparisons, logic
- Colon definitions and redefinition
- Control flow (IF/ELSE/THEN, BEGIN/UNTIL, BEGIN/WHILE/REPEAT, RECURSE)
- core.fs words (CR, SPACE, MOD, /, TRUE, FALSE, etc.)
- Number parsing (decimal, hex, binary, negative)
- Error handling (unknown words, compile-only, unresolved/mismatched control flow)
- Return stack operations, case insensitivity
- BYE exit behavior

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

| Layer              | Approach           | Status                          |
|--------------------|--------------------|---------------------------------|
| `core.s`           | C harness (unit)   | 119 tests, both arches          |
| Full binary        | Shell integration   | 318 tests, both arches          |
| `core.fs`          | Forth testbench    | Future                          |
