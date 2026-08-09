# Random Numbers

A pseudo-random generator (xorshift64 — fast, well-mixed in every bit). It is
seeded from the kernel's entropy pool at startup, so each session gets an
independent sequence; store a known value into `seed` to make runs repeatable.

At a glance:

    random  ( -- n )       next raw 64-bit pseudo-random value
    rnd     ( n -- u )     random 0..n-1 — the dice-roll word
    seed    ( -- a-addr )  variable: the generator state
    entropy ( -- x ior )   a fresh value from the kernel, not the generator

## random ( -- n )
The next raw pseudo-random cell — any 64-bit value, positive or negative.
Mostly you want `rnd` instead.

    random random = .     \ 0   (two calls, different values)

## rnd ( n -- u )
A random number in `0` to `n-1` — the BASIC `RND`. The workhorse for games:

    6 rnd 1+ .            \ a die: 1..6
    2 rnd .               \ a coin: 0 or 1
    : rand-xy  screen-width rnd  screen-height rnd ;

## seed ( -- a-addr )
The generator's state cell. Set it for a repeatable sequence (tests, replays):

    42 seed !  6 rnd .    \ same value every time from a fresh 42

Every value works, `0` included. Zero is xorshift's fixed point — the state
would stay there and every draw would be 0 — so `random` folds it to a fixed
constant, which makes `0 seed !` an ordinary repeatable stream like any other.
No other seed is altered.

To go back to an unpredictable sequence mid-run, seed from the kernel:

    entropy if drop ms@ then  1 or seed !

## entropy ( -- x ior )
One 64-bit value from the **kernel's** random pool, not from `random` — real
entropy, for seeding or for anything that must not be predictable. `ior` is 0
on success; anything else means `x` is meaningless.

    entropy if  ." no kernel entropy" cr  else  seed !  then

Two cells rather than one because the failure could not be folded into the
value: 0 is a legal random number, and it is also exactly the seed that stops
xorshift dead, so a caller could not tell "unlucky" from "broken".

It can fail. The call is non-blocking, so before the pool is initialised — very
early in boot — it returns a failure rather than waiting, and a kernel without
`getrandom` (pre-3.17) fails the same way. Startup falls back to `ms@` on that
path, which is why the clock is still in the picture at all.

Each call is a syscall, so this is for seeding, not for drawing numbers in a
loop. `rnd` is the word for that, and it costs no syscall at all.

## See Also

- `help arithmetic` — `mod`, which `rnd` uses to fold `random` into range.
- `help terminal` — `ms@`, the fallback seed source when `entropy` fails.
