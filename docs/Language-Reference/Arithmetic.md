# Arithmetic

Integer maths on the data stack. Operands go on first, operator last (see
`man stack` for the RPN idea). All values are signed 64-bit cells unless a word
says otherwise. `.s` shows the stack as `<count> bottom ... top`; examples start
from an empty stack.

Division **truncates toward zero**: `-7 2 /` is `-3`, and `mod` takes the sign
of the dividend (`-7 2 mod` is `-1`). For floored or symmetric division see the
mixed-precision words below.

## + ( n1 n2 -- n3 )
Add.

    2 3 + .           \ 5

## - ( n1 n2 -- n3 )
Subtract: `n1 - n2`.

    10 3 - .          \ 7

## * ( n1 n2 -- n3 )
Multiply.

    6 7 * .           \ 42

## / ( n1 n2 -- n3 )
Divide: `n1 / n2`, truncated toward zero.

    17 5 / .          \ 3

## mod ( n1 n2 -- rem )
Remainder of `n1 / n2`.

    17 5 mod .        \ 2

## /mod ( n1 n2 -- rem quot )
Remainder and quotient together.

    17 5 /mod .s      \ <2> 2 3

## */ ( n1 n2 n3 -- n4 )
`n1 * n2 / n3`, computing the product in double precision so it doesn't overflow
midway. Useful for scaling.

    10 3 4 */ .       \ 7   (30/4)

## */mod ( n1 n2 n3 -- rem quot )
Like `*/`, but leaves the remainder too.

    10 3 4 */mod .s   \ <2> 2 7

## 1+ ( n -- n+1 )
Add one.

    41 1+ .           \ 42

## 1- ( n -- n-1 )
Subtract one.

    43 1- .           \ 42

## negate ( n -- -n )
Arithmetic negation.

    5 negate .        \ -5

## abs ( n -- u )
Absolute value.

    -5 abs .          \ 5

## min ( n1 n2 -- n3 )
The smaller of two values.

    3 8 min .         \ 3

## max ( n1 n2 -- n3 )
The larger of two values.

    3 8 max .         \ 8

## 2* ( x -- x*2 )
Multiply by two (a left shift).

    5 2* .            \ 10

## 2/ ( x -- x/2 )
Divide by two (an arithmetic right shift, so the sign is preserved).

    -8 2/ .           \ -4

## Double and mixed precision

A *double* is a 128-bit signed number held as two cells, **low cell then high
cell** (the high cell on top of the stack). These words bridge between single
and double precision — the foundation `*/`, `*/mod`, and pictured numeric output
(`man number-output`) are built on.

## s>d ( n -- d )
Sign-extend a single number to a double.

    5 s>d .s          \ <2> 5 0
    -5 s>d .s         \ <2> -5 -1

## m* ( n1 n2 -- d )
Signed multiply producing a double (never overflows).

    -6 7 m* .s        \ <2> -42 -1

## um* ( u1 u2 -- ud )
Unsigned multiply producing a double.

    6 7 um* .s        \ <2> 42 0

## um/mod ( ud u -- rem quot )
Unsigned divide of a double by a single.

    10 0 3 um/mod .s  \ <2> 1 3

## fm/mod ( d n -- rem quot )
Floored signed divide (quotient rounds toward negative infinity; the remainder
takes the sign of the divisor).

    -7 -1 2 fm/mod .s \ <2> 1 -4

## sm/rem ( d n -- rem quot )
Symmetric signed divide (quotient truncates toward zero; the remainder takes the
sign of the dividend).

    -7 -1 2 sm/rem .s \ <2> -1 -3

## d+ ( d1 d2 -- d3 )
Add two doubles.

    1 0 2 0 d+ .s     \ <2> 3 0

## d- ( d1 d2 -- d3 )
Subtract two doubles: `d1 - d2`.

    100 0 1 0 d- .s   \ <2> 99 0

## dnegate ( d -- -d )
Negate a double.

    5 s>d dnegate .s  \ <2> -5 -1

## dabs ( d -- ud )
Absolute value of a double.

    -5 s>d dabs .s    \ <2> 5 0

## See Also

- `man stack` — rearranging operands before an operation.
- `man comparison-and-logic` — tests and bitwise operators.
- `man number-output` — printing numbers and `<# #S #>` formatting (built on the
  double words here).
