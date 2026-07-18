# Comparison and Logic

Comparisons leave a **flag**: `-1` (all bits set) for true, `0` for false. These
work directly with the control-flow words (`help conditionals`) and, because true
is all-ones, with the bitwise operators below. The `u` variants treat values as
unsigned, which matters for addresses and large positive values.

At a glance:

    =       ( x1 x2 -- flag )     equal?
    <>      ( x1 x2 -- flag )     not equal?
    <       ( n1 n2 -- flag )     signed less-than?
    >       ( n1 n2 -- flag )     signed greater-than?
    u<      ( u1 u2 -- flag )     unsigned less-than?
    u>      ( u1 u2 -- flag )     unsigned greater-than?
    within  ( n lo hi -- flag )   lo <= n < hi?
    0=      ( x -- flag )         zero? (logical NOT)
    0<>     ( x -- flag )         non-zero?
    0<      ( n -- flag )         negative?
    0>      ( n -- flag )         positive?

    and     ( x1 x2 -- x3 )       bitwise AND
    or      ( x1 x2 -- x3 )       bitwise OR
    xor     ( x1 x2 -- x3 )       bitwise exclusive-OR
    invert  ( x -- ~x )           bitwise NOT
    lshift  ( x u -- x<<u )       shift left u bits
    rshift  ( x u -- x>>u )       logical shift right u bits

## = ( x1 x2 -- flag )
True if the two values are equal.

    5 5 = .           \ -1
    5 6 = .           \ 0

## <> ( x1 x2 -- flag )
True if the two values differ.

    5 6 <> .          \ -1

## < ( n1 n2 -- flag )
Signed less-than: true if `n1 < n2`.

    3 5 < .           \ -1

## > ( n1 n2 -- flag )
Signed greater-than: true if `n1 > n2`.

    5 3 > .           \ -1

## u< ( u1 u2 -- flag )
Unsigned less-than. Note `-1` is the largest value unsigned:

    1 2 u< .          \ -1
    -1 1 u< .         \ 0   (-1 is huge unsigned)

## u> ( u1 u2 -- flag )
Unsigned greater-than.

    2 1 u> .          \ -1

## within ( n lo hi -- flag )
True if `lo <= n < hi` (the upper bound is exclusive). Works for both signed and
unsigned ranges.

    5 1 10 within .   \ -1
    15 1 10 within .  \ 0

## 0= ( x -- flag )
True if the value is zero. Doubles as a logical NOT, since it turns any non-zero
value into false and zero into true.

    0 0= .            \ -1
    5 0= .            \ 0

## 0<> ( x -- flag )
True if the value is non-zero.

    5 0<> .           \ -1

## 0< ( n -- flag )
True if the value is negative.

    -3 0< .           \ -1

## 0> ( n -- flag )
True if the value is positive.

    7 0> .            \ -1

## Bitwise logic

These operate on all 64 bits. Because true is `-1` (all ones) and false is `0`,
`and`/`or`/`invert` also serve as logical operators on flags.

## and ( x1 x2 -- x3 )
Bitwise AND.

    6 3 and .         \ 2

## or ( x1 x2 -- x3 )
Bitwise OR.

    6 3 or .          \ 7

## xor ( x1 x2 -- x3 )
Bitwise exclusive-OR.

    6 3 xor .         \ 5

## invert ( x -- ~x )
Bitwise NOT (one's complement). On a flag it flips true and false.

    0 invert .        \ -1

## lshift ( x u -- x<<u )
Shift left by `u` bits (zeros shifted in).

    1 4 lshift .      \ 16

## rshift ( x u -- x>>u )
Logical shift right by `u` bits (zeros shifted in — use `2/` for a sign-preserving
halving).

    256 2 rshift .    \ 64

## See Also

- `help conditionals` — `if` and friends consume these flags.
- `help loops` — `until` / `while` consume them too.
- `help arithmetic` — `2*` / `2/` for sign-aware doubling and halving.
