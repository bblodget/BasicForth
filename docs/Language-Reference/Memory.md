# Memory

BasicForth memory is byte-addressed; a **cell** is 8 bytes (64 bits). These
words read and write memory and compute address offsets. Get an address to play
with from `variable`, `create`, `pad` (a scratch buffer), or `allocate` — see
`man defining-words` for the first two.

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

## move ( addr1 addr2 u -- )
Copy `u` bytes from `addr1` to `addr2`, handling overlap correctly.

    create src 2 cells allot  create dst 2 cells allot
    11 src !  22 src cell+ !
    src dst 2 cells move  dst @ dst cell+ @ .s      \ <2> 11 22

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

- `man defining-words` — `variable`, `create`, `constant`, `value`, and
  `here`/`allot` for dictionary storage.
- `man stack` — `2dup`/`over` for juggling address/value pairs.
- docs/Persistence.md — heap-backed buffers in practice.
