# DEFER / IS — Deferred (Vectored) Words

A *deferred* word is a word whose behavior can be set — and changed — after it is
created. Calling it executes whatever execution token (xt) it currently points
at. This is Forth's standard mechanism for **late binding**: forward references,
stubbing, and swapping an implementation without recompiling the words that call
it.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `defer` | ( "name" -- ) | create a deferred word `name` |
| `is` | ( xt "name" -- ) | set `name`'s action to `xt` (state-aware, like `to`) |

`is` works both interpreting and inside a definition, exactly like `to` for
`value`s:

```
xt is name          \ interpret: set name's action now
: setup  ... is name ... ;   \ compile: set it at run time
```

Until you set its action, executing a deferred word reports
`uninitialized deferred word` and returns to the prompt.

> **`is` and `to` are the same operation** — both store a cell into the named
> word's data field — so they are interchangeable and **unchecked**. By
> convention use `is` for deferred words and `to` for `value`s, but `5 is x`
> (on a value) and `' w to d` (on a defer) also work. Beware the dangerous
> direction: `5 to game` puts a plain number where a deferred word expects an
> xt, so calling `game` would jump to that address and crash.

## Why: top-down development

In Forth a colon definition resolves the names it calls *at compile time*, so
normally a high-level word can't be written before the words it calls exist.
`defer` removes that restriction — declare the pieces as deferred, write the
high-level structure first, then fill in the parts:

```
> defer setup   defer play   defer finish
> : game  setup play finish ;        \ compiles now — the parts are deferred
> :noname ." setup"  cr ; is setup   \ stub them out to test the structure
> :noname ." play"   cr ; is play
> :noname ." finish" cr ; is finish
> game
setup
play
finish
```

## Swapping behavior with no recompilation

Because a deferred word calls *through* its action cell, re-pointing it with `is`
takes effect everywhere immediately — the callers are never recompiled:

```
> : real-play  ... the real thing ... ;
> ' real-play is play     \ ' gets real-play's xt; is installs it
> game                    \ game now runs real-play; game was not recompiled
```

Compare this with an ordinary (non-deferred) word: redefining it does **not**
change words that were already compiled to call it (BasicForth is
subroutine-threaded, so the call address is baked in). To make existing callers
pick up a redefined ordinary word, recompile them — see `redo` in
`docs/Redo.md`. `defer` is the tool to use at the seams you expect to iterate on;
`redo` (or editing a file and `reload`) handles the rest.

## Setting an action

There are two ways to get the xt that `is` installs:

- `:noname ... ;` — an anonymous definition leaves its xt on the stack:
  `:noname ... ; is name`.
- `'` (tick) — get a named word's xt: `' word is name`. Inside a definition,
  `'` compiles the xt, so `: switch  ' word is name ;` works too.

## How it works

`defer` compiles a tiny word whose body is "push the stored xt, then `execute`
it". The xt lives in an inline cell at the same offset `value` uses for its
datum, so `is` is mechanically the same operation as `to` — it stores a cell into
that slot. A freshly deferred word's cell points at an internal handler that
prints `uninitialized deferred word` and aborts.

## Persistence

`save` records the `defer` declaration **and** any direct `is` assignment you
type at the prompt, so a deferred word's action survives `save`/reload (the same
now holds for `to` on a `value`). One nuance: only a *direct* `is`/`to` — one you
type interactively — is captured. An `is` performed *inside* a word you then call
is not saved, because at that point the assignment runs as compiled code, not as
the interpreter word; the runtime effect happens but isn't logged. So set the
actions your program needs with a direct `is` (or put them in a file you
`include`), not by hiding them inside a helper you call.

## See also

- `docs/Redo.md` — recompile an ordinary word from its saved source.
- `docs/Defining_Words.md` — `create`/`does>`, `value`/`to`.
- `docs/See.md` — view a word's source.
