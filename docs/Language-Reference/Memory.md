# Memory

BasicForth memory is byte-addressed; a **cell** is 8 bytes (64 bits). These
words read and write memory, compute addresses, and reserve space — in the
dictionary (`here`/`allot`) or on the heap (`allocate`). Get an address to
play with from `variable` or `create` (`help defining-words`).

At a glance:

    @        ( a-addr -- x )         fetch a cell
    !        ( x a-addr -- )         store a cell
    +!       ( n a-addr -- )         add n to the cell at addr
    ?        ( a-addr -- )           fetch and print
    c@       ( c-addr -- char )      fetch a byte
    c!       ( char c-addr -- )      store a byte
    2@       ( a-addr -- x1 x2 )     fetch two cells
    2!       ( x1 x2 a-addr -- )     store two cells
    w@       ( c-addr -- u )         fetch 16 bits, zero-extended
    w!       ( x c-addr -- )         store the low 16 bits
    l@       ( c-addr -- u )         fetch 32 bits, zero-extended
    l!       ( x c-addr -- )         store the low 32 bits
    cell+    ( a-addr -- a-addr+8 )  advance one cell
    cells    ( n -- n*8 )            n cells, in bytes
    char+    ( c-addr -- c-addr+1 )  advance one byte
    chars    ( n -- n )              n chars, in bytes
    fill     ( c-addr u char -- )    set u bytes to char
    erase    ( c-addr u -- )         zero u bytes
    move     ( addr1 addr2 u -- )    copy u bytes (overlap-safe)
    dump     ( addr u -- )           hex + ASCII memory dump

    Dictionary space:
    here     ( -- addr )             next free dictionary address
    allot    ( n -- )                reserve n dictionary bytes
    ,        ( x -- )                append a cell to the dictionary
    c,       ( char -- )             append a byte to the dictionary
    align    ( -- )                  pad HERE up to a cell boundary
    aligned  ( addr -- a-addr )      round an address up to a cell boundary

    Heap (OS-backed, outside the dictionary):
    allocate ( u -- a-addr ior )     get a block of u bytes
    free     ( a-addr -- ior )       release a block
    resize   ( a-addr1 u -- a-addr2 ior )  grow/shrink a block

Examples below use `variable`/`create` to make an address, and `.s` shows the
stack as `<count> bottom ... top`.

## @ ( a-addr -- x )
Fetch the cell stored at an address ("fetch").

    variable v  42 v !  v @ .     \ 42

## ! ( x a-addr -- )
Store a cell at an address ("store").

    variable v  42 v !  v @ .     \ 42

## +! ( n a-addr -- )
Add `n` to the cell at an address — read, add, write back.

    variable w  40 w !  5 w +!  w @ .   \ 45

## ? ( a-addr -- )
Fetch and print the cell at an address (`@ .`). Quick way to look at a
variable.

    variable v  42 v !  v ?     \ 42

## c@ ( c-addr -- char )
Fetch a single byte.

    create b 4 allot  65 b c!  b c@ .   \ 65

## c! ( char c-addr -- )
Store a single byte.

    create b 4 allot  65 b c!  b c@ .   \ 65

## 2@ ( a-addr -- x1 x2 )
Fetch two consecutive cells (the cell at `a-addr` ends up on top).

    create pr 2 cells allot  11 22 pr 2!  pr 2@ .s   \ <2> 11 22

## 2! ( x1 x2 a-addr -- )
Store two consecutive cells.

    create pr 2 cells allot  11 22 pr 2!  pr 2@ .s   \ <2> 11 22

## w@ ( c-addr -- u )
Fetch 16 bits, zero-extended into a cell. For packed records and FFI
structures; the address needs no particular alignment.

    create h 8 allot  -1 h w!  h w@ .   \ 65535

## w! ( x c-addr -- )
Store the low 16 bits of `x`.

    create h 8 allot  -1 h w!  h w@ .   \ 65535

## l@ ( c-addr -- u )
Fetch 32 bits, zero-extended into a cell.

    create h 8 allot  -1 h l!  h l@ .   \ 4294967295

## l! ( x c-addr -- )
Store the low 32 bits of `x`.

    create h 8 allot  -1 h l!  h l@ .   \ 4294967295

## cell+ ( a-addr -- a-addr+8 )
Advance an address by one cell.

    1 cell+ .         \ 9

## cells ( n -- n*8 )
Convert a cell count to a byte count — size arrays and offsets with it.

    1 cells .         \ 8

## char+ ( c-addr -- c-addr+1 )
Advance an address by one character (one byte).

    100 char+ .       \ 101

## chars ( n -- n )
Convert a character count to bytes — a no-op here (one char = one byte), but use
it for portable, self-documenting code.

    5 chars .         \ 5

## fill ( c-addr u char -- )
Set `u` bytes starting at `c-addr` to `char`.

    create buf 8 allot  buf 5 char * fill  buf 5 type   \ *****

## erase ( c-addr u -- )
Set `u` bytes to zero.

    create e 2 cells allot  99 e !  e 2 cells erase  e @ .   \ 0

## dump ( addr u -- )
Print `u` bytes starting at `addr` as a classic hex dump — address, sixteen
bytes per row in hex, then the same bytes as ASCII (unprintable bytes shown
as `.`).

    create msg 72 c, 105 c,
    msg 16 dump       \ one row: 48 69 ... |Hi..............|

## move ( addr1 addr2 u -- )
Copy `u` bytes from `addr1` to `addr2`, handling overlap correctly.

    create src 2 cells allot  create dst 2 cells allot
    11 src !  22 src cell+ !
    src dst 2 cells move  dst @ dst cell+ @ .s      \ <2> 11 22

## Dictionary space

The dictionary is where definitions and `create`d data live, growing upward
from `here`. Space taken with `allot`/`,` is permanent until a `marker` or
`forget` rolls it back — check what's left with `unused`. Prefer the heap
(below) for big runtime buffers.

## here ( -- addr )
The next free dictionary address. New definitions, `,`, and `allot` all
advance it.

    here 8 allot  here swap - .   \ 8

## allot ( n -- )
Reserve `n` bytes of dictionary space (advance `here`). The classic array
idiom pairs it with `create`:

    create buf 10 cells allot     \ buf: a 10-cell array
    7 buf 3 cells + !  buf 3 cells + @ .   \ 7

## , ( x -- )
Append a cell holding `x` to the dictionary ("comma"). Builds initialized
tables at compile time.

    create primes 2 , 3 , 5 , 7 ,
    primes 3 cells + @ .          \ 7

## c, ( char -- )
Append a single byte to the dictionary.

    create greet 72 c, 105 c,
    greet c@ emit  greet 1+ c@ emit   \ Hi

## align ( -- )
Advance `here` to the next 8-byte boundary (a no-op if already aligned). Use
after byte-granular building (`c,`, string data) before storing cells.

    create v 1 c, align 42 ,
    v 1+ aligned @ .              \ 42

## aligned ( addr -- a-addr )
Round an address up to the next 8-byte boundary (unchanged if already
aligned).

    9 aligned .                   \ 16

## The heap

`allocate`, `free`, and `resize` manage memory **outside** the dictionary
(backed by the OS), so large or transient buffers don't consume dictionary
space. Each returns an `ior` — `0` on success, non-zero on failure — so check it.

## allocate ( u -- a-addr ior )
Allocate `u` bytes. On success `a-addr` is the block and `ior` is `0`.

    16 allocate nip .     \ 0   (ior: success)

## free ( a-addr -- ior )
Release a block obtained from `allocate`/`resize`.

    16 allocate drop free .   \ 0

## resize ( a-addr1 u -- a-addr2 ior )
Grow or shrink a block to `u` bytes, preserving its contents; `a-addr2` may
differ from `a-addr1`.

    16 allocate drop 32 resize nip .   \ 0   (ior: success)

## See Also

- `help defining-words` — `variable`, `create`, `constant`, `value`.
- `help interpreter` — `unused`, how much dictionary space is left.
- `help stack` — `2dup`/`over` for juggling address/value pairs.
