#!/usr/bin/env basicforth

: make-test ( -- )
    s" test.txt" w/o create-file ( -- fileid ior )
    if ." cannot create file" cr 1 bye-code then
    >r
    s" Hello, file!" r@ write-line if ." write failed" cr 1 bye-code then
    s" line two" r@ write-line if ." write failed" cr 1 bye-code then
    r> close-file if ." close failed" cr 1 bye-code then
    ." wrote test.txt" cr ;
make-test
0 bye-code

