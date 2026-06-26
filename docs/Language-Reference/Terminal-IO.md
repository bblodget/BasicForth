# Terminal I/O

Reading the keyboard and writing to the screen: characters, lines, cursor
positioning, and timing. Words that read keys or move the cursor only do
something useful at an interactive terminal, so a few below are described rather
than shown.

## emit ( char -- )
Print one character by its code.

    65 emit           \ A

## cr ( -- )
Start a new line.

    : two  ." line1" cr ." line2" ;
    two               \ line1 / line2

## space ( -- )
Print one space.

    : ab  ." a" space ." b" ;   ab    \ a b

## spaces ( n -- )
Print `n` spaces.

    : ab  ." a" 3 spaces ." b" ;   ab \ a   b

## key ( -- char )
Wait for a keypress and return its character code. Blocks until a key is pressed.

    \ : pause  ." press a key" key drop ;

## key? ( -- flag )
True if a key is waiting to be read — a non-blocking check you can poll in a loop
without stopping for input.

    \ begin key? until      \ spin until a key is available

## accept ( c-addr +n1 -- +n2 )
Read a line of input (up to `n1` characters) into the buffer at `c-addr`, with
backspace editing, and return the number of characters actually read.

    \ : ask  pad 80 accept  pad swap type ;

## page ( -- )
Clear the screen and move the cursor to the top-left.

## at-xy ( x y -- )
Move the cursor to column `x`, row `y` (counting from `0 0` at the top-left).

    \ : hi  page  10 5 at-xy  ." here" ;

## screen-width ( -- n )
The terminal width in columns.

    screen-width .    \ 80

## screen-height ( -- n )
The terminal height in rows.

    screen-height .   \ 25

## cursor-off ( -- )
Hide the text cursor (useful while drawing).

## cursor-on ( -- )
Show the text cursor again.

## ms ( n -- )
Pause for `n` milliseconds.

    \ 500 ms           \ wait half a second

## ms@ ( -- n )
A free-running millisecond counter — read it twice and subtract to time an
operation.

    \ ms@  ... work ...  ms@ swap -  .   \ elapsed ms

## See Also

- `man number-output` — `.`, `.s`, and friends for printing numbers.
- `man strings` — `type` and `."` for printing text.
- docs/Platform_Layer.md — how these map to terminal/syscall operations.
