# MARKER — Dictionary Restore Points

`MARKER` creates a named restore point in the dictionary. Running that word
later "rewinds" the dictionary to the moment the marker was defined — forgetting
the marker and everything defined after it, and reclaiming the space. It is the
modern, standard replacement for `FORGET`, and the key tool for an
edit / compile / run loop.

## Word

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `marker` | ( "name" -- ) | define `name`; running `name` later forgets `name` and all later definitions |

## Example

```
> marker -work
> : double  dup + ;
> : square  dup * ;
> 5 double .
10
> -work            \ forget double, square, and -work itself
> double
? double           \ undefined again
```

By convention marker names start with `-` (e.g. `-work`, `-session`), a visual
cue that the word *removes* things.

## What gets forgotten

Running the marker restores `HERE` (the dictionary allocation pointer) and
`LATEST` (the newest-word pointer) to their values from just before the marker
was created. So everything defined *after* the marker — words, `variable`s,
`create`d data, the marker itself — is forgotten, and `HERE` returns to exactly
its earlier value, making the space available again:

```
> here marker -m : a 1 ; : b 2 ; -m here =  .
-1                 \ HERE is bit-for-bit back where it started
```

Markers nest naturally: running an *outer* marker also forgets any inner markers
(and their definitions) made after it.

## Caveats

- A marker only rewinds the dictionary. It does **not** undo side effects — files
  written, variables in the heap, terminal output, etc.
- After a marker runs, any words you defined after it are gone; holding an
  execution token (`'`) to a forgotten word and then executing it is undefined.
- Markers are forward-only restore points. To partially roll back, place several
  markers and run the earliest one you want to keep *below*.

## Relation to SAVE / sessions

The session system uses this idea for its edit/compile/run loop. Rather than
writing a marker into `session.fs`, BasicForth records a restore point just past
`core.fs` at startup; `-session` rewinds to it and `reload` does `-session` +
re-`include session.fs`. So `session.fs` stays pure definitions and is cleanly
reloadable after a hand-edit. See [Persistence.md](Persistence.md).

## How it works

`MARKER` is defined in `core.fs` with `CREATE ... DOES>`, much like `CONSTANT`,
but it snapshots `HERE`/`LATEST` *before* `CREATE` builds its own header, stores
them in the new word's body, and on execution restores them instead of fetching:

```forth
: marker ( "name" -- )
    here (latest@)  create swap , ,     \ body = [saved-here][saved-latest]
  does> dup @ swap cell+ @ (restore-dict) ;
```

Two small assembly primitives back it (both architectures):

- `(latest@) ( -- a )` — push the `LATEST` register (mirrors `here`).
- `(restore-dict) ( here latest -- )` — set the `HERE` and `LATEST` registers.

When the marker runs, `(restore-dict)` moves the registers back; the marker's own
now-orphaned code sits just above the new `HERE` and is overwritten by the next
definition.
