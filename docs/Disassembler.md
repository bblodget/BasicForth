# Disassembler — `dis`, machine code via objdump

`see` shows a word's *source*; `dis` shows its *machine code*. It is an
on-demand Linux dev module:

```
> require disasm.fs
 ok
> : sq dup * ;
 ok
> dis sq
sq: 11 bytes at 0043AEE4 (dictionary)
  43aee4:  e8 fb 67 fc ff    call   0x4016e4  \ dup
  43aee9:  e8 df 68 fc ff    call   0x4017cd  \ *
  43aeee:  c3                ret
> dis dup
dup: primitive at 004016E4 (in the binary)
00000000004016e4 <forth_dup>:
  4016e4:  49 8b 07          mov    (%r15),%rax
  4016e7:  49 83 ef 08       sub    $0x8,%r15
  4016eb:  49 89 07          mov    %rax,(%r15)
  4016ee:  c3                ret
```

The decoding itself is **binutils `objdump`** — already a build dependency,
and it speaks x86-64 *and* aarch64, so the same pure-Forth module works on
both architectures with no hand-rolled per-arch decoder. What `dis` adds on
top is the half no external tool can do: it knows the dictionary.

## Two paths

BasicForth code lives in two places, and each dictionary header records
which (the `CodeLen` field — see docs/Defining_Words.md):

- **Dictionary words** (`CodeLen` ≠ 0): colon definitions, `create` /
  `constant` / `variable` / `defer` stubs. The code bytes sit in the RWX
  dictionary mmap, which objdump cannot see — so `dis` writes the word's
  byte range (`xt .. xt+CodeLen`) to a temp file and runs `objdump -D -b
  binary -m <arch> --adjust-vma=<xt>`; the same shell command removes the
  temp file, and every error path between creating it and that command
  removes it explicitly, so nothing is left behind. The file is made by
  `mktemp` under `$TMPDIR` (default `/tmp`) — mode 0600 and an
  unpredictable name, so a predictable-name symlink attack has nothing to
  aim at. Addresses in the listing are the word's real dictionary
  addresses.

- **Primitives** (`CodeLen` = 0): the code is in the binary's own `.text`.
  BasicForth links `-no-pie` and unstripped, so runtime addresses equal
  file addresses and every primitive has a symbol: `objdump -d
  --start-address=<xt>` on the binary starts at exactly our word, the
  symbol table bounds the listing (`dis` stops at the next symbol header),
  and objdump labels call targets and globals by name for free.

## Annotation — the STC payoff

Compiled code under Subroutine Threaded Code is mostly `call` instructions,
but a raw listing shows only target addresses. `dis` reverse-maps each
line's target through the dictionary (walking the `LATEST` chain, matching
the header `CodePtr` fields) and appends the word's name:

```
  43aee4:  e8 fb 67 fc ff    call   0x4016e4  \ dup
```

That turns the listing into a readable decompile of the definition.

## Idiom-aware listings

Compiled code embeds data in the instruction stream in exactly two shapes:
a literal is `call lit` + 8 value bytes, and `s"` / `."` / `abort"`
compile a call to the string runtime + an 8-byte length + the characters
(padded to 4 alignment on ARM64). A linear disassembler decodes that data
as garbage instructions — on x86 the variable-width decode can even lose
step and swallow the following real instructions.

`dis` knows both idioms. The dict path *scans* the word first, splitting
it into code spans (each decoded by objdump with `--start/--stop-address`
over one shared temp file) and data spans, which are printed as what they
are — hex column intact, meaning in the margin:

```
  43d5f1:  05 00 00 00 00 00 00 00   \ literal: 5
  43d629:  08 00 ... 68 69 20 74 ..  \ s" hi there"
  43d669:  e4 16 40 00 00 00 00 00   \ xt: dup
```

A literal that matches a word's `CodePtr` is named (`['] dup` reads as
`\ xt: dup`); the string runtime's own call is annotated `\ (s")` even
though it has no dictionary entry.

The idiom addresses are **self-calibrated**: at load time the module
compiles two `:noname` probes (`0` and `s" x"`) and reads the call targets
back out of its own compiled bytes. No dependence on internal names, and
if the core ever moves those helpers, `dis` recalibrates on the next
load. If calibration fails, the addresses stay 0, no call ever matches,
and the scanner degrades to whole-range listings.

## Finding the binary and its architecture

Both paths need to know which file is running and what `-m` to hand
objdump. `dis` reads the answer from the source of truth:

- The binary path is `argv[0]` (`0 arg`), resolved against `(startup-dir)`
  when relative, with `readlink /proc/$PPID/exe` as a fallback (`$PPID`
  because the probe runs in a `/bin/sh` child, whose parent is this
  process). argv[0] is checked first because under qemu user-mode
  emulation `/proc/$PPID/exe` names *qemu*, not the guest Forth.
- The architecture comes from the binary's own ELF header (`e_machine` at
  offset 18): `0x3E` → `i386:x86-64`, `0xB7` → `aarch64`. No shell-out,
  and immune to the qemu host/guest mismatch (`uname -m` in a child would
  report the host).
- When the target is aarch64 and `aarch64-linux-gnu-objdump` exists, it is
  preferred — a plain host objdump often lacks aarch64 support (this is
  what makes `dis` work under qemu on the dev laptop; the board's native
  objdump handles aarch64 itself).

The shell plumbing — bounds-checked command composition, quoting, capture,
and the mktemp pattern — lives in `shellutil.fs` (pulled in by `require`),
so every path spliced into a command is single-quoted with embedded quotes
escaped: a directory name with spaces or shell metacharacters is data,
never syntax. See docs/Shelling_Out.md.

The probes run once, on first use, and are retried until they succeed — so
installing binutils mid-session just works. Without objdump, `dis` prints
`dis: needs objdump (binutils) on PATH` and returns; it is never loaded on
a system where you don't ask for it (`require disasm.fs`).

## Limits

- **`:noname` code has no header**, so there is no `CodeLen` to bound it
  and nothing to look up — `dis` needs a name.
- **Hidden words** (`lit` and friends) are not findable by `dis <name>`,
  though the annotator still names them when they are call targets.
- A **stripped or PIE build** would break the primitive path (no symbols /
  shifted addresses). The stock build is neither.
- Long strings show their first 40 characters (and 16 hex bytes) with an
  ellipsis; unprintable bytes display as dots, like `dump`.

## Testing

Integration tests (`tests/test_integration.sh`, "DIS" section) cover both
paths, the annotation, the error messages, and temp-file cleanup. They skip
when objdump is missing, and under qemu when no aarch64-capable objdump is
on the host.

## See Also

- docs/Defining_Words.md — the dictionary entry layout (`CodePtr`,
  `CodeLen`).
- docs/Shelling_Out.md — `(system)` / `open-pipe`, and the `shellutil.fs`
  composition layer `dis` is built on.
- docs/See.md — `see`, the source-level view.
- `help tools` — the reference entry for `dis`.
- docs/Tutorial/Machine-Code.md — the interactive lesson
  (`tutorial machine-code`).
