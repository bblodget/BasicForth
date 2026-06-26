\ BasicForth core.fs -- Forth-defined words
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded automatically at startup. These words build on the
\ ASM primitives in core.s.

\ Output helpers
: CR    10 emit ;
: SPACE 32 emit ;
: BL    32 ;

\ Boolean constants
: TRUE  -1 ;
: FALSE  0 ;

\ Arithmetic helpers
: MOD   /mod drop ;
: /     /mod nip ;

\ Stack helpers
: CELL+ 8 + ;
: CELLS 8 * ;

\ Comparison
: <>    = invert ;
: 0<>   0= invert ;

\ Derived stack words
: -ROT    rot rot ;
: 2OVER   3 pick 3 pick ;
: 2SWAP   rot >r rot r> ;

\ Derived arithmetic
: 2*      1 lshift ;
: */      >r * r> / ;

\ Output helpers
: SPACES  dup 0 > if 0 do space loop else drop then ;

\ String helpers
: COUNT   dup 1+ swap c@ ;

\ Number base
: DECIMAL   #10 base ! ;
: HEX       $10 base ! ;

\ Pictured numeric output
\ Builds strings right-to-left in PAD buffer.
: <#        pad 68 + hld ! ;
: HOLD      hld @ 1- dup hld ! c! ;
: SIGN      0< if 45 hold then ;
: >DIGIT    ( n -- char ) dup 10 < if 48 + else 10 - 65 + then ;
: #         ( ud-lo ud-hi -- qd-lo qd-hi )
            \ Step 1: divide ud-hi by BASE (using 0:ud-hi as double)
            swap >r               ( ud-hi                R: ud-lo )
            0 base @ um/mod       ( rem-hi quot-hi       R: ud-lo )
            \ Step 2: divide (rem-hi:ud-lo) by BASE
            r> swap >r            ( rem-hi ud-lo         R: quot-hi )
            swap base @ um/mod    ( rem quot-lo          R: quot-hi )
            \ rem is the digit, convert and HOLD
            swap >digit hold      ( quot-lo              R: quot-hi )
            r> ;                  ( qd-lo qd-hi )
: #S        begin # 2dup or 0= until ;
: #>        2drop hld @ pad 68 + over - ;

\ Double-cell helpers
: DNEGATE   ( d-lo d-hi -- d-lo' d-hi' )
            invert swap invert 1+ swap over 0= if 1+ then ;
: DABS      ( d-lo d-hi -- d-lo d-hi )
            dup 0< if dnegate then ;

\ Formatted output
: U.        0 <# #S #> type space ;
: .         dup >r s>d dabs <# #S r> sign #> type space ;
: .R        >r dup >r s>d dabs <# #S r> sign #> r> over - spaces type ;

\ Redefine */ using double-width intermediate
: */MOD     >r m* r> fm/mod ;
: */        */mod nip ;

\ Memory operations
: +!        dup @ rot + swap ! ;
: 2!        swap over ! cell+ ! ;
: 2@        dup cell+ @ swap @ ;
: CHAR+     1+ ;
: CHARS     ;
: FILL      ( c-addr u char -- )
            -rot begin dup 0 > while
                >r 2dup c! 1+ r> 1-
            repeat drop 2drop ;
: MOVE      ( addr1 addr2 u -- )
            dup 0 > if
                >r 2dup u< if
                    \ dest < src: copy forward
                    r> 0 do over i + c@ over i + c! loop
                else
                    \ dest >= src: copy backward
                    r> begin dup 0 > while
                        1- >r
                        over r@ + c@    ( src dest byte )
                        over r@ + c!    ( src dest )
                        r>
                    repeat drop
                then 2drop
            else drop 2drop then ;
: ALIGN     here 7 + -8 and here - allot ;
: ALIGNED   7 + -8 and ;

\ Character helpers
\ CHAR ( "name" -- c )  first character of the next word; 0 if there is no next
\ word (so `char` with nothing after it does not fetch a stray address). Note:
\ CHAR parses at run time — inside a definition use [CHAR] to bake in a literal.
: CHAR      parse-word if c@ else drop 0 then ;

\ System words
: ENVIRONMENT?  ( c-addr u -- false ) 2drop false ;

\ Helper: convert char to digit value, or -1 if invalid
: >DIGIT?   ( char -- n true | false )
            dup 48 < if drop false exit then
            dup 58 < if 48 - dup base @ < if true else drop false then exit then
            dup 65 < if drop false exit then
            dup 91 < if 55 - dup base @ < if true else drop false then exit then
            dup 97 < if drop false exit then
            dup 123 < if 87 - dup base @ < if true else drop false then exit then
            drop false ;

\ >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
\ Convert string to number, accumulating into double ud.
\ Stack order: ( ud-lo ud-hi c-addr u ) with u on top.
\ Stops at first non-digit character.
: >NUMBER  ( ud-lo ud-hi c-addr u -- ud-lo' ud-hi' c-addr' u' )
    begin dup 0 > while
        over c@ >digit?
        0= if exit then             ( ud-lo ud-hi c-addr u digit )
        \ Stash c-addr and u on return stack, keep digit on data stack
        swap >r swap >r             ( ud-lo ud-hi digit  R: u c-addr )
        rot rot                     ( digit ud-lo ud-hi )
        swap >r                     ( digit ud-hi  R: u c-addr ud-lo )
        base @ *                    ( digit ud-hi*base )
        r> base @ um*               ( digit ud-hi*base prod-lo prod-hi )
        rot +                       ( digit prod-lo new-ud-hi )
        -rot +                      ( new-ud-hi new-ud-lo )
        swap                        ( new-ud-lo new-ud-hi )
        r> 1+ r> 1-                 ( new-ud-lo new-ud-hi c-addr+1 u-1 )
    repeat ;

\ ABORT" ( flag "ccc" -- )  IMMEDIATE, COMPILE_ONLY
\ If flag is true at runtime, print message and abort.
: ABORT"  postpone if  postpone s"  postpone type  postpone abort  postpone then ; immediate

\ WORD ( char "<chars>ccc<char>" -- c-addr )
\ Parse delimited string, return counted string at HERE.
: WORD
    drop                            \ ignore delimiter (use whitespace)
    parse-word                      ( c-addr u )
    dup here c!                     \ store count at HERE
    here 1+ swap                    ( c-addr here+1 u )
    dup >r                          ( c-addr here+1 u  R: u )
    move                            \ copy string to HERE+1
    r> here 1+ + 0 swap c!         \ null-terminate (optional)
    here ;                          \ return counted string address

\ Core extension words
: 0>        0 > ;
: U>        swap u< ;
: WITHIN    over - >r - r> u< ;
: ERASE     0 fill ;
: U.R       >r 0 <# #S #> r> over - spaces type ;
: HOLDS     begin dup 0 > while 1- 2dup + c@ hold repeat 2drop ;
: .(        \ parse and print text up to the closing paren
            [char] ) parse type ; immediate

\ Defining words
: VARIABLE  create 1 cells allot ;

\ Standard alias for PARSE-WORD
: PARSE-NAME  parse-word ;

\ String words (17)
: /STRING   ( c-addr u n -- c-addr+n u-n ) rot over + -rot - ;
: CMOVE     ( c-addr1 c-addr2 u -- )
            dup 0 > if 0 do over i + c@ over i + c! loop 2drop
            else drop 2drop then ;
: CMOVE>    ( c-addr1 c-addr2 u -- )
            dup 0 > if
                begin dup 0 > while
                    1- >r over r@ + c@ over r@ + c! r>
                repeat drop
            then 2drop ;
: -TRAILING ( c-addr u1 -- c-addr u2 )
            begin dup 0> while
                2dup + 1- c@ 32 <> if exit then
                1-
            repeat ;
: BLANK     ( c-addr u -- ) 32 fill ;
\ COMPARE: use variables to avoid deep stack juggling
variable (cmp-a1)  variable (cmp-u1)
variable (cmp-a2)  variable (cmp-u2)
: COMPARE   ( c-addr1 u1 c-addr2 u2 -- n )
    (cmp-u2) ! (cmp-a2) ! (cmp-u1) ! (cmp-a1) !
    (cmp-u1) @ (cmp-u2) @ min   ( min-len )
    0 ?do
        (cmp-a1) @ i + c@
        (cmp-a2) @ i + c@
        2dup <> if
            < if -1 else 1 then
            unloop exit
        then 2drop
    loop
    (cmp-u1) @ (cmp-u2) @
    2dup = if 2drop 0
    else < if -1 else 1 then then ;

\ Programming-Tools words (15)
: ?     ( a-addr -- ) @ . ;

\ Hex output helpers for DUMP
: H.2   ( u -- ) base @ >r hex
        0 <# # # #> type
        r> base ! ;

: H.ADDR ( u -- ) base @ >r hex
        0 <# # # # # # # # # #> type
        r> base ! ;

\ DUMP uses variables to keep the logic simple
variable (dump-addr)  variable (dump-len)
: DUMP  ( addr u -- )
        (dump-len) ! (dump-addr) !
        begin (dump-len) @ 0 > while
            (dump-addr) @ h.addr ." : "
            (dump-len) @ 16 min   ( n -- bytes this row )
            dup 0 do (dump-addr) @ i + c@ h.2 space loop
            dup 16 < if 16 over - 0 do ."    " loop then
            ."  |"
            dup 0 do
                (dump-addr) @ i + c@ dup 32 < over 126 > or
                if drop 46 then emit
            loop
            ." |" cr
            dup (dump-addr) @ + (dump-addr) !
            negate (dump-len) @ + (dump-len) !
        repeat ;

\ Key constants (abstract codes matching platform_key escape parsing)
27  constant KEY_ESCAPE
129 constant KEY_UP
130 constant KEY_DOWN
131 constant KEY_RIGHT
132 constant KEY_LEFT

\ Random number generator (Linear Congruential Generator)
\ seed = (seed * 1103515245 + 12345) mod 2^64
variable seed  ms@ seed !
: random ( -- n ) seed @ 1103515245 * 12345 + dup seed ! ;
: rnd    ( n -- 0..n-1 ) random swap mod abs ;

\ Double-Number words (8)
: D+    ( d1-lo d1-hi d2-lo d2-hi -- d3-lo d3-hi )
        rot + >r              ( d1-lo d2-lo  R: hi-sum )
        over + dup rot u< if r> 1+ else r> then ;
: D-    ( d1 d2 -- d3 ) dnegate d+ ;
: D0=   ( d -- flag ) or 0= ;
: D0<   ( d -- flag ) nip 0< ;
: D=    ( d1 d2 -- flag ) d- d0= ;
: D<    ( d1 d2 -- flag ) d- d0< ;
: D.    ( d -- ) dup >r dabs <# #s r> sign #> type space ;

\ File-output words (fileid = raw OS file descriptor)
0 constant stdin
1 constant stdout
2 constant stderr

\ WRITE-FILE ( c-addr u fileid -- ior ) is an ASM primitive in core.s.
\ WRITE-LINE writes the string then a single newline to the same fileid,
\ returning the ior of the first write that fails (0 if both succeed).
create (write-nl) 10 c,
: write-line ( c-addr u fileid -- ior )
        dup >r write-file ?dup if r> drop exit then
        (write-nl) 1 r> write-file ;

\ READ-LINE ( c-addr u1 fileid -- u2 flag ior )
\ Reads one line from fileid into c-addr, one byte at a time via READ-FILE,
\ always reading through the line terminator so every call returns exactly one
\ line. At most u1 characters are stored (u2 <= u1); the terminator (LF, with a
\ CR immediately before it removed so CRLF text reads cleanly) is consumed but
\ not stored. flag is false only at end of file with nothing read, true
\ otherwise; ior = 0 (incl. normal EOF) or a positive errno.
\
\ A line longer than u1 fills the buffer, then the remaining characters of that
\ line are read and discarded, so the next call starts at the following line.
\ (One read-line = one line; an over-long line is truncated, not continued — a
\ deliberate choice over the ANS "return the rest next call" behavior.) No state
\ is kept between calls, so reading several files or reused fds is always safe.
\ One read() syscall per byte — fine for source/text; a buffered version can
\ replace this later behind the same interface.
variable (rl-fid)                       \ open file id
variable (rl-buf)                       \ buffer base address
variable (rl-max)                       \ buffer size (u1)
create   (rl-ch) 1 allot                \ 1-byte scratch for each read
: read-line ( c-addr u1 fileid -- u2 flag ior )
        (rl-fid) ! (rl-max) ! (rl-buf) !
        0                               ( count )
        begin
            (rl-ch) 1 (rl-fid) @ read-file   ( count u2 ior )
            ?dup if                     \ I/O error
                >r drop                 ( count ; ior on R )
                dup 0> r> exit          ( count flag ior )
            then
            0= if                       \ u2 = 0 → end of file
                dup 0> 0 exit           ( count flag ior )
            then
            (rl-ch) c@                  ( count ch )
            dup 10 = if                 \ LF → end of line
                drop                    ( count )
                dup 0> if               \ strip a trailing CR if present
                    dup 1- (rl-buf) @ + c@ 13 = if 1- then
                then
                true 0 exit             ( count flag ior )
            then
            over (rl-max) @ < if        \ room left? store it; else discard
                over (rl-buf) @ + c!  1+    ( count+1 )
            else
                drop                    ( count )  \ buffer full: drop the char
            then
        again ;

\ File-access methods (fam): the values passed to OPEN-FILE / CREATE-FILE.
\ They are the OS open() flags; BIN is a no-op (Linux has no text/binary mode).
0 constant r/o
1 constant w/o
2 constant r/w
: bin ( fam1 -- fam2 ) ;

\ ===== Dynamic memory: ANS MEMORY wordset =====
\ A heap separate from the dictionary, one mmap per allocation. Each block has
\ a one-cell header at its mmap base recording the mapped length (so FREE /
\ RESIZE know how much to unmap); the address handed to the caller is
\ base + 1 cell, still cell-aligned. The heap is data-only (no execute).
\ Allocations are page-granular, so this suits a few large buffers rather than
\ many tiny ones; the interface can be re-backed by a finer allocator later.

\ ALLOCATE ( u -- a-addr ior )  reserve u bytes; ior 0 on success. A zero-size
\ request is rejected with a non-zero ior (no allocation), matching gforth.
: allocate ( u -- a-addr ior )
    dup 0= if  drop 0 22 exit  then   \ reject 0 bytes (EINVAL); nothing mapped
    cell+ dup (mmap-anon)             ( total addr )  \ map header + payload
    dup 0< if  nip negate 0 swap exit  then           ( 0 errno )  \ mmap failed
    tuck !                            ( base )  \ stash total length in header
    cell+ 0 ;                         ( a-addr 0 )

\ FREE ( a-addr -- ior )  return a block from ALLOCATE/RESIZE to the system.
\ A null a-addr (e.g. a failed ALLOCATE's result) is rejected with a non-zero
\ ior instead of dereferencing the header at a-addr - cell.
: free ( a-addr -- ior )
    dup 0= if  drop 22 exit  then     \ reject null (EINVAL); don't deref
    1 cells -                         ( base )  \ step back to the header
    dup @ (munmap)                    ( n )    \ unmap base for its stored length
    negate ;                          \ 0 stays 0; -errno → positive ior

\ RESIZE ( a-addr1 u -- a-addr2 ior )  change a block's size, preserving its
\ contents up to the smaller of old/new. May move the block. On failure the
\ original block is unchanged and a-addr2 = a-addr1. A null a-addr1 is rejected
\ with a non-zero ior (it would otherwise deref a wild header).
: resize ( a-addr1 u -- a-addr2 ior )
    over 0= if  drop 22 exit  then    ( 0 ior )  \ reject null a-addr1
    over 1 cells - @ 1 cells -        ( a1 u olduser )  \ old payload byte count
    over min >r                       ( a1 u )  \ R: bytes to copy = min(u,old)
    dup allocate                      ( a1 u a2 ior )
    ?dup if                           \ allocate failed → keep original
        >r 2drop r> r> drop exit      ( a1 ior )
    then
    nip 2dup r> move                  ( a1 a2 )  \ copy payload into new block
    swap free ;                       ( a2 ior )  \ release old; ior from FREE

\ ===== Dictionary restore points: MARKER =====
\ MARKER <name> defines <name> as a word that, when executed, restores HERE and
\ LATEST to their values just before the marker — forgetting <name> and every
\ definition made after it (and reclaiming the dictionary space). The modern
\ replacement for FORGET; handy for an edit/compile/run loop.
\
\ Like CONSTANT (create , does> @), but it snapshots HERE/LATEST *before* CREATE
\ builds its own header, stores them in the body, and restores instead of
\ fetching. Executing the marker sets the registers back via (restore-dict); its
\ now-orphaned code sits above the new HERE and is overwritten by the next word.
: marker ( "name" -- )
    here (latest@)                    ( saved-here saved-latest )
    create swap , ,                   \ body: [saved-here][saved-latest]
  does> ( body -- )
    dup @ swap cell+ @ (restore-dict) ;

\ ===== Session persistence (SAVE) =====
\ Capture the source text of interactive definitions into a heap-backed log,
\ which SAVE writes to session.fs. At startup an interactive session seeds the
\ log from an existing session.fs and re-INCLUDEs it. The asm REPL drives this
\ through three hook words registered with (hook!) (0=boot 1=line 2=reset).
\
\ A buffer is a 3-cell struct: [ addr  len  cap ]. addr is a heap block (0 until
\ first use), len the bytes in use, cap the bytes allocated. It doubles on grow.

64 constant (buf-min)
variable (ap-len)                       \ scratch: byte count for (buf-append)

: (buf-ensure) ( n buf -- )             \ ensure room for n more bytes
    >r                                  ( n )                  \ R: buf
    r@ cell+ @ +                        ( need = len + n )
    r@ 2 cells + @                      ( need cap )
    2dup u> 0= if  2drop r> drop exit  then    \ cap >= need → already room
    drop                                ( need )
    r@ 2 cells + @ 2* max               ( newcap )  \ = max of need and 2*cap
    (buf-min) max                       ( newcap )
    r@ @ 0= if                          \ no block yet → allocate
        dup allocate  abort" SAVE: out of memory"   ( newcap a )
        r@ !
    else                                \ grow existing block
        r@ @ over resize  abort" SAVE: out of memory"  ( newcap a2 )
        r@ !
    then
    r@ 2 cells + !                      \ buf.cap = newcap
    r> drop ;

: (buf-append) ( c-addr u buf -- )      \ append u bytes to the buffer
    >r                                  ( c-addr u )           \ R: buf
    dup (ap-len) !                      \ remember u (move consumes it)
    r@ (buf-ensure)                     ( c-addr )
    r@ @ r@ cell+ @ +                   ( c-addr dest = addr+len )
    (ap-len) @ move                     ( )
    (ap-len) @ r@ cell+ +!             \ buf.len += u
    r> drop ;

: (buf-append-buf) ( src dst -- )       \ append all of src's bytes to dst
    >r  dup @ swap cell+ @  r> (buf-append) ;

: (buf-reset) ( buf -- )  0 swap cell+ ! ;   \ keep the allocation, length := 0

\ The two live buffers and the capture bookkeeping.
create (log)  3 cells allot             \ accumulated definitions (seed + session)
create (pend) 3 cells allot             \ lines of the definition being entered
variable (cap-latest)                   \ LATEST at the start of the pending group
variable (skip-capture)                 \ one-shot: skip logging the next line (RELOAD)
variable (session-on)                   \ true only after (session-init) ran — i.e.
                                        \ an interactive session (scopes SAVE/RELOAD)
create (nl) 10 c,                       \ a single newline byte

\ SEE directory: an index over (log) so SEE can show a word's source. Each
\ captured group adds one fixed 3-cell record — [log-off, log-len, xt] — to
\ (dir), where xt is the execution token FIND returns for the just-defined word.
\ SEE keys off the live word's xt (not its name), so it always shows the source
\ of the definition that is actually in force: a redefinition shadows the older
\ source, and a definition forgotten by -session or a marker — which restores an
\ older same-named word — never matches, so no stale source is shown. (dir)
\ tracks (log)'s lifecycle (reset together in (seed-log)), so SEE covers words
\ defined interactively this session (seeded/reloaded definitions live in
\ session.fs, editable on disk).
create (dir)     3 cells allot          \ cell buffer: 3-cell records (see above)
create (dir-rec) 3 cells allot          \ scratch: one record being built

\ entry → the execution token FIND returns: load the CodePtr at the aligned
\ offset align8(9 + name-len) past the entry. Mirrors FIND's xt calculation.
: (xt-of) ( entry -- xt )
    dup 8 + c@ 31 and  9 +  7 + -8 and  +  @ ;

\ (dir-add): record one captured group. entry = LATEST (the header just linked).
: (dir-add) ( log-off log-len entry -- )
    (xt-of)                             ( log-off log-len xt )
    (dir-rec) 2 cells + !               \ rec[2] = xt
    (dir-rec) cell+ !                   \ rec[1] = log-len
    (dir-rec) !                         \ rec[0] = log-off
    (dir-rec) 3 cells (dir) (buf-append) ;  \ append the 24-byte record

\ (capture-line): the asm REPL calls this after each successfully interpreted
\ line, passing the current LATEST. Accumulate the line in (pend); when STATE
\ returns to interpret, decide whether the group defined a word — flush it to the
\ log — or not — discard it. A line is a definition only when LATEST moved
\ *forward* (a new header linked), so transient actions, bare ALLOT/,/C, and
\ marker runs / -session (which move LATEST *backward*) are all not captured.
\ RELOAD sets (skip-capture) so its own line is never logged either.
: (capture-line) ( c-addr u latest -- )
    >r                                  ( c-addr u )   \ R: latest
    (pend) (buf-append)                 \ append the raw line...
    (nl) 1 (pend) (buf-append)          \ ...plus a newline
    state @ if  r> drop exit  then      \ still compiling → wait for more lines
    (skip-capture) @ if                 \ RELOAD etc.: discard, don't log
        false (skip-capture) !
        (pend) (buf-reset)  r> (cap-latest) !  exit
    then
    r@ (cap-latest) @ u> if             \ LATEST moved forward → a word was defined
        (log) cell+ @  (pend) cell+ @    \ log-off (pre-flush) and group length
        (pend) (log) (buf-append-buf)    \ flush the group into the log FIRST, so an OOM
        r@ (dir-add)                     \ here aborts before any SEE record is written;
    then                                \ only index source that is actually in the log
    (pend) (buf-reset)                  \ clear pending
    r> (cap-latest) ! ;                 \ next group's baseline = current LATEST

\ (capture-reset): called at the top of the REPL loop with the current LATEST.
\ Drops a pending partial definition left behind by a line error or fault (only
\ when not compiling), and resyncs the LATEST baseline. Also clears a stuck
\ (skip-capture): RELOAD sets that one-shot flag and expects the next
\ (capture-line) to consume it, but if RELOAD aborts/faults first (e.g. an
\ out-of-memory in seed-log) that never happens — so clear it here, else the
\ next real definition would be silently not captured.
: (capture-reset) ( latest -- )
    false (skip-capture) !
    state @ if  drop exit  then
    (pend) cell+ @ if  (pend) (buf-reset)  then
    (cap-latest) ! ;

: (slurp-into-log) ( fileid -- )        \ append a whole file to the log
    >r
    begin
        4096 (log) (buf-ensure)
        (log) @ (log) cell+ @ +         ( dest = addr+len )
        4096 r@ read-file               ( u2 ior )
        abort" SAVE: read error"        ( u2 )
        dup 0= if  drop r> drop exit  then    \ end of file
        (log) cell+ +!                  \ log.len += u2
    again ;

\ (seed-log): reset the log and load the current session.fs's bytes into it, so
\ SAVE rewrites the file's content (plus later additions) rather than drifting
\ from a hand-edited file. No-op (empty log) when session.fs is absent.
: (seed-log) ( -- )
    (log) (buf-reset)
    (dir) (buf-reset)                   \ SEE index tracks the log's lifecycle
    s" session.fs" r/o open-file        ( fileid ior )
    if drop exit then                   \ no session.fs → log stays empty
    dup (slurp-into-log)                \ copy its text into the log
    close-file drop ;

\ (session-init): runs once at interactive startup (after core.fs, before
\ session.fs is loaded). Records the restore point so -session/RELOAD rewind to
\ here — keeping core.fs and the session words — then seeds the log.
: (session-init) ( -- )
    (session-mark!)
    true (session-on) !                 \ mark this run as an interactive session
    (seed-log) ;

\ SAVE: rewrite session.fs from the whole log (seed + this session's additions).
\ A no-op when nothing has been captured (e.g. capture wasn't active), so it
\ never litters an empty session.fs. Writes to session.fs.new first, then
\ atomically renames it over session.fs, so a write failure can never destroy
\ an existing session.fs.
: save ( -- )
    (log) cell+ @ 0= if  ." nothing to save" cr  exit  then
    s" session.fs.new" w/o create-file  ( fileid ior )
    abort" save: cannot open session.fs.new"   ( fileid )
    >r
    (log) @ (log) cell+ @ r@ write-file ( ior )
    abort" save: write error"
    r> close-file                       \ deferred write errors can surface here
    abort" save: close error"           \ (e.g. ENOSPC on NFS) — don't publish
    s" session.fs.new" s" session.fs" rename-file
    abort" save: rename error"
    ." saved to session.fs" cr ;

\ -session: forget everything defined since startup (the session definitions and
\ anything entered interactively), keeping core.fs and the session words. A no-op
\ outside an interactive session (no restore point recorded).
: -session ( -- )  (session-restore) ;

\ RELOAD: the edit/compile/run loop — forget the current session definitions and
\ re-load the (possibly hand-edited) session.fs. (skip-capture) keeps the RELOAD
\ line out of the captured log. The log is re-synced from the file (so a later
\ SAVE matches it) ONLY when the file loads cleanly; if a line errors, the file's
\ own diagnostic (filename:line: ? token) is shown, loading stops there, the log
\ is left untouched (so SAVE can't persist a broken file), and RELOAD reports
\ that the session may be incomplete. The REPL keeps running — fix the file and
\ reload again.
: reload ( -- )
    \ Persistence is interactive-only: do nothing when there is no active session
    \ (e.g. RELOAD called from a script or a pipe), so it never auto-loads
    \ session.fs outside that scope.
    (session-on) @ 0= if  ." reload: no active session" cr  exit  then
    \ Verify session.fs is readable BEFORE destroying the live session — a
    \ missing or unreadable file must not forget the session or wipe the log
    \ (forth_included silently treats a missing file as a clean no-op).
    s" session.fs" r/o open-file        ( fileid ior )
    if  drop ." reload: cannot read session.fs" cr  exit  then
    close-file drop
    true (skip-capture) !
    -session
    s" session.fs" (included?)          ( ior )
    if  ." reload: session.fs had errors — session may be incomplete" cr  exit  then
    (seed-log) ;

\ SEE: print the source of a word's definition this session. A source lister,
\ not a decompiler — it replays exactly what you typed (from the capture log), so
\ it covers your own interactive definitions, not core.fs words. It resolves the
\ name with FIND (case-insensitive, searches from LATEST) and shows the log slice
\ for the matching xt — so it only ever shows a word that is currently defined,
\ and shows the source of the definition actually in force.
variable (see-a)  variable (see-u)      \ the name SEE is searching for (for messages)
variable (see-xt)                       \ the live word's xt SEE is matching
: see ( "name" -- )
    parse-word dup 0= if  2drop ." see: needs a word name" cr exit  then
    (see-u) !  (see-a) !
    (see-a) @ (see-u) @ find ?dup if    ( xt flag )   \ currently defined
        drop (see-xt) !                 ( )
        (dir) cell+ @  3 cells /        ( count )   \ records, newest = highest index
        begin  dup 0>  while
            1-                          ( i )
            dup 3 cells *  (dir) @ +    ( i rec )
            dup 2 cells + @  (see-xt) @ = if         ( i rec )   \ this record's word
                dup @  (log) @ +  swap cell+ @  type ( i )   \ source ends in a newline
                drop exit
            then
            drop                        ( i )
        repeat
        drop                            \ defined but no captured source (core/seeded)
    else                                ( a u )   \ not currently defined
        2drop
    then
    ." see: " (see-a) @ (see-u) @ type ."  not found" cr ;

\ Initialize the buffers and register the hooks with the asm REPL.
(log)  3 cells erase
(pend) 3 cells erase
(dir)   3 cells erase
0 (cap-latest) !  0 (skip-capture) !  0 (session-on) !
' (session-init)  0 (hook!)
' (capture-line)  1 (hook!)
' (capture-reset) 2 (hook!)
