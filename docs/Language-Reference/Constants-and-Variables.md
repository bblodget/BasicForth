# Built-in Constants and Variables

A handful of named values are always available. **Constants** push a fixed value;
**variables** push the *address* of a cell you read with `@` and write with `!`
(see `man memory`). To define your own, see `man defining-words`.

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
default). `decimal`, `hex`, and `bin` set it; see `man number-output`.

    base @ .          \ 10

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

- `man defining-words` — `constant`, `variable`, and `value` to make your own.
- `man memory` — `@` / `!` for reading and writing variables.
- `man number-output` — `decimal` / `hex` / `bin` and the `base` variable.
