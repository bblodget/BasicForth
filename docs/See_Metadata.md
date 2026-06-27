# SEE via Dictionary Source Metadata — Design

**Status:** design / plan (branch `dict-source-meta`). Not yet implemented.

This is the "real fix" deferred from the session-log `SEE` MVP (see
[See.md](See.md), the *Future* note in [TODO.md](TODO.md), and the
*"SEE for any word"* section of [WildIdeas.md](WildIdeas.md)).

## Goal

Let `see <word>` show the source of **any** file-loaded word — `core.fs`
words, `include`d files, and words made by *custom defining words* — not just
session-captured ones. Assembly primitives are labelled *primitive (assembly)*.

The current session-log `SEE` stays as-is for **unsaved REPL definitions** (it
is the only thing that knows their text before `save`). The two mechanisms
coexist; nothing about the log path is removed.

## Approach: hybrid (small header field + out-of-dict source table)

Two pieces:

1. **Per-word metadata in the dictionary header** — a tiny fixed record
   `(source-id, offset, length)` stamped at compile time. Source-id selects
   *where* the bytes are; offset/length is the span within that source.
2. **A source table** mapping `source-id → (kind, path)`. `see` uses it to
   re-open the file and read `[offset, offset+length)`. The bulky path strings
   live outside the dictionary (see open decision below).

Why hybrid (recap of the design discussion):
- A pure heap side-table can't index `core.fs`: `core.fs` is loaded by the asm
  `forth_included` **before** the Forth machinery that would record into a heap
  table exists (the capture words and `(hook!)` calls live mid-/end-`core.fs`).
- The header is the natural place for asm to stamp per-word data uniformly
  (`build_header` runs for every `:`/`CREATE`/`CONSTANT`, including every
  `core.fs` word), with no chicken-and-egg.
- But path strings are bulky and few, so they do **not** go in the header —
  only the compact `(source-id, offset, length)` does.

## Header layout change

Today (both arches), each entry is:

```
[Link:8] [Flags+Len:1] [Name:N] [pad→8] [CodePtr:8] [CodeLen:4]   then inline code
```

Add a fixed 8-byte metadata block **after `CodeLen`, before the code body**:

```
[Link:8] [Flags+Len:1] [Name:N] [pad→8] [CodePtr:8] [CodeLen:4] [SrcId:2] [Len:2] [Off:4]   then code
```

- Packed to **8 bytes/word**: `SrcId` u16 (source-table id), `Len` u16 (a single
  definition's source span is never near 64 KB), `Off` u32 (byte offset into the
  source file, < 4 GB). ~2 KB total for `core.fs`. (A 12-byte three-`u32` form
  cost ~1 KB more and pushed `examples/sort.fs`'s tuned buffers over the dict
  limit — the packed form keeps the same safe ranges with room to spare.)
- `CodePtr` keeps its current offset (`align8(9+namelen)`), so **`FIND` and the
  Forth-side xt derivation are unchanged** — the metadata sits *past* the
  CodePtr cell. Only the code-start cursor moves:
  - `build_header`: `CodePtr = HERE + 8 + 4 + 8` (was `+12`); write metadata
    placeholder (`SrcId = cur_source_id`, `Off = cur_line_off`, `Len = 0`);
    advance HERE past the new fields.
  - `;` (`forth_semicolon`) and the other defining words that fill `CodeLen`:
    code-start = `code_len_addr + 4 + 8` (the `+8` is the new block). On x86
    these are `forth_semicolon`, `forth_value`, `forth_create`,
    `forth_constant`, and `forth_does_runtime`; `forth_recurse` reads `CodePtr`
    (`code_len_addr − 8`) and `>BODY` is xt-relative, so both are unaffected.
- `DEFWORD` (primitives): append the fields with `SrcId = PRIM` sentinel,
  `Off = Len = 0`.

Metadata address from an entry (for the Forth read path):
`codeptr_cell = entry + align8(9+namelen)`; `meta = codeptr_cell + 12`
(skip CodePtr:8 + CodeLen:4); then `SrcId` (u16), `Len` (u16 at +2),
`Off` (u32 at +4).

### Source-id values

| source-id | meaning | how `see` shows it |
|-----------|---------|--------------------|
| `PRIM` (`0xFFFF`) | assembly primitive | print *primitive (assembly)* |
| `0` | REPL-typed, no file yet | fall back to the **session-log directory** (today's path) |
| `≥ 1` | a file in the source table | open path, read `[Off, Off+Len)`, `type` it |

## Recording (all in asm — covers `core.fs`, no hooks)

Two new globals: `cur_source_id` (0 = REPL/no file) and `cur_line_off` (byte
offset of the current line within the current file).

`forth_included` already has exactly what we need in its line loop: `RBX` =
mmap base, `R14` = line-start offset, `R8` = next-line-start offset. Changes:

1. **On open:** assign this file a source-id and register the **resolved path**
   that was actually opened — not the as-typed name. `core.fs` is found via
   `BASICFORTH_PATH`, not the CWD, and the mmap is released after load, so `see`
   must re-open by the resolved path (`forth_included` already computes it into
   `incl_path_buf`); store an absolute form so a later CWD change can't break
   re-open. Save the previous `cur_source_id`/`cur_line_off`, set
   `cur_source_id` to the new id. Restore on every exit path (mirrors the
   existing source-pointer save/restore for nested includes).
2. **Per line, before `call forth_interpret_line`:** `cur_line_off = R14`.
   `build_header` (called during that line) stamps `SrcId = cur_source_id`,
   `Off = cur_line_off`, `Len = 0`.
3. **Per line, after the call:** finalize spans **per word off the HIDDEN bit**,
   not off global `STATE`. A still-compiling colon def is HIDDEN; `;` clears it.
   With `end = R8` (next-line-start offset):

   ```
   p = LATEST
   loop:
     flags = [p + 8]
     if (flags & HIDDEN):              p = link(p); continue   # in-progress def — finalize later
     if (meta.SrcId != cur_source_id): break                   # crossed into a prior file / primitives
     if (meta.Len != 0):               break                   # already finalized on an earlier line
     meta.Len = end - meta.Off                                 # span = whole line(s), through the newline
     p = link(p)
   ```

   *Why not gate on `STATE == 0`?* A line can finish a single-line def **and**
   open a colon def (`variable v   : a`). Gating on `STATE` skips `v`, and when
   `;` closes `a` on a later line the walk would fill *both* with the later
   line's end offset — a bogus span for `v`. The HIDDEN bit finalizes `v`
   immediately (it is not hidden) and leaves `a` for its closing line. The
   `SrcId != cur_source_id` stop bounds the walk to this file's newly-added
   words (which sit contiguously at the chain top) — without it the walk runs
   the whole primitive chain every line and could misattribute nested-`include`
   words.

This handles:
- **Multi-line `: … ;`** — `Off` stamped on the opening line (line 1); `Len`
  filled when `;` clears HIDDEN on the closing line → span covers all lines.
- **Several defs on one line** (`: a ; : b ;`) — both get the same line span.
- **Custom defining words** (`5 my-const five`) — `build_header` runs inside the
  defining word regardless of *which* word called it, so `five` is stamped just
  like a built-in. This is the case the text-parse MVP could not do.
- **REPL input** — `cur_source_id` is 0 there, so header `Off/Len` stay 0 and
  `see` uses the session log (unchanged).

## `see` read path (Forth)

```
see name:
  resolve name → entry (header address)      \ via FIND, see new primitive below
  not found            → "not found this session"  (unchanged message family)
  meta = entry-derived (SrcId, Off, Len)
  SrcId == PRIM        → "name: primitive (assembly)"
  SrcId == 0           → existing session-log directory lookup (today's code)
  SrcId  ≥ 1           → path = (source-path SrcId)
                         open path r/o, read [Off, Off+Len) into a buffer, type, close
```

The session-log directory (`(dir)`, the `[log-off,len,xt]` records) and all of
`(index-seeded)` can **eventually be retired** once file metadata covers seeded
words — but they stay for now to cover unsaved REPL words and to de-risk the
change. (`save`/`reload` are untouched either way.)

### New primitives

- `(>entry) ( c-addr u -- entry | 0 )` — like `FIND` but returns the header
  address (so Forth can read the metadata block). Or extend `FIND`. *(Forth can
  already compute `align8(9+namelen)` from an entry — the capture code does.)*
- `(source-path) ( id -- c-addr u )` — path string for a source-id (`0 0` if
  none).

Reading the file span reuses existing file words (`open-file`/`read-file`/
`close-file`) — no new platform calls. The read buffer can be heap-allocated
(`ALLOCATE`) like the pager/getdents buffers.

## Decided — source table lives in asm `.bss`

The per-word `(source-id, offset, length)` is settled (header). For the
**id → path table** we chose **(A) the asm `.bss` fixed table** (recommended
below): it keeps paths out of the dictionary, needs no heap, and sidesteps the
`core.fs` load-order problem. The alternatives considered:

- **(A) asm `.bss` fixed table** *(recommended)* — e.g. up to N source files,
  each a copied **resolved** path string (see Bug 2 above — store the path that
  was actually opened, absolute where possible, so `see` can re-open it).
  Simplest, needs no heap, and sidesteps the `core.fs` chicken-and-egg entirely
  (`forth_included` registers the path in asm as it opens the file). Honors
  "keep it out of the dictionary." Cost: a fixed `.bss` cap on distinct source
  files per run (generous N, e.g. 64–128).
- **(B) heap table via a registration hook** — `forth_included` calls a Forth
  hook to register the path on the `ALLOCATE` heap (unbounded). But `core.fs`
  loads before that hook exists, so `core.fs` needs a special reserved id /
  hard-coded path anyway — extra complexity for little gain.

Recommendation: **(A) .bss**. It keeps paths out of the dictionary (the actual
goal of "heap source table") while avoiding the load-order problem. Flagging
because it revises the earlier "heap" wording.

## Implementation plan (phased, each step builds + tests green both arches)

1. **[DONE] Header field, inert.** Added the 8-byte block to `DEFWORD` and
   `build_header`/`;` (both arches); `PRIM` for primitives, `0/0/0` otherwise.
   No behavior change; full suite green (validated the layout change against
   `FIND`/`>BODY`/`DOES>`/`marker`/`:NONAME`). Committed `29b4c4b`.
2. **[DONE] Source table + `forth_included` stamping.** `.bss` table
   (`src_register` with dedup, `(source-path)`), `cur_source_id`/`cur_line_off`
   globals saved/restored across (nested) includes, register-on-open with the
   **absolute** path (a new `platform_getcwd` + `make_absolute` turn a CWD- or
   `BASICFORTH_PATH`-relative path into `getcwd()+'/'+path`, so `see` re-opens
   correctly even if the CWD later changes — Bug 2), `build_header` stamps
   `SrcId`/`Off`, and a per-line `src_finalize` (HIDDEN-based walk) fills `Len`.
   Added `(find-meta)` to read a word's metadata. Verified on both arches:
   `core.fs` words → `srcid=1` with correct `off`/`len` and an absolute path;
   primitives → `PRIM`; REPL words → `srcid=0`; seeded `session.fs` words →
   their own id (the case the text-parse MVP couldn't do).
3. **[NEXT] `see` read path.** Branch on source-id: primitive label / log
   fallback (srcid 0) / file span (srcid ≥ 1, via `(source-path)` + read). `see`
   then works for `core.fs`, includes, and custom-defining-word words.
4. **Docs + tests.** Update [See.md](See.md) (drop the MVP-limitation caveats),
   integration tests (`see` a `core.fs` word, an `include`d word, a
   custom-defining-word word, a primitive), and this doc → "implemented."
5. **(Optional, later)** Retire `(index-seeded)` and the seeded path once file
   metadata is proven to cover those words.

## Risks / notes

- **Layout change is the sharp edge.** `>BODY`, `DOES>`, `CREATE` data fields,
  `marker`/forget, and `:NONAME` (no name → no header metadata) all interact
  with header geometry. Step 1 is deliberately inert so the layout change is
  validated by the full suite before any new behavior rides on it.
- **`.bss` cap** on distinct source files per run — log what happens past the
  cap (fall back to source-id 0 / "no source") rather than overflow silently.
- **Re-open path** must be the resolved path actually opened (Bug 2), absolute
  where possible; a relative path plus a later CWD change would otherwise make
  `see` open the wrong file or fail.
- **Span finalize** is per-word off the HIDDEN bit, not global `STATE` (Bug 1);
  a line that mixes a completed single-line def with the start of a colon def
  must not back-fill the earlier word with the later line's offset.
- **Both arches** must mirror every asm change (x86-64 + ARM64), and any new
  primitive that calls a platform/main symbol needs a stub in both
  `test_helper_*.s`.
- Spans are byte ranges into the *file as it was at load time*; editing the file
  afterward (without `reload`) could skew a span. Acceptable — same caveat as
  any source lister; `reload` re-stamps.
