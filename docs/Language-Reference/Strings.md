# Strings

In BasicForth a string is usually an address/length pair on the stack:
`( c-addr u )` — a start address and a byte count. `s"` makes one, `type` prints
one, and the rest read, compare, and copy them.

`s"` and `."` are **compile-only**, so the examples wrap them in a short word you
then run.

## ." ( -- )  (compile-only)
Compile a string that is printed when the word runs. The text runs from after the
space to the closing `"`.

    : greet  ." hello" ;
    greet             \ hello

## s" ( -- c-addr u )  (compile-only)
Compile a string and, at run time, push its address and length.

    : msg  s" abc" type ;
    msg               \ abc

## type ( c-addr u -- )
Print `u` characters starting at `c-addr`.

    : msg  s" abc" type ;   msg       \ abc

## count ( c-addr -- c-addr u )
Convert a *counted* string (a length byte followed by the text) into an
address/length pair. Useful with `create`d strings.

    create cs  3 c, char a c, char b c, char c c,
    cs count type     \ abc

## compare ( c-addr1 u1 c-addr2 u2 -- n )
Compare two strings: `0` if equal, `-1` if the first is "less", `1` if "greater"
(lexicographic).

    : same  s" abc" s" abc" compare ;   same .    \ 0
    : diff  s" abc" s" abd" compare ;   diff .    \ -1

## /string ( c-addr u n -- c-addr+n u-n )
Drop the first `n` characters of a string (advance the address, shorten the
count).

    : tail  s" hello" 2 /string type ;
    tail              \ llo

## -trailing ( c-addr u -- c-addr u2 )
Shorten the count to drop trailing spaces.

    : trim  s" hi   " -trailing type ;
    trim              \ hi

## cmove ( c-addr1 c-addr2 u -- )
Copy `u` bytes from the first address to the second, **low to high**. Correct
when the destination is below the source (or they don't overlap).

    create src 3 allot  create dst 3 allot
    char A src c!  char B src 1+ c!  char C src 2 + c!
    src dst 3 cmove  dst 3 type        \ ABC

## cmove> ( c-addr1 c-addr2 u -- )
Copy `u` bytes **high to low** — the right choice when the destination is above
the source and the regions overlap.

    create s2 3 allot  create d2 3 allot
    char X s2 c!  char Y s2 1+ c!  char Z s2 2 + c!
    s2 d2 3 cmove>  d2 3 type          \ XYZ

## blank ( c-addr u -- )
Fill `u` bytes with spaces (like `fill` with `bl`).

    create buf 3 allot  buf 3 blank  buf 3 type    \ (3 spaces)

## char ( "name" -- c )
Parse the next word and push the code of its first character — at the interpreter.

    char A .          \ 65

## [char] ( "name" -- c )  (compile-only)
The in-definition form of `char`: compile the next word's first character code as
a literal.

    : letterA  [char] A ;
    letterA .         \ 65

## See Also

- `man memory` — `fill`, `move`, and addresses behind these strings.
- `man number-output` — `type` is also how pictured numeric output is printed.
- docs/String_Words.md — the fuller treatment.
