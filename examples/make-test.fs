#!/usr/bin/env basicforth

: make-test ( -- )
    s" test.txt" w/o create-file ( -- fileid ior )
    if ." cannot create file" cr 1 bye-code then
    >r
    s" Hello, file!" r@ write-line drop
    s" line two" r@ write-line drop
    r> close-file drop
    ." wrote test.txt" cr ;
make-test
0 bye-code

