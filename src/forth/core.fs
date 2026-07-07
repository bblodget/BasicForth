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
                    \ src < dest (shift right): copy backward, high to low
                    r> begin dup 0 > while
                        1- >r
                        over r@ + c@    ( src dest byte )
                        over r@ + c!    ( src dest )
                        r>
                    repeat drop
                else
                    \ src >= dest (shift left): copy forward, low to high
                    r> 0 do over i + c@ over i + c! loop
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
                repeat drop 2drop
            else drop 2drop then ;
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
\ xorshift64 (Marsaglia): every bit of the output is well-mixed. The previous
\ LCG returned its raw seed, whose LOW bits have tiny periods (bit 0 simply
\ alternates) — and rnd's mod uses the low bits, so 2 rnd flip-flopped.
variable seed  ms@ 1 or seed !             \ nonzero seed or xorshift sticks at 0
: random ( -- n )
    seed @
    dup 13 lshift xor
    dup  7 rshift xor
    dup 17 lshift xor
    dup seed ! ;
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
variable (dirty)                        \ true = the log holds changes SAVE hasn't written
variable (cap-assign)                   \ this line ran a direct TO/IS (read from (assign?))
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
\ offset align8(10 + name-len) past the entry. Mirrors FIND's xt calculation.
: (xt-of) ( entry -- xt )
    dup 8 + c@ 31 and  10 +  7 + -8 and  +  @ ;

\ (dir-add): record one captured group. entry = a header just linked.
: (dir-add) ( log-off log-len entry -- )
    (xt-of)                             ( log-off log-len xt )
    (dir-rec) 2 cells + !               \ rec[2] = xt
    (dir-rec) cell+ !                   \ rec[1] = log-len
    (dir-rec) !                         \ rec[0] = log-off
    (dir-rec) 3 cells (dir) (buf-append) ;  \ append the 24-byte record

\ (dir-add-group): index EVERY word newly defined in this group, not just the
\ last. Walk the dictionary link chain (link is the first cell of each header)
\ from the new LATEST back to the group's baseline, adding a SEE record — sharing
\ this group's log span — for each new header. Without this, a line that defines
\ several words (": a ;  : b ;") would index only the final one, so SEE would
\ miss the earlier, valid definitions.
variable (dg-off)  variable (dg-len)  variable (dg-stop)
: (dir-add-group) ( log-off log-len old-latest new-latest -- )
    >r  (dg-stop) !  (dg-len) !  (dg-off) !   ( )   \ R: new-latest = walk cursor
    r>
    begin  dup (dg-stop) @ u>  while          ( entry )   \ newer than the baseline
        (dg-off) @ (dg-len) @  2 pick (dir-add)
        @                                      \ follow link to the previous header
    repeat  drop ;

\ (capture-line): the asm REPL calls this after each successfully interpreted
\ line, passing the current LATEST. Accumulate the line in (pend); when STATE
\ returns to interpret, decide whether the group defined a word — flush it to the
\ log — or not — discard it. A line is a definition only when LATEST moved
\ *forward* (a new header linked), so transient actions, bare ALLOT/,/C, and
\ marker runs / -session (which move LATEST *backward*) are all not captured.
\ RELOAD sets (skip-capture) so its own line is never logged either.
: (capture-line) ( c-addr u latest -- )
    (assign?) (cap-assign) !            \ read+clear: did a direct TO/IS run this line?
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
        (cap-latest) @  r@  (dir-add-group)  \ here aborts before any SEE record is
        true (dirty) !
    else (cap-assign) @ if              \ no new word, but a direct TO/IS ran:
        (pend) (log) (buf-append-buf)    \ persist the assignment line (no SEE record)
        true (dirty) !
    then then                           \ otherwise discard (transient line)
    (pend) (buf-reset)                  \ clear pending
    r> drop                             \ done with the latest param
    (latest@) (cap-latest) ! ;          \ baseline = current LATEST

\ (capture-reset): called at the top of the REPL loop with the current LATEST.
\ Drops a pending partial definition left behind by a line error or fault (only
\ when not compiling), and resyncs the LATEST baseline. Also clears a stuck
\ (skip-capture): RELOAD sets that one-shot flag and expects the next
\ (capture-line) to consume it, but if RELOAD aborts/faults first (e.g. an
\ out-of-memory in seed-log) that never happens — so clear it here, else the
\ next real definition would be silently not captured.
: (capture-reset) ( latest -- )
    false (skip-capture) !
    (assign?) drop                      \ clear a stale assign flag from an errored line
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

\ Named-file persistence (replaces the old fixed session.fs). Your interactive
\ definitions accumulate in the capture log; SAVE <name> writes that log to
\ <name> in the current directory, and `basicforth <name>` loads <name> and
\ seeds the log from it so you can keep editing and SAVE it back. Files are
\ explicit and cwd-relative — there is no magic session.fs.
1024 constant (cf-max)
create (cur-file) (cf-max) allot         \ ABSOLUTE path of the current file (0 len = none)
variable (cur-file-len)
: (cur-file@) ( -- c-addr u )  (cur-file) (cur-file-len) @ ;

\ Generic "append at a write pointer" buffer builder (also used by the ~ expansion
\ in the shell words below).
variable (sp-end)                        \ write pointer while building a buffer
: (sp-add) ( c-addr u -- )               \ append u bytes at (sp-end)
    dup >r  (sp-end) @  swap  cmove       \ cmove( src dest u )
    r> (sp-end) +! ;

: (store-name) ( c-addr u -- )           \ copy <name> verbatim into (cur-file)
    (cf-max) min  dup (cur-file-len) !  (cur-file) swap cmove ;
\ Remember <name> as the current file, resolved to an ABSOLUTE path so a later
\ bare SAVE always rewrites the same file regardless of any `cd`. A relative name
\ is anchored to the current directory at the moment it is set (startup load or
\ SAVE <name>); an absolute name is kept as-is. Falls back to the bare name if
\ <cwd>/<name> would not fit.
: (set-cur-file) ( c-addr u -- )
    over c@ [char] / = if  (store-name) exit  then        \ already absolute
    dup (cwd) nip + 1+ (cf-max) > if  (store-name) exit  then   \ would overflow → bare name
    (cur-file) (sp-end) !
    (cwd) (sp-add)  s" /" (sp-add)  (sp-add)              \ <cwd>/<name>
    (sp-end) @ (cur-file) - (cur-file-len) ! ;

create (path-a) (cf-max) allot           \ scratch: target path "<name>"
create (path-b) (cf-max) allot           \ scratch: temp path  "<name>.new"
variable (path-a-len)  variable (path-b-len)
: (name>paths) ( c-addr u -- )           \ split <name> into (path-a) and (path-b)="<name>.new"
    (cf-max) 4 - min  >r                  ( c-addr )   \ R: u (room left for ".new")
    r@ (path-a-len) !
    dup (path-a) r@ cmove                 \ path-a = name
    (path-b) r@ cmove                     \ path-b = name
    s" .new" (path-b) r@ + swap cmove     \ path-b += ".new"
    r> 4 + (path-b-len) ! ;

\ (seed-log): reset the log + SEE index, then load the current file's bytes into
\ the log so SAVE rewrites it cumulatively. Empty when there is no current file
\ (a fresh session) or the file does not exist yet (a new file).
: (seed-log) ( -- )
    (log) (buf-reset)
    (dir) (buf-reset)                   \ SEE index tracks the log's lifecycle
    false (dirty) !                     \ log now mirrors the file (or is empty)
    (cur-file-len) @ 0= if  exit  then  \ no current file → log stays empty
    (cur-file@) r/o open-file           ( fileid ior )
    if drop exit then                   \ file does not exist yet → log stays empty
    dup (slurp-into-log)                \ copy its text into the log
    close-file drop ;

\ (session-init): boot hook, run once when entering the interactive REPL, with
\ the startup file path ( c-addr u ) or ( 0 0 ) if none. Records the -session
\ restore point, marks the session active, sets the current file, seeds the log.
: (session-init) ( c-addr u -- )
    true (session-on) !                 \ mark this run as an interactive session
    dup if  (set-cur-file)  else  2drop  0 (cur-file-len) !  then
    (seed-log) ;
\ NOTE: the -session restore mark is captured at the END of core.fs (below), not
\ here — so -session/new/load forget the WHOLE module (the loaded file's words
\ plus interactive ones), since the startup file loads after core.fs but before
\ this hook runs.

\ SAVE <name> (bare SAVE → the current file): write the whole log to <name> in
\ the cwd, via "<name>.new" + atomic rename, so a write failure never destroys an
\ existing file. SAVE <name> also makes <name> the current file (save-as). A
\ no-op when nothing has been captured, so it never litters an empty file.
: (save) ( -- )                         \ write the log to the current file
    (log) cell+ @ 0= if  ." nothing to save" cr  exit  then
    (cur-file@) (name>paths)
    (path-b) (path-b-len) @ w/o create-file   ( fileid ior )
    abort" save: cannot create temp file"     ( fileid )
    >r
    (log) @ (log) cell+ @ r@ write-file ( ior )
    abort" save: write error"
    r> close-file                       \ deferred write errors can surface here
    abort" save: close error"           \ (e.g. ENOSPC on NFS) — don't publish
    (path-b) (path-b-len) @  (path-a) (path-a-len) @  rename-file
    abort" save: rename error"
    false (dirty) !
    ." saved to " (cur-file@) type cr ;

: save ( "name" -- )
    parse-word dup if  (set-cur-file)
    else
        2drop (cur-file-len) @ 0= if
            ." save: no current file (use: save <name>)" cr exit
        then
    then
    (save) ;

\ ===== Dirty-guard: don't silently discard unsaved work =====
\ (dirty) is set when the capture log gains something SAVE hasn't written (a
\ definition, a direct to/is, an edit) and cleared by SAVE and (seed-log). When
\ the module is dirty, NEW / LOAD / BYE / BYE-CODE ask before discarding:
\ y = save first (needs a current file), n = discard, any other key = cancel.
\ Only a real terminal prompts — pipes and scripts proceed silently, so
\ automation never blocks. RELOAD stays unguarded on purpose: it is the
\ pull-from-disk verb, and a save-first there would overwrite the very file
\ edits being pulled in.
: (dirty-guard) ( -- proceed? )
    (dirty) @ 0= if  true exit  then
    (tty?) 0= if  true exit  then       \ non-interactive: never prompt
    ." unsaved changes — save first? (y/n) "
    key
    dup 32 127 within if  dup emit  then  cr    \ raw mode: echo the answer
    dup [char] y =  over [char] Y =  or if  drop
        (cur-file-len) @ 0= if
            ." save: no current file (use: save <name>)" cr  false exit
        then
        (save)  true exit
    then
    dup [char] n =  swap [char] N =  or if  true exit  then
    ." (cancelled)" cr  false ;

\ BYE / BYE-CODE, guarded. The inner call is the assembly primitive — a new
\ definition stays hidden until its `;`, so the name still finds the old one
\ here. A cancelled exit just returns to the REPL.
: bye ( -- )  (dirty-guard) if  bye  then ;
: bye-code ( n -- )  (dirty-guard) if  bye-code  then  drop ;

\ -session: low-level forget — restore HERE/LATEST to the startup mark, dropping
\ every definition made since (the module's words). A no-op outside an interactive
\ session. Used by NEW / LOAD / RELOAD; leaves the log and current file alone.
: -session ( -- )  (session-restore) ;

\ (open-module): forget the old module, (re)load the current file, reseed the log
\ so SAVE rewrites it. (skip-capture) keeps this line out of the log.
: (open-module) ( -- )
    true (skip-capture) !
    -session
    (cur-file@) (included?)             ( ior )
    if  ." load error in " (cur-file@) type ."  — module may be incomplete" cr  exit  then
    (seed-log) ;                        \ reseed the log for SAVE (SEE reads file metadata)

\ LOAD <file>: open <file> as the current module — a clean swap, like
\ `basicforth <file>` mid-session. Verified readable BEFORE anything is forgotten,
\ so a typo can't wipe your work. Discards unsaved changes — SAVE first to keep.
: load ( "name" -- )
    parse-word dup 0= if  2drop ." usage: load <file>" cr exit  then
    2dup r/o open-file if  drop ." load: cannot read " type cr exit  then
    close-file drop                     ( c-addr u )
    (dirty-guard) 0= if  2drop exit  then    \ unsaved work: ask before discarding
    (set-cur-file)                       \ absolutize + adopt as the current file
    (open-module) ;

\ NEW: clear the module — forget every definition, empty the log, drop the current
\ file. A clean slate (core vocabulary only). Discards unsaved changes.
: new ( -- )
    (dirty-guard) 0= if  exit  then     \ unsaved work: ask before discarding
    -session
    0 (cur-file-len) !
    (seed-log) ;                        \ no current file → empties the log + SEE index

\ RELOAD: refresh the current module from disk (edit-on-disk loop) — forget the
\ session and re-read the current file. Verified readable before forgetting, so a
\ missing/unreadable file never wipes your work.
: reload ( -- )
    (session-on) @ 0= if  ." reload: no active session" cr  exit  then
    (cur-file-len) @ 0= if  ." reload: no current file" cr  exit  then
    (cur-file@) r/o open-file           ( fileid ior )
    if  drop ." reload: cannot read " (cur-file@) type cr  exit  then
    close-file drop
    (open-module) ;

\ SEE: print the source of the definition currently in force. A source lister,
\ not a decompiler. File-loaded words are read from their source file via the
\ per-word metadata; REPL-typed words from the capture log; primitives are
\ labelled. (See the dispatch in `see` below, and docs/See_Metadata.md.)
variable (see-a)  variable (see-u)      \ the name SEE is searching for (for messages)
variable (see-xt)                       \ the live word's xt (for the REPL session-log path)

\ Message prefix ("see" / "edit") so the shared source helpers report under the
\ command the user actually typed.
variable (msg-a)  variable (msg-u)

\ (see-post): hook run after SEE prints a word's source. The real body — the
\ deferred-word binding report — is installed near EOF once its helpers exist.
defer (see-post)  :noname ; is (see-post)
: (msg:) ( -- )  (msg-a) @ (msg-u) @ type ." : " ;

\ Source sink: SEE types a word's source straight out; EDIT redirects it into the
\ preload buffer instead. Both go through (see-emit) ( c-addr u -- ).
variable (see-emit-xt)
: (see-emit) ( c-addr u -- )  (see-emit-xt) @ execute ;
' type (see-emit-xt) !

\ --- file-source reader: print [off, off+len) of a source file by source-id ---
variable (sf-fid)  variable (sf-buf)
variable (sf-off)  variable (sf-len)  variable (sf-need)  variable (sf-got)

\ Read (sf-need) bytes from the start of (sf-fid) into (sf-buf); set (sf-got).
\ Loops over short reads; stops early at EOF or a read error.
: (sf-read) ( -- )
    0 (sf-got) !
    begin  (sf-got) @ (sf-need) @ <  while
        (sf-buf) @ (sf-got) @ +              ( dest )
        (sf-need) @ (sf-got) @ -             ( dest remaining )
        (sf-fid) @ read-file                 ( u2 ior )
        if  drop exit  then                  \ read error → stop with what we have
        dup 0= if  drop exit  then           \ EOF (0 bytes) → stop
        (sf-got) +!
    repeat ;

\ Open the source file for `srcid` and TYPE its [off, off+len) byte span.
: (see-file) ( off len srcid -- )
    (source-path)                            ( off len c-addr u )
    r/o open-file if                         ( off len fileid )
        drop 2drop (msg:) ." cannot open source file" cr exit
    then  (sf-fid) !                         ( off len )
    (sf-len) !  (sf-off) !
    (sf-off) @ (sf-len) @ +  (sf-need) !
    (sf-need) @ allocate if                  ( a-addr )   \ ior nonzero → failure
        drop  (sf-fid) @ close-file drop
        (msg:) ." out of memory" cr exit
    then  (sf-buf) !
    (sf-read)
    (sf-got) @ (sf-off) @ > if               \ emit [off, min(off+len, got))
        (sf-buf) @ (sf-off) @ +
        (sf-got) @ (sf-off) @ -  (sf-len) @ min
        (see-emit)
    then
    (sf-buf) @ free drop
    (sf-fid) @ close-file drop ;

\ Print a REPL-typed word's source from the session capture log (matched by xt).
: (see-from-log) ( -- )
    (dir) cell+ @  3 cells /                 ( count )   \ records, newest = highest index
    begin  dup 0>  while
        1-                                   ( i )
        dup 3 cells *  (dir) @ +             ( i rec )
        dup 2 cells + @  (see-xt) @ = if      ( i rec )   \ this record's word
            dup @  (log) @ +  swap cell+ @  (see-emit) ( i )  \ source ends in a newline
            drop exit
        then
        drop                                 ( i )
    repeat
    drop
    (msg:) (see-a) @ (see-u) @ type ."  defined, but no source captured" cr ;

\ SEE shows the source of the definition currently in force. It reads the
\ per-word source metadata (find-meta): a file-loaded word (core.fs, session.fs,
\ or any included file) is shown straight from its source file; a word typed at
\ the REPL this session comes from the capture log; an assembly primitive is
\ labelled as such. The live xt is matched, so a redefined or forgotten word
\ shows what is actually in force (or reports "not found").
: see ( "name" -- )
    s" see" (msg-u) ! (msg-a) !  ' type (see-emit-xt) !   \ report as `see`, type source
    parse-word dup 0= if  2drop (msg:) ." needs a word name" cr exit  then
    (see-u) !  (see-a) !
    (see-a) @ (see-u) @ (find-meta)          ( xt off len srcid flag )
    0= if  2drop 2drop                       \ not currently defined
        (msg:) (see-a) @ (see-u) @ type ."  not found" cr exit
    then
    dup 65535 = if                           ( xt off len srcid )   \ PRIM sentinel
        2drop 2drop
        (msg:) (see-a) @ (see-u) @ type ."  is a primitive (assembly)" cr exit
    then
    dup 0= if                                \ srcid 0 → REPL word: use the capture log
        drop  2drop  (see-xt) !
        (see-from-log)  (see-post) exit
    then
    >r  rot drop  r>                         ( off len srcid )   \ srcid ≥ 1 → from file
    (see-file)  (see-post) ;

\ (el-pre)/(el-pre-len): a one-line preload the interactive line editor can drop
\ onto the next prompt. EDIT no longer uses it (it opens an external editor now,
\ defined near EOF), but it stays as line-editor infrastructure — (edit-line)
\ honours (el-pre-len) for any future inline-recall feature.
create (el-pre)  256 allot               \ preload text for the next (edit-line)
variable (el-pre-len)  0 (el-pre-len) !  \ pending preload length; 0 = none

\ ===== REDO: recompile a REPL-defined word from its captured source =====
\ redo <name> re-evaluates a word's saved source, so callers that were compiled
\ against an earlier version of a *leaf* it uses pick up the change (BasicForth is
\ subroutine-threaded: redefining a word does not update already-compiled
\ callers; recompiling them does). It is the REPL companion to editing a file and
\ RELOAD-ing it, and to DEFER/IS (which avoids recompilation entirely at the
\ seams you choose). v1 handles words defined at the REPL this session (source in
\ the capture log); file-loaded words say to edit-and-reload, primitives decline.

variable (rd-a)  variable (rd-u)        \ the source span REDO is walking

\ Index of the first byte == c in (rd-a)[0..(rd-u)), or (rd-u) if absent.
: (rd-chpos) ( c -- n )
    (rd-u) @ 0 ?do
        dup (rd-a) @ i + c@ = if  drop i unloop exit  then
    loop drop (rd-u) @ ;

\ Interpret a multi-line source buffer one line at a time, the way INCLUDED does
\ — NOT as a single EVALUATE, because a `\` comment would otherwise swallow the
\ rest of the whole buffer (EVALUATE has no line boundaries). STATE persists
\ across the per-line EVALUATEs, so a colon definition may span several lines.
\ ALL loop bookkeeping lives in variables, never on the data stack: evaluated
\ content may leave items between lines (a `:noname ... ; is x` group parks
\ its xt on the stack until the closing line's `is` pops it), and anything of
\ ours on the stack would be shadowed by them.
variable (rd-n)                         \ bytes consumed by the current line
: (rd-eval-lines) ( c-addr u -- )
    (rd-u) !  (rd-a) !
    begin (rd-u) @ 0> while
        10 (rd-chpos)  dup (rd-n) !     ( idx-of-newline-or-len )
        (rd-a) @ swap evaluate          ( )   \ only content's items remain
        (rd-n) @  dup (rd-u) @ < if 1+ then   ( consumed, +1 for the newline )
        dup (rd-a) +!
        (rd-u) @ swap - (rd-u) !
    repeat ;

\ Find the newest capture-log directory record for (see-xt). ( -- rec true | false )
: (rd-dir-find) ( -- rec true | false )
    (dir) cell+ @  3 cells /            ( count )
    begin dup 0> while
        1-                              ( i )
        dup 3 cells *  (dir) @ +        ( i rec )
        dup 2 cells + @  (see-xt) @ = if  nip true exit  then
        drop                            ( i )
    repeat
    drop false ;

\ Recompile the REPL word whose old xt is in (see-xt), then repoint its log
\ record at the new definition so SEE keeps working after the redefinition.
: (redo-from-log) ( -- )
    (rd-dir-find) 0= if
        ." redo: " (see-a) @ (see-u) @ type ."  has no captured source" cr exit
    then                                ( rec )
    \ The recompile moves LATEST, so the REPL would otherwise log the `redo`
    \ command line itself as the word's new source. Suppress that one capture
    \ (same one-shot flag RELOAD uses); we repoint the existing record below.
    true (skip-capture) !
    dup @  (log) @ +                    ( rec src-addr )
    over cell+ @                        ( rec src-addr src-len )
    (rd-eval-lines)                     ( rec )
    (see-a) @ (see-u) @ find            ( rec xt -1 | rec c-addr u 0 )
    if  swap 2 cells + !  else  2drop drop  then ;

: redo ( "name" -- )
    parse-word dup 0= if  2drop ." redo: needs a word name" cr exit  then
    (see-u) !  (see-a) !
    (see-a) @ (see-u) @ (find-meta)     ( xt off len srcid flag )
    0= if  2drop 2drop
        ." redo: " (see-a) @ (see-u) @ type ."  not found" cr exit  then
    dup 65535 = if  2drop 2drop
        ." redo: " (see-a) @ (see-u) @ type ."  is a primitive (cannot redo)" cr exit  then
    dup 0<> if  2drop 2drop             \ srcid >= 1 → loaded from a file
        ." redo: " (see-a) @ (see-u) @ type ."  was loaded from a file; edit it and reload" cr exit  then
    drop  2drop  (see-xt) !             \ srcid 0 → REPL word: old xt for the log lookup
    (redo-from-log) ;

\ Initialize the buffers and register the hooks with the asm REPL.
(log)  3 cells erase
(pend) 3 cells erase
(dir)   3 cells erase
0 (cap-latest) !  0 (skip-capture) !  0 (session-on) !  0 (dirty) !
' (session-init)  0 (hook!)
' (capture-line)  1 (hook!)
' (capture-reset) 2 (hook!)

\ ===== Interactive line editor (REPL input hook, slot 3) =====
\ Engaged only when stdin is an interactive terminal (main.s gates on isatty);
\ piped/redirected input falls back to the asm forth_accept. Provides in-line
\ editing: type anywhere, move with the left/right arrows (Ctrl-A/Ctrl-E jump to
\ start/end), and insert/delete mid-line. Echo is manual (raw mode clears ECHO).
\ Each edit just mutates the buffer and calls (el-redraw), which paints a
\ horizontally-scrolled one-row window onto the buffer (so a line wider than the
\ terminal scrolls sideways instead of wrapping). KEY already decodes arrows to
\ 131 (right) / 132 (left); 129/130 (up/down) drive history recall.
variable (el-buf)   \ buffer base address
variable (el-max)   \ capacity in chars
variable (el-len)   \ current line length
variable (el-pos)   \ cursor index, 0..len

\ Horizontal-scroll state: the editable area shows a window buf[vstart..) that
\ fits one terminal row. (el-scol) is the terminal cursor's column offset from
\ the prompt margin; (el-vshown) the number of chars currently drawn there.
: (el-margin) ( -- n )  \ columns the REPL prompt occupies: "... " while a
    state @ if  4  else  2  then ;  \ definition is open (main.s prints it), else "> "
variable (el-vstart)               \ leftmost visible buffer index (scroll offset)
variable (el-scol)                 \ cursor column, as an offset from the margin
variable (el-vshown)               \ chars currently drawn in the editable area
variable (el-w)                    \ scratch: usable width during a redraw

: (el-bsp)    ( n -- ) begin dup 0> while  8 emit  1- repeat  drop ;
: (el-spaces) ( n -- ) begin dup 0> while 32 emit  1- repeat  drop ;
: (el-width)  ( -- w ) \ usable editable columns (leave the last column free)
    screen-width (el-margin) - 1 -  1 max ;

\ Redraw the editable area as a horizontally-scrolled window onto the buffer,
\ keeping the cursor visible, then leave the terminal cursor at the cursor
\ column. Uses only backspace/space/printables (no escape sequences), so every
\ edit op is just "mutate the buffer, then (el-redraw)".
: (el-redraw) ( -- )
    (el-width) (el-w) !
    (el-pos) @ (el-vstart) @ < if  (el-pos) @ (el-vstart) !  then     \ scroll left
    (el-pos) @ (el-vstart) @ -  (el-w) @ 1- > if                      \ scroll right
        (el-pos) @ (el-w) @ 1- -  (el-vstart) !
    then
    \ never leave the window past the end of the line, or a recalled/shrunk
    \ shorter line would render blank (vstart stale-high from a longer line)
    (el-vstart) @  (el-len) @ (el-w) @ - 1+  0 max  min  (el-vstart) !
    (el-scol) @ (el-bsp)                                 \ cursor back to the margin
    (el-len) @ (el-vstart) @ -  (el-w) @ min             ( vlen )
    (el-buf) @ (el-vstart) @ +  over  type               ( vlen )    \ draw the window
    (el-vshown) @ over -  dup 0> if  dup (el-spaces) (el-bsp)  else drop then  ( vlen )
    dup  (el-pos) @ (el-vstart) @ -  -  (el-bsp)          ( vlen )    \ back to cursor col
    (el-vshown) !
    (el-pos) @ (el-vstart) @ -  (el-scol) ! ;

\ Self-contained byte shifts, kept independent of MOVE/CMOVE (simple and tested;
\ they also predate the MOVE/CMOVE> overlap fix).
: (el-open) ( -- )   \ open a 1-char gap at pos: copy buf[pos..len) up by 1, high→low
    (el-len) @                                            \ i, from len down to pos+1
    begin dup (el-pos) @ > while
        1-  (el-buf) @ over +  dup c@ swap 1+ c!          \ buf[i+1] = buf[i]
    repeat drop ;
: (el-close) ( -- )  \ delete buf[pos-1]: copy buf[pos..len) down by 1, low→high
    (el-pos) @                                            \ i, from pos up to len-1
    begin dup (el-len) @ < while
        (el-buf) @ over +  dup c@ swap 1- c!  1+          \ buf[i-1] = buf[i]
    repeat drop ;

: (el-insert) ( c -- )   \ insert char at the cursor, shifting the tail right
    (el-len) @ (el-max) @ < 0= if  drop exit  then        \ buffer full: ignore
    (el-open)  (el-buf) @ (el-pos) @ + c!
    1 (el-len) +!  1 (el-pos) +!  (el-redraw) ;

: (el-back) ( -- )   \ delete the char before the cursor, shifting the tail left
    (el-pos) @ 0= if  exit  then
    (el-close)  -1 (el-len) +!  -1 (el-pos) +!  (el-redraw) ;

: (el-left)  ( -- )  (el-pos) @ 0= if  exit  then  -1 (el-pos) +!  (el-redraw) ;
: (el-right) ( -- )  (el-pos) @ (el-len) @ < 0= if  exit  then  1 (el-pos) +!  (el-redraw) ;
: (el-home)  ( -- )  0 (el-pos) !  (el-redraw) ;
: (el-end)   ( -- )  (el-len) @ (el-pos) !  (el-redraw) ;

\ ----- Command history (up/down recall) -----
\ A circular ring of recent submitted lines on the heap; each slot is a length
\ cell followed by the line bytes. Within one edit, (el-hpos) browses 0..count:
\ count = the (stashed) in-progress line, count-1 = newest entry, 0 = oldest.
\ Up walks toward older, down toward newer/in-progress. If allocation fails,
\ (hist-buf) stays 0 and history is silently disabled (editing still works).
64  constant (hist-cap)               \ number of remembered lines
256 constant (hist-wid)               \ line bytes per slot (= INPUT_BUF_SIZE)
variable (hist-buf)                   \ heap base (0 until allocated)
variable (hist-stash)                 \ in-progress line saved while browsing
variable (hist-slen)                  \ stashed line length
variable (hist-head)                  \ next slot to write (0..cap-1)
variable (hist-count)                 \ live entries (0..cap)
variable (el-hpos)                    \ browse cursor within one edit

: (hist-stride) ( -- n )  (hist-wid) cell+ ;          \ bytes per slot
: (hist-slot) ( i -- addr )  (hist-stride) *  (hist-buf) @ + ;
: (hist-entry) ( hpos -- src u )      \ map a browse position to ( bytes len )
    (hist-head) @ (hist-count) @ -  +  (hist-cap) +  (hist-cap) mod
    (hist-slot)  dup cell+ swap @ ;
: (hist-put) ( src u i -- )           \ store a line into slot i
    (hist-slot) >r  dup r@ !  r> cell+ swap  cmove ;   \ len cell, then bytes

: (el-stash-save) ( -- )              \ remember the in-progress line before browsing
    (el-buf) @ (hist-stash) @ (el-len) @ cmove  (el-len) @ (hist-slen) ! ;
: (el-show) ( src u -- )              \ load src/u into the buffer, cursor at end, redraw
    (el-max) @ min  dup (el-len) !  (el-buf) @ swap cmove
    (el-len) @ (el-pos) !  (el-redraw) ;
: (el-recall) ( src u -- )  (el-show) ;   \ (el-redraw) erases any longer prior line

: (el-up) ( -- )                      \ recall an older line
    (hist-count) @ 0= if  exit  then
    (el-hpos) @ 0= if  exit  then                      \ already at the oldest
    (el-hpos) @ (hist-count) @ = if  (el-stash-save)  then
    -1 (el-hpos) +!
    (el-hpos) @ (hist-entry) (el-recall) ;
: (el-down) ( -- )                    \ move toward newer / the in-progress line
    (hist-count) @ 0= if  exit  then
    (el-hpos) @ (hist-count) @ = if  exit  then        \ already in-progress
    1 (el-hpos) +!
    (el-hpos) @ (hist-count) @ = if
        (hist-stash) @ (hist-slen) @ (el-recall)       \ restore the typed line
    else
        (el-hpos) @ (hist-entry) (el-recall)
    then ;

: (hist-add) ( -- )                   \ append the just-submitted line as newest
    (hist-buf) @ 0= if  exit  then     \ history disabled
    (el-len) @ 0= if  exit  then       \ skip empty lines
    (hist-count) @ 0> if               \ skip if identical to the newest entry
        (hist-count) @ 1- (hist-entry)  (el-buf) @ (el-len) @  compare 0= if  exit  then
    then
    (el-buf) @ (el-len) @ (hist-head) @ (hist-put)
    (hist-head) @ 1+ (hist-cap) mod (hist-head) !
    (hist-count) @ (hist-cap) < if  1 (hist-count) +!  then ;

: (edit-line) ( c-addr max -- count )
    (el-max) !  (el-buf) !  0 (el-len) !  0 (el-pos) !
    0 (el-vstart) !  0 (el-scol) !  0 (el-vshown) !   \ fresh prompt: cursor at margin
    (hist-count) @ (el-hpos) !
    (el-pre-len) @ if                                \ `edit` left text to pre-fill
        (el-pre) (el-pre-len) @ (el-show)  0 (el-pre-len) !
    then
    begin
        key
        dup 10 = if  drop  (el-end) 10 emit  (hist-add) (el-len) @ exit  then
        dup 8 = over 127 = or if  drop (el-back)  else
        dup 131 =             if  drop (el-right) else
        dup 132 =             if  drop (el-left)  else
        dup 1 =               if  drop (el-home)  else
        dup 5 =               if  drop (el-end)   else
        dup 129 =             if  drop (el-up)    else
        dup 130 =             if  drop (el-down)  else
        dup 32 <              if  drop            else   \ ignore other controls
        dup 126 >             if  drop            else   \ ignore >126 (other escapes)
        (el-insert)
        then then then then then then then then then
    again ;

\ Allocate the history ring + stash buffer (best-effort; failure disables
\ history). Both-or-nothing: (hist-buf) is the sentinel the rest of the code
\ tests, so if the stash allocation fails we free the ring and leave (hist-buf)
\ null — otherwise a partial success would let (el-stash-save) cmove into a null
\ stash. Wrapped in a word because IF/THEN are compile-only (no top-level use).
: (hist-init) ( -- )
    0 (hist-buf) !  0 (hist-stash) !  0 (hist-head) !  0 (hist-count) !
    (hist-cap) (hist-stride) *  allocate if  drop exit  then  (hist-buf) !
    (hist-wid) allocate if                          \ stash failed:
        drop  (hist-buf) @ free drop  0 (hist-buf) ! \ free ring, disable history
    else  (hist-stash) !  then ;
(hist-init)
' (edit-line)  3 (hook!)

\ ===== Help system: docs browser (man / topics / apropos) =====
\ Reads the docs/*.md files in the colon-separated directories named by
\ BASICFORTH_DOCS. Directory listing uses (getdents); files are read on demand.

variable (gd)                            \ getdents record buffer (heap, lazy)
4096 constant (gd-size)
: (gd@) ( -- a )                         \ allocate the buffer once, return it
    (gd) @ ?dup if exit then
    (gd-size) allocate abort" help: out of memory" dup (gd) ! ;

\ linux_dirent64 record: d_reclen at +16 (16-bit LE), d_name at +19 (asciiz).
: (de-reclen) ( ptr -- u )  dup 16 + c@ swap 17 + c@ 8 lshift or ;
: (de-name)   ( ptr -- c-addr )  19 + ;
: (cstr-len)  ( c-addr -- u )  0 begin 2dup + c@ while 1+ repeat nip ;
: (ends-md?)  ( c-addr u -- f )          \ does the name end in ".md"?
    dup 3 < if 2drop false exit then
    + 3 -                                ( p )   \ start of the last 3 chars
    dup    c@ [char] . =
    over 1+ c@ [char] m = and
    swap 2 + c@ [char] d = and ;

\ Iterate the BASICFORTH_DOCS dirs, calling an xt with ( dir-addr dir-u ).
variable (dd-xt)  variable (dd-cur)  variable (dd-rem)
: (index-of) ( c-addr u ch -- n )        \ first index of ch in the string, else u
    >r over + over                       ( c-addr end cur )   \ R: ch
    begin 2dup u> while
        dup c@ r@ = if  nip swap -  r> drop exit  then
        1+
    repeat  drop swap -  r> drop ;
: (each-dir) ( xt -- )
    (dd-xt) !
    (docs-path) (dd-rem) ! (dd-cur) !
    begin (dd-rem) @ while
        (dd-cur) @ (dd-rem) @ [char] : (index-of)   ( seglen )
        dup if  (dd-cur) @ over (dd-xt) @ execute  then
        dup (dd-rem) @ < if 1+ then                 ( advance )
        dup (dd-cur) +!  (dd-rem) @ swap - (dd-rem) !
    repeat ;

\ Last path component of a directory (the "section" name shown by topics).
variable (bn-a)  variable (bn-u)
: (basename) ( c-addr u -- ba bu )
    dup 0= if exit then
    2dup + 1- c@ [char] / = if 1- then        \ ignore one trailing '/'
    (bn-u) ! (bn-a) !
    0                                          ( start = index after last '/' )
    (bn-u) @ 0 ?do
        (bn-a) @ i + c@ [char] / = if drop i 1+ then
    loop
    (bn-a) @ over +  swap  (bn-u) @ swap - ;   ( ba bu )

\ TOPICS: list the available .md topics, grouped under their section (the
\ directory each topic lives in) and sorted alphabetically within each section.
\ Names are copied into a heap buffer first — the getdents buffer is reused
\ across reads, so a name pointer into it is not stable — then sorted and printed.
variable (sec-a)  variable (sec-u)         \ current section name (a basename)
variable (tn-buf)                          \ heap: names, each a counted string
variable (tn-ptr)                          \ heap: array of pointers into (tn-buf)
variable (tn-w)  variable (tn-n)  variable (tn-d)
4096 constant (tn-bufsz)
256  constant (tn-max)
: (tn-buf@) ( -- a )
    (tn-buf) @ ?dup if exit then
    (tn-bufsz) allocate abort" topics: out of memory" dup (tn-buf) ! ;
: (tn-ptr@) ( -- a )
    (tn-ptr) @ ?dup if exit then
    (tn-max) cells allocate abort" topics: out of memory" dup (tn-ptr) ! ;
: (tn-ptr-at) ( i -- a-addr )  cells (tn-ptr@) + ;
: (tn-collect) ( name u -- )               \ copy a display name into the buffer
    (tn-n) @ (tn-max) < 0= if 2drop exit then
    dup 255 > if 2drop exit then
    dup (tn-w) @ + 1+ (tn-bufsz) > if 2drop exit then
    (tn-buf@) (tn-w) @ + (tn-d) !          ( name u )   \ dest = buf + w
    dup (tn-d) @ c!                        \ dest[0] = length
    dup >r                                 ( name u )   \ R: u
    (tn-d) @ 1+ swap cmove                 \ copy name bytes to dest+1
    (tn-d) @ (tn-n) @ (tn-ptr-at) !        \ ptr[n] = dest
    1 (tn-n) +!
    r> 1+ (tn-w) +! ;                      \ advance write by 1 + u
: (tn-cmp) ( cp1 cp2 -- n )                \ compare two counted strings
    >r count r> count compare ;
: (tn-sort) ( -- )                          \ insertion sort ptr[0..n) by name
    (tn-n) @ 2 < if exit then
    (tn-n) @ 1 ?do
        i (tn-ptr-at) @  i 1-              ( key j )
        begin
            dup 0< if 0 else
                dup (tn-ptr-at) @ 2 pick (tn-cmp) 0>
            then
        while                              ( key j )
            dup (tn-ptr-at) @  over 1+ (tn-ptr-at) !   \ ptr[j+1] = ptr[j]
            1-
        repeat
        1+ (tn-ptr-at) !                   \ ptr[j+1] = key
    loop ;
: (topics-in) ( dir-addr dir-u -- )
    2dup r/o open-file if drop 2drop exit then   ( dir-addr dir-u fileid )
    >r                                            ( dir-addr dir-u )   \ R: fileid
    (basename) (sec-u) ! (sec-a) !
    0 (tn-n) !  0 (tn-w) !
    begin
        r@ (gd@) (gd-size) (getdents)     ( n )
        dup 0> while                       ( n )
        (gd@) +  (gd@)                     ( end ptr )
        begin 2dup u> while                ( end ptr )
            dup (de-name) dup (cstr-len)   ( end ptr name namelen )
            2dup (ends-md?) if  3 - (tn-collect)  else  2drop  then
            dup (de-reclen) +              ( end nextptr )
        repeat 2drop
    repeat drop
    r> close-file drop
    (tn-n) @ 0= if exit then               \ no topics here → no header
    (tn-sort)
    (sec-a) @ (sec-u) @ type cr  space space        \ section header
    (tn-n) @ 0 ?do  i (tn-ptr-at) @ count type space  loop
    cr ;
: topics ( -- )
    (docs-path) nip 0= if  ." (BASICFORTH_DOCS not set)" cr exit  then
    ['] (topics-in) (each-dir) ;

\ --- case-insensitive helpers ---
: (lc) ( ch -- ch )  dup [char] A [char] Z 1+ within if 32 + then ;
: (ci=) ( a1 u1 a2 u2 -- f )             \ case-insensitive string equal
    rot 2dup = 0= if 2drop 2drop false exit then   ( a1 a2 u2 u1 )
    drop >r 0                                        ( a1 a2 i )   \ R: len
    begin dup r@ < while
        2 pick over + c@ (lc)
        2 pick 2 pick + c@ (lc)
        <> if r> drop drop drop drop false exit then
        1+
    repeat r> drop drop drop drop true ;

\ --- pager: print a file fd, pausing each screenful ---
256 constant (pg-bufsz)
variable (pg-buf)                        \ line buffer (heap, lazy)
variable (pg-row)                        \ lines shown since last pause
variable (pg-quit)                       \ true once the user pressed q
: (pg-buf@) ( -- a )
    (pg-buf) @ ?dup if exit then
    (pg-bufsz) allocate abort" help: out of memory" dup (pg-buf) ! ;
: (pg-prompt) ( -- )
    ." -- more (space=page, q=quit) --" key cr
    dup [char] q = swap [char] Q = or if  true (pg-quit) !  then
    0 (pg-row) ! ;
: (pg-line) ( c-addr u -- )
    type cr  1 (pg-row) +!
    (tty?) 0= if exit then                 \ piped: no --more-- pause, ever
    (pg-row) @ screen-height 1 - < 0= if (pg-prompt) then ;
\ page-file: page a file fd a screenful at a time. Always closes the fd. Returns
\ a read-error flag (true if read-line failed) rather than aborting — it is a
\ shared helper called from contexts that hold their own resources (e.g. (man-in)
\ keeps a directory fd open), so a non-local abort here would skip their cleanup.
\ Each caller decides whether to abort.
: page-file ( fileid -- read-error? )
    0 (pg-row) ! false (pg-quit) !
    >r
    begin
        (pg-buf@) (pg-bufsz) r@ read-line   ( u flag ior )
        if  2drop  ." (read error)" cr  r> close-file drop  true exit  then  \ I/O error
        if  (pg-buf@) swap (pg-line)
        else  drop  r> close-file drop  false exit  then   \ EOF: done, no error
        (pg-quit) @ if  r> close-file drop  false exit  then  \ user quit: not an error
    again ;

\ --- MAN: find <topic>.md (case-insensitive) in the docs dirs and page it ---
512 constant (mpath-sz)
create (mpath) (mpath-sz) allot          \ "<dir>/<name>" scratch path
variable (md-dir)  variable (md-dirn)    \ current dir for (build-path)
variable (mn-t)    variable (mn-tn)      \ requested topic
variable (mn-found)
: (build-path) ( name namelen -- c-addr u )   \ "<dir>/<name>" in (mpath); u=0 if too long
    \ Bail out (empty, unopenable path) rather than overrun (mpath) when the
    \ docs dir + filename won't fit — guards against long BASICFORTH_DOCS values.
    dup (md-dirn) @ + 1+  (mpath-sz) > if  2drop (mpath) 0 exit  then
    >r                                          ( name )   \ R: namelen
    (md-dir) @ (mpath) (md-dirn) @ cmove
    [char] / (mpath) (md-dirn) @ + c!
    (mpath) (md-dirn) @ + 1+  r@  cmove
    (mpath)  (md-dirn) @ 1+ r> + ;
: (man-in) ( dir-addr dir-u -- )
    (mn-found) @ if 2drop exit then
    (md-dirn) ! (md-dir) !
    (md-dir) @ (md-dirn) @ r/o open-file if drop exit then   ( fileid )
    >r
    begin
        r@ (gd@) (gd-size) (getdents)            ( n )
        dup 0> while
        (gd@) + (gd@)                            ( end ptr )
        begin 2dup u> while                      ( end ptr )
            dup (de-name) dup (cstr-len)         ( end ptr name namelen )
            2dup (ends-md?) if
                2dup 3 - (mn-t) @ (mn-tn) @ (ci=) if
                    (build-path) r/o open-file
                    if drop else page-file drop true (mn-found) ! then  \ drop page-file's flag
                    2drop r> close-file drop exit
                then
            then
            2drop  dup (de-reclen) +
        repeat 2drop
    repeat drop
    r> close-file drop ;
: man ( "topic" -- )
    parse-word                              ( c-addr u )
    dup 0= if 2drop ." usage: man <topic>" cr exit then
    (mn-tn) ! (mn-t) !  false (mn-found) !
    (docs-path) nip 0= if  ." (BASICFORTH_DOCS not set)" cr exit  then
    ['] (man-in) (each-dir)
    (mn-found) @ 0= if
        ." no help for " (mn-t) @ (mn-tn) @ type ."  (try TOPICS)" cr
    then ;

\ --- APROPOS: list topics whose file contains <keyword> (case-insensitive) ---
variable (akw)  variable (akn)           \ requested keyword
variable (ap-l)  variable (ap-ln)  variable (ap-k)  variable (ap-kn)   \ scratch
: (ci-at?) ( pos -- f )                  \ keyword matches line at byte offset pos?
    0
    begin dup (ap-kn) @ < while
        2dup + (ap-l) @ + c@ (lc)
        over (ap-k) @ + c@ (lc)
        <> if 2drop false exit then
        1+
    repeat 2drop true ;
: (ci-has?) ( line u kw ku -- f )        \ does line contain kw (case-insensitive)?
    (ap-kn) ! (ap-k) ! (ap-ln) ! (ap-l) !
    (ap-kn) @ 0= if true exit then
    (ap-ln) @ (ap-kn) @ < if false exit then
    (ap-ln) @ (ap-kn) @ -                ( lastpos )
    0 begin 2dup < 0= while              ( last i )
        dup (ci-at?) if 2drop true exit then
        1+
    repeat 2drop false ;
: (file-has-kw?) ( name namelen -- f )   \ open <dir>/<name>, true if any line has kw
    (build-path) r/o open-file if drop false exit then   ( fileid )
    >r
    begin
        (pg-buf@) (pg-bufsz) r@ read-line   ( u flag ior )
        if  2drop r> close-file drop false exit  then
        if  (pg-buf@) swap (akw) @ (akn) @ (ci-has?)
            if  r> close-file drop true exit  then
        else  drop r> close-file drop false exit  then
    again ;
: (apropos-in) ( dir-addr dir-u -- )
    (md-dirn) ! (md-dir) !
    (md-dir) @ (md-dirn) @ r/o open-file if drop exit then   ( fileid )
    >r
    begin
        r@ (gd@) (gd-size) (getdents)            ( n )
        dup 0> while
        (gd@) + (gd@)                            ( end ptr )
        begin 2dup u> while                      ( end ptr )
            dup (de-name) dup (cstr-len)         ( end ptr name namelen )
            2dup (ends-md?) if
                2dup (file-has-kw?) if      \ print "topic (section)"
                    2dup 3 - type
                    space [char] ( emit
                    (md-dir) @ (md-dirn) @ (basename) type
                    [char] ) emit cr
                then
            then
            2drop  dup (de-reclen) +
        repeat 2drop
    repeat drop
    r> close-file drop ;
: apropos ( "keyword" -- )
    parse-word                              ( c-addr u )
    dup 0= if 2drop ." usage: apropos <keyword>" cr exit then
    (akn) ! (akw) !
    (docs-path) nip 0= if  ." (BASICFORTH_DOCS not set)" cr exit  then
    ['] (apropos-in) (each-dir) ;

\ Print the version/banner string (same text shown at startup). The string is
\ supplied by the (version-str) primitive so it always matches the build.
: version ( -- )  (version-str) type ;

\ --- SHELL-LIKE WORDS: navigate and inspect the filesystem from the REPL.
\ `cd` changes the real process directory (so relative include/open agree with
\ it); session.fs stays pinned to the startup directory. Path tokens come from
\ parse-word, so they can't contain spaces yet.
: pwd ( -- )  (cwd) type cr ;
\ Expand a leading ~ to $HOME: only "~" or "~/sub" expand ("~" -> HOME,
\ "~/sub" -> HOME + "/sub"). "~user" is a different, unsupported form and is left
\ unchanged, as is a token without a leading ~ or one where HOME is unset. The
\ result is bounded by (tilde-sz): an over-long HOME+tail is left unexpanded
\ rather than overrunning the buffer. Reuses (sp-add) from the session builder.
1024 constant (tilde-sz)
create (tilde-buf) (tilde-sz) allot
: (tilde-expand) ( c-addr u -- c-addr2 u2 )
    dup 0= if exit then                        \ empty -> unchanged
    over c@ [char] ~ = 0= if exit then         \ no leading ~ -> unchanged
    dup 1 > if                                 \ "~x...": only "~/..." expands
        over 1+ c@ [char] / = 0= if exit then  \   "~user" is unsupported -> unchanged
    then
    (home-dir) nip 0= if exit then             \ HOME unset -> leave ~ (chdir errors)
    (home-dir) nip  over 1- +                  ( c-addr u need )  \ HOME + (token past ~)
    (tilde-sz) 1- > if exit then               \ need >= buffer/chdir limit -> leave ~
    (tilde-buf) (sp-end) !
    (home-dir) (sp-add)                        \ HOME
    1 /string (sp-add)                         \ the rest of the token after the ~
    (tilde-buf) (sp-end) @ over - ;            \ ( c-addr2 u2 )
\ Parse the next token as a path, expanding a leading ~ to $HOME. Used by every
\ path-taking shell word so ~ works uniformly (cd / pushd / ls / cat / more).
: (parse-path) ( -- c-addr u )  parse-word (tilde-expand) ;
: cd ( "path" -- )
    (parse-path)                            ( c-addr u )   \ ~ already expanded
    dup 0= if  2drop  (startup-dir)  then   \ bare cd -> startup (home) directory
    2dup chdir                              ( c-addr u ior )
    if  ." cd: cannot access " type cr  abort  else  2drop  then ;

\ ls: list a directory (the current one by default), one entry per line, using
\ the same getdents machinery as the help browser. "." and ".." are skipped.
: (dotdir?) ( c-addr u -- f )            \ is the name "." or ".."?
    dup 1 = if  drop c@ [char] . =  exit  then
    dup 2 = if  drop dup c@ [char] . = swap 1+ c@ [char] . = and  exit  then
    2drop false ;
: ls ( "[dir]" -- )
    (parse-path)                            ( c-addr u )
    dup 0= if  2drop s" ."  then            \ no argument -> current directory
    r/o open-file if  drop ." ls: cannot open directory" cr abort  then  ( fileid )
    >r
    begin
        r@ (gd@) (gd-size) (getdents)        ( n )
        dup 0< if  ." ls: read error" cr  r> close-file drop abort  then  \ negative errno
        dup 0> while                          ( n )
        (gd@) +  (gd@)                         ( end ptr )
        begin 2dup u> while                    ( end ptr )
            dup (de-name) dup (cstr-len)       ( end ptr name namelen )
            2dup (dotdir?) 0= if  type cr  else  2drop  then   ( end ptr )
            dup (de-reclen) +                  ( end nextptr )
        repeat 2drop
    repeat drop
    r> close-file drop ;

\ cat: dump a file to stdout (no paging). Reuses the pager's line buffer for
\ chunked reads. more: page a file a screenful at a time (built on page-file).
\ (`page` already means clear-screen, so the paged viewer is `more`.)
\ Error paths ABORT after reporting (closing any open file first), so the REPL
\ shows the message and no " ok" — a failed command must not look like success.
: cat ( "file" -- )
    (parse-path)                            ( c-addr u )
    dup 0= if  2drop ." usage: cat <file>" cr abort  then
    r/o open-file if  drop ." cat: cannot open file" cr abort  then  ( fileid )
    >r
    begin
        (pg-buf@) (pg-bufsz) r@ read-file   ( u2 ior )
        if  ." cat: read error" cr  drop  r> close-file drop abort  then   ( u2 )
        dup 0>                               ( u2 f )   \ 0 bytes (no error) = EOF
    while                                    ( u2 )
        \ Write to stdout via write-file (fd 1) rather than TYPE, so a write
        \ failure (broken pipe, ENOSPC) is surfaced instead of silently ignored.
        (pg-buf@) swap 1 write-file          ( ior )
        if  ." cat: write error" cr  r> close-file drop abort  then
    repeat  drop
    r> close-file drop ;
: more ( "file" -- )
    (parse-path)                            ( c-addr u )
    dup 0= if  2drop ." usage: more <file>" cr abort  then
    r/o open-file if  drop ." more: cannot open file" cr abort  then  ( fileid )
    \ page-file closed the fd and reported any read error; abort so a failed
    \ `more` doesn't return " ok". Safe here: top-level word, no fd held.
    page-file if  abort  then ;

\ Directory stack: pushd saves the current dir (absolute) and cd's to a new one;
\ popd returns to the most recently saved dir; dirs lists current + saved (top
\ first). Saved paths are absolute, so popd is correct across intervening cds.
16   constant (ds-max)                     \ max directory-stack depth
1024 constant (ds-slot)                    \ max bytes per saved path
variable (ds-buf)                          \ heap: (ds-max)*(ds-slot) path bytes (lazy)
create  (ds-len) (ds-max) cells allot      \ length of each saved path
variable (ds-n)                            \ number of saved entries
: (ds-buf@) ( -- a )
    (ds-buf) @ ?dup if exit then
    (ds-max) (ds-slot) * allocate abort" pushd: out of memory" dup (ds-buf) ! ;
: (ds-slot-at) ( i -- a )  (ds-slot) * (ds-buf@) + ;
: (ds-len-at)  ( i -- a )  cells (ds-len) + ;
: (ds-store) ( c-addr u i -- )             \ save path (c-addr u) into slot i
    >r
    dup r@ (ds-len-at) !                    \ (ds-len)[i] := u
    r> (ds-slot-at)  swap cmove ;           \ copy the bytes into slot i
: (ds-fetch) ( i -- c-addr u )  dup (ds-slot-at) swap (ds-len-at) @ ;
: pushd ( "dir" -- )
    (parse-path)                            ( c-addr u )
    dup 0= if  2drop ." usage: pushd <dir>" cr abort  then
    (ds-n) @ (ds-max) < 0= if  2drop ." pushd: stack full" cr abort  then
    \ save the current dir BEFORE cd (into slot n; commit n only if cd succeeds)
    (cwd) dup (ds-slot) < 0= if             ( c-addr u cwd-a cwd-u )
        2drop 2drop ." pushd: path too long" cr abort  then
    (ds-n) @ (ds-store)                     ( c-addr u )
    2dup chdir if  ." pushd: cannot access " type cr abort  then  ( c-addr u )
    2drop  1 (ds-n) +! ;
: popd ( -- )
    (ds-n) @ 0= if  ." popd: directory stack empty" cr abort  then
    \ Try the restore BEFORE popping, so a failed chdir (the saved dir vanished)
    \ keeps the entry on the stack instead of silently losing it.
    (ds-n) @ 1- (ds-fetch)                   ( c-addr u )   \ top entry; not popped yet
    chdir if  ." popd: cannot restore directory" cr abort  then
    -1 (ds-n) +! ;                           \ restored OK -> now pop the entry
: dirs ( -- )                              \ current dir, then saved dirs top-first
    (cwd) type
    (ds-n) @ 0 ?do
        space  (ds-n) @ 1- i - (ds-fetch) type
    loop  cr ;

\ --- TUTORIAL: walk a docs file one "## " step at a time, returning to the
\ REPL after each step so you can type the examples, then  next / back  to move.
\ A tutorial is just a <name>.md file in the docs dirs (resolved like MAN); each
\ level-2 heading "## ..." starts a new step, and the title + intro before the
\ first heading is step 1.
80 constant (tut-max)
create (tut-name) (tut-max) allot         \ stable copy of the current tutorial name
variable (tut-nlen)                        \ its length (0 = no tutorial started)
variable (tut-step)                        \ current step (1-based)
variable (tut-found)                       \ matching file located this pass?
variable (tut-existed)                     \ requested step existed in the file?
variable (ts-want)                         \ step (print-step) should print
variable (ts-cur)                          \ step counter while scanning
variable (ts-any)                          \ printed any line of the wanted step?
: (tut-head?) ( c-addr u -- f )            \ does the line begin with "## "?
    3 u< if drop false exit then
    dup c@ [char] # =
    over 1+ c@ [char] # = and
    swap 2 + c@ bl = and ;
: (print-step) ( fileid -- existed? )      \ print step (ts-want); paged; close file
    (tty?) if page then
    0 (pg-row) ! false (pg-quit) !
    1 (ts-cur) !  false (ts-any) !
    >r
    begin
        (pg-buf@) (pg-bufsz) r@ read-line  ( u flag ior )
        if  2drop  r> close-file drop (ts-any) @ exit  then     \ I/O error
        if                                 ( u )                \ got a line
            (pg-buf@) over (tut-head?) if  \ heading: step boundary
                1 (ts-cur) +!
                (ts-cur) @ (ts-want) @ u> if
                    drop r> close-file drop (ts-any) @ exit
                then
            then
            (ts-cur) @ (ts-want) @ = if
                (pg-buf@) swap (pg-line) true (ts-any) !
            else drop then
            (pg-quit) @ if r> close-file drop (ts-any) @ exit then
        else  drop  r> close-file drop (ts-any) @ exit  then    \ EOF
    again ;
: (tut-in) ( dir-addr dir-u -- )           \ scan one docs dir for <name>.md
    (tut-found) @ if 2drop exit then
    (md-dirn) ! (md-dir) !
    (md-dir) @ (md-dirn) @ r/o open-file if drop exit then   ( fileid )
    >r
    begin
        r@ (gd@) (gd-size) (getdents)           ( n )
        dup 0> while
        (gd@) + (gd@)                           ( end ptr )
        begin 2dup u> while                     ( end ptr )
            dup (de-name) dup (cstr-len)        ( end ptr name namelen )
            2dup (ends-md?) if
                2dup 3 - (tut-name) (tut-nlen) @ (ci=) if
                    true (tut-found) !
                    (build-path) r/o open-file  ( end ptr fileid ior )
                    if drop else (print-step) (tut-existed) ! then
                    2drop r> close-file drop exit
                then
            then
            2drop  dup (de-reclen) +
        repeat 2drop
    repeat drop
    r> close-file drop ;
: (tut-go) ( -- )                          \ show (tut-step) of the current tutorial
    false (tut-found) !  false (tut-existed) !
    (tut-step) @ (ts-want) !
    (docs-path) nip 0= if  ." (BASICFORTH_DOCS not set)" cr exit  then
    ['] (tut-in) (each-dir)
    (tut-found) @ 0= if
        ." no tutorial named " (tut-name) (tut-nlen) @ type ."  (try TOPICS)" cr
        0 (tut-nlen) ! exit
    then
    (tut-existed) @ 0= if
        ." -- end of '" (tut-name) (tut-nlen) @ type ." ' --" cr
        ." Type  back  to review,  end-tutorial  to leave, or  tutorial <name>  to start another." cr
        (tut-step) @ 1 > if -1 (tut-step) +! then         \ clamp so back works
        exit
    then
    cr ." [ step " (tut-step) @ 0 u.r ." :  next   back   step [n] = replay/jump   end-tutorial ]" cr ;
defer (step-val?)                          \ ( a u -- n true | false ) value-name
:noname 2drop false ; is (step-val?)       \ lookup; real body after (nt-by-name)
: (step#?) ( -- n true | false )           \ parse optional step: number or value
    >in @ >r  parse-word                    ( a u )
    dup 0= if 2drop r> drop false exit then
    2dup 0 0 2swap >number nip              ( a u ud u2 )
    0= if  drop nip nip  r> drop  true exit  then   \ fully numeric: ( n true )
    2drop                                   ( a u )
    (step-val?) if  r> drop  true exit  then        \ a value's contents
    r> >in !  false ;                       \ neither: un-parse it
: tutorial ( "name" ["step"] -- )
    parse-word (tut-max) min                ( c-addr u )
    dup 0= if 2drop
        ." usage: tutorial <name> [step]   then  next / back / step  to move" cr
        topics exit
    then
    dup (tut-nlen) !                        ( c-addr u )
    >r (tut-name) r> cmove
    1 (tut-step) !
    (step#?) if 1 max (tut-step) ! then     \ tutorial chase 10 = resume there
    (tut-go) ;
: next ( -- )
    (tut-nlen) @ 0= if ." (start a tutorial first: tutorial <name>)" cr exit then
    1 (tut-step) +! (tut-go) ;
: back ( -- )
    (tut-nlen) @ 0= if ." (start a tutorial first: tutorial <name>)" cr exit then
    (tut-step) @ 1 > if -1 (tut-step) +! then (tut-go) ;
: step ( ["step"] -- )                     \ replay current step; step 10 = jump
    (step#?)                                ( n true | false )
    (tut-nlen) @ 0= if
        if drop then
        ." (start a tutorial first: tutorial <name>)" cr exit
    then
    if 1 max (tut-step) ! then
    (tut-go) ;
: end-tutorial ( -- )                      \ drop the bookmark; definitions remain
    (tut-nlen) @ 0= if ." (no tutorial in progress)" cr exit then
    0 (tut-nlen) !
    ." (tutorial ended -- your definitions remain)" cr ;

\ ===== .MODULE : the words in your module =====
\ WORDS dumps the whole dictionary (~330 built-ins); .MODULE shows just what YOU
\ added on top of core.fs — your module — the BASIC "LIST": "what have I built?".
\ It walks the dictionary chain (newest-first: link at offset 0, flags+len at
\ offset 8 with the length in the low 5 bits, name at offset 9) from LATEST back
\ to (sw-mark) — the dictionary head captured when core.fs finished loading.
\ Everything past that mark is your module (a LOADed file or anything INCLUDEd
\ at the REPL counts too).
variable (sw-mark)                          \ LATEST at end of core.fs (module start)

: (sw-name) ( nt -- c-addr u )              \ name slice of a dictionary entry
    dup 10 +  swap 8 + c@ 31 and ;
: (sw-anon?) ( nt -- f )                    \ :noname entry (empty name)?
    8 + c@ 31 and 0= ;
: (sw-end?) ( nt -- nt f )                  \ true when nt is the boundary or chain end
    dup (sw-mark) @ =  over 0= or ;
: (sw-count) ( -- n )
    0 (latest@)
    begin (sw-end?) 0= while
        dup (sw-anon?) 0= if  swap 1+ swap  then  @  repeat  drop ;
: (sw-list) ( -- )
    (latest@)
    begin (sw-end?) 0= while
        dup (sw-anon?) 0= if  dup (sw-name) type space  then  @  repeat  drop  cr ;

: .module ( -- )
    (sw-count) ?dup 0= if
        ." (empty module — no words defined yet)" cr exit
    then
    dup .  1 = if ." word" else ." words" then
    ."  in this module (newest first):" cr
    (sw-list) ;

\ ===== USES : which module words reference a given word =====
\ `uses <word>` lists the module words whose source mentions <word> as a whole
\ token (case-insensitive) — a grep over your own definitions, handy before
\ renaming something. It resolves each word's source the way SEE does — from the
\ capture log for words typed at the REPL, or from the file for words LOADed /
\ INCLUDEd — so it covers everything .MODULE lists, skipping only <word>'s own
\ defining line. A :noname group that is the current action of a deferred word
\ is covered too, reported as (:noname is <name>); superseded groups are not.
variable (uses-xt)
: (src-of) ( xt -- c-addr u true | false )  \ captured source span of xt, if any
    (uses-xt) !
    (dir) cell+ @ 3 cells /                 ( count )
    begin dup 0> while
        1-  dup 3 cells * (dir) @ +         ( i rec )       \ newest record first
        dup 2 cells + @ (uses-xt) @ = if    ( i rec )       \ rec's xt == target?
            dup @ (log) @ +  swap cell+ @   ( i c-addr u )
            rot drop  true exit
        then
        drop                                ( i )
    repeat
    drop  false ;

variable (u-src)   variable (u-srclen)
variable (u-tgt)   variable (u-tgtlen)   variable (u-pos)
: (u-ws?) ( i -- f )  (u-src) @ + c@ 33 < ;     \ char at offset i is a delimiter?
: (word-in?) ( src u t tu -- f )            \ does src contain t as a whole token (ci)?
    (u-tgtlen) !  (u-tgt) !  (u-srclen) !  (u-src) !
    0 (u-pos) !
    begin (u-pos) @ (u-srclen) @ < while
        (u-pos) @ (u-ws?) if  1 (u-pos) +!
        else
            (u-pos) @                       ( tok-start )
            begin (u-pos) @ (u-srclen) @ <  (u-pos) @ (u-ws?) 0=  and
            while  1 (u-pos) +!  repeat
            (u-src) @ over +  (u-pos) @ rot -   ( tok-addr tok-len )
            (u-tgt) @ (u-tgtlen) @ (ci=) if  true exit  then
        then
    repeat
    false ;

\ Source of a FILE-loaded word (srcid >= 1): read its file once and index into
\ it. (uf-buf) caches the most recently read file's whole contents, so a run of
\ words from the same file — the common case — costs a single read. Reuses SEE's
\ span reader ((sf-*)).
variable (uf-srcid)  variable (uf-buf)  variable (uf-len)
: (uf-free) ( -- )  (uf-buf) @ if  (uf-buf) @ free drop  0 (uf-buf) !  then  0 (uf-srcid) ! ;
: (uf-want) ( srcid -- ok? )                \ ensure (uf-buf) holds this srcid's file
    dup (uf-srcid) @ = if  drop  (uf-buf) @ 0<>  exit  then   \ already cached
    (uf-free)
    dup (source-path) dup 0= if  2drop drop  false exit  then  ( srcid c-addr u )
    r/o open-file if  drop  false exit  then  ( srcid fileid )
    (sf-fid) !                                ( srcid )
    (sf-fid) @ file-size if                   ( srcid lo hi )
        2drop  (sf-fid) @ close-file drop  drop  false exit  then
    drop  dup (sf-need) !                     ( srcid size )
    allocate if                               ( srcid a )
        drop  (sf-fid) @ close-file drop  drop  false exit  then
    dup (sf-buf) !  (uf-buf) !                ( srcid )
    (sf-read)
    (sf-got) @ (uf-len) !
    (uf-srcid) !
    (sf-fid) @ close-file drop
    true ;
: (file-span) ( off len srcid -- c-addr u true | false )
    (uf-want) 0= if  2drop  false exit  then  ( off len )
    over (uf-len) @ <  0= if  2drop false exit  then       \ off past EOF
    over (uf-len) @ swap -  min               ( off u )    \ u = min(len, uf-len-off)
    swap (uf-buf) @ +  swap  true ;

\ --- header introspection: word type, code span, recorded source ---
\ Every header (named or :noname) records its Flags2 type, code span, and source
\ metadata; these read them back. (nt-src) resolves the recorded source from the
\ capture log (srcid 0) or the source file. (anon-owner) answers "which deferred
\ word currently runs this :noname?" — the identity USES and edit-propagation
\ report a live anonymous definition by, as (:noname is <name>).
: (nt-type) ( nt -- type )  9 + c@ 15 and ;  \ Flags2 word-type code
: (nt>code) ( nt -- xt len )                 \ a word's code span, from its header
    dup 8 + c@ 31 and 10 + 7 + -8 and +      ( cp-addr )
    dup @  swap 8 + l@ ;
: (xt>nt) ( xt -- nt true | false )          \ header owning this xt (incl. :noname)
    (latest@)
    begin dup while                          ( xt nt )
        dup 8 + c@ 64 and 0= if
            2dup (xt-of) = if  nip true exit  then
        then
        @
    repeat
    2drop  false ;
: (nt-meta) ( nt -- off len srcid )          \ source-metadata fields of a header
    dup 8 + c@ 31 and 10 + 7 + -8 and +      ( cp-addr )
    dup 16 + l@  over 14 + w@  rot 12 + w@ ;
: (nt-src) ( nt -- c-addr u true | false )   \ a header's recorded source (log/file)
    dup (nt-meta)                            ( nt off len srcid )
    dup 0= if                                \ REPL word: source from the capture log
        drop 2drop  (nt>code) drop  (src-of)  exit  then
    >r >r >r drop r> r> r>  (file-span) ;    \ file word: (off len srcid)
: (anon-owner) ( xt -- nt true | false )     \ deferred word whose CURRENT action is xt
    (latest@)
    begin dup while                          ( xt nt )
        dup 8 + c@ 64 and 0= if
            dup (nt-type) 1 = if
                2dup (xt-of) defer@ = if  nip true exit  then
            then
        then
        @
    repeat
    2drop  false ;

variable (uses-t)  variable (uses-tu)  variable (uses-n)
variable (uh-xt)  variable (uh-off)  variable (uh-len)  variable (uh-srcid)
: (word-src) ( nt -- c-addr u true | false )  \ source of the in-force def named by nt
    dup (sw-anon?) if  drop  false exit  then  \ :noname: no name to look up — an empty
                                               \ name would MATCH the newest anon; use
                                               \ (nt-src) for a specific anon's source
    dup (sw-name) (find-meta)                 ( nt xt off len srcid flag )
    0= if  2drop 2drop drop  false exit  then  \ name not currently defined
    (uh-srcid) !  (uh-len) !  (uh-off) !  (uh-xt) !   ( nt )
    (xt-of) (uh-xt) @ <> if  false exit  then  \ a shadowed (not in-force) entry → skip
    (uh-srcid) @ 65535 = if  false exit  then  \ primitive: no source
    (uh-srcid) @ 0= if
        (uh-xt) @ (src-of)                     \ REPL word: from the capture log
    else
        (uh-off) @ (uh-len) @ (uh-srcid) @ (file-span)   \ file word: from its source file
    then ;
: (uses-hit?) ( nt -- f )                   \ does this word reference the target?
    dup (sw-name) (uses-t) @ (uses-tu) @ (ci=) if  drop false exit  then  \ skip its own def
    (word-src) if  (uses-t) @ (uses-tu) @ (word-in?)  else  false  then ;
: (uses-anon?) ( nt -- f )                  \ live :noname group referencing the target?
    dup (nt>code) drop (anon-owner) 0= if  drop  false exit  then  ( nt owner )
    (sw-name) (uses-t) @ (uses-tu) @ (ci=) if  drop false exit  then  \ skip its own `is` line
    (nt-src) if  (uses-t) @ (uses-tu) @ (word-in?)  else  false  then ;
: (.anon) ( nt -- )                         \ label a LIVE anon by its deferred word
    ." (:noname is "  (nt>code) drop (anon-owner) drop (sw-name) type  ." )" ;
: uses ( "name" -- )
    parse-word  dup 0= if  2drop  ." usage: uses <word>" cr  exit  then
    (uses-tu) !  (uses-t) !
    0 (uses-n) !
    (uses-t) @ (uses-tu) @ type ."  is used by:"
    (latest@)
    begin  dup (sw-mark) @ <>  over 0<>  and  while   ( nt )
        dup (sw-anon?) if                    \ a :noname group: report it if it is the
            dup (uses-anon?) if              \ CURRENT action of some deferred word
                space  dup (.anon)  1 (uses-n) +!  then
        else
            dup (uses-hit?) if  space  dup (sw-name) type  1 (uses-n) +!  then
        then
        @
    repeat  drop
    (uf-free)                                  \ release the cached source file
    (uses-n) @ 0= if  ."  (none)"  then  cr ;

\ ===== Deferred-word introspection: ACTION-OF + SEE's binding report =====
\ `defer@` (asm) reads a deferred word's action cell. ACTION-OF is the checked,
\ named form. SEE uses them to append what a deferred word currently does:
\ uninitialized / bound to a named word / set by a logged assignment line.

: (nt-by-name) ( c-addr u -- nt true | false )   \ in-force header for a name
    (latest@)
    begin dup while                          ( c-addr u nt )
        dup 8 + c@ 64 and 0= if              \ skip hidden entries
            dup (sw-name)  4 pick 4 pick (ci=) if
                nip nip  true exit
            then
        then
        @
    repeat
    drop 2drop  false ;

\ (step-val?) real body: fetch a VALUE's contents by name, for the optional
\ step argument of tutorial/step. Only type-2 (value) words execute — a value
\ just pushes its cell, so this is side-effect free; anything else is refused
\ and the caller un-parses the token.
:noname ( c-addr u -- n true | false )
    (nt-by-name) 0= if false exit then       ( nt )
    dup (nt-type) 2 <> if drop false exit then
    (nt>code) drop execute  true ;  is (step-val?)

: action-of ( "name" -- xt )                 \ a deferred word's current action
    parse-word 2dup (nt-by-name) 0= if
        type ." : not found" cr abort  then  ( c-addr u nt )
    dup (nt-type) 1 <> if
        drop type ." : not a deferred word" cr abort  then
    nip nip  (xt-of) defer@ ;

: (xt>name) ( xt -- c-addr u true | false )  \ NAME owning this xt (:noname skipped)
    (xt>nt) 0= if  false exit  then          ( nt )
    dup (sw-anon?) if  drop false exit  then
    (sw-name) true ;

\ --- last direct-assignment line in the log targeting a given name ---
variable (t2-fa) variable (t2-fu)            \ a line's first token
variable (t2-pa) variable (t2-pu)            \ ...second-to-last token
variable (t2-la) variable (t2-lu)            \ ...last token
variable (l2-src) variable (l2-len) variable (l2-pos)
: (l2-ws?) ( i -- f )  (l2-src) @ + c@ 33 < ;
: (last2!) ( a u -- )                        \ record first + last two tokens
    (l2-len) !  (l2-src) !  0 (l2-pos) !
    0 (t2-fu) !  0 (t2-pu) !  0 (t2-lu) !
    begin (l2-pos) @ (l2-len) @ < while
        (l2-pos) @ (l2-ws?) if  1 (l2-pos) +!
        else
            (l2-pos) @                       ( tok-start )
            begin (l2-pos) @ (l2-len) @ <  (l2-pos) @ (l2-ws?) 0=  and
            while  1 (l2-pos) +!  repeat
            (t2-la) @ (t2-pa) !  (t2-lu) @ (t2-pu) !
            (l2-src) @ over +  (t2-la) !  (l2-pos) @ swap - (t2-lu) !
            (t2-fu) @ 0= if  (t2-la) @ (t2-fa) !  (t2-lu) @ (t2-fu) !  then
        then
    repeat ;
variable (sb-t)  variable (sb-tu)            \ the binding target being searched
: (assign-line?) ( a u -- f )                \ "... is <target>" / "... to <target>"?
    (last2!)
    (t2-fa) @ (t2-fu) @ s" \" (ci=) if  false exit  then   \ not a comment line
    (t2-la) @ (t2-lu) @ (sb-t) @ (sb-tu) @ (ci=) 0= if  false exit  then
    (t2-pa) @ (t2-pu) @ s" is" (ci=)
    (t2-pa) @ (t2-pu) @ s" to" (ci=)  or ;
variable (sb-a)  variable (sb-u)             \ best (= last) matching line
: (last-assign?) ( -- f )                    \ leaves the line in (sb-a)/(sb-u)
    0 (sb-a) !
    (log) @ (rd-a) !  (log) cell+ @ (rd-u) !
    begin (rd-u) @ 0> while
        10 (rd-chpos)                        ( linelen )
        (rd-a) @ over (assign-line?) if
            (rd-a) @ (sb-a) !  dup (sb-u) !
        then
        dup (rd-u) @ < if 1+ then
        dup (rd-a) +!  (rd-u) @ swap - (rd-u) !
    repeat
    (sb-a) @ 0<> ;

variable (sb-xt)  variable (sb-len)  variable (sb-act)
: (see-binding) ( -- )                       \ SEE's report for a deferred word
    (see-a) @ (see-u) @ (nt-by-name) 0= if  exit  then   ( nt )
    dup (nt-type) 1 <> if  drop exit  then   \ only deferred words
    (nt>code)  (sb-len) !  dup (sb-xt) !  defer@ (sb-act) !
    (sb-act) @  (sb-xt) @  (sb-xt) @ (sb-len) @ +  within if
        ." \ currently: uninitialized" cr  exit  then   \ still the uninit stub
    (sb-act) @ (xt>name) if                  ( c-addr u )
        ." \ currently: ' " type ."  is " (see-a) @ (see-u) @ type cr  exit  then
    (sb-act) @ (xt>nt) if                    ( nt )    \ a :noname — its own header
        dup (sw-anon?) if                    \ carries the recorded source
            (nt-src) if
                ." \ currently: " cr  type  (uf-free)  exit  then
            (uf-free)
        else drop then
    then
    ." \ currently: an unnamed word (no recorded source)" cr ;
' (see-binding) is (see-post)

\ ===== EDIT-propagation body (armed by `edit`, fired from (capture-line)) =====
\ Subroutine threading bakes call targets, so redefining a word doesn't reach its
\ callers. After `edit <word>` resubmits, recompile every module word that
\ (transitively) uses it. Walk the module words oldest-first (definition order is
\ a valid dependency order) with a growing dirty set, recompiling each affected
\ caller from its source (log or file, via (word-src)) and re-logging it so
\ SEE/USES/SAVE stay correct. A :noname group whose anon is the CURRENT action
\ of a deferred word is re-run whole (the trailing `is` re-binds); its defer is
\ NOT added to the dirty set — callers reach it through the action cell.
8192 constant (prop-max)                    \ max source bytes of one definition handled
create (prop-src) (prop-max) allot          \ scratch copy (survives a log realloc)
512 constant (prop-nmax)
create (prop-nts) (prop-nmax) cells allot   \ snapshot of the module's entries (newest-first)
variable (prop-n)
create (prop-dirty) 4096 allot              \ space-separated names known to need recompiling
variable (prop-dirty-len)
variable (prop-count)                       \ how many callers were recompiled

: (prop-dirty+) ( c-addr u -- )             \ add a name to the dirty set
    dup (prop-dirty-len) @ + 2 + 4096 > if  2drop exit  then
    (prop-dirty) (prop-dirty-len) @ +  (sp-end) !
    (sp-add)  s"  " (sp-add)
    (sp-end) @ (prop-dirty) - (prop-dirty-len) ! ;
: (prop-name-dirty?) ( c-addr u -- f )      \ is this name already in the dirty set?
    (prop-dirty) (prop-dirty-len) @  2swap  (word-in?) ;

variable (pmd-src)  variable (pmd-srclen)  variable (pmd-pos)
: (pmd-ws?) ( i -- f )  (prop-dirty) + c@ 33 < ;
: (prop-mentions-dirty?) ( src u -- f )     \ does this source mention any dirty word?
    (pmd-srclen) !  (pmd-src) !
    0 (pmd-pos) !
    begin (pmd-pos) @ (prop-dirty-len) @ < while
        (pmd-pos) @ (pmd-ws?) if  1 (pmd-pos) +!
        else
            (pmd-pos) @                     ( tok-start )
            begin (pmd-pos) @ (prop-dirty-len) @ <  (pmd-pos) @ (pmd-ws?) 0=  and
            while 1 (pmd-pos) +! repeat
            (prop-dirty) over +  (pmd-pos) @ rot -      ( tok-addr tok-len )
            (pmd-src) @ (pmd-srclen) @ 2swap (word-in?) if  true exit  then
        then
    repeat
    false ;

variable (ev-d0)                            \ stack depth before the re-evaluation
: (eval+log) ( c-addr u -- )                \ evaluate source as a new def + log it (srcid 0)
    dup (prop-max) > if  2drop exit  then    ( c-addr u )
    >r  (prop-src) r@ cmove  r>             ( u )       \ copy out (survive log realloc)
    (log) cell+ @  >r                       ( u )       \ R: log-off
    (prop-src) over (log) (buf-append)      ( u )       \ append source to the log
    (nl) 1 (log) (buf-append)               ( u )       \ + a newline separator
    depth (ev-d0) !
    (log) @ r@ +  over  (rd-eval-lines)     ( u )       \ compile from the log copy
    begin depth (ev-d0) @ > while  drop  repeat        \ a definition group must
                                            \ leave nothing: drop its leftovers
                                            \ (they sit above our u) so the
                                            \ caller's stack frame cannot shift
    r>  over  (latest@) (dir-add)           ( u )       \ index the new word's source
    drop  true (dirty) ! ;
: (prop-recompile) ( nt -- )                \ re-evaluate nt's source + re-log it
    (word-src) 0= if  exit  then            ( c-addr u )
    (eval+log)  1 (prop-count) +! ;

: (prop-snapshot) ( -- )                    \ collect the module's entries (newest-first)
    0 (prop-n) !
    (latest@)
    begin (sw-end?) 0= while
        (prop-n) @ (prop-nmax) < if
            dup  (prop-n) @ cells (prop-nts) +  !  1 (prop-n) +!
        then
        @
    repeat drop ;

: (prop-anon) ( nt -- )                     \ re-run a live :noname group that calls a dirty word
    dup (nt>code) drop (anon-owner) 0= if  drop exit  then   ( nt owner )
    >r                                       \ superseded groups have no owner and are
                                             \ skipped: re-running one would clobber a
                                             \ NEWER binding of the same deferred word
    (nt-src) 0= if  r> drop exit  then       ( c-addr u ) ( R: owner )
    2dup (prop-mentions-dirty?) 0= if  2drop  r> drop  exit  then
    (eval+log)  1 (prop-count) +!            \ re-fires the group's trailing `is`
    space ." (:noname is "  r> (sw-name) type  ." )" ;
: (prop-one) ( nt -- )                      \ recompile this word if it uses a dirty word
    dup (sw-anon?) if  (prop-anon) exit  then   \ :noname group: re-run it (re-binds)
    dup (sw-name) (prop-name-dirty?) if  drop exit  then   \ already dirty → skip
    dup (word-src) 0= if  drop exit  then    ( nt c-addr u )
    (prop-mentions-dirty?) 0= if  drop exit  then  ( nt )
    dup (prop-recompile)
    dup (sw-name) (prop-dirty+)
    space (sw-name) type ;

: (propagate) ( c-addr u -- )               \ recompile the edited word's transitive callers
    0 (prop-dirty-len) !  0 (prop-count) !
    (prop-dirty+)                           \ the edited word is dirty
    (prop-snapshot)
    ." updated:"
    (prop-n) @ 0 ?do
        (prop-n) @ 1- i -  cells (prop-nts) + @    \ oldest-first
        (prop-one)
    loop
    (prop-count) @ 0= if  ."  (nothing)"  then  cr
    (uf-free) ;                             \ release the file cache used by (word-src)

\ ===== COMPACT: a deduped, dependency-ordered snapshot of the module =====
\ SAVE rewrites the whole loaded file verbatim (comments and all) then appends, so
\ redefinitions accumulate. COMPACT instead emits each module word's in-force
\ source ONCE, at its first (oldest) definition position — deduped, in dependency
\ order. It writes a sibling "<base>.compact<.ext>" so you can diff it against
\ SAVE's output; it drops the file's between-definition comments (definitions
\ only). Reuses the module snapshot and the SEE/USES source resolver.
create (cmp-seen) 4096 allot                \ space-separated names already written
variable (cmp-seen-len)
variable (cmp-fid)
variable (ld-pos)
: (cmp-seen+) ( c-addr u -- )
    dup (cmp-seen-len) @ + 2 + 4096 > if  2drop exit  then
    (cmp-seen) (cmp-seen-len) @ +  (sp-end) !
    (sp-add)  s"  " (sp-add)
    (sp-end) @ (cmp-seen) - (cmp-seen-len) ! ;
: (cmp-seen?) ( c-addr u -- f )  (cmp-seen) (cmp-seen-len) @ 2swap (word-in?) ;
: (src-by-name) ( c-addr u -- src-addr src-u true | false )  \ in-force source of a name
    (find-meta) 0= if  2drop 2drop  false exit  then         ( xt off len srcid )
    (uh-srcid) !  (uh-len) !  (uh-off) !  (uh-xt) !
    (uh-srcid) @ 65535 = if  false exit  then                \ primitive: no source
    (uh-srcid) @ 0= if  (uh-xt) @ (src-of)
    else  (uh-off) @ (uh-len) @ (uh-srcid) @ (file-span)  then ;
: (last-dot) ( c-addr u -- pos )            \ index of the last '.', or u if none
    dup (ld-pos) !
    0 ?do  dup i + c@ [char] . = if  i (ld-pos) !  then  loop  drop
    (ld-pos) @ ;
: (compact-name) ( c-addr u -- )            \ (path-a) := "<base>.compact<.ext>"
    2dup (last-dot) >r                       ( c-addr u )   \ R: dotpos
    (path-a) (sp-end) !
    over r@ (sp-add)  s" .compact" (sp-add)  r@ /string (sp-add)
    r> drop
    (sp-end) @ (path-a) - (path-a-len) ! ;
: (compact-one) ( nt -- )                   \ write this word's source if not already written
    dup (sw-anon?) if                        \ :noname: each is unique — emit its
        (nt-src) if                          \ whole group (it ends in `is <name>`,
            (cmp-fid) @ write-file abort" compact: write error"   \ so replaying
            (nl) 1 (cmp-fid) @ write-file abort" compact: write error"  \ rebinds)
        then  exit  then
    (sw-name) 2dup (cmp-seen?) if  2drop exit  then
    2dup (cmp-seen+)
    (src-by-name) if                         ( src-addr src-u )
        (cmp-fid) @ write-file abort" compact: write error"
        (nl) 1 (cmp-fid) @ write-file abort" compact: write error"
    then ;
\ (cmp-assign): a definitions-only snapshot would lose a deferred word's
\ binding and a value's contents — those live in direct `is`/`to` lines, not in
\ any definition. For each in-force defer/value in the module, append its LAST
\ logged direct assignment (found with SEE's (last-assign?) scanner), so the
\ compacted file loads to the same behavior the module has now.
: (cmp-assign) ( nt -- )
    dup (nt-type)  dup 1 =  swap 2 =  or  0= if  drop exit  then
    dup dup (sw-name) (nt-by-name) 0= if  2drop exit  then   ( nt nt nt' )
    = 0= if  drop exit  then                 ( nt )   \ shadowed entry → skip
    dup (nt-type) 1 = if                     \ defer bound to a :noname? its
        dup (nt>code) drop defer@            ( nt act )   \ emitted group already
        (xt>nt) if  (sw-anon?) if  drop exit  then  then  \ carries the binding
    then                                     ( nt )
    (sw-name)  (sb-tu) !  (sb-t) !
    (last-assign?) 0= if  exit  then          \ never directly assigned
    (sb-a) @ (sb-u) @ (cmp-fid) @ write-file abort" compact: write error"
    (nl) 1 (cmp-fid) @ write-file abort" compact: write error" ;

: compact ( "name" -- )
    parse-word dup 0= if
        2drop (cur-file@) dup 0= if
            drop ." compact: no current file (use: compact <name>)" cr exit
        then
    then                                     ( c-addr u )
    (compact-name)
    (path-a) (path-a-len) @ w/o create-file   ( fileid ior )
    abort" compact: cannot create file"       ( fileid )
    (cmp-fid) !
    0 (cmp-seen-len) !
    (prop-snapshot)
    (prop-n) @ 0 ?do
        (prop-n) @ 1- i - cells (prop-nts) + @    \ oldest-first
        (compact-one)
    loop
    (prop-n) @ 0 ?do                          \ final is/to binding per target
        (prop-n) @ 1- i - cells (prop-nts) + @
        (cmp-assign)
    loop
    (cmp-fid) @ close-file abort" compact: close error"
    (uf-free)
    ." compacted to " (path-a) (path-a-len) @ type cr ;

\ ===== sh : run a Linux command (the rest of the line) via the shell =====
\ `sh <command...>` runs the rest of the input line as a shell command, the way
\ you'd type it at a terminal — `sh ls -la`, `sh git status`. It is a thin word
\ over the (system) primitive (/bin/sh -c). Output goes straight to the terminal;
\ the exit status is discarded (call (system) yourself if you want it). `sh` runs
\ a transient command, so nothing is captured to the module. See
\ docs/Shelling_Out.md.
: sh ( "command<eol>" -- )
    10 parse                                 ( c-addr u )   \ the rest of the input line
    begin  dup 0> if  over c@ bl =  else  false  then  while
        1 /string                            \ trim leading spaces left after "sh"
    repeat
    dup 0= if  2drop  ." usage: sh <command>" cr exit  then
    (system) drop ;

\ ===== EDIT: open a word's source in an external editor, then recompile =====
\ `edit <name>` writes the word's current source to a temp file, opens it in your
\ editor ($VISUAL, else $EDITOR, else vi), and on a clean exit re-reads the file,
\ recompiles the word from it (preserving your multi-line formatting — unlike a
\ one-line REPL recall), and PROPAGATES the change to every module word that uses
\ it (subroutine threading bakes call targets, so callers must be recompiled too,
\ just as the redo/IS machinery handles). The edited definition is logged like a
\ REPL redefinition, so SEE/USES/SAVE see the new source even for a word that was
\ originally loaded from a file. The temp file is a fixed path, so two BasicForth
\ sessions editing at the same moment would share it (a known v1 limitation).
: (edit-tmp) ( -- c-addr u )  s" /tmp/basicforth-edit.fs" ;
variable (er-fid)  variable (er-buf)  variable (er-len)
: (edit-write) ( src-addr src-u -- ok? )    \ write the source span to the temp file
    (edit-tmp) w/o create-file if  drop 2drop  false exit  then  ( src-addr src-u fid )
    dup >r  write-file  r> close-file drop  0= ;             \ ok? = (write ior = 0)
: (edit-read) ( -- c-addr u true | false )  \ slurp the temp file into a fresh allocation
    (edit-tmp) r/o open-file if  drop  false exit  then      ( fid )
    (er-fid) !
    (er-fid) @ file-size if  2drop  (er-fid) @ close-file drop  false exit  then  ( lo hi )
    drop  dup (er-len) !                     ( size )        \ assume < 4 GB
    allocate if  drop  (er-fid) @ close-file drop  false exit  then   ( a )
    dup (er-buf) !
    (er-len) @  (er-fid) @  read-file        ( u2 ior )
    (er-fid) @ close-file drop
    if  drop  (er-buf) @ free drop  false exit  then         ( u2 )
    (er-buf) @ swap true ;                   ( c-addr u2 true )
: (edit-run) ( -- status )                  \ open the temp file in the user's editor
    \ The path here MUST match (edit-tmp); the shell resolves $VISUAL/$EDITOR/vi.
    s" ${VISUAL:-${EDITOR:-vi}} /tmp/basicforth-edit.fs" (system) ;
: (s=) ( a1 u1 a2 u2 -- f )                 \ exact string equality
    rot 2dup <> if  2drop 2drop  false exit  then
    drop                                     ( a1 a2 u )
    0 ?do  over i + c@  over i + c@  <> if  2drop  false unloop exit  then  loop
    2drop true ;
variable (ed-pre)  variable (ed-pu)          \ temp-file image before the editor ran
: (edit-src) ( src-addr src-u -- new? )     \ temp-file edit cycle; true if a def landed
    (edit-write) 0= if  ." edit: cannot write temp file" cr  false exit  then
    (edit-read) 0= if  ." edit: cannot read temp file" cr  false exit  then  ( pre-a pre-u )
    (ed-pu) !  (ed-pre) !                     \ pre-image: what the editor was given
    (edit-run) ?dup if                        ( status )
        (ed-pre) @ free drop
        ." edit: editor exited with status " . cr  false exit  then
    (edit-read) 0= if
        (ed-pre) @ free drop
        ." edit: cannot read temp file" cr  false exit  then  ( c-addr u )
    2dup (ed-pre) @ (ed-pu) @ (s=) if         \ file untouched (e.g. vi :q! exits 0)
        drop free drop  (ed-pre) @ free drop
        ." edit: unchanged" cr  false exit  then
    (ed-pre) @ free drop
    true (skip-capture) !                     \ keep THIS `edit` command line out of the log
    (latest@) >r                              \ R: LATEST before recompiling
    2dup (eval+log)  drop free drop           \ redefine + log; release the slurp
    (latest@) r> = if
        ." edit: no change" cr  false exit  then   \ the source defined nothing new
    true ;
: (edit-defer) ( nt -- )                     \ edit what a deferred word RUNS
    (nt>code) (sb-len) !  dup (sb-xt) !  defer@ (sb-act) !
    (sb-act) @  (sb-xt) @  (sb-xt) @ (sb-len) @ +  within if
        ." edit: " (see-a) @ (see-u) @ type ."  is uninitialized — set it first:  ' <word> is "
        (see-a) @ (see-u) @ type cr  exit  then
    (sb-act) @ (xt>name) if                  ( c-addr u )   \ bound to a named word
        ." edit: " (see-a) @ (see-u) @ type ."  is deferred — its action is "
        2dup type ." ; edit " type ."  instead" cr  exit  then
    (sb-act) @ (xt>nt) if                    ( nt' )   \ bound to a :noname — edit
        dup (sw-anon?) if                    \ ITS group; re-running it rebinds
            (nt-src) if  (edit-src) drop  (uf-free)  exit  then
            (uf-free)
        else drop then
    then
    ." edit: " (see-a) @ (see-u) @ type ."  is deferred; its action has no editable source" cr ;
: edit ( "name" -- )
    parse-word dup 0= if  2drop  ." edit: needs a word name" cr  exit  then
    (see-u) !  (see-a) !
    (see-a) @ (see-u) @ (find-meta)          ( xt off len srcid flag )
    0= if  2drop 2drop
        ." edit: " (see-a) @ (see-u) @ type ."  not found" cr exit  then
    dup 65535 = if  2drop 2drop
        ." edit: " (see-a) @ (see-u) @ type ."  is a primitive (assembly); cannot edit" cr exit  then
    2drop 2drop                              \ done with the meta cells
    (see-a) @ (see-u) @ (nt-by-name) if      ( nt )
        dup (nt-type) 1 = if  (edit-defer) exit  then   \ deferred: follow the binding
        drop
    then
    (see-a) @ (see-u) @ (src-by-name) 0= if
        ." edit: " (see-a) @ (see-u) @ type ."  has no editable source" cr exit  then  ( src-addr src-u )
    (edit-src) 0= if  exit  then
    (see-a) @ (see-u) @ (propagate) ;         \ recompile transitive callers (prints "updated:")

(latest@) (sw-mark) !                       \ .MODULE boundary: LATEST at end of core.fs
(session-mark!)                             \ -session/new/load restore point: HERE+LATEST
                                            \ here, so they forget the whole module (keep last!)
