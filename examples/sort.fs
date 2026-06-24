#!/usr/bin/env basicforth
\ BasicForth — sort, a Unix utility written in Forth
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Sort the lines of a text file. Reads the file named on the command line and
\ writes a sorted copy alongside it, inserting "_sorted" before the extension:
\
\   ./sort.fs unsorted.txt      ->  unsorted_sorted.txt
\   ./sort.fs data.csv          ->  data_sorted.csv
\
\ Lines are compared in byte (ASCII) order, ascending. Demonstrates the whole
\ Phase 4 file stack: OPEN-FILE / FILE-SIZE / READ-FILE to slurp the input,
\ COMPARE-based sorting, then CREATE-FILE / WRITE-LINE / CLOSE-FILE to emit it.
\
\ Fixed buffers (no dynamic memory): up to 16 KB of input and 1024 lines.
\ Larger inputs report an error on stderr and exit non-zero.
\
\ Usage (basicforth on PATH; BASICFORTH_PATH so core.fs is found):
\   chmod +x examples/sort.fs
\   ./examples/sort.fs unsorted.txt

16384 constant max-bytes
1024  constant max-lines

create srcbuf  max-bytes      allot     \ raw file contents
create lines   max-lines 2* cells allot \ per line: ( addr len ), 2 cells each
create outname 256            allot     \ derived output filename

variable srclen      \ bytes actually read
variable #lines      \ number of lines parsed
variable lstart      \ start address of the current line during parsing
variable fits?       \ false if the line array overflowed
variable outfid      \ output fileid (a VARIABLE, not the return stack: DO uses that)

\ -- line array accessors (record i = two cells at lines + i*2 cells) ----------
: line[]     ( i -- a )  2* cells lines + ;
: line-addr@ ( i -- a )  line[] @ ;
: line-len@  ( i -- u )  line[] cell+ @ ;
: line-set   ( a u i -- )  dup >r line[] cell+ ! r> line[] ! ;

\ -- read the whole input file into srcbuf -----------------------------------
: slurp ( c-addr u -- flag )    \ true on success; false on any I/O error / too big
    r/o open-file if drop false exit then          ( fileid )
    >r
    r@ file-size                                   ( ud-lo ud-hi ior )
    if 2drop r> close-file drop false exit then    ( size ud-hi )
    drop                                           ( size )
    max-bytes > if r> close-file drop false exit then
    0                                              ( total )
    begin
        srcbuf over +                              ( total dest )
        max-bytes 2 pick -                         ( total dest remaining )
        r@ read-file                               ( total u2 ior )
        if 2drop r> close-file drop false exit then \ read error -> fail, don't truncate
        dup 0>
    while                                          ( total u2 )
        +                                          ( total' )
    repeat
    drop                                           ( total )
    srclen !
    r> close-file if false exit then               \ close error -> fail, don't claim success
    true ;

\ -- split srcbuf into the line array ----------------------------------------
: record-line ( end -- )        \ record [lstart, end) as one line
    lstart @ swap over -         ( start len )
    #lines @ max-lines < if
        #lines @ line-set  1 #lines +!
    else
        2drop  false fits? !
    then ;

: split-lines ( -- )
    0 #lines !  true fits? !
    srcbuf lstart !
    srclen @ 0 ?do
        srcbuf i + c@ 10 = if
            srcbuf i + record-line          \ line ends at the newline
            srcbuf i + 1+ lstart !          \ next line starts after it
        then
    loop
    \ trailing line with no final newline
    srcbuf srclen @ +  dup lstart @ u> if record-line else drop then ;

\ -- selection sort by byte order --------------------------------------------
variable mini
: sort-lines ( -- )
    #lines @ 0 ?do
        i mini !                            \ only the outer loop is live: I = outer index
        #lines @ i 1+ ?do
            \ inside the inner loop, I is the inner (candidate) index
            i line-addr@ i line-len@  mini @ line-addr@ mini @ line-len@  compare
            0< if i mini ! then
        loop
        i mini @ <> if                      \ inner loop ended: I = outer index again
            \ swap records i and mini
            i line-addr@ i line-len@  mini @ line-addr@ mini @ line-len@
            ( ai li amin lmin )  i line-set  mini @ line-set
        then
    loop ;

\ -- build "base_sorted.ext" from the input name -----------------------------
variable dotpos  variable inaddr  variable inlen  variable outlen
: find-dot ( c-addr u -- )      \ dotpos := index of last '.', or u if none
    dup dotpos !                 ( c-addr u )
    0 ?do
        dup i + c@ [char] . = if i dotpos ! then
    loop drop ;
: build-outname ( c-addr u -- ) \ fills outname + outlen
    2dup find-dot  inlen ! inaddr !
    inaddr @                outname               dotpos @       cmove   \ base
    s" _sorted"             outname dotpos @ +    swap           cmove   \ tag
    inaddr @ dotpos @ +     outname dotpos @ + 7 +   inlen @ dotpos @ -  cmove  \ ext
    inlen @ 7 + outlen ! ;

\ -- main --------------------------------------------------------------------
: emit-error ( c-addr u -- )  stderr write-line drop ;
variable write-err
: write-sorted ( -- )           \ create output and write every line + newline
    0 write-err !
    outname outlen @ w/o create-file if
        drop s" sort: cannot create output file" emit-error  1 bye-code
    then
    outfid !
    #lines @ 0 ?do
        i line-addr@ i line-len@ outfid @ write-line
        ?dup if write-err ! leave then       \ stop on the first write error
    loop
    outfid @ close-file ?dup if write-err ! then
    write-err @ if
        s" sort: error writing output file" emit-error  1 bye-code
    then ;

: sort-main ( -- )
    next-arg dup 0= if
        2drop s" usage: sort.fs FILE" emit-error  2 bye-code
    then                                  ( c-addr u )
    2dup build-outname                    ( c-addr u )
    slurp 0= if
        s" sort: cannot read input (missing, unreadable, or > 16 KB)" emit-error
        1 bye-code
    then
    split-lines
    fits? @ 0= if
        s" sort: too many lines (limit 1024)" emit-error  1 bye-code
    then
    sort-lines
    write-sorted
    0 bye-code ;

sort-main
