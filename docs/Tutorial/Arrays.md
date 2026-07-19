# Arrays — Your First Data Structure

Forth has no built-in array type — and after this short lesson you won't miss
it. You'll build arrays yourself from three small words: `create`, `allot`,
and `cells`, the same way every Forth program does. About ten minutes,
typing as you go.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## A named patch of memory

An array is just a run of memory with a name. `create` makes the name;
`allot` reserves the memory right after it:

    create nums   5 cells allot

Read it aloud: "create `nums`, then reserve room for 5 cells." Type it —
you now own 5 numbers' worth of memory. Type `next`.

## What did create make?

`nums` is now a word like any other. Run it:

    nums .

It pushes an **address** — where your reserved memory starts. That's the
whole secret: every array in Forth is a name that pushes an address.

## Why "cells"?

A *cell* is one stack item — 8 bytes in BasicForth (64 bits). `cells`
scales a count into bytes so you never write 8 by hand:

    1 cells .          \ 8
    5 cells .          \ 40

So `5 cells allot` reserved 40 bytes: room for five numbers, elements 0–4.

## Store and fetch

`!` (store) puts a value at an address; `@` (fetch) reads it back:

    42 nums !
    nums @ .           \ 42

You just used element 0. The other four are lined up right behind it.

## Reaching element i

Element `i` lives at `nums + i cells` — address arithmetic, nothing more:

    99 nums 2 cells + !
    nums 2 cells + @ .     \ 99

## Name the pattern

Typing `cells +` gets old fast. Wrap it once:

    : nth ( i -- addr )  cells nums + ;
    7 3 nth !
    3 nth @ .          \ 7

Nearly every Forth array gets a little access word like this. Note that it's
0-based: `0 nth` is the first element, `4 nth` the last.

## Fill it with a loop

    : init  5 0 do  i i *  i nth !  loop ;
    init

Each pass stores i×i into element i. (`do … loop` counts i from 0 to 4
here — `help loops` has the full story.)

## Print it with a loop

    : show  5 0 do  i nth @ .  loop  cr ;
    show               \ 0 1 4 9 16

`init` and `show` are *the* array idiom: loop an index, `nth` it, fetch or
store. You'll write this pair for every array you ever make.

## Tables you write out by hand

When you know the contents up front, `,` (comma) reserves one cell and
stores a value into it — no `allot` needed:

    create days  31 , 28 , 31 , 30 , 31 , 30 , 31 , 31 , 30 , 31 , 30 , 31 ,
    : days-in ( month -- n )  1- cells days + @ ;
    2 days-in .        \ 28   (February)

`create`-comma tables are how Forth spells constant data.

## Zeroing

`erase` clears a run of memory to zeros:

    nums 5 cells erase
    show               \ 0 0 0 0 0

Its sibling `fill` sets every **byte** to a value — bytes, not cells! Try
`nums 5 cells 255 fill show`: every cell reads -1, because a cell of
all-ones bytes is -1. Try `15 fill` and you get a huge strange number —
eight 15-bytes glued together, not five 15s. Zero is the one value where
bytes and cells agree, which is why `erase` is the one you'll reach for.
To set every *cell* to some other value, loop with `!` like `init` did.

## Byte arrays

For text or flags, a whole cell per element is overkill. `allot` counts
plain bytes, and `c@` / `c!` move single bytes:

    create board  16 allot
    char X  board 3 +  c!
    board 3 + c@ emit  \ X

Byte arrays are where `fill` shines, and `dump` lets you *see* the memory:

    board 16 char X fill
    board 16 dump      \ 58 58 ... |XXXXXXXXXXXXXXXX|

(58 is hex for X.) Same trick, different width — the Snake tutorial's game
board works exactly like this.

## No seatbelts

One honest warning: nothing checks your index.

    9 nth @ .

That read past the end of `nums` — into whatever sits next in the
dictionary — and printed noise. Forth trusts you with raw memory. The
habit that keeps you honest: put the size in a constant and loop to it —
`5 constant #nums`. (A truly wild address is caught by BasicForth's guard
pages, and your session survives to try again.)

## Where to go next

You've met the pattern behind every Forth data structure: **a name, an
address, and arithmetic**. The Snake tutorial puts arrays to work in a real
game; in the reference, `help memory` covers `allot` `,` `erase` `fill`,
and `help variables-constants` the one-cell case.

    tutorials          \ pick your next lesson

Type `end-tutorial` to wrap up. Happy allotting!
