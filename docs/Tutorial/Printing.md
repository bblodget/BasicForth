# Printing — Make Numbers Look Right

BASIC had `PRINT`. Forth has `.` — and then a small kit for saying exactly how
a number should appear: in columns, zero-padded, as money, as a percentage.
This lesson works through both halves, ending with a `$12.34` you built
yourself. About ten minutes, typing as you go.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## `.` prints a number

    42 .
    1 . 2 . 3 .

`.` takes the number off the stack and prints it — **followed by a space**.
That trailing space is the Forth convention, and it's why `1 . 2 . 3 .` comes
out readable instead of running together as `123`. Worth knowing now: it means
`.` is rarely the last word on a line you're laying out by hand.

## Lines and gaps

Three words place things:

    42 . cr
    1 .  4 spaces  2 . cr
    ." total:" space 99 . cr

`cr` ends the line, `space` emits one blank, `spaces` emits as many as you
ask. (`."` prints text — `tutorial Strings` covers text properly; here it's
just glue.)

## `emit` — one character, by number

    65 emit cr
    char ! emit cr

`emit` prints a single character from its code. `char` reads the next word and
gives you the code of its first letter, so you rarely need to remember that A
is 65. Useful when the character is *computed* — a separator, a bar in a
chart, a box-drawing corner.

## Columns that line up

`.` is left-to-right, so numbers of different widths don't align. `.r` prints
right-justified in a field you choose:

    : row ( n -- )  8 .r cr ;
    1234 row
    42 row
    7 row

Every number ends in the same column. That's the whole trick behind a table:
pick a field wide enough for your biggest value.

## Zero padding — a clock

`u.0r` is `.r` with zeros instead of blanks, which is what times and dates
want:

    : hhmm ( h m -- )  swap 2 u.0r  [char] : emit  2 u.0r cr ;
    12 5 hhmm
    9 30 hhmm

`12:05`, then `09:30` — not `12:5` and `9:30`.

Note the `[char]`: inside a definition that's the one to use, and it's
**compile-only** — typed at the prompt it just reports `compile only`. At the
prompt you want plain `char`, as in the step before. Same idea, two homes.

## Numbers print in the current base

    255 hex . decimal cr

That prints `FF`. Printing follows the `base` variable, and so does *reading*
a number you type — which is the part that catches people out, since after
`hex` the digits `255` mean something else entirely. `help numbers` covers
bases properly; just remember the two travel together.

## The wall

Now the thing `.` can't do. You have a price in cents:

    1234 .

You want `$12.34`. There's no `.` variant for that, and reaching for string
concatenation would be a lot of work for a number. Forth's answer is a small
machine for building a number's text, one piece at a time. Type `next`.

## The frame

Every custom format is wrapped in `<#` and `#>`:

    1234 s>d <# #s #> type cr

That prints `1234` — the plain case, so far no gain. Read it as: `s>d` widens
the number (these words work on a double-width number, so hand them one),
`<#` starts building, `#s` converts **all remaining digits**, and `#>` ends
the build and hands you an address and length — which `type` prints.

The one thing to hold on to: it builds the text **right to left**.

## `hold` — push a character in

Since we build right to left, the decimal point goes in after the two cents
digits and before the rest:

    1234 s>d <# # # char . hold #s #> type cr

`12.34`. Reading the code in build order: `#` takes one digit (the rightmost,
`4`), `#` takes another (`3`), `hold` inserts a literal `.`, and `#s` takes
everything left over (`12`). The pieces come out in the order you asked for
them — reversed, because the text grows leftward.

## `sign` — where the minus goes

A negative number needs its `-` at the far left, i.e. added *last*:

    -50 dup abs s>d <# # # char . hold #s rot sign #> type cr

`-0.50`. Three things happen: `dup` keeps the original number, `abs` makes the
digits positive so `#` doesn't choke on the sign, and at the end `rot` digs
the original back out for `sign`, which adds a `-` only if it was negative.

## Name it

That's a word, not a one-liner. Add a `$` while you're there — also `hold`,
also last:

    : money ( n -- )  dup abs s>d
        <# # # [char] . hold #s [char] $ hold rot sign #> type ;

    1234 money cr
    -50 money cr
    5 money cr

`$12.34`, `-$0.50`, `$0.05`. The minus lands outside the dollar sign because
`sign` runs after the `$` — build order is display order, reversed.

## `holds` — a whole string at once

`hold` places one character; `holds` places a string:

    : pct ( n -- )  s>d <# s" %" holds #s #> type ;
    42 pct cr

Units, currency codes, suffixes — anything fixed. Between `#`, `#s`, `hold`,
`holds` and `sign` you can produce any layout a number needs, and it stays a
number until the moment `#>` hands you text.

## Where to go next

You've met both halves: `.` `.r` `u.0r` `emit` for placement, and
`<# # #s hold holds sign #>` for format. `help printing` is the reference for
all of them (plus `.s`, which prints the whole stack and is the debugging
tool you'll reach for most). `docs/Pictured_Numeric_Output.md` explains the
double-cell machinery underneath, and `help numbers` covers bases.

    tutorials          \ pick another lesson

Type `end-tutorial` to wrap up. Your `money` word stays defined.
