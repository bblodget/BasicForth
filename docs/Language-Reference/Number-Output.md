# Number Output

Printing numbers, choosing the number base, and building custom formats with the
"pictured numeric output" words. Numbers are read and printed in the current
**base** (`base`, default 10); see also `man constants-and-variables`.

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

## .s ( -- )
Print the whole data stack non-destructively as `<count> bottom ... top` — the
single most useful debugging word.

    1 2 3 .s          \ <3> 1 2 3

## Number base

## decimal ( -- )
Switch to base 10.

    decimal 255 .     \ 255

## hex ( -- )
Switch to base 16 (digits print in uppercase).

    255 hex .  decimal    \ FF

For any other base, store it directly into `base`:

    : .bin  2 base ! . decimal ;
    5 .bin            \ 101

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

## Number input

## >number ( ud c-addr u -- ud c-addr u )
Convert leading digits of a string into a double, in the current base. Returns
the accumulated value plus whatever of the string was left unconverted.

    : value  0 0 s" 42" >number 2drop drop . ;
    value             \ 42

## See Also

- `man arithmetic` — the double-precision words (`s>d`, etc.) behind pictured output.
- `man constants-and-variables` — the `base` variable.
- docs/Pictured_Numeric_Output.md — the fuller treatment.
