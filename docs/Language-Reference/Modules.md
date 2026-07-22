# Modules

Your interactive work is a **module**: the words you've defined on top of
core, which you can write to a file and load back (BASIC's `SAVE`/`LOAD`).
Definitions append; a word changed with `edit`/`:e` is *mutated* — replaced
where it stands in the file. Full story: docs/Persistence.md.

At a glance:

    save <name>   ( "name" -- )    write the module to a file (bare: re-save)
    load <name>   ( "name" -- )    switch to a module file
    new           ( -- )           clear the module, clean slate
    list          ( -- )           page the current module file
    reload        ( -- )           re-read the current file from disk
    .module       ( -- )           list the words you have defined
    uses <name>   ( "name" -- )    which of your words mention <name>?
    edit <name>   ( "name" | -- )  revise a word in your editor (bare: the file)
    define <name> ( "name" -- )    write a new word in your editor
    :e <name> ...;                 retype one definition at the prompt
    redo <name>   ( "name" -- )    re-evaluate a word's source
    keep          ( -- )           save this line too, though it defined nothing
    on-start      ( -- )           you define it: runs after the module loads
    on-stop       ( -- )           you define it: runs before it is torn down
    -session      ( -- )           low-level: forget all module words

## save ( "name" -- )  /  save ( -- )
`save <name>` writes the module to `<name>` (relative to the current directory)
and makes it the current file; bare `save` re-writes the current file. The
file text is kept byte-for-byte (comments, layout, every definition in order)
and the session's definitions and direct `is`/`to` assignments append in the
order they happened, so the file **replays to exactly the live state** — a
plain `:` redefinition appends (earlier words keep the binding they captured;
Forth is hyper-static). The exception: a word changed with **`edit`** is a
*mutation* — its definition is replaced where it stands, so edit history
never accumulates and saving twice is byte-identical. Writes atomically, so
a failure never corrupts an existing file.

## load ( "name" -- )
Open `<file>` as the module — forget the old one, load the new one, make it
current. Like `basicforth <file>`, mid-session. If you have unsaved changes it
asks "save first? (y/n)" at the terminal.

## new ( -- )
Clear the module — forget every definition, back to a clean slate (core only).
If you have unsaved changes it asks "save first? (y/n)" at the terminal.

## list ( -- )
Page the current module file — BASIC's `LIST`, your whole program at once.
Bindings typed since the last save live in the capture log, not the file,
so a dirty session prints "(unsaved changes - save to include them)" first.

## reload ( -- )
Re-read the current file from disk — the edit/compile/run loop (`-session` then
re-load the current module file).

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

## edit ( "name" | -- )
`edit <word>` opens the word's source in your editor (`$EDITOR`); saving and
quitting **mutates** the word — the file is spliced in place and reloaded, so
callers rebuild against the new definition. Bare `edit` opens the whole
current module file. The temp file is `<module>.edit.fs`, so editors
syntax-highlight it as Forth. Quit without changes and nothing happens
("edit: unchanged").

## define ( "name" -- )
`edit`'s creating twin: open your editor on a skeleton for a **new** word
named `<name>`, and append it to the module on save. Refused if the name
already exists (that's what `edit` is for).

## :e ( "name body... ;" -- )
Mutate a word by retyping it at the prompt — `edit` without the editor
round-trip, for one-line fixes. Same splice-and-reload semantics and guards
as `edit`. Abandon a half-typed `:e` with `cancel;`
(`help defining-words`).

    \ :e square  dup * ;      \ square replaced, callers rebuilt

## redo ( "name" -- )
Re-evaluate a word's source — the text you typed when you defined it — layering
a fresh binding that picks up the *current* definitions of everything it calls.
The by-hand escape hatch when you've redefined a leaf and want one caller to
notice (hyper-static words otherwise keep the bindings they captured).

    \ redo snake              \ recompile snake from its source

## keep ( -- )
Put **this line** in the module even though it defined nothing. `save` records a
line when it defines a word, so setup lines are normally invisible — a window
you opened, a variable you initialised, rows of `,` after a `create`. End the
line with `keep` and it is written verbatim, where you typed it.

    \ 320 180 sdl-open  keep         \ the module reopens its window on load
    \ create tbl  1 , 2 , 3 ,  keep  \ table data survives the save

It can go anywhere on the line, not just last, and on a line that already
defines a word it does nothing. `keep` only acts at the terminal, so the copy
written into the file is an inert token when the module reloads — nothing to
clean up.

## on-start ( -- )  /  on-stop ( -- )
Not words BasicForth defines — words **you** may define in a module, which it
then calls at the right moment:

    : on-start  320 180 sdl-open ;    \ after the module's file has loaded
    : on-stop   sdl-close ;           \ before its words are forgotten

`on-start` runs when the module is opened — at startup (`basicforth game.fs`),
after `load`, and after every `reload`, including the reloads that `edit` and
`:e` perform. Use it to (re)acquire whatever the module needs to run.

`on-stop` runs just before the module's words are thrown away, by `reload`,
`load`, `new` or `-session`. This is where you release things the *system* is
holding for you — a window, an audio device, an open file. Reloading rebuilds
everything in the file, but a handle stored in a `value` is zeroed by the
rollback while the resource itself lives on, unreachable. `on-stop` still has
the valid handle, so it can close it properly.

Both are optional; a module that defines neither behaves exactly as before. If
a hook fails it reports (`error in on-start hook: -4`) and the load continues —
a broken hook can't leave you with no module at all.

## -session ( -- )
Low-level "forget the module's words" back to the end of `core.fs` — the helper
`new` / `load` / `reload` build on. Runs `on-stop` first, which is why every one
of those verbs releases the module's resources.

## See Also

- `help defining-words` — `:`, `cancel;`, `marker`.
- `help tools` — `see` / `words` / `sh`, and browsing these docs.
- docs/Persistence.md — the full module story: capture, the dirty-guard, limits.
- docs/Line_Editor.md — the editor integration (`edit`, `define`, `:e`).
- docs/Redo.md — `redo` and hyper-static binding, in depth.
