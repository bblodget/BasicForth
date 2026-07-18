# Scripting

Run a Forth file as a Unix program: `basicforth file.fs args...`, or make it
executable with a first line of `#!/usr/bin/env basicforth` (the shebang line
is skipped by the loader). A script reads its command-line arguments with the
words below and ends with `bye` — or `bye-code` to report success/failure to
the shell. See `examples/hello.fs` and `examples/echo.fs`.

At a glance:

    arg         ( u -- c-addr u )   the u-th argument (0 = program name)
    next-arg    ( -- c-addr u )     take the next argument (0 0 when done)
    shift-args  ( -- )              drop the next argument, keep arg 0
    argc        ( -- a-addr )       variable: the argument count
    argv        ( -- a-addr )       variable: the raw char** base
    bye-code    ( n -- )            exit with status n

## arg ( u -- c-addr u )
The `u`-th command-line argument as a string — `0 arg` is the program name,
`1 arg` the first real argument. Out of range returns `( 0 0 )`.

    \ ./greet.fs world
    1 arg type        \ world

## next-arg ( -- c-addr u )
Take the next argument and consume it (the rest shift down; `0 arg` stays the
program name). Returns `( 0 0 )` when none remain — the argument-loop idiom:

    : each-arg  begin next-arg dup while type cr repeat 2drop ;

## shift-args ( -- )
Consume the next argument without fetching it — `next-arg` minus the fetch.
No-op when none remain.

## argc ( -- a-addr )
Variable holding the argument count (including the program name).

    argc @ .          \ 2   (program + one argument)

## argv ( -- a-addr )
Variable holding the raw `char**` argument base — for FFI-style walking; the
words above are built on it.

## bye-code ( n -- )
Exit with status `n`, so shells and Makefiles can test the result. Like
`bye`, the dirty-guard asks about unsaved work first at a terminal.

    : main  ok? if 0 else 1 then bye-code ;

## See Also

- `help files` — `stdin` / `stdout` / `stderr` for filter scripts.
- `help interpreter` — plain `bye`.
- examples/echo.fs, examples/cat.fs, examples/sort.fs — working scripts.
