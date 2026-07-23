# Printing

Printing numbers, and building custom formats with the "pictured numeric
output" words. Numbers print in the current **base** (`base`, default 10) —
switching bases and typing numbers *in* is `help numbers`.

At a glance:

    .        ( n -- )               print signed, then a space
    u.       ( u -- )               print unsigned
    .r       ( n width -- )         print right-justified in a field
    u.r      ( u width -- )         unsigned, right-justified
    u.0r     ( u width -- )         unsigned, right-justified, zero-padded
    d.       ( d -- )               print a double (128-bit)
    .s       ( -- )                 show the whole stack (follows base)
    h.2      ( u -- )               print a byte as two hex digits
    h.addr   ( u -- )               print as eight hex digits

    Pictured output (custom formats — details below):
    <# # #s hold holds sign #>

## . ( n -- )
Print a signed number followed by a space.

    42 .              \ 42

## u. ( u -- )
Print an unsigned number — the same bits read as non-negative.

    -1 u.             \ 18446744073709551615

## .r ( n width -- )
Print a signed number right-justified in a field `width` characters wide.

    42 6 .r           \ "    42"

## u.r ( u width -- )
Print an unsigned number right-justified in a field.

    42 6 u.r          \ "    42"

## u.0r ( u width -- )
Like `u.r`, but pads with **zeros** instead of spaces, so a column of
fixed-width values lines up digit for digit. A number too wide for the
field prints in full — digits are never truncated.

    42 6 u.0r         \ 000042
    255 2 u.0r        \ 255      (wider than the field: printed whole)

Like every numeric print it follows `base`, and it leaves `base` alone.
That makes it the natural way to read a value whose width is part of its
meaning — a `$RRGGBB` color, or a row of bitmap art:

    hex FF00 6 u.0r  decimal      \ 00FF00
    binary #60 #8 u.0r  decimal   \ 00111100

Note the `#` prefix on `#60` and `#8`: once you are in binary, `60` and
`8` have no valid reading, and `#` forces a number to be read as decimal
(see `help numbers`). The name is ours, not standard: read it as `u.r`
with a zero for the pad.

## d. ( d -- )
Print a signed double (128-bit, two cells) followed by a space.

    5 s>d d.          \ 5
    -1 -1 d.          \ -1

## h.2 ( u -- )
Print the low byte of `u` as exactly two hex digits, regardless of the
current base. Handy for byte-level debugging (`dump` uses it).

    10 h.2            \ 0A

## h.addr ( u -- )
Print `u` as exactly eight hex digits, regardless of the current base.

    255 h.addr        \ 000000FF

## .s ( -- )
Print the whole data stack non-destructively as `<count> bottom ... top` — the
single most useful debugging word. Follows `base`, like `.` (the count too).

    1 2 3 .s          \ <3> 1 2 3
    binary 110 .s     \ <1> 110

## Pictured numeric output

These build a number's text right-to-left into a buffer, for full control over
formatting (currency, leading zeros, separators). They work on a **double**
(`ud`) — push `0` after a single number to make one. The skeleton is
`<# … #>`, then `type` the result.

## <# ( -- )
Begin a pictured conversion.

## # ( ud1 -- ud2 )
Add the next least-significant digit.

    : last-digit  0 <# # #> type ;
    42 last-digit     \ 2

## #s ( ud -- 0 0 )
Add all remaining digits at once (always emits at least one).

    : show  0 <# #s #> type ;
    42 show           \ 42

## hold ( char -- )
Insert a literal character into the output.

    : money  0 <# #s [char] $ hold #> type ;
    42 money          \ $42

## holds ( c-addr u -- )
Insert a whole string into the output.

    : tagged  0 <# #s s" #" holds #> type ;
    42 tagged         \ #42

## sign ( n -- )
Insert a minus sign if `n` is negative — pass the *original* signed value.

    : .num  dup abs 0 <# #s rot sign #> type ;
    -42 .num          \ -42

## #> ( ud -- c-addr u )
End the conversion, dropping `ud` and leaving the finished string to `type`.

## See Also

- `help numbers` — bases, the `$`/`%`/`#` prefixes, and `>number`.
- `help arithmetic` — the double-precision words (`s>d`, etc.) behind pictured output.
- docs/Pictured_Numeric_Output.md — the fuller treatment.
