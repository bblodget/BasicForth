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

No code changes were made. This document records what to fix.

## Summary

The layering is in good shape. There are no raw syscalls above the platform
layer, and no ioctl numbers, termios offsets, or struct layouts leak upward.
The terminal-control story is exemplary and is the pattern the fixes below
should be brought up to. Three items need attention: one structural leak
(#1), one hygiene fix (#2), and one contract to write down (#3).

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
made above the platform boundary. On a backend whose native access-mode
encoding differs — or where the `O_CREAT` bit is not `0x40` (it is `0x200`
on macOS, for example) — the pass-through breaks, and the break originates
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

**Location:** `src/forth/core.fs:387, 398, 1434`

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

## Priority

| # | Finding                                   | Type          | Effort | Priority |
|---|-------------------------------------------|---------------|--------|----------|
| 1 | `fam` constants are raw Linux open flags  | Structural    | Low    | High     |
| 2 | Hardcoded `22`/`EINVAL` in portable Forth | Hygiene       | Trivial| Medium   |
| 3 | Negative-errno `ior` convention unwritten | Documentation | Trivial| Medium   |

None of these block a port. Fixing #1 is what turns the *next* backend into
"fill in ~40 functions" instead of "fill in ~40 functions and also chase down
why file modes behave wrongly." #2 and #3 are cleanup that keeps the boundary
honest.
