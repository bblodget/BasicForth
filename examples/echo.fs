#!/usr/bin/env basicforth
\ BasicForth — echo, a Unix utility written in Forth
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Prints its command-line arguments separated by single spaces, then a
\ newline — like /bin/echo. Demonstrates Tier 3 scripting: NEXT-ARG to read
\ arguments and BYE-CODE to exit with a status (silently).
\
\ Usage (basicforth on PATH; BASICFORTH_PATH so core.fs is found):
\   chmod +x examples/echo.fs
\   ./examples/echo.fs hello forth world
\   → hello forth world

: echo ( -- )
  next-arg dup if               \ first argument (no leading space)
    type
    begin next-arg dup while    \ remaining arguments
      space type
    repeat
  then
  2drop cr ;

echo
0 bye-code
