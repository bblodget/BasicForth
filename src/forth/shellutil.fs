\ BasicForth shellutil.fs -- safe shell-command plumbing for library code
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ The building blocks a Forth tool needs to drive external programs
\ safely: compose a command with interpolated data QUOTED (so a path with
\ spaces or shell metacharacters is data, never syntax), run it, capture
\ its output, and make temp files that cannot leak or be symlink-attacked.
\ Grown out of disasm.fs and hardened by review there; require this
\ instead of re-rolling string handling per tool:
\
\   require shellutil.fs
\
\   (cmd0)  s" wc -l " (cmd+)  my-path count (cmd+q)
\   (cmd-line1) if (cmd-ln) swap type cr else drop then
\
\ This is plumbing for library authors -- interactive use wants `sh`
\ (help tools). See docs/Shelling_Out.md.

\ --- command buffer ---
\ One shared build buffer: compose with the words below, then run with
\ (cmd-run) / (cmd-open) / (cmd-line1). Nothing here re-enters, so one
\ buffer is enough; treat a composed command as consumed once run.
\ An append that does not fit sets (cmd-ovf), and a command marked
\ overflowed REFUSES to run — a truncated command could have lost its
\ cleanup tail or a closing quote, so executing it is never safe. 4 KB
\ comfortably holds worst-case quoted paths (a 255-byte path quotes to
\ at most ~1 KB).
create (cmd-buf) 4096 allot   variable (cmd-#)   variable (cmd-ovf)
: (cmd0)  ( -- ) 0 (cmd-#) !  0 (cmd-ovf) ! ;   \ start a new command
: (cmd$)  ( -- a u ) (cmd-buf) (cmd-#) @ ;  \ the composed command
: (cmd+)  ( a u -- )                        \ append
    (cmd-#) @ over + 4096 > if 2drop true (cmd-ovf) ! exit then
    dup >r  (cmd-buf) (cmd-#) @ +  swap move  r> (cmd-#) +! ;
: (cmd+c) ( ch -- )                         \ append one character
    (cmd-#) @ 4096 < if  (cmd-buf) (cmd-#) @ + c!  1 (cmd-#) +!
    else  drop true (cmd-ovf) !  then ;
: (cmd+q) ( a u -- )    \ append single-quoted, ' escaped as '\'' -- use
    [char] ' (cmd+c)    \ for EVERY path or datum spliced into a command
    begin dup 0> while
        over c@ dup [char] ' = if  drop s" '\''" (cmd+)  else  (cmd+c)  then
        1 /string
    repeat 2drop
    [char] ' (cmd+c) ;
: (cmd+x) ( u -- )                          \ append the number as 0x<hex>
    s" 0x" (cmd+)
    base @ >r hex  0 <# #s #>  r> base !  (cmd+) ;

\ --- run + capture ---
create (cmd-ln) 512 allot                   \ one captured output line
variable (cmd-fid)
: (cmd-run)   ( -- status )                 \ run; output to the terminal
    (cmd-ovf) @ if -1 exit then             \ overflowed: refuse (as spawn fail)
    (cmd$) (system) ;
: (cmd-open)  ( -- f )                      \ run, capturing stdout
    (cmd-ovf) @ if false exit then          \ overflowed: refuse
    (cmd$) r/o open-pipe  if drop false else (cmd-fid) ! true then ;
: (cmd-read)  ( -- u true | false )         \ next line into (cmd-ln)
    (cmd-ln) 511 (cmd-fid) @ read-line      ( u flag ior )
    if 2drop false else 0= if drop false else true then then ;
: (cmd-close) ( -- ) (cmd-fid) @ close-pipe 2drop ;
: (cmd-line1) ( -- u true | false )         \ run; first line -> (cmd-ln)
    (cmd-open) 0= if false exit then
    (cmd-read)
    begin (cmd-read) while drop repeat      \ drain so the child can exit
    (cmd-close) ;

\ --- temp files ---
\ (sh-mktemp) makes a temp file under $TMPDIR (default /tmp): mode 0600
\ and an unpredictable name, so nobody can pre-plant a symlink there for
\ the caller to write through. The path lands in (cmd-ln) -- COPY IT OUT
\ before composing the next command. The child shell itself removes the
\ file and reports nothing when the path exceeds 255 bytes, so an
\ overlong $TMPDIR cannot leak a file (a caller-side rm would need the
\ full path, which the capped line capture could have truncated).
\ The stem is spliced into the template inside the shell's double quotes,
\ where $ ` \ " would still be LIVE syntax -- so it is validated, not
\ trusted: anything but a plain filename fragment is refused.
\ Assembled command:
\   f=$(mktemp "${TMPDIR:-/tmp}/<stem>-XXXXXX") &&
\     { [ ${#f} -le 255 ] && printf '%s\n' "$f" || rm -f "$f"; }
: (fname-ch?) ( ch -- f )                   \ letter, digit, - _ .
    dup  [char] 0 [char] 9 1+ within
    over [char] a [char] z 1+ within or
    over [char] A [char] Z 1+ within or
    over [char] - = or
    over [char] _ = or
    swap [char] . = or ;
: (sh-fname?) ( a u -- f )                  \ non-empty plain filename fragment?
    dup 0= if 2drop false exit then
    begin dup 0> while
        over c@ (fname-ch?) 0= if 2drop false exit then
        1 /string
    repeat 2drop true ;
: (sh-mktemp) ( stem-a stem-u -- u true | false )
    2dup (sh-fname?) 0= if 2drop false exit then
    (cmd0)
    s" f=$(mktemp " (cmd+)  [char] " (cmd+c)
    s" ${TMPDIR:-/tmp}/" (cmd+)  (cmd+)  s" -XXXXXX" (cmd+)  [char] " (cmd+c)
    s" ) && { [ ${#f} -le 255 ] && printf '%s\n' " (cmd+)  [char] " (cmd+c)
    s" $f" (cmd+)  [char] " (cmd+c)
    s"  || rm -f " (cmd+)  [char] " (cmd+c)
    s" $f" (cmd+)  [char] " (cmd+c)
    s" ; }" (cmd+)
    (cmd-line1) ;
: (sh-rm) ( a u -- )                        \ remove a file, path quoted
    (cmd0) s" rm -f " (cmd+)  (cmd+q)  (cmd-run) drop ;
