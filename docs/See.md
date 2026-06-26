# SEE — Show a Word's Source

`SEE` prints the source of a word's most recent definition. It is a *source
lister*, not a decompiler: it replays exactly what you typed — spacing, comments,
multiple lines and all — by reading the session capture log rather than
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
see: nope not found this session
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

`SEE` covers words you define **interactively this session**. It is part of the
interactive session system, so it does nothing useful outside one (a script or a
pipe captures nothing).

Words loaded from `session.fs` at startup or by `reload` are **not** in the
index — but that file is plain text you edit on disk, so its definitions are
already in front of you. (Indexing seeded/reloaded definitions too is a planned
follow-up.) `SEE` also does not cover `core.fs` words or assembly primitives,
which have no captured source.

`SEE` works for any defining word — `:`, `variable`, `constant`, `value`,
`create`, `marker`. A redefinition shadows the earlier source, and — crucially —
a definition that has been **forgotten** (by `-session` or by a marker, which can
restore an *older* same-named word) is never shown: `SEE` only ever displays the
source of the definition that is actually in force.

## How it works

`SEE` reuses the session capture log — the same buffer `save` writes to
`session.fs` (see [Persistence.md](Persistence.md)). As each definition is
captured, an entry is appended to a small **directory** built alongside the log:

```
[ log-offset, log-length, xt ]   \ one fixed 3-cell record
```

`xt` is the execution token `FIND` would return for the just-defined word — read
from its header at `LATEST` (the CodePtr at `align8(9 + name-len)` past the
entry, mirroring `FIND`'s own calculation).

When a single input line defines **several** words (e.g. `: a ;  : b ;`), one
record is added for *each* new word, found by walking the dictionary link chain
from the new `LATEST` back to the group's baseline. Every record points at the
same log slice — the whole line's source — so `see a` and `see b` each show that
line. (Indexing only the final `LATEST` was a bug: `see` of any earlier word on
the line reported *not found*.)

`see name` resolves the name with `FIND` (case-insensitive, searching from
`LATEST`):

- If `FIND` fails, the word is not currently defined — never defined, or
  forgotten by `-session`/a marker — and `SEE` reports *not found*.
- Otherwise it scans the directory **newest-first** for the record whose `xt`
  equals the live word's `xt`, and `type`s that slice of the log.
- If the word is defined but no record matches — a primitive, a `core.fs` word,
  or a word loaded from `session.fs` — `SEE` reports *defined, but no source
  captured*, distinct from *not found*.

Matching on the live `xt` (rather than the name) is what makes `SEE` immune to
stale source: a forgotten definition's record can linger in the log, but its
`xt` no longer matches anything `FIND` can return, so it is skipped. The
directory shares the log's lifecycle — both are reset in `(seed-log)`.

All of this lives in `core.fs`; no new assembly primitive was needed (the header
is read through the existing `(latest@)` view of the dictionary layout).
