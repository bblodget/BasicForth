# Tools

Environment commands you use *at the prompt* rather than inside programs:
inspecting words, browsing the docs, running tutorials, and shelling out.
(Saving and editing your work moved to `help modules`.)

At a glance:

    see <name>     ( "name" -- )      show a word's source
    words          ( -- )             list every word in the dictionary
    marker <name>  ( "name" -- )      set a forget-point (help defining-words)
    version        ( -- )             print the build version banner
    sh <command>   ( "cmd<eol>" -- )  run a shell command
    (system)       ( c-addr u -- status )  run a command, return its status

    Browsing the docs (BASICFORTH_DOCS):
    topics         ( -- )             list the help topics by section
    man <topic>    ( "topic" -- )     page a topic file
    apropos <key>  ( "keyword" -- )   which topics mention a keyword?

    Tutorials (one step at a time, at the REPL):
    tutorial <name> ( "name" ["step"] -- )  start a tutorial (bare: list them)
    next           ( -- )             show the next step
    back           ( -- )             show the previous step
    step [n]       ( ["step"] -- )    replay the current step, or jump to n
    end-tutorial   ( -- )             leave (your definitions remain)

## Inspecting words

## see ( "name" -- )
Print the source of a word you defined interactively, exactly as you typed it.
Reports *defined, but no source captured* for primitives and `core.fs` words.
See docs/See.md.

    \ : sq dup * ;   see sq      \ : sq dup * ;

## words ( -- )
List **every** word in the dictionary, newest first — the built-ins plus
anything you've added. Handy for discovery, but a lot to scroll; `.module`
(`help modules`) lists just yours.

## marker ( "name" -- )
Define a dictionary restore point (also a defining word — see
`help defining-words` and docs/Marker.md).

## version ( -- )
Print the version banner shown at startup (the build's `git describe` string).

    version           \ *** BasicForth v0.10.0 (Linux/x86-64) ***

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

## topics ( -- )
List the available help topics, grouped by section.

## man ( "topic" -- )
Find `<topic>.md` (case-insensitive) and page it a screenful at a time
(space = next page, q = quit).

## apropos ( "keyword" -- )
List the topics whose text contains `<keyword>`, each labelled with its section.

## Tutorials

An interactive walk through a lesson file, one step at a time — unlike `man`,
which pages a whole file. See docs/Tutorial_System.md.

## tutorial ( "name" ["step"] -- )
Start tutorial `<name>` (resolved case-insensitively across the docs dirs) at
step 1 — or at an optional step number. With no name, prints a hint and the
available topics.

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
- docs/Help_System.md — `topics`, `man`, `apropos`, and sections.
- docs/Tutorial_System.md — the tutorial system, including writing lessons.
- docs/Shelling_Out.md — `sh` / `(system)`: running Linux programs.
