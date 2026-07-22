# Modules and Persistence

Your interactive work in BasicForth is a **module** — the words you've defined on
top of `core.fs`. You can write a module to a named file and load it back later,
in the spirit of 1980s BASIC's `SAVE "GAME"` / `LOAD "GAME"`. Persistence is
**source-replay**: a module file is an ordinary, hand-editable Forth source file —
the *source text* of your definitions — not a binary image.

There is no magic `session.fs`. Files are explicit and named.

## The module verbs

| Word | Stack | Meaning |
|------|-------|---------|
| `save <name>` | ( "name" -- ) | write the module to `<name>` (relative to the current directory); also makes `<name>` the current file |
| `save` | ( -- ) | re-write the **current file** (the one you loaded or last `save <name>`d) |
| `load <file>` | ( "name" -- ) | open `<file>` as the module — forget the old one, load the new one, make it current |
| `new` | ( -- ) | clear the module — forget every definition, back to a clean slate (core only) |
| `reload` | ( -- ) | re-read the **current file** from disk (the edit/compile/run loop) |
| `list` | ( -- ) | page the current file — BASIC's `LIST` (a dirty session notes its unsaved bindings) |
| `.module` | ( -- ) | list the module's words (see `help tools`) |
| `-session` | ( -- ) | low-level "forget the module's words" (the helper `new`/`load`/`reload` build on) |

```
> 22 constant W   variable score   : tick  score @ 1+ score ! ;
> save game.fs
saved to game.fs
```

Later — anywhere — open it:

```
$ basicforth game.fs        # or, mid-session:  load game.fs
> tick  score @ .
1
```

`basicforth <file>` at startup is just `load` done at launch: it defines the
file's words and makes it the current module, so editing + a bare `save` writes
it back. A file ending in `bye`/`bye-code` is a *script* — it runs and exits
before any of this (see **Scope** below).

## The current file (where `save` writes)

`save <name>` resolves `<name>` against the **current directory** at the moment
you type it (so it lands where `ls`/`cat`/`cd` are looking), and remembers it as
an **absolute** path. So a later bare `save` always rewrites *that* file, even
after you `cd` elsewhere — exactly like an editor:

```
$ basicforth ~/proj/game.fs    # current file = /home/you/proj/game.fs
> cd /tmp                       # ls/cat now act on /tmp
> save                          # still writes /home/you/proj/game.fs
> save sketch.fs                # writes /tmp/sketch.fs — and that's now current
```

Only typing a name (startup arg, or `save <name>`) ever resolves a relative path;
after that the current file is a fixed identity.

## The edit / compile / run loop

A module file is plain, hand-editable Forth. Edit it in another terminal, then
pull the changes in:

```
> reload
```

`reload` forgets the current module (`-session`) and re-reads the current file —
a clean redefinition every time, no duplicate buildup, and words you deleted from
the file actually disappear.

If the edited file has an error, `reload` shows the file's own `name:line: ?
token` diagnostic and reports the module may be incomplete; loading stops at the
bad line, the in-memory log is left untouched (so a later `save` won't persist a
broken file), and the REPL keeps running — fix the file and `reload` again. A
broken file is verified readable *before* anything is forgotten, so a missing or
unreadable file never wipes your work.

`load` and `new` ask before discarding unsaved changes (see **The dirty-guard**
below). `reload` deliberately does **not** — it is the pull-from-disk verb, so it
always discards unsaved REPL changes in favor of the file.

## The dirty-guard

BasicForth tracks whether the module is **dirty** — whether the capture log holds
changes `save` hasn't written (a new definition, a direct `to`/`is`, an `edit`).
When it is, `new`, `load`, `bye`, and `bye-code` ask before discarding:

```
> : score+  1 score +! ;
 ok
> bye
unsaved changes — save first? (y/n)
```

- **y** — save to the current file first, then proceed. With no current file it
  prints `save: no current file (use: save <name>)` and cancels, so you can
  `save <name>` yourself.
- **n** — proceed, discarding the unsaved changes.
- **any other key** — cancel; you're back at the REPL.

The flag clears on `save` and whenever the log is rebuilt to match a file
(`load`, `reload`, `new`, startup).

Two words skip the prompt on purpose:

- **`reload`** always proceeds: answering "save first" there would overwrite the
  external file edits you are trying to pull in.
- The prompt only appears at a **real terminal**. Piped input and scripts never
  prompt (they proceed silently), so automation can't block on a question — and
  Ctrl-D (end of input) exits without prompting.

## What gets captured

While you type at the interactive prompt, BasicForth watches each line. A line
(or group of lines) is captured if it **adds to the dictionary** (defines a word),
**performs a direct `to`/`is` assignment** (so a `value`'s contents and a
deferred word's action persist), or **ends with `keep`** (see below). Other
transient actions are *not* captured:

```
> : double dup + ;      \ captured (defines a word)
> variable count        \ captured
> 0 value hits          \ captured
> 5 to hits             \ captured (a direct assignment)
> 5 double .            \ NOT captured (just prints 10)
> page                  \ NOT captured (just clears the screen)
> 320 180 sdl-open      \ NOT captured (opens a window, defines nothing)
> 320 180 sdl-open keep \ captured — you asked for it
```

### `keep` — save a line that defined nothing

The rule above is what keeps a module file clean, but it has a cost: the lines
that *set your module up* are exactly the ones that define nothing, so they
vanish. `keep` is the override. Put it on the line and the line is written
verbatim, in the order you typed it:

```
> 320 180 sdl-open  keep      \ the module reopens its window when it loads
> create tbl  1 , 2 , 3 ,  keep
```

That second case is the answer to a sharp edge: `create` moves the dictionary
pointer, so it is captured, but the rows of `,` that fill the table are not —
without `keep`, `save` writes a bare `create tbl` and the data is silently gone.
(Building the table inside a colon word, `: tbl-data 1 , 2 , 3 ; create tbl
tbl-data`, is the other way, and stays the nicer one for anything long.)

`keep` may appear anywhere on the line, not only at the end, and on a line that
already defines a word it does nothing. It acts **only at the terminal**: when
the saved line is replayed on load, `source-id` is the file, not the keyboard, so
the `keep` token sitting in your file is inert. That is why the token can simply
stay there — nothing has to strip it back out, and re-saving a reloaded module is
still byte-identical.

Only a *direct* assignment counts — a `to`/`is` performed inside a word you call
runs as compiled code, not as the interpreter, so calling that word is not
captured and its runtime effect is not saved. A definition that **errors** partway
through is rolled back and not captured. The `-session`/`reload`/`load`/`save`
lines are never captured either, so a saved file stays **pure definitions**,
clean to hand-edit.

`save` distinguishes **bindings** from **mutations** (see
docs/Module_Architecture.md — Forth's dictionary is *hyper-static*: `:` never
changes an existing definition, it layers a new one, and earlier words keep
what they captured). The file text is kept byte-for-byte — comments, blank
lines, every binding in order — and everything you typed appends in the order
it happened, so the file **replays to exactly the live session's state**: a
plain `: thrust 25 ;` appends, and words defined before it still get the old
`thrust`, live and after reload alike. The exception is a **mutation** —
`edit <word>` (and the future `:e`) means "that text was wrong" — which
replaces the word's definition where it stands instead of appending, so
mutation history never accumulates: saving after ten edits of the same word
leaves one definition, in place. Saving is **idempotent** (saving twice
writes a byte-identical file). A bare `save` with nothing captured prints
`nothing to save`; with no current file it prints
`save: no current file (use: save <name>)`.

## Module lifecycle hooks: `on-start` and `on-stop`

A reload rolls the dictionary back to the end of `core.fs` and replays the module
file. Anything the file builds comes back — that is the whole idea. What does
*not* come back is anything the module was **holding**: an SDL window, an audio
device, an open file. Its handle lives in a `value`, the rollback takes the
`value` with everything else, and the resource carries on existing with nothing
left that can reach or release it.

A module fixes this by defining either or both of these names. BasicForth does
not define them; it just looks them up and calls them if they exist.

```forth
: on-start  320 180 sdl-open ;    \ after the module's file has been (re)read
: on-stop   sdl-close ;           \ before the module's words are forgotten
```

| Hook | Runs | Use it to |
|------|------|-----------|
| `on-start` | after the file loads — at startup (`basicforth game.fs`), after `load`, and after every `reload`, including those `edit` and `:e` perform | (re)acquire what the module needs to run |
| `on-stop` | just before the words are forgotten, by `reload`, `load`, `new` or `-session` | release what the system is holding for you |

`on-stop` is the half `keep` cannot do. Putting `sdl-close` at the top of your
file does not work: the file runs *after* the rollback, when the handles are
already zeroed. `on-stop` runs *before* it, while they are still valid, so the
orphan is never created.

This is what makes `:e` usable on a program that is running. Without hooks you
must close the window by hand first; with them:

```
> : on-stop   sdl-close ;
> : on-start  320 180 sdl-open ;
> :e ship-art  s" ..####.." row,  s" .#....#." row, ;
```

closes the window, reloads the module, and reopens it — one command.

Both are optional, and a module that defines neither behaves exactly as it always
has. A hook that fails is **reported, not fatal** (`error in on-start hook: -4`)
— a broken hook must not abort the reload that is rebuilding your module, or you
would be left with neither the old one nor the new one. A hook that itself
reloads finds the inner hooks suppressed, so it cannot recurse.

Two things they deliberately do *not* do: they don't run at `bye` (process exit
releases what the OS knows about), and `marker` rollbacks don't call `on-stop` —
a marker is a dictionary tool, not a module verb.

## Scope: interactive sessions only

Capture is active **only in an interactive session** — when standard input is a
terminal, or `BASICFORTH_SESSION=1` forces it. Running a Forth script
(`basicforth tool.fs` that ends in `bye`) or piping input captures nothing, so
utilities and automation stay clean. Outside an interactive session `reload`
reports `reload: no active session` and does nothing, and `save` has an empty log.

A broken module reflects this split: an **interactive** `basicforth game.fs` with
a compile error reports the error and **drops to the REPL** so you can fix it; a
**non-interactive** run (a pipe or script) **exits non-zero**, like a failing Unix
utility.

| `BASICFORTH_SESSION` | Effect |
|-------|--------|
| unset | default — on when stdin is a terminal |
| `1`   | force the session on (e.g. to drive capture through a pipe) |
| `0`   | force the session off, even at an interactive terminal |

## Limitations

Persistence saves **definitions and direct `to`/`is` assignments**, not other
runtime state. A `variable`'s contents (set with `!`) are not captured, so a
`variable` reloads *uninitialized*:

```
> variable hits   10 hits !
> save game.fs     \ captures `variable hits`, NOT the `10 hits !`
\ ...next load: `hits @` is 0, not 10
```

A `value` set with a direct `to` *does* survive (`0 value hits` then `5 to hits`).
For other mutable state, prefer a `value` you assign with `to`, initialize it
inside a defining word, or mark the line with `keep` (`10 hits !  keep`).

Other notes:

- **Mutation (splice) details.** An `edit` happens directly on the module
  file (stage 2): the new text replaces the word's newest definition in the
  file — verified against the expected text, written atomically — and the
  module reloads. Older same-name definitions are older bindings and are
  never touched; editing again rewrites the same spot, so edit history
  never exists. A word typed this session must be saved before it can be
  edited (the terminal prompts; a script must `save` explicitly).
  `is`/`to` assignment lines and `:noname ... ; is x` groups are
  order-dependent effects: the file's stay put, the session's append in the
  order they happened, and the last one wins on replay.
- **There is no `compact`** — and for a stronger reason than redundancy:
  deduping a hyper-static file *rewires bindings* (a word that captured an
  earlier definition comes back bound to the latest one). Since mutations
  splice in place, nothing accumulates that would need compacting (see
  docs/Module_Architecture.md).
- **A library `include`d by a module** stays referenced, not inlined: `save`
  keeps the `include other.fs` line, not a copy of `other.fs`. The library's
  words are part of the live module (`.module`/`see`/`uses` show them, read from
  the library file).
- **Reload is bounded by dictionary space**, the same limit you'd hit typing it
  all in.

## How it works

The capture log lives in a heap-backed buffer (see the MEMORY wordset). The
interactive REPL (`main.s`) drives three hook words defined in `core.fs` and
registered with the internal `(hook!)` primitive:

- `(session-init)` — at startup, records the `-session` restore point, marks the
  run interactive, sets the current file from the startup arg (if any), and seeds
  the log from it — the log holds the file's own text followed by session
  captures, and `save` writes it back verbatim. (The restore mark itself is
  captured at the *end of `core.fs`*, before any module loads, so `-session`/
  `new`/`load` forget the whole module — the loaded file's words plus interactive
  ones.)
- `(capture-line)` — after each interpreted line; flushes a completed definition
  to the log (detected by `LATEST` advancing while `STATE` is back to interpret,
  so bare `ALLOT`/`,`/`C,` that move only `HERE` are not captured).
- `(capture-reset)` — at the top of the REPL loop; discards a pending partial
  definition left by a line error.

`save` writes the log to a temporary `<name>.new` and then `rename-file`s it over
`<name>` — an atomic replace, so a write failure (e.g. a full disk) leaves the
existing file untouched rather than truncating it. The `-session` restore point
is a HERE/LATEST mark (the same mechanism as [Marker.md](Marker.md)).
