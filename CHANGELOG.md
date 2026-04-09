# Changelog

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
