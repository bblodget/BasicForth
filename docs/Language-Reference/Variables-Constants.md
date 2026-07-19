# Built-in Constants and Variables

A handful of named values are always available. **Constants** push a fixed value;
**variables** push the *address* of a cell you read with `@` and write with `!`
(see `help memory`). To define your own, see `help defining-words`.

At a glance:

    true   ( -- -1 )        the canonical true flag (all bits set)
    false  ( -- 0 )         the false flag
    bl     ( -- 32 )        the space character code
    base   ( -- a-addr )    variable: the current number base
    state  ( -- a-addr )    variable: 0 interpreting, non-zero compiling
    pad    ( -- c-addr )    transient scratch buffer

## Constants

## true ( -- -1 )
The canonical true flag — all bits set. Comparisons and `if` treat any non-zero
value as true, but words that *produce* a flag return this.

    true .            \ -1

## false ( -- 0 )
The false flag — zero.

    false .           \ 0

## bl ( -- 32 )
The character code for a space (BLank). Handy with `emit`, `fill`, etc.

    bl .              \ 32
    bl emit           \ prints a space

## Variables

## base ( -- a-addr )
Holds the current number base used for reading and printing numbers (10 by
default). `decimal`, `hex`, and `binary` set it; see `help numbers`
(including the `$` / `%` / `#` literal prefixes that sidestep it for one
number). Beware: `base @ .` prints `10` in **every** base — the value of
the base, shown in its own base, is always "10". To see it in decimal:

    base @ dup decimal . base !     \ 16 (say), base unchanged

## state ( -- a-addr )
Holds the interpreter state: 0 while interpreting, non-zero while compiling a
definition. Mostly of interest to immediate words.

    state @ .         \ 0   (at the prompt, interpreting)

## Scratch space

## pad ( -- c-addr )
The address of a small scratch buffer free for your own temporary use (formatting
text, building strings). It is not preserved across words that use it internally,
so treat it as transient.

    pad 3 char * fill  pad 3 type   \ ***

## See Also

- `help defining-words` — `constant`, `variable`, and `value` to make your own.
- `help memory` — `@` / `!` for reading and writing variables.
- `help numbers` — `decimal` / `hex` and the `$`/`%`/`#` prefixes.
