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
\  - dictionary words (header CodeLen != 0): the word is scanned for the
\    compiler's two inline-data idioms (call lit + value:8, and the s"
\    runtime + len:8 + chars), then decoded as alternating code spans
\    (objdump -D -b binary over a temp file) and data spans printed as
\    what they are (\ literal: 5, \ s" hi", \ xt: dup). Call targets
\    matching dictionary words are annotated with the word's name --
\    the readable half no external tool can do alone. The idiom
\    addresses are self-calibrated from :noname probes at load time.
\  - primitives (CodeLen == 0): the code sits in the (unstripped,
\    no-pie) binary itself; `objdump -d --start-address` finds it and
\    the symbol table both bounds it and labels its call targets.
\
\ A Linux dev tool: it shells out (via shellutil.fs -- safe quoting,
\ capture, temp files), so it needs /bin/sh and objdump on PATH, and
\ reports gracefully when either is missing. Known limit: :noname xts
\ have no header, so there is nothing to look up.
\ See docs/Disassembler.md.

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
: (d-hexdig) ( u -- ch ) dup 10 < if [char] 0 + else 10 - [char] a + then ;
: (d-h.)  ( u -- )                          \ lowercase hex, objdump-style
    dup 4 rshift ?dup if recurse then  15 and (d-hexdig) emit ;
: (d-h2.) ( b -- ) dup 4 rshift (d-hexdig) emit  15 and (d-hexdig) emit ;

\ --- the compiler's inline-data idioms ---
\ Compiled code embeds data in the instruction stream in exactly two
\ shapes: CALL lit + value:8, and CALL s_quote_runtime + len:8 + chars
\ (4-aligned on ARM64). A linear disassembler decodes that data as
\ garbage, so the dict path splits the word into code spans (objdump)
\ and data spans (printed as what they are). The helper addresses are
\ SELF-CALIBRATED at load time: we compile :noname probes and read the
\ call targets back out of our own bytes — no reliance on internal
\ names, and automatic recalibration if the core ever moves them.
0 value (d-x86?)    0 value (d-lit)    0 value (d-sq)
: (sext32) ( u -- n ) dup $80000000 and if $100000000 - then ;
: (sext26) ( u -- n ) dup $2000000 and if $4000000 - then ;
: (d-call@) ( addr -- target true | false ) \ decode a CALL/BL at addr
    (d-x86?) if
        dup c@ $E8 <> if drop false exit then
        dup 1+ l@ (sext32)  swap 5 + +  true
    else
        dup l@ dup $FC000000 and $94000000 <> if 2drop false exit then
        $3FFFFFF and (sext26) 4 *  +  true
    then ;
: (d-cs) ( -- u ) (d-x86?) if 5 else 4 then ;   \ CALL/BL size
: (d-lit?) ( p -- f )       \ (calibration failure -> 0 -> never matches)
    (d-lit) 0= if drop false exit then
    (d-call@) if (d-lit) = else false then ;
: (d-sq?)  ( p -- f )
    (d-sq) 0= if drop false exit then
    (d-call@) if (d-sq) = else false then ;
: (d-sq-size) ( p -- u )    \ inline data size of the string idiom at p
    (d-cs) + @  8 +  (d-x86?) 0= if 3 + -4 and then ;
: (d-target1) ( xt -- addr | 0 )    \ first CALL/BL target in a probe word
    (d-x86?) 0= if 4 + then         \ ARM64 colon words open with STP
    (d-call@) 0= if 0 then ;

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
            dup (xt>nt) ?dup if
                nip ."   \ " (nt>name) type
            else                        \ the string runtime has no entry,
                (d-sq) = if             \ but the scanner knows its address
                    ."   \ (s" [char] " emit ." )"
                then
            then
        then
    then cr ;

\ --- dictionary words: split into code spans (objdump) + data spans ---
: (d-rm-tmp) ( -- ) (d-tmp) (d-tmp#) @ (sh-rm) ;
variable (d-xt)                             \ the word's code start (for vma)
: (d-objdump) ( start end -- )              \ decode one code span
    (cmd0) (d-od) (d-od#) @ (cmd+)
    s"  -D -b binary -m " (cmd+)  (d-arch) (d-arch#) @ (cmd+)
    s"  --adjust-vma=" (cmd+)  (d-xt) @ (cmd+x)
    s"  --stop-address=" (cmd+)  (cmd+x)
    s"  --start-address=" (cmd+)  (cmd+x)
    s"  " (cmd+)  (d-tmp) (d-tmp#) @ (cmd+q)
    (cmd-open) 0= if ." dis: objdump failed to start" cr exit then
    begin (cmd-read) while
        \ instruction lines are indented; col-0 lines ("Disassembly of
        \ section", the synthetic <.data> label) are objdump boilerplate
        (cmd-ln) swap
        2dup (d-code-line?) if
            over c@ bl = if (d-annotate) else 2drop then
        else 2drop then
    repeat (cmd-close) ;
: (d-data.) ( a u -- )      \ synthetic-line prefix: addr + capped hex column
    2 spaces  over (d-h.) ." :" 9 emit
    dup 16 min 0 do  over i + c@ (d-h2.) space  loop
    dup 16 > if ." .. " then  2drop  9 emit ;
: (d-text.) ( a u -- )      \ string body, unprintables as dots, capped
    dup 40 min 0 ?do
        over i + c@ dup 32 < over 126 > or if drop [char] . then emit
    loop
    40 > if ." ..." then  drop ;
: (d-lit-line) ( a -- )     \ a = the 8 inline bytes of a literal
    dup 8 (d-data.)
    @ dup (xt>nt) ?dup if nip ." \ xt: " (nt>name) type cr exit then
    ." \ literal: "
    dup -65536 65536 within if . else ." 0x" (d-h.) then cr ;
: (d-sq-line) ( a u -- )    \ a = len:8 + chars(+pad), u = total size
    2dup (d-data.)
    drop  dup @ swap 8 + swap           ( c-addr len )
    ." \ s" [char] " emit space  (d-text.)  [char] " emit cr ;
variable (d-p)  variable (d-span)  variable (d-end)
: (d-flush) ( end -- )      \ objdump the pending code span up to end
    (d-span) @ over 2dup < if (d-objdump) else 2drop then drop ;
: (d-scan) ( xt len -- )    \ alternate code spans and data spans
    over + (d-end) !  dup (d-span) !  (d-p) !
    begin (d-p) @ (d-end) @ < while
        (d-p) @ (d-lit?) if
            (d-p) @ (d-cs) +  dup (d-flush)         \ span includes the call
            dup (d-lit-line)
            8 +  dup (d-span) !  (d-p) !
        else (d-p) @ (d-sq?) if
            (d-p) @ (d-cs) +  dup (d-flush)
            (d-p) @ (d-sq-size)  2dup (d-sq-line)
            +  dup (d-span) !  (d-p) !
        else
            (d-p) @  (d-x86?) if 1+ else 4 + then  (d-p) !
        then then
    repeat
    (d-end) @ (d-flush) ;
: (d-dict) ( xt len -- )
    over (d-xt) !
    s" basicforth-dis" (sh-mktemp) 0= if
        2drop ." dis: cannot create a temp file (TMPDIR too long?)" cr exit then
    (cmd-ln) swap (d-tmp) (d-tmp#) (d-keep)
    (d-tmp) (d-tmp#) @ w/o open-file        ( xt len fileid ior )
    if drop 2drop ." dis: cannot open the temp file" cr (d-rm-tmp) exit then
    >r  2dup r@ write-file  r> close-file drop   ( xt len ior )
    if 2drop ." dis: temp file write failed" cr (d-rm-tmp) exit then
    (d-scan)
    (d-rm-tmp) ;

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

\ --- self-calibration (runs now, at load) ---
\ Compile two probes and read the compiler's own idiom addresses out of
\ their first call instructions. If either read fails, its address stays
\ 0 and the scanner simply never splits (stage-1 whole-range listings).
:noname 0 ;                                 ( lit-probe-xt )
:noname s" x" 2drop ;                       ( lit-probe-xt str-probe-xt )
over c@ $E8 = to (d-x86?)
swap (d-target1) to (d-lit)
(d-target1) to (d-sq)
