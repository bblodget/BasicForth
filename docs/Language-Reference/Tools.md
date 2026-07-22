# Tools

Environment commands you use *at the prompt* rather than inside programs:
inspecting words, browsing the docs, running tutorials, and shelling out.
(Saving and editing your work moved to `help modules`.)

At a glance:

    see <name>     ( "name" -- )      show a word's source
    dis <name>     ( "name" -- )      show a word's machine code (require disasm.fs)
    words          ( -- )             list every word in the dictionary
    marker <name>  ( "name" -- )      set a forget-point (help defining-words)
    version        ( -- )             print the build version banner
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
- docs/Disassembler.md — how `dis` decodes and annotates machine code.
- docs/Help_System.md — `help`, `tutorials`, `apropos`, and sections.
- docs/Tutorial_System.md — the tutorial system, including writing lessons.
- docs/Shelling_Out.md — `sh` / `(system)`: running Linux programs.
