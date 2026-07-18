# Arithmetic

Integer maths on the data stack. Operands go on first, operator last (see
`help stack` for the RPN idea). All values are signed 64-bit cells unless a word
says otherwise. Division **truncates toward zero**: `-7 2 /` is `-3`, and `mod`
takes the sign of the dividend (`-7 2 mod` is `-1`).

At a glance:

    +       ( n1 n2 -- n3 )         add
    -       ( n1 n2 -- n3 )         subtract: n1-n2
    *       ( n1 n2 -- n3 )         multiply
    /       ( n1 n2 -- n3 )         divide: n1/n2, toward zero
    mod     ( n1 n2 -- rem )        remainder of n1/n2
    /mod    ( n1 n2 -- rem quot )   remainder and quotient
    */      ( n1 n2 n3 -- n4 )      n1*n2/n3, double-wide inside
    */mod   ( n1 n2 n3 -- rem quot ) like */ with remainder
    1+      ( n -- n+1 )            add one
    1-      ( n -- n-1 )            subtract one
    negate  ( n -- -n )             flip the sign
    abs     ( n -- u )              absolute value
    min     ( n1 n2 -- n3 )         the smaller
    max     ( n1 n2 -- n3 )         the larger
    2*      ( x -- x*2 )            shift left one bit
    2/      ( x -- x/2 )            arithmetic shift right

    Doubles (128-bit, low cell then high cell — see below):
    s>d     ( n -- d )              sign-extend single to double
    m*      ( n1 n2 -- d )          signed multiply, double result
    um*     ( u1 u2 -- ud )         unsigned multiply, double result
    um/mod  ( ud u -- rem quot )    unsigned double / single
    fm/mod  ( d n -- rem quot )     floored signed divide
    sm/rem  ( d n -- rem quot )     symmetric signed divide
    d+      ( d1 d2 -- d3 )         add doubles
    d-      ( d1 d2 -- d3 )         subtract doubles
    dnegate ( d -- -d )             negate a double
    dabs    ( d -- ud )             absolute value of a double
    d0=     ( d -- flag )           double equals zero?
    d0<     ( d -- flag )           double negative?
    d=      ( d1 d2 -- flag )       doubles equal?
    d<      ( d1 d2 -- flag )       d1 less than d2?

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
(`help printing`) are built on.

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

## d0= ( d -- flag )
True if a double is zero.

    0 s>d d0= .       \ -1
    5 s>d d0= .       \ 0

## d0< ( d -- flag )
True if a double is negative.

    -5 s>d d0< .      \ -1

## d= ( d1 d2 -- flag )
True if two doubles are equal.

    5 s>d 5 s>d d= .  \ -1

## d< ( d1 d2 -- flag )
True if `d1` is less than `d2` (signed).

    1 s>d 2 s>d d< .  \ -1

## See Also

- `help stack` — rearranging operands before an operation.
- `help comparison` — tests and bitwise operators.
- `help printing` — printing numbers and `<# #S #>` formatting (built on the
  double words here).
