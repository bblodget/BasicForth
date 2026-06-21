#!/usr/bin/env basicforth
\ BasicForth — Executable Script Example
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Demonstrates running a Forth file as a Unix #! script. BasicForth skips
\ the leading "#!" line, runs the rest, and the closing "bye" exits.
\
\ Usage (basicforth must be on your PATH; BASICFORTH_PATH lets it find core.fs
\ from any directory):
\
\   export PATH="$PATH:$PWD/src/arch/x86"
\   export BASICFORTH_PATH="$PWD/src/arch/x86"
\   chmod +x examples/hello.fs
\   ./examples/hello.fs
\
\ Or load it like any other source file:
\
\   include examples/hello.fs

.( Hello from BasicForth!) cr
.( Running as an executable #! script.) cr
cr

\ Print an n-row triangle of stars.
: triangle  ( n -- )
  1+ 1 do
    i 0 do  [char] * emit  loop
    cr
  loop ;

.( A triangle:) cr
5 triangle
cr

.( 6 * 7 = ) 6 7 * . cr

\ bye
