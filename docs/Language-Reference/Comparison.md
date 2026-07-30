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
    <=      ( n1 n2 -- flag )     signed less-or-equal?
    >=      ( n1 n2 -- flag )     signed greater-or-equal?
    u<      ( u1 u2 -- flag )     unsigned less-than?
    u>      ( u1 u2 -- flag )     unsigned greater-than?
    u<=     ( u1 u2 -- flag )     unsigned less-or-equal?
    u>=     ( u1 u2 -- flag )     unsigned greater-or-equal?
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

## <= ( n1 n2 -- flag )
Signed less-or-equal: true if `n1 <= n2`.

    3 5 <= .          \ -1
    5 5 <= .          \ -1

## >= ( n1 n2 -- flag )
Signed greater-or-equal: true if `n1 >= n2`.

    5 5 >= .          \ -1
    3 5 >= .          \ 0

## u< ( u1 u2 -- flag )
Unsigned less-than. Note `-1` is the largest value unsigned:

    1 2 u< .          \ -1
    -1 1 u< .         \ 0   (-1 is huge unsigned)

## u> ( u1 u2 -- flag )
Unsigned greater-than.

    2 1 u> .          \ -1

## u<= ( u1 u2 -- flag )
Unsigned less-or-equal.

    1 2 u<= .         \ -1
    -1 1 u<= .        \ 0   (-1 is huge unsigned)

## u>= ( u1 u2 -- flag )
Unsigned greater-or-equal.

    2 2 u>= .         \ -1

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

## There is no `not`

A reasonable thing to reach for, and deliberately absent. "Not" has two
meanings, and they disagree on anything that is not already a flag:

    3 invert .        \ -4   non-zero, so a TRUE flag
    3 0= .            \ 0    FALSE

Older Forths spelled one of these `NOT` — FORTH-83 made it the bitwise one,
while other systems used it for the logical one — so the same word did opposite
things on different machines. The standard settled it by dropping `NOT` and
keeping two names that say which they mean: **`invert`** for bits, **`0=`** for
truth. We follow that.

On a well-formed flag the two coincide, since true is all-ones:

    0 invert .        \ -1
    0 0= .            \ -1

So `invert` is safe on a flag you produced with a comparison, and `0=` is what
you want on an arbitrary number. If you are coming from BASIC, its `NOT` was
bitwise over -1/0 flags too — that is `invert` here.

## Why `<=` costs less than `> 0=`

`<=` and its three companions are not in the Forth 2012 standard; the classic
set stops at `<` and `>`, leaving you to write `> 0=`. That is correct, and it
is also three subroutine calls to recompute a condition the processor already
had in its flags register after the compare. Each of these words is a single
primitive — the same instructions as `<`, with one condition code changed — so
it costs what `<` costs. See `docs/Performance.md` for the measurement.

One tempting shortcut is worth naming: `: <= 1+ < ;` is **wrong**. It breaks
when `n2` is the largest cell value, where `1+` wraps to the most negative.
`> 0=` has no such flaw; it is just the slow spelling.

## See Also

- `help conditionals` — `if` and friends consume these flags.
- `help loops` — `until` / `while` consume them too.
- `help arithmetic` — `2*` / `2/` for sign-aware doubling and halving.
