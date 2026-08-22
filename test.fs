require disasm.fs
: t1
s" dis"  where-path if type cr else ." (no file)" cr then ;
: t2
s" dup"  where-path if type cr else ." (no file)" cr then ;
: t3
s" nope" where-path if type cr else ." (no file)" cr then ;
: mine 1 ;
: t4 s" mine" where-path if type cr else ." (no file)" cr then ;
: wdeps ( "name" -- )
    parse-word where-path
    if  2dup (dp-run) (dp-verdict)
    else  ." no file for that word" cr  then ;
] 1 2 + drop [
: hello 42 . ;
