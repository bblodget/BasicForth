# BasicForth — Platform Layer Review

A review of how well the platform boundary holds — whether OS-specific
assumptions stay confined to `platform_linux.s`, or leak upward into the
supposedly platform-independent layers (`core.s`) and the fully portable
Forth layer (`core.fs` and friends).

The motivating question: *if we add a second backend (macOS, Windows, bare
metal), is a port "fill in ~40 platform functions" with no surprises, or do
OS assumptions above the boundary have to be chased down first?*

Scope of the audit: `src/arch/{x86,arm64}/core.s`, `src/arch/{x86,arm64}/main.s`,
and `src/forth/{core,graphics,sdl3,ffi}.fs`, cross-referenced against the
contract in [Platform_Layer.md](Platform_Layer.md).

No code changes were made. This document records what to fix. A second
review pass (2026-07-10) verified the original findings against the code,
corrected one supporting example, and added findings #4–#6.

## Summary

The layering is in good shape. There are no raw syscalls above the platform
layer, and no ioctl numbers, termios offsets, or struct layouts leak upward.
The terminal-control story is exemplary and is the pattern the fixes below
should be brought up to. Six items need attention: two structural leaks
(#1, #4), two hygiene fixes (#2, #6), one contract to write down (#3), and
one batch of hosted-OS conventions to eventually push down (#5).

## What is already clean

- **No raw syscalls above the platform layer.** Zero `svc` / `syscall` in
  either `core.s` or any `.fs` file. (The `0x54…` matches in
  `arm64/core.s` are ARM64 `B.cond` instruction opcodes; `SYS_CMD_MAX` is a
  command-buffer size constant — neither is OS-related.)
- **No ioctl request numbers, termios offsets, or `stat`/`winsize` layouts
  leak upward.** All confined to `platform_linux.s`, as documented.
- **Terminal control is the model to imitate.** `PAGE`, `AT-XY`, and cursor
  on/off are primitives backing `platform_page` / `platform_at_xy` / etc.
  There is **not a single `ESC[` escape sequence in `core.fs`** — the ANSI
  encoding lives entirely below the boundary. A future framebuffer backend
  swaps it out with nothing above noticing. This is the pattern the leaks
  below should match.
- **Abstract key codes are clean** (`src/forth/core.fs:277-282`). The
  sequence `ESC [ A` is decoded *inside* `platform_key`; `KEY_UP=129 …`
  emerge as backend-neutral codes. The one raw value,
  `27 constant KEY_ESCAPE`, is a deliberate API constant, not a leak.
- **`sdl3.fs` / `ffi.fs` library names are a deliberate non-finding.**
  `s" libSDL3.so.0" dlopen` is an ELF/Linux name, but FFI binding files are
  inherently per-OS artifacts — the FFI itself presupposes a dynamic
  linker. A macOS port would ship a sibling binding file (`.dylib`), not
  patch this one. Not counted as a leak.

## Findings

### 1. `r/o` / `w/o` / `r/w` are raw Linux `open()` flags — structural

**Location:** `src/forth/core.fs:367-372`

```forth
\ File-access methods (fam): the values passed to OPEN-FILE / CREATE-FILE.
\ They are the OS open() flags; BIN is a no-op (Linux has no text/binary mode).
0 constant r/o
1 constant w/o
2 constant r/w
: bin ( fam1 -- fam2 ) ;
```

The comment states the problem plainly: the portable Forth layer is choosing
*OS flag values*. These constants pass straight through
`platform_open_file_mode` into `openat()` with **no translation**, and
`platform_create_file` OR-s in `O_CREAT | O_TRUNC`. It works today only
because Linux happens to define `O_RDONLY / O_WRONLY / O_RDWR = 0 / 1 / 2`.

Why it is a leak: the *decision* about what a file-access mode encodes was
made above the platform boundary. Note the blast radius precisely: `O_CREAT`
differing per OS (`0x200` on macOS vs `0x40` on Linux) is **not** an example
of this leak — that bit is OR'd inside `platform_create_file`, below the
boundary. And the accmode values `0/1/2` are POSIX-universal, not a Linux
coincidence, so macOS and the BSDs would work unchanged. The pass-through
breaks only on **non-POSIX** backends (Windows, bare metal) — but those are
exactly the ports this layer exists to enable, and the break would originate
in code that is supposed to be OS-agnostic.

**Fix (low cost):** keep `0 / 1 / 2`, but redefine the *contract* so `fam`
is an **abstract enum**, and make `platform_open_file_mode` *translate* it to
native flags. Today the platform function is an identity pass-through; making
the translation explicit (even while it remains identity on Linux) moves the
decision back below the boundary and lets the comment describe an abstraction
rather than confess a leak.

### 2. Hardcoded `22` (Linux `EINVAL`) in portable Forth — hygiene

**Location:** `src/forth/core.fs:385, 395, 405`

`ALLOCATE` / `FREE` / `RESIZE` synthesize `ior = 22` for their zero-size and
null-pointer rejects:

```forth
: allocate ( u -- a-addr ior )
    dup 0= if  drop 0 22 exit  then   \ reject 0 bytes (EINVAL); nothing mapped
...
: free ( a-addr -- ior )
    dup 0= if  drop 22 exit  then     \ reject null (EINVAL); don't deref
...
: resize ( a-addr1 u -- a-addr2 ior )
    over 0= if  drop 22 exit  then    ( 0 ior )  \ reject null a-addr1
```

`22` is Linux's `EINVAL`. ANS Forth defines `ior` as system-dependent, so any
non-zero value is *legal* — this is not a correctness bug. But three copies
of a raw Linux errno constant hardcoded in backend-neutral code is a smell,
and it silently ties the "invalid argument" result to one OS's numbering.

**Fix (trivial):** define a single named constant (e.g.
`22 constant EINVAL`, ideally sourced from / owned by the platform layer) and
reference it at all three sites.

### 3. "negative-errno-in, magnitude-out" is an implicit contract — document

**Location:** `src/forth/core.fs:388, 399` (the same convention appears in
core.s file words, e.g. `FILE-SIZE`'s error path)

Several portable words negate a platform return value to produce an ANS
`ior`, and the resulting *magnitude* is a raw Linux errno:

```forth
    dup 0< if  nip negate 0 swap exit  then   ( 0 errno )  \ mmap failed
...
    negate ;                                  \ 0 stays 0; -errno → positive ior
```

This is acceptable — `ior` is explicitly system-dependent — but it encodes an
**unwritten contract** that every future backend must honor: platform
functions return `0` on success or `-errno` on failure, the magnitude *is*
the platform's `ior`, and callers may only test its sign or zero-ness (never
compare it to a specific number).

**Fix (documentation only):** record this rule explicitly in
[Platform_Layer.md](Platform_Layer.md) so a non-Linux backend author knows the
sign/zero convention is load-bearing and the magnitude is opaque.

**Refinement (from #4):** the rule cannot be written as a blanket "never
compare the magnitude" — `INCLUDED` legitimately needs to distinguish
*not-found* from every other open failure (finding #4). The contract must
therefore sanction exactly one distinguished value: the platform layer
exports a "file not found" code (on Linux, ENOENT) that callers may compare
against; every other magnitude stays opaque.

### 4. `INCLUDED` compares a raw Linux errno (`-2`, ENOENT) in core.s — structural

**Location:** `src/arch/x86/core.s:2511`, `src/arch/arm64/core.s:2758`
(and the `(source-path)`/SEE reopen path documents the same dependence,
`src/arch/arm64/core.s:2473`)

```asm
.Lincl_open_err:
    # Check for ENOENT (-2) — try BASICFORTH_PATH fallback
    cmp $-2, %rax
    jne .Lincl_open_other
```

The BASICFORTH_PATH search fires only when `platform_open_file` returns
exactly `-2` — Linux's ENOENT — hard-coded in `core.s`, above the boundary.
This is the very rule finding #3 formulates, violated in the
platform-independent layer, and it is *behavioral*, not hygiene: on a
backend where "not found" is any other value, `include` silently stops
searching `BASICFORTH_PATH` at all (every miss looks like a hard error).

This class of bug is live, not theoretical: the same routine's mmap check
(`cmp $-1`, missing raw `-errno` returns) shipped a segfault on
`include <directory>` until it was fixed on 2026-07-10 — misreading raw
platform return values above the boundary is where this code has actually
broken.

**Fix (low cost):** export the distinguished value from the platform layer —
either a named constant the platform owns (e.g. `PLATFORM_ENOENT`) that
core.s compares against, or normalize `platform_open_file` to return a
documented backend-neutral "not found" code. Pairs with the contract
refinement under #3.

### 5. Hosted-OS conventions in portable Forth: `/tmp`, `$EDITOR`, `/` — push down eventually

**Location:** `src/forth/core.fs:2133` (`s" /tmp/basicforth-edit.fs"`),
`core.fs:2152, 2156` (`${VISUAL:-${EDITOR:-vi}}` — POSIX shell syntax),
`core.fs:611` (`s" /"` path-separator join)

The `edit`/`define` words hardcode a Unix temp path, POSIX shell parameter
expansion, and the `/` separator in the portable layer. These features are
inherently hosted-OS (`(system)` runs `/bin/sh -c` by contract), so this is
not a today-bug — but by the terminal-words standard above, the temp-file
path and editor-command construction belong below the boundary (e.g.
`platform_tmp_path`, or a platform-owned command template) before a
non-Unix hosted port is attempted. Bare metal simply stubs the whole
feature out.

**Fix (defer):** record as a port-time task; no change needed while Linux
is the only backend.

### 6. `stdin`/`stdout`/`stderr` = `0/1/2` in portable Forth — hygiene

**Location:** `src/forth/core.fs:310-312`

Same class as #1: POSIX fd numbering chosen above the boundary, and the
whole fileid abstraction equates "file handle" with "raw OS fd". Legal
today, and any POSIX backend matches — but the *decision* lives in the
wrong layer. The same abstract-enum treatment as #1 applies: keep the
values, declare them platform-translated handles, and let the platform
layer own the mapping.

## Priority

| # | Finding                                   | Type          | Effort | Priority | Status |
|---|-------------------------------------------|---------------|--------|----------|--------|
| 1 | `fam` constants are raw Linux open flags  | Structural    | Low    | High     | **Fixed** 2026-07-10 |
| 4 | `INCLUDED` compares raw ENOENT in core.s  | Structural    | Low    | High     | **Fixed** 2026-07-10 |
| 2 | Hardcoded `22`/`EINVAL` in portable Forth | Hygiene       | Trivial| Medium   | **Fixed** 2026-07-10 |
| 3 | Negative-errno `ior` convention unwritten | Documentation | Trivial| Medium   | **Fixed** 2026-07-10 |
| 6 | `stdin`/`stdout`/`stderr` fd numbers      | Hygiene       | Trivial| Low      | **Fixed** 2026-07-10 |
| 5 | `/tmp`, `$EDITOR`, `/` in `edit`/`define` | Structural    | Medium | Low (port-time) | Parked |

None of these block a port. Fixing #1 and #4 is what turns the *next*
backend into "fill in ~40 functions" instead of "fill in ~40 functions and
also chase down why file modes behave wrongly and why `BASICFORTH_PATH`
stopped searching." #2, #3, and #6 are cleanup that keeps the boundary
honest; #5 is deferred until a second hosted OS is actually attempted.

Fixes landed on the `platform-boundary` branch, 2026-07-10, in the order
#3 (contract written into Platform_Layer.md, including the distinguished
not-found value `platform_err_not_found`) → #4, #1 (core.s and the platform
layer made to conform) → #2, #6 (magic numbers named). #5 stays parked
until a second hosted OS is attempted.
