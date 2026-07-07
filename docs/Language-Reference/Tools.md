# Tools

Environment commands you use *at the prompt* rather than inside programs:
inspecting words, saving your session, and browsing the docs. Each has a fuller
topic page (`man <topic>`), linked below.

## Module persistence

Your interactive definitions are a **module** you can write to a named file and
load back (BASIC's `SAVE`/`LOAD`). Capture runs in an interactive session. See
`man persistence`.

## save ( "name" -- )  /  save ( -- )
`save <name>` writes the module to `<name>` (relative to the current directory)
and makes it the current file; bare `save` re-writes the current file. Writes
the whole loaded file verbatim (comments and all) plus your edits, so
redefinitions accumulate. Writes atomically, so a failure never corrupts an
existing file.

## compact ( "name" -- )  /  compact ( -- )
Write a **deduped** snapshot of the module — each word's latest source once, in
dependency order, then each `value`/deferred word's **final direct `to`/`is`
assignment** — to a sibling **`<base>.compact<.ext>`** (e.g. `game.fs` →
`game.compact.fs`), so you can `diff` it against `save`'s output. Drops the
file's between-definition comments. Bare `compact` uses the current file's name.

## load ( "name" -- )
Open `<file>` as the module — forget the old one, load the new one, make it
current. Like `basicforth <file>`, mid-session. If you have unsaved changes it
asks "save first? (y/n)" at the terminal.

## new ( -- )
Clear the module — forget every definition, back to a clean slate (core only).
If you have unsaved changes it asks "save first? (y/n)" at the terminal.

## reload ( -- )
Re-read the current file from disk — the edit/compile/run loop (`-session` then
re-load the current module file).

## -session ( -- )
Low-level "forget the module's words" back to the end of `core.fs` — the helper
`new` / `load` / `reload` build on.

## Inspecting words

## see ( "name" -- )
Print the source of a word you defined interactively, exactly as you typed it.
Reports *defined, but no source captured* for primitives and `core.fs` words.
See `man see`.

    \ : sq dup * ;   see sq      \ : sq dup * ;

## words ( -- )
List **every** word in the dictionary, newest first — the ~330 built-ins plus
anything you've added. Handy for discovery, but a lot to scroll.

## .module ( -- )
List just the words **you** have defined — your module — everything added on top
of `core.fs` (a `load`ed file or anything `include`d at the REPL), newest first,
with a count. The BASIC `LIST`: *"what have I built?"*

    \ : sq dup * ;   variable n   .module
    \ 2 words in this module (newest first):
    \ n sq

## uses ( "name" -- )
List the module words whose source mentions `<name>` as a whole token
(case-insensitive) — a grep over your own definitions, handy before renaming
something. It reads each word's source the way `see` does — from the interactive
capture log for words you typed, or from the file for words loaded via a startup
argument, `load`, or `include` — so it covers everything `.module` lists.
`<name>`'s own defining line is not counted. A `:noname … ; is x` group that
is the current action of a deferred word is scanned too, reported as
`(:noname is x)`; superseded groups are skipped, and so is the binding group
of `<name>` itself when `<name>` is a deferred word.

    \ variable mcount  : step  mcount @ . ;  : tick  mcount 1+ . ;
    \ uses mcount
    \ mcount is used by: tick step

## marker ( "name" -- )
Define a dictionary restore point (also a defining word — see
`man defining-words` and `man marker`).

## Shelling out

Run Linux programs from the prompt. See `docs/Shelling_Out.md`.

## sh ( "command<eol>" -- )
Run the rest of the line as a shell command (`/bin/sh -c`), the way you'd type it
at a terminal — `sh ls -la`, `sh git status`. Output goes to the terminal; it's
transient, so nothing is captured to the module.

## (system) ( c-addr u -- status )
The primitive `sh` is built on: run a command string via `/bin/sh -c` and return
its exit status (0–255), or -1 on a spawn failure. Use it when you want the
status or are building the command in code.

## Browsing the docs

These read the `*.md` topics in the directories named by `BASICFORTH_DOCS`. See
`man help-system`.

## topics ( -- )
List the available help topics, grouped by section.

## man ( "topic" -- )
Find `<topic>.md` (case-insensitive) and page it a screenful at a time
(space = next page, q = quit).

## apropos ( "keyword" -- )
List the topics whose text contains `<keyword>`, each labelled with its section.

## See Also

- docs/Persistence.md — modules: `save <name>`, `load`, `new`, `reload` in depth.
- docs/See.md — how `see` reconstructs source.
- docs/Marker.md — dictionary restore points.
- docs/Help_System.md — `topics`, `man`, `apropos`, and sections.
- docs/Shelling_Out.md — `sh` / `(system)`: running Linux programs.
