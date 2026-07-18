# Conditionals

Words that choose what runs based on a flag (see `help comparison`
for where flags come from). Any non-zero value counts as true; only `0` is
false. These are **compile-only** structure words — use them inside a `:`
definition.

At a glance:

    if ... then              ( flag -- )   run the branch when true
    if ... else ... then     ( flag -- )   two-way branch
    case                     ( x -- )      multi-way branch on a value
      n of ... endof                       one arm, runs when x = n
      ...                                  optional default arm
    endcase                                end of case (drops x)
    exit                     ( -- )        return from the word now

## if … then ( flag -- )
Run the words between `if` and `then` only when the flag is true.

    : sign?  dup 0> if ." positive " then drop ;
    5 sign?           \ positive
    -5 sign?          \ (nothing)

## if … else … then ( flag -- )
Run the first branch when true, the `else` branch when false.

    : pick  0> if 111 else 222 then ;
    5 pick .          \ 111
    -5 pick .         \ 222

## case … of … endof … endcase ( x -- )
Multi-way branch on a value — cleaner than nested `if`s. Each `of … endof` runs
when `x` equals its selector; an optional default before `endcase` handles
everything else. `endcase` discards the value.

    : classify
        case
            1 of ." one"  endof
            2 of ." two"  endof
            ." many"
        endcase ;
    1 classify        \ one
    2 classify        \ two
    9 classify        \ many

Inside an `of`, the value has already been consumed, so the branch starts with a
clean stack. In the default branch the value is still present; `endcase` drops it.

## exit ( -- )
Return from the current word immediately. Handy for an early-out guard.

    : report  dup 0> if ." big " exit then ." small " drop ;
    5 report          \ big
    -5 report         \ small

Inside a `do … loop`, call `unloop` before `exit` (see `help loops`).

## See Also

- `help comparison` — the tests that produce the flags used here.
- `help loops` — `begin`/`until`, `do`/`loop`, and friends.
