# Numbers

How BasicForth reads numbers. Values are signed 64-bit cells. A bare literal
is read in the current **base** (`base`, default 10); a one-character prefix
overrides the base for that literal only.

At a glance:

    decimal  ( -- )                 switch base to 10
    hex      ( -- )                 switch base to 16
    >number  ( ud c u -- ud c u )   convert string digits to a number

    Literal prefixes (any time, whatever the base):
    #99      decimal   $FF      hex   %1011    binary

    A minus sign works on either side of a prefix: -$FF or $-FF.

## decimal ( -- )
Switch to base 10.

    decimal 255 .     \ 255

## hex ( -- )
Switch to base 16 (digits print in uppercase).

    255 hex .  decimal    \ FF

For any other base, store it directly into `base`:

    : .bin  2 base ! . decimal ;
    5 .bin            \ 101

## Number prefixes ($ hex, % binary, # decimal)

A literal can carry its own base as a one-character prefix, without touching
`base`: `$` reads the number as hex, `%` as binary, `#` as decimal. The
prefix applies to that literal only. A minus sign may sit on either side of
the prefix (`-$FF` and `$-FF` both work).

    $FF .             \ 255
    %1011 .           \ 11
    hex #255 .  decimal   \ FF  (entered in decimal, printed in hex)

The `#` prefix earns its keep when the base is *not* ten — as in the last
example, or inside a hex-mode debugging session.

## >number ( ud c-addr u -- ud c-addr u )
Convert leading digits of a string into a double, in the current base. Returns
the accumulated value plus whatever of the string was left unconverted.

    : parse42  0 0 s" 42" >number 2drop drop . ;
    parse42           \ 42

## See Also

- `help printing` — printing numbers: `.`, `.r`, and pictured output.
- `help variables-constants` — the `base` variable itself.
- `help arithmetic` — what you can do with numbers once you have them.
