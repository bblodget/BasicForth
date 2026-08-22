# Tools

Environment commands you use *at the prompt* rather than inside programs:
inspecting words, browsing the docs, running tutorials, and shelling out.
(Saving and editing your work moved to `help modules`.)

At a glance:

    see <name>     ( "name" -- )      show a word's source
    where <name>   ( "name" -- )      which file a word came from
    where-path     ( c-addr u -- c-addr u true | false )  ...as a string
    word-deps <nm> ( "name" -- )      what the word's file requires
    dis <name>     ( "name" -- )      show a word's machine code (require disasm.fs)
    time <name>    ( "name" -- )      run a word, print the wall clock it took
    words          ( -- )             list every word in the dictionary
    marker <name>  ( "name" -- )      set a forget-point (help defining-words)
    version        ( -- )             print the build version line
    license        ( -- )             print the copyright and warranty notice
    sh <command>   ( "cmd<eol>" -- )  run a shell command
    (system)       ( c-addr u -- status )  run a command, return its status

    Browsing the docs (BASICFORTH_DOCS):
    help           ( -- )             list the help topics
    help <topic>   ( "topic" -- )     print a topic's summary
    help <word>    ( "word" -- )      print a word's reference entries
    tutorials      ( -- )             list the interactive tutorials
    apropos <key>  ( "keyword" -- )   which topics mention a keyword?

    Tutorials (one step at a time, at the REPL):
    tutorial <name> ( "name" ["step"] -- )  start a tutorial (bare: list them)
    next           ( -- )             show the next step
    back           ( -- )             show the previous step
    step [n]       ( ["step"] -- )    replay the current step, or jump to n
    end-tutorial   ( -- )             leave (your definitions remain)

## Inspecting words

## see ( "name" -- )
Print the source of a word's most recent definition, exactly as written —
whether typed this session or loaded from a file (including `core.fs`).
Assembly primitives have no source; `see` points you at `help <name>` and
`dis <name>` instead.
See docs/See.md.

    \ : sq dup * ;   see sq      \ : sq dup * ;

## where ( "name" -- )
Print the path of the file a word was loaded from — the question `see` answers
on its way to printing source, asked on its own. Use it when you want the
filename rather than the text, typically to hand to `deps`:

    require disasm.fs
    where dis
    \ /usr/local/share/basicforth/forth/disasm.fs
    deps /usr/local/share/basicforth/forth/disasm.fs

The answer is the full path, not the bare name, because a checkout and an
installed tree can both hold a `disasm.fs` and only the path says which one is
in force. `deps` accepts a path, so the answer is still exactly what the file
words want.

The same four cases as `see`: a word from a file gives its path, an assembly
primitive says so, a word typed this session says so, and an undefined name
reports `not found`.

`where` reports where the definition **in force** came from, not where a copy
of its text exists. `save` writes a file; it does not make that file the word's
origin, because nothing has loaded it. `reload` does:

    : hello 42 . ;
    where hello       \ where: hello was typed at the REPL this session
    save work.fs
    where hello       \ where: hello was typed at the REPL this session
    reload
    where hello       \ /home/you/work.fs

A word can also come from a file BasicForth can no longer name. Source ids come
from a 64-entry table, and once it is full every later file is stamped with the
same id the REPL uses — so the origin is genuinely unknown rather than
mistakable for something else, and `where` says that instead of guessing:

    where f70
    \ where: f70 came from a file this run cannot name
    \ where: the source table is full (64 files)

## where-path ( c-addr u -- c-addr u true | false )
`where` for programs: takes a word's name as a string and **returns** the path
rather than printing it, so you can build on it.

Only a file-loaded word has a path. A primitive, a word typed this session, an
undefined name, and a word from past the 64-file table all answer `false` —
none of them names a file you could open. A caller that needs to tell those
apart asks `(find-meta)` directly, as `where` does.

The string points into the source table, so it stays valid for the run and must
not be freed.

It pairs with `deps-path`, which is `deps` over a path you already hold, so the
two compose into "what does this word's file require" — which ships as
`word-deps`. `see word-deps` is the whole of it:

    : word-deps ( "name" -- )
        parse-word ...
        2dup where-path if 2swap 2drop deps-path exit then
        ...

## word-deps ( "name" -- )
What the file that defines a word requires — `deps` reached through the
dictionary instead of through a filename. Use it when you are holding a word,
not a file:

    require disasm.fs
    word-deps dis
    \ /usr/local/share/basicforth/forth/disasm.fs
    \   require shellutil.fs      loaded
    \   wants-cmd objdump         ok -- /usr/bin/objdump
    \   ... all 2 requirements met.

A word with no file to inspect — a primitive, one typed this session, an
undefined name — says so and points at `where`.

This is deliberately a third word rather than a smarter `deps`: resolving a
*name* to a file does not belong in the layer that handles filenames. It is
built from `where-path` and `deps-path`, both public, and `see word-deps` shows
the join.

## dis ( "name" -- )
Disassemble a word's machine code — the other side of `see`. Colon words show
their compiled code straight from the dictionary, each `call` annotated with
the word it targets; primitives show their assembly from the binary, bounded
by symbol. Needs `require disasm.fs` and binutils `objdump` on PATH. See
docs/Disassembler.md.

    require disasm.fs
    : sq dup * ;
    dis sq
    \ sq: 11 bytes at 0043AEE4 (dictionary)
    \   43aee4:  e8 fb 67 fc ff   call 0x4016e4  \ dup
    \   43aee9:  e8 df 68 fc ff   call 0x4017cd  \ *
    \   43aeee:  c3               ret

## time ( "name" -- )
The benchmarking front door: run `<name>` and print how long it took, as
seconds with three decimals.
It is a transparent wrapper: the stack going in is untouched, so a word
that takes arguments still works, and whatever the word leaves is still
there afterwards.

    : bench 1000000000 0 do loop ;
    time bench             \ 0.419 s
    50000000 time spin     \ a word that takes an argument

Resolution is the millisecond tick of `ms@`, so anything faster than that
prints `0.000 s` — run it a few million times in a loop, which is what you
need for a per-operation figure anyway. The duration always prints in
decimal, whatever `BASE` you are working in, and `BASE` is left as it was.
Inside a definition, time with `ms@` directly: `ms@ ... ms@ swap - .`. See
docs/Performance.md for what the numbers mean and how to read the
generated code behind them.

## words ( -- )
List **every** word in the dictionary, newest first — the built-ins plus
anything you've added. Handy for discovery, but a lot to scroll; `.module`
(`help modules`) lists just yours.

## marker ( "name" -- )
Define a dictionary restore point (also a defining word — see
`help defining-words` and docs/Marker.md).

## version ( -- )
Print the version line — the first line of the startup banner, and exactly
what `basicforth -v` prints (the build's `git describe` string).

    version           \ *** BasicForth v0.12.0 (Linux/x86-64) ***

## license ( -- )
Print the copyright and warranty notice, as the startup banner invites. The
notice is built in rather than read from the `LICENSE` file, so it works from
an installed binary that has no source tree to look in.

    license           \ GPL-2.0-only, no warranty, where the full text lives

BasicForth is free software under the GNU General Public License, version 2.
The complete text ships as `LICENSE` in the source distribution.

## Shelling out

Run Linux programs from the prompt. See `docs/Shelling_Out.md`, and
`help shell` for the built-in `ls` / `cat` / `cd` family.

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
docs/Help_System.md.

## help ( ["name"] -- )
The front door to the reference manual. Three forms:

    help              \ list every topic (tutorials get their own lister)
    help stack        \ a topic: print its summary and at-a-glance table
    help allot        \ a word: print that word's reference entry

A topic name matches its `.md` file case-insensitively, folding `-` and `_`
(`help help-system` finds `Help_System.md`). Anything that isn't a topic is
looked up as a word across the reference pages — and every entry naming it
is shown, so `help begin` prints all three `begin …` loop forms.

## tutorials ( -- )
List the interactive tutorials — start one with `tutorial <name>`.

## apropos ( "keyword" -- )
List the topics whose text contains `<keyword>`, each labelled with its section.

## Tutorials

An interactive walk through a lesson file, one step at a time — unlike `help`,
which prints and returns. See docs/Tutorial_System.md.

## tutorial ( "name" ["step"] -- )
Start tutorial `<name>` (resolved case-insensitively across the docs dirs) at
step 1 — or at an optional step number. With no name, prints a hint and the
tutorial list.

    tutorial snake        \ step 1 of the Snake lesson appears

## next ( -- )
Show the tutorial's next step.

## back ( -- )
Show the previous step.

## step ( ["step"] -- )
Replay the current step — handy after running something that drew all over
the screen. With a number (or the name of a `value` holding one), jump
straight there: `step 7`.

## end-tutorial ( -- )
Leave the tutorial: forgets which step `next` would show, nothing else —
**your definitions remain**.

## See Also

- `help modules` — `save` / `load` / `edit` and friends (moved from this page).
- docs/See.md — how `see` reconstructs source.
- `help deps` — what a file requires; `where` gives it the filename.
- docs/Disassembler.md — how `dis` decodes and annotates machine code.
- docs/Performance.md — measured speed, and the compiled code that explains it.
- docs/Help_System.md — `help`, `tutorials`, `apropos`, and sections.
- docs/Tutorial_System.md — the tutorial system, including writing lessons.
- docs/Shelling_Out.md — `sh` / `(system)`: running Linux programs.
