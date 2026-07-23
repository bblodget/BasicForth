# REDO — Recompile a Word From Its Saved Source

`redo <name>` re-evaluates a word's source — the text you typed when you defined
it — recompiling the word. Its purpose is to make existing callers pick up a
change to a *leaf* word during interactive development, without retyping anything.

## Word

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `redo` | ( "name" -- ) | recompile `name` from its captured source |

## Why you need it

BasicForth is subroutine-threaded: when you compile `: snake setup play ;`, the
calls to `setup` and `play` are turned into machine instructions pointing at
those words' *current* code. If you later redefine `setup`, the new definition is
a separate word — `snake` still calls the **old** one:

```
> : setup ." OLD" cr ;
> : snake setup ;
> snake
OLD
> : setup ." NEW" cr ;   \ improved leaf
redefined setup
> snake
OLD                       \ snake still calls the old setup
> redo snake             \ recompile snake from its source
redefined snake
> snake
NEW                       \ now it calls the new setup
```

`redo` re-evaluates `snake`'s saved source (`: snake setup ;`), so the fresh
definition binds to the current `setup`.

## Scope

`redo` works on words you defined **at the REPL this session** — their source is
in the capture log (the same log `see` and `save` use). For other words it
declines with a hint:

- **A word loaded from a file** (`core.fs`, an `include`d file): `redo` says to
  edit the file and `reload` — re-running the file recompiles everything in
  order, which is the right tool there.
- **An assembly primitive**: there is no Forth source to recompile.
- **An unknown word**: reported as not found.

Multi-line definitions are handled correctly (the source is replayed a line at a
time, so `\` comments stay confined to their line). `see` keeps working after a
`redo`: the source record is repointed to the new definition, and the `redo`
command line itself is not captured.

## Relationship to DEFER/IS and reload

Three tools, three scopes:

- **`defer` / `is`** (`docs/Deferred_Words.md`) — for seams you *expect* to
  change. A deferred word calls through an indirection, so swapping its action
  with `is` updates all callers instantly, with no recompilation. Use this when
  you plan to iterate on a part.
- **`redo`** — for the occasional "I changed an ordinary leaf, rebuild this
  caller" during REPL exploration. No indirection cost; recompiles on demand.
- **edit + `reload`** (`docs/Persistence.md`) — the file workflow: edit
  `session.fs` (or any source file) and reload it, recompiling everything. Best
  once the work is larger than a few words, and the tool of choice for
  file-loaded words.

## Notes

- Each `redo` creates a new definition (the old one is shadowed), so repeated
  `redo`s accumulate dead definitions in the dictionary — use `marker` if you
  want to reclaim the space.
- `redo` replays the *saved* source; to change what a word does, retype its
  definition (which is recaptured) and then `redo` its callers.
- `redo`'s effect is not persisted by `save`: the log record is repointed in
  place rather than re-captured, and `save` replays definitions in capture order,
  so a reloaded `session.fs` binds a caller to whatever leaf preceded it in the
  file — not to the post-`redo` version. Treat `redo` as a live-session tool; for
  durable changes edit the source and `reload`. See `docs/TODO.md`.

## See also

- `docs/Deferred_Words.md` — `defer` / `is`.
- `docs/See.md` — view a word's source.
- `docs/Persistence.md` — `save`, `reload`, the session log.
