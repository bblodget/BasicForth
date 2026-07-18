# Random Numbers

A pseudo-random generator (xorshift64 — fast, well-mixed in every bit). It is
seeded from the millisecond clock at startup, so each session gets a different
sequence; store a known value into `seed` to make runs repeatable.

At a glance:

    random  ( -- n )       next raw 64-bit pseudo-random value
    rnd     ( n -- u )     random 0..n-1 — the dice-roll word
    seed    ( -- a-addr )  variable: the generator state

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
The generator's state cell. Set it for a repeatable sequence (tests, replays);
never set it to `0` (xorshift sticks there — startup seeding guards against
this).

    42 seed !  6 rnd .    \ same value every time from a fresh 42

## See Also

- `help arithmetic` — `mod`, which `rnd` uses to fold `random` into range.
- `help terminal` — `ms@`, the startup seed source.
