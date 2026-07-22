\ BasicForth disasm.fs -- dis: disassemble a word via objdump
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ `dis <name>` shows the machine code behind a word, using the system
\ objdump (binutils) to do the decoding -- so the same module works on
\ x86-64 and ARM64, and on any future arch objdump knows.
\
\   require disasm.fs
\   dis dup        \ a primitive: code lives in the binary's .text
\   dis half       \ a colon word: code lives in the dictionary
\
\ Two paths, because BasicForth code lives in two places:
\  - dictionary words (header CodeLen != 0): the code bytes are written
\    to a temp file and decoded with `objdump -D -b binary`; any call
\    target that matches a dictionary word is annotated with the word's
\    name (call 0x404f2a  \ dup) -- the readable half no external tool
\    can do alone.
\  - primitives (CodeLen == 0): the code sits in the (unstripped,
\    no-pie) binary itself; `objdump -d --start-address` finds it and
\    the symbol table both bounds it and labels its call targets.
\
\ A Linux dev tool: it shells out (via shellutil.fs -- safe quoting,
\ capture, temp files), so it needs /bin/sh and objdump on PATH, and
\ reports gracefully when either is missing. Known limits (v1): an
\ inline literal (call lit + 8 data bytes) desyncs the linear decode
\ for a few instructions after it; :noname xts have no header, so
\ there is nothing to look up. See docs/Disassembler.md.

require shellutil.fs

\ --- dictionary header navigation ---
\ Entry layout (docs/Defining_Words.md):
\ [Link:8][Flags+Len:1][Flags2:1][Name:N][align8][CodePtr:8][CodeLen:4][SrcMeta:8][code...]
: (nt>flags) ( nt -- flags ) 8 + c@ ;
: (nt>name)  ( nt -- c-addr u ) dup 10 +  swap (nt>flags) 31 and ;
: (nt>xtf)   ( nt -- a-addr )   \ address of the CodePtr field
    dup (nt>flags) 31 and  10 + 7 + -8 and  + ;
: (nt>xt)    ( nt -- xt ) (nt>xtf) @ ;
: (nt>clen)  ( nt -- u )  (nt>xtf) 8 + l@ ;   \ 0 for assembly primitives
: (xt>nt)    ( xt -- nt | 0 )   \ reverse lookup: whose code starts here?
    (latest@)
    begin dup while
        2dup (nt>xt) = if nip exit then
        @
    repeat nip ;

\ --- small string helpers ---
: (hex-digit?) ( ch -- f )
    dup  [char] 0 [char] 9 1+ within
    over [char] a [char] f 1+ within or
    swap [char] A [char] F 1+ within or ;
: (d-lead-bl) ( a u -- a' u' )              \ drop leading blanks
    begin  dup 0> if over c@ bl = else false then  while
        1 /string
    repeat ;

\ Find the tail after the LAST "0x" in the line (objdump prints branch
\ targets last, but immediates like $0x8 appear earlier -- those parse
\ to small numbers no dictionary entry matches, so they annotate nothing).
variable (d0x-a)  variable (d0x-u)
: (d-last-0x) ( a u -- a' u' true | false )
    0 (d0x-a) !
    begin dup 1 > while
        over c@ [char] 0 = if
            over 1+ c@ [char] x = if
                over 2 + (d0x-a) !  dup 2 - (d0x-u) !
            then
        then
        1 /string
    repeat 2drop
    (d0x-a) @ ?dup if (d0x-u) @ true else false then ;
: (d-hexnum) ( a u -- n true | false )      \ leading hex digits -> n
    dup 0= if 2drop false exit then
    over c@ (hex-digit?) 0= if 2drop false exit then
    base @ >r hex  0 0 2swap >number  r> base !
    2drop drop true ;

\ --- one-time probes (re-run until they succeed, so installing objdump
\ --- mid-session just works) ---
create (d-bin) 256 allot   variable (d-bin#)    \ path of the running binary
create (d-arch) 64 allot   variable (d-arch#)   \ objdump -m name for -b binary
create (d-tmp) 256 allot   variable (d-tmp#)    \ mktemp'd dump-file path
create (d-od) 64 allot     variable (d-od#)     \ which objdump to run
0 value (d-ready)

: (d-keep) ( a u buf len-var -- )           \ copy a string into buf, note len
    >r  over r> !  swap move ;
: (d-elf-arch) ( -- f )     \ read (d-bin)'s ELF header, set (d-arch)
    (d-bin) (d-bin#) @ r/o open-file  if drop false exit then
    >r  (cmd-ln) 20 r@ read-file  r> close-file drop   ( u ior )
    if drop false exit then  20 < if false exit then
    (cmd-ln) l@ $464C457F <> if false exit then      \ "\x7fELF"
    (cmd-ln) 18 + w@                                 \ e_machine
    dup $3E = if drop s" i386:x86-64" (d-arch) (d-arch#) (d-keep) true exit then
    dup $B7 = if drop s" aarch64"     (d-arch) (d-arch#) (d-keep) true exit then
    drop false ;
: (d-try-bin) ( a u -- f )      \ adopt this path if it's an ELF we understand
    dup 255 > if 2drop false exit then
    (d-bin) (d-bin#) (d-keep)  (d-elf-arch) ;
: (d-find-bin) ( -- f )         \ locate the running binary, learn its arch
    \ argv[0] first: it names the right file even under qemu user-mode
    \ emulation, where /proc/$PPID/exe seen from a (native) child shell
    \ is qemu itself, not this Forth
    0 arg dup 0<> if
        over c@ [char] / = if
            (d-try-bin) if true exit then
        else                            \ relative: resolve from the launch dir
            (cmd0) (startup-dir) (cmd+) s" /" (cmd+) (cmd+)
            (cmd$) (d-try-bin) if true exit then
        then
    else 2drop then
    (cmd0) s" readlink /proc/$PPID/exe" (cmd+)
    (cmd-line1) 0= if false exit then
    (cmd-ln) swap (d-try-bin) ;
: (d-probe) ( -- f )                        \ true when dis is usable
    (d-ready) if true exit then
    (cmd0) s" command -v objdump" (cmd+)
    (cmd-line1) 0= if ." dis: needs objdump (binutils) on PATH" cr false exit then
    drop
    (d-find-bin) 0= if
        ." dis: cannot identify the running binary" cr false exit then
    \ decoding aarch64 may need the cross objdump (a plain host objdump
    \ under qemu user-mode emulation often has no aarch64 support)
    s" objdump" (d-od) (d-od#) (d-keep)
    (d-arch) (d-arch#) @ s" aarch64" compare 0= if
        (cmd0) s" command -v aarch64-linux-gnu-objdump" (cmd+)
        (cmd-line1) if drop
            s" aarch64-linux-gnu-objdump" (d-od) (d-od#) (d-keep) then
    then
    1 to (d-ready)  true ;

\ --- output: filter to code lines, annotate call targets ---
: (d-code-line?) ( a u -- f )               \ instruction/symbol lines start
    (d-lead-bl) dup 0= if 2drop false exit then   \ with a hex address
    drop c@ (hex-digit?) ;
: (d-annotate) ( a u -- )   \ print the line; name the address it targets
    2dup type
    (d-last-0x) if
        (d-hexnum) if
            (xt>nt) ?dup if ."   \ " (nt>name) type then
        then
    then cr ;

\ --- dictionary words: dump the bytes, decode as raw binary ---
: (d-rm-tmp) ( -- ) (d-tmp) (d-tmp#) @ (sh-rm) ;    \ error paths; the happy
: (d-dict) ( xt len -- )                            \ path rm's in-command
    s" basicforth-dis" (sh-mktemp) 0= if
        2drop ." dis: cannot create a temp file (TMPDIR too long?)" cr exit then
    (cmd-ln) swap (d-tmp) (d-tmp#) (d-keep)
    (d-tmp) (d-tmp#) @ w/o open-file        ( xt len fileid ior )
    if drop 2drop ." dis: cannot open the temp file" cr (d-rm-tmp) exit then
    >r  2dup r@ write-file  r> close-file drop   ( xt len ior )
    if 2drop ." dis: temp file write failed" cr (d-rm-tmp) exit then
    (cmd0) (d-od) (d-od#) @ (cmd+)
    s"  -D -b binary -m " (cmd+)  (d-arch) (d-arch#) @ (cmd+)
    s"  --adjust-vma=" (cmd+)  over (cmd+x)
    s"  " (cmd+)  (d-tmp) (d-tmp#) @ (cmd+q)
    s" ; rm -f " (cmd+)  (d-tmp) (d-tmp#) @ (cmd+q)
    2drop
    (cmd-open) 0= if ." dis: objdump failed to start" cr (d-rm-tmp) exit then
    begin (cmd-read) while
        \ instruction lines are indented; col-0 lines ("Disassembly of
        \ section", the synthetic <.data> label) are objdump boilerplate
        (cmd-ln) swap
        2dup (d-code-line?) if
            over c@ bl = if (d-annotate) else 2drop then
        else 2drop then
    repeat (cmd-close) ;

\ --- primitives: let objdump bound the code by symbol ---
variable (d-in)                             \ inside our symbol's block?
: (d-prim) ( xt -- )
    (cmd0) (d-od) (d-od#) @ (cmd+)
    s"  -d --start-address=" (cmd+)  (cmd+x)
    s"  " (cmd+)  (d-bin) (d-bin#) @ (cmd+q)
    (cmd-open) 0= if ." dis: objdump failed to start" cr exit then
    0 (d-in) !
    begin (cmd-read) while
        (cmd-ln) swap
        2dup (d-code-line?) 0= if 2drop else
            over c@ bl <> if                \ column-0 address: a symbol header
                \ ... unless it's "Disassembly of section .text:", whose 'D'
                \ passes the hex test — real headers have 16 hex digits
                over 1+ c@ (hex-digit?) 0= if 2drop else
                (d-in) @ if 2drop (cmd-close) exit then   \ next symbol: done
                1 (d-in) !  type cr  then
            else
                (d-in) @ if (d-annotate) else 2drop then
            then
        then
    repeat (cmd-close)
    (d-in) @ 0= if ." dis: no code at that address (stripped binary?)" cr then ;

\ --- dis <name> ---
: (d-banner) ( xt nt -- xt nt )
    dup (nt>name) type ." : "
    dup (nt>clen) ?dup if
        u. ." bytes at " over h.addr ."  (dictionary)" cr
    else
        ." primitive at " over h.addr ."  (in the binary)" cr
    then ;
: dis ( "name" -- )                         \ disassemble a word's machine code
    parse-name dup 0= if 2drop ." usage: dis <word>" cr exit then
    find ?dup 0= if ." ? " type cr exit then drop   ( xt )
    (d-probe) 0= if drop exit then
    dup (xt>nt) dup 0= if 2drop ." dis: word has no dictionary entry" cr exit then
    (d-banner)
    dup (nt>clen) ?dup if nip (d-dict) else drop (d-prim) then ;
