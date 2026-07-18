# Strings

In BasicForth a string is usually an address/length pair on the stack:
`( c-addr u )` — a start address and a byte count. `s"` makes one, `type` prints
one, and the rest read, compare, and copy them.

`s"` and `."` work both ways: inside a definition they compile the string
into the word; at the prompt they act immediately.

At a glance:

    .(        ( "text)" -- )            print now, even while compiling
    ."        ( -- )                    print text (compiled into the word)
    s"        ( -- c-addr u )           make a string
    type      ( c-addr u -- )           print a string
    count     ( c-addr -- c-addr u )    counted string -> addr/len
    compare   ( c1 u1 c2 u2 -- n )      compare two strings (-1/0/1)
    /string   ( c u n -- c+n u-n )      drop n chars from the front
    -trailing ( c u -- c u2 )           drop trailing spaces
    cmove     ( c1 c2 u -- )            copy u bytes, front to back
    cmove>    ( c1 c2 u -- )            copy u bytes, back to front
    blank     ( c u -- )                fill with spaces
    char      ( "name" -- c )           first char of the next word
    [char]    ( "name" -- c )           char, compile-time version

## .( ( "text)" -- )
Print text up to the closing `)` — immediately, even in the middle of
compiling. The classic use is progress messages from a file being loaded.

    .( loading graphics...)   \ prints right now, compile mode or not

## ." ( -- )
Inside a definition: compile a string that is printed when the word runs. At
the prompt: print it right away. The text runs from after the space to the
closing `"`.

    : greet  ." hello" ;
    greet             \ hello
    ." hi there"      \ hi there

## s" ( -- c-addr u )
Inside a definition: compile a string and, at run time, push its address and
length. At the prompt: push the string via a transient buffer — valid until
the second-next interpreted `s"` (two can be live at once; max 256 chars).

    : msg  s" abc" type ;
    msg               \ abc
    s" abc" type      \ abc

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

- `help memory` — `fill`, `move`, and addresses behind these strings.
- `help printing` — `type` is also how pictured numeric output is printed.
- docs/String_Words.md — the fuller treatment.
