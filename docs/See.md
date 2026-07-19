# SEE — Show a Word's Source

`SEE` prints the source of a word's most recent definition. It is a *source
lister*, not a decompiler: it replays the original source — spacing, comments,
multiple lines and all — read straight from the word's source file (or, for a
word just typed at the REPL, from the session capture log) rather than
reconstructing code from the dictionary.

## Word

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `see` | ( "name" -- ) | print the source of `name`'s most recent definition this session |

## Example

```
> : square  dup * ;   \ area of a side
> see square
: square  dup * ;   \ area of a side
> : square  dup dup * ;     \ redefine
> see square
: square  dup dup * ;     \ redefine     <- the most recent wins
> see nope
see: nope not found
```

It also works for `core.fs` words and labels assembly primitives:

```
> see spaces
: SPACES  dup 0 > if 0 do space loop else drop then ;
> see dup
see: dup is a primitive (assembly) — try: help dup
```

Multi-line definitions and non-colon defining words come back whole:

```
> : big
>   1 2 +
>   . ;
> see big
: big
  1 2 +
  . ;
> 42 constant answer
> see answer
42 constant answer
```

## Scope

`SEE` shows the source of the definition currently in force, for:

- words you define **interactively** this session (from the capture log),
- words loaded from **any source file** — `core.fs`, a `load`ed module, or any
  `include`d file — read straight from that file,
- **including** words made by your own *custom* defining words.

Assembly **primitives** have no source span, so `SEE` labels them
*`<name>` is a primitive (assembly)* and points at `help <name>` for the
reference entry. A name that isn't currently defined (never
defined, or **forgotten** by `-session`/a marker, which can restore an *older*
same-named word) reports *`<name>` not found*.

`SEE` matches the **live xt**, so a redefinition shows the newest source and a
forgotten definition is never shown — only what is actually in force. A
just-typed (unsaved) word relies on the interactive capture log, so it is
see-able only inside a session; file-loaded words are see-able wherever the file
is readable.

## How it works

Every compiled word carries a small **source-metadata** record in its dictionary
header — `(source-id, offset, length)` — see
[See_Metadata.md](See_Metadata.md). `see name` reads it with `(find-meta)`
(resolving the name like `FIND`: case-insensitive, from `LATEST`, matching the
live xt) and dispatches on the source-id:

- **not found** → *not found*.
- **primitive sentinel** → *`<name>` is a primitive (assembly)* + a `help
  <name>` hint.
- **source-id 0** (typed at the REPL, not yet saved) → scan the capture-log
  directory for the matching xt and `type` that slice (below).
- **source-id ≥ 1** (loaded from a file) → `(source-path)` gives the file's
  absolute path; `SEE` re-opens it and prints bytes `[offset, offset+length)`.

### File-loaded words (core.fs, modules, includes)

The metadata is stamped at **compile time** by the file loader
(`forth_included` → `build_header`), so the span is exact regardless of which
defining word created the word — `:`, a built-in defining word, or a *custom*
one (`: my-const create , does> @ ;` then `5 my-const x`). This is precisely
what the earlier text-parsing seeded-`SEE` could not do reliably; the metadata
approach replaces it. Source paths are absolutized at load time (via `getcwd`),
so `SEE` re-opens the file even if the working directory later changes. (If the
file is edited on disk after loading, `SEE` shows the file's *current* bytes for
that span — re-`reload` to re-stamp.)

### Interactive (unsaved) words

A word typed at the REPL has **no file** until you `save`, so its source lives in
the capture log — the same buffer `save` writes to a module file (see
[Persistence.md](Persistence.md)). A small **directory** of records is built as
each definition is captured:

```
[ log-offset, log-length, xt ]   \ one fixed 3-cell record
```

When one input line defines several words (e.g. `: a ;  : b ;`), each gets a
record pointing at the whole line, so `see a` and `see b` both show it. `SEE`
scans newest-first for the record whose `xt` matches the live word; matching on
the xt (not the name) keeps a forgotten definition's lingering record from ever
being shown.
