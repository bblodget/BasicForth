#!/usr/bin/env basicforth
\ BasicForth — lines, a Unix utility written in Forth
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Prints each command-line argument on its own line to stdout, and logs the
\ count to stderr. With no arguments it prints a usage message to stderr and
\ exits non-zero. Demonstrates the file-output words: WRITE-LINE / WRITE-FILE
\ to STDOUT and STDERR, so the data and the diagnostics are separate streams.
\
\ Usage (basicforth on PATH; BASICFORTH_PATH so core.fs is found):
\   chmod +x examples/lines.fs
\   ./examples/lines.fs alpha beta        \ data + "lines: 2" log on terminal
\   ./examples/lines.fs alpha beta > out  \ out holds just the lines;
\                                         \ the log stays on the terminal
\   ./examples/lines.fs                   \ usage on stderr, exit code 2

: log-count ( n -- )                    \ "lines: <n>\n" to stderr
    s" lines: " stderr write-file drop
    0 <# #s #> stderr write-line drop ;

: lines ( -- )
    next-arg dup 0= if                  \ no arguments at all
        2drop
        s" usage: lines ARG..." stderr write-line drop
        2 bye-code
    then
    0 >r                                \ count on the return stack
    begin   ( c-addr u )
        stdout write-line drop          \ the data → stdout, one line each
        r> 1+ >r                        \ bump count
        next-arg dup 0=                 \ ( c-addr u flag )
    until
    2drop                               \ drop the empty 0 0
    r> log-count                        \ report the count → stderr
    0 bye-code ;

lines
