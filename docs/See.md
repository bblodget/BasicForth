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

`SEE` covers your **session** definitions: both the words you define
interactively *and* the words loaded from `session.fs` at startup or by `reload`
— anything that can be written to or loaded from `session.fs`. It is part of the
interactive session system, so it does nothing useful outside one (a script or a
pipe captures nothing).

`SEE` does **not** cover `core.fs` words or assembly primitives, which have no
captured source — those report *defined, but no source captured*.

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

### Seeded definitions

Words loaded from `session.fs` are defined by the asm file loader, which bypasses
the capture hook — so their source is in the log (the byte-for-byte seed) but not
yet in the directory. `(index-seeded)` closes that gap: after the file is loaded
(on the first REPL tick at startup, and at the end of `reload`), it parses the
seeded log into definition groups and adds a record for each.

The parser walks the log token by token, comment/string aware (`\`, `( )`, and
`." " / s" "`-style strings are skipped, so a `;` inside them doesn't end a
definition). For a `:` group the name is the token after `:` and the span runs to
the matching `;`; for a single-line defining word (`variable`, `constant`,
`value`, `create`, `marker`, `2variable`, `2constant`) the name follows the
defining word and the span is the whole line. Each name is resolved with `FIND`
to its live `xt`, so seeded records key the same way as captured ones.

This is best-effort source listing: a mis-delimited group only makes `SEE` show
slightly wrong text — it never touches the dictionary, `save`, or `reload`.

**MVP limitation — custom defining words.** The seeded indexer recognises
definitions by their *defining word*, so it covers `:` and the built-in defining
words above, but **not words created by your own defining words** (e.g.
`: my-const create , does> @ ;` then `5 my-const five`). `see five` reports the
honest *defined, but no source captured*. (Words made interactively with a custom
defining word *are* indexed, since capture keys off `LATEST` moving, not off a
word list — this gap is only for seeded/reloaded ones.)

This is a fundamental limit of parsing the file *after* loading: `FIND` only
knows a word's *live* `xt`, so the indexer can't always tell a definition from a
use, or which of several same-named definitions is in force. In the common cases
it is correct (a built-in redefinition like `1 constant x` / `2 constant x` shows
the live `2 constant x`), but there is a rare **sharp edge**: if a name is first
defined by a recognised defining word and then *redefined* by a custom one
(`1 constant x` … `2 my-const x`), `see x` can show the earlier, now-shadowed
source. Honest where it can be, occasionally wrong at this edge — the seeded
indexer is best-effort.

The real fix is the longer-term direction (recorded in WildIdeas): store each
word's source location in its dictionary header at compile time, so `SEE` reads
the span straight from the file — covering *any* file-loaded word (including
`core.fs` and custom-defining-word words) and resolving these attribution edges,
with primitives labelled and decompilation as a far-future tier.

All of this lives in `core.fs`; no new assembly primitive was needed (the header
is read through the existing `(latest@)` view of the dictionary layout).
