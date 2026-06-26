# Loops

Repetition comes in two flavours: **indefinite** loops (`begin …`) that run until
a condition says stop, and **counted** loops (`do …`) that run over a range. All
of these are **compile-only** structure words — use them inside a `:` definition.
Examples wrap each in a short word you then run.

## begin … until ( -- ) ( flag consumed at until )
Run the body, then test: repeat while the flag at `until` is false, stop when it
is true. The body always runs at least once.

    : countdown  5 begin dup . 1- dup 0= until drop ;
    countdown         \ 5 4 3 2 1

## begin … again ( -- )
An unconditional (infinite) loop. Leave it with `exit` (or `leave` if it is also
inside a `do … loop`).

    : countup  0 begin 1+ dup . dup 3 > if exit then again ;
    countup           \ 1 2 3 4

## begin … while … repeat ( -- ) ( flag consumed at while )
Test in the *middle*: `while` checks a flag and, if false, jumps past `repeat`.
The body between `while` and `repeat` may run zero times.

    : whilecd  5 begin dup 0> while dup . 1- repeat drop ;
    whilecd           \ 5 4 3 2 1

## do … loop ( limit start -- )
Counted loop from `start` up to but not including `limit`, stepping by one. The
current index is `i`.

    : five  5 0 do i . loop ;
    five              \ 0 1 2 3 4

## ?do … loop ( limit start -- )
Like `do`, but runs the body zero times when `start` equals `limit` (a plain
`do` would wrap around and run billions of times).

    : maybe  0 0 ?do i . loop ;
    maybe             \ (nothing)

## +loop ( n -- )
End a counted loop adding `n` to the index each pass (instead of 1). Use it to
step by more than one, or downward with a negative `n`.

    : evens  10 0 do i . 2 +loop ;
    evens             \ 0 2 4 6 8

## i ( -- n )
The index of the innermost counted loop.

    : five  5 0 do i . loop ;   five    \ 0 1 2 3 4

## j ( -- n )
The index of the *next outer* counted loop, when loops are nested.

    : grid  2 0 do  2 0 do  j i + .  loop loop ;
    grid              \ 0 1 1 2

## leave ( -- )
Exit the innermost counted loop immediately.

    : upto3  10 0 do i . i 3 = if leave then loop ;
    upto3             \ 0 1 2 3

## unloop ( -- )
Discard the loop's control parameters so you can `exit` the whole word from
inside a counted loop. Always pair `unloop` with `exit`.

    : find3  10 0 do i 3 = if unloop exit then i . loop ;
    find3             \ 0 1 2

## recurse ( -- )
Call the current definition from within itself — the iterative alternative for
problems that divide naturally.

    : fact  dup 1 > if dup 1- recurse * then ;
    5 fact .          \ 120

## See Also

- `man conditionals` — `if`/`else`/`then` and `case`, often used inside loops.
- `man return-stack` — `i`/`j` live on the return stack; mind `>r`/`r>` inside loops.
