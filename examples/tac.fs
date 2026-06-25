#!/usr/bin/env basicforth
\ BasicForth — tac, a Unix utility written in Forth
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Concatenate standard input and print its lines in reverse order — the Unix
\ `tac` (cat backwards). The last line comes out first:
\
\   printf 'one\ntwo\nthree\n' | ./tac.fs   ->  three / two / one
\
\ This is the showcase for the heap (ALLOCATE / RESIZE / FREE). Unlike sort.fs,
\ which slurps a *file* whose size FILE-SIZE reports up front (and so uses a
\ fixed 16 KB buffer), tac reads *stdin* — a pipe whose size is unknown and
\ that cannot be seeked or measured. So the buffer has to grow as data arrives:
\ ALLOCATE a small block, double it with RESIZE whenever it fills, then FREE it
\ at the end. There is no fixed input limit; tac holds as much as the kernel
\ will give it.
\
\ A line includes its trailing newline; input with no final newline keeps that
\ property (the unterminated last line is emitted first, with no newline added),
\ matching GNU tac.
\
\ Usage (basicforth on PATH; BASICFORTH_PATH so core.fs is found):
\   chmod +x examples/tac.fs
\   printf 'a\nb\nc\n' | ./examples/tac.fs
\ or:
\   printf 'a\nb\nc\n' | basicforth examples/tac.fs

256 constant INIT-CAP        \ initial heap buffer size; doubles as needed

variable buf                 \ heap block holding the whole input (a-addr)
variable cap                 \ current capacity of buf, in bytes
variable len                 \ bytes of input stored so far
variable cursor              \ scan position while emitting in reverse
variable lstart              \ start of the line currently being emitted

10 constant NL               \ newline byte

: die ( c-addr u -- )        \ report on stderr and exit non-zero (clean stdout)
    stderr write-line drop  1 bye-code ;

\ Make sure buf has room for at least one more byte; grow by doubling.
: ensure-room ( -- )
    len @ cap @ = if
        buf @ cap @ 2* resize    ( a2 ior )
        if  s" tac: out of memory" die  then
        buf !                    \ resize may have moved the block
        cap @ 2* cap !
    then ;

\ Read all of stdin into buf, growing the block whenever it fills.
: slurp ( -- )
    begin
        ensure-room
        buf @ len @ +            ( dest )   \ append point
        cap @ len @ -            ( dest room ) \ bytes of free space
        stdin read-file          ( u2 ior )
        dup if  drop drop  s" tac: read error" die  then
        drop                     ( u2 )
        dup 0= if  drop exit  then          \ end of input
        len +!                   \ advance by the bytes just read
    again ;

\ Write buf[lstart .. cursor) to stdout (the record keeps its own newline).
\ A write failure (broken pipe, full disk, …) must not be swallowed: report it
\ and exit non-zero rather than silently truncating the output.
: emit-record ( -- )
    cursor @ lstart @ -          ( count )
    buf @ lstart @ +             ( count c-addr )
    swap stdout write-file       ( ior )
    if  s" tac: write error" die  then ;

\ Set lstart to the beginning of the record that ends just before cursor:
\ the byte after the previous newline, or the start of the buffer.
: find-start ( -- )
    cursor @ 1- lstart !
    begin
        lstart @ 0> if
            lstart @ 1- buf @ + c@ NL <>
        else false then
    while
        lstart @ 1- lstart !
    repeat ;

\ Emit the buffered input one record at a time, last record first.
: emit-reversed ( -- )
    len @ cursor !
    begin cursor @ 0> while
        find-start
        emit-record
        lstart @ cursor !        \ next record ends where this one began
    repeat ;

: tac ( -- )
    INIT-CAP allocate            ( a ior )
    if  s" tac: out of memory" die  then
    buf !  INIT-CAP cap !  0 len !
    slurp
    emit-reversed
    buf @ free drop ;

tac 0 bye-code
