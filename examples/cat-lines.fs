#!/usr/bin/env basicforth
\ BasicForth — cat-lines, a line-oriented cat written in Forth
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Concatenate the named files to stdout, reading one line at a time. This is the
\ companion to examples/cat.fs: cat.fs copies raw bytes with READ-FILE, while
\ this version reads whole lines with READ-LINE and re-emits each with
\ WRITE-LINE — the full "Unix utility in Forth" arc, line-oriented:
\
\   read args  →  open r/o  →  read-line loop  →  write-line to stdout  →  close
\
\ Because READ-LINE strips the line terminator and WRITE-LINE appends a single
\ LF, this version is NOT byte-exact like cat.fs — it normalizes CRLF to LF,
\ adds a trailing newline if the last line lacked one, and truncates any line
\ longer than the buffer (see LINEMAX). Use cat.fs when exact bytes matter;
\ use this when you want to work a line at a time.
\
\ A file that cannot be opened produces a message on stderr and a non-zero
\ exit; with no arguments it prints a usage line on stderr and exits 2.
\
\ Usage (basicforth on PATH; BASICFORTH_PATH so core.fs is found):
\   chmod +x examples/cat-lines.fs
\   ./examples/cat-lines.fs file1 file2

4096 constant LINEMAX                   \ longest line kept whole; longer ones truncate
create linebuf LINEMAX allot
0 value exit-status

: cat-fd ( fileid -- )                  \ copy fileid to stdout a line at a time
    >r
    begin
        linebuf LINEMAX r@ read-line    ( u2 flag ior )
        if 2drop  1 to exit-status  r> drop exit then   \ read error: stop, fail
        ( u2 flag )
    while                               ( u2 )          \ flag true → got a line
        linebuf swap stdout write-line  ( ior )         \ line + newline to stdout
        if 1 to exit-status  r> drop exit then          \ write error: stop, fail
    repeat                              ( u2 )
    drop  r> drop ;                     \ flag false (EOF): drop u2, done

: cat-file ( c-addr u -- )
    2dup r/o open-file                  ( c-addr u fileid ior )
    if                                  \ open failed
        drop                            ( c-addr u )
        s" cat-lines: cannot open " stderr write-file drop
        stderr write-line drop
        1 to exit-status
        exit
    then
    nip nip                             ( fileid )
    dup cat-fd
    close-file if 1 to exit-status then ;

: cat-lines ( -- )
    next-arg dup 0= if
        2drop  s" usage: cat-lines FILE..." stderr write-line drop  2 bye-code
    then
    begin   ( c-addr u )
        cat-file
        next-arg dup 0=
    until
    2drop
    exit-status bye-code ;

cat-lines
