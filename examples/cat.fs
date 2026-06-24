#!/usr/bin/env basicforth
\ BasicForth — cat, a Unix utility written in Forth
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Concatenate the named files to stdout. Demonstrates the Phase 4 file words
\ (OPEN-FILE / READ-FILE / CLOSE-FILE) together with arguments, WRITE-FILE,
\ stderr, and exit codes — the full "Unix utility in Forth" arc:
\
\   read args  →  open r/o  →  read-file loop  →  write-file to stdout  →  close
\
\ A file that cannot be opened produces a message on stderr and a non-zero
\ exit; with no arguments it prints a usage line on stderr and exits 2.
\
\ Usage (basicforth on PATH; BASICFORTH_PATH so core.fs is found):
\   chmod +x examples/cat.fs
\   ./examples/cat.fs file1 file2

create catbuf 4096 allot
0 value exit-status

: cat-fd ( fileid -- )                  \ copy fileid to stdout; flag any I/O error
    >r
    begin
        catbuf 4096 r@ read-file        ( u2 ior )
        if drop  1 to exit-status  r> drop exit then   \ read error: stop, fail
        dup 0>
    while                               ( u2 )
        catbuf swap stdout write-file   ( ior )
        if 1 to exit-status  r> drop exit then          \ write error: stop, fail
    repeat
    drop  r> drop ;

: cat-file ( c-addr u -- )
    2dup r/o open-file                  ( c-addr u fileid ior )
    if                                  \ open failed
        drop                            ( c-addr u )
        s" cat: cannot open " stderr write-file drop
        stderr write-line drop
        1 to exit-status
        exit
    then
    nip nip                             ( fileid )
    dup cat-fd
    close-file if 1 to exit-status then ;

: cat ( -- )
    next-arg dup 0= if
        2drop  s" usage: cat FILE..." stderr write-line drop  2 bye-code
    then
    begin   ( c-addr u )
        cat-file
        next-arg dup 0=
    until
    2drop
    exit-status bye-code ;

cat
