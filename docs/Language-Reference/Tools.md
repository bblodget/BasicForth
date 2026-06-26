# Tools

Environment commands you use *at the prompt* rather than inside programs:
inspecting words, saving your session, and browsing the docs. Each has a fuller
topic page (`man <topic>`), linked below.

## Session persistence

These work in an interactive session; definitions you enter are captured so they
can be saved and reloaded. See `man persistence`.

## save ( -- )
Write the words you've defined this session to `session.fs` in the current
directory (auto-loaded next start). Writes atomically, so a failure never
corrupts an existing file.

## -session ( -- )
Forget everything defined since startup — the session definitions and anything
entered interactively — keeping `core.fs` and the loaded session words.

## reload ( -- )
`-session` followed by re-loading the (possibly hand-edited) `session.fs` — the
edit/compile/run loop.

## Inspecting words

## see ( "name" -- )
Print the source of a word you defined interactively, exactly as you typed it.
Reports *defined, but no source captured* for primitives and `core.fs` words.
See `man see`.

    \ : sq dup * ;   see sq      \ : sq dup * ;

## marker ( "name" -- )
Define a dictionary restore point (also a defining word — see
`man defining-words` and `man marker`).

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

- docs/Persistence.md — `save`, `-session`, `reload` in depth.
- docs/See.md — how `see` reconstructs source.
- docs/Marker.md — dictionary restore points.
- docs/Help_System.md — `topics`, `man`, `apropos`, and sections.
