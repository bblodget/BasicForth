# Terminal I/O

Reading the keyboard and writing to the screen: characters, lines, cursor
positioning, and timing. Words that read keys or move the cursor only do
something useful at an interactive terminal, so a few below are described rather
than shown.

At a glance:

    emit        ( char -- )       print one character
    cr          ( -- )            newline
    space       ( -- )            one space
    spaces      ( n -- )          n spaces
    key         ( -- char )       wait for a keypress
    key?        ( -- flag )       has a key been pressed?
    accept      ( c u1 -- u2 )    read a line into a buffer
    page        ( -- )            clear the screen
    at-xy       ( x y -- )        move the cursor (0,0 = top left)
    screen-width  ( -- n )        terminal width in columns
    screen-height ( -- n )        terminal height in rows
    cursor-off  ( -- )            hide the cursor
    cursor-on   ( -- )            show it again
    color       ( n -- )          text color (0-15, QBasic palette)
    bold        ( -- )            bold text on
    reverse     ( -- )            reverse video on
    normal      ( -- )            reset color/bold/reverse
    ms          ( n -- )          sleep n milliseconds
    ms@         ( -- n )          monotonic milliseconds counter
    key_up key_down key_left key_right key_escape
                ( -- code )       arrow/escape key codes from key

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

## color ( n -- )
Set the text (foreground) color from the 16-color QBasic/VGA palette: 0 black,
1 blue, 2 green, 3 cyan, 4 red, 5 magenta, 6 brown, 7 white, and 8–15 the
bright variants (14 is yellow, 15 bright white). Stays in effect until
changed or `normal`. Like all the attribute words, it emits nothing when
output is piped or redirected, so scripts stay clean.

    \ 4 color ." warning!" normal cr

## bold ( -- )
Turn on bold text. `normal` turns it off.

    \ bold ." heading" normal cr

## reverse ( -- )
Turn on reverse video (swap foreground and background) — good for status bars
and highlights. `normal` turns it off.

    \ reverse ."  -- score: 42 --  " normal cr

## normal ( -- )
Reset all text attributes: color, bold, and reverse. BasicForth also resets
attributes automatically on exit.

## ms ( n -- )
Pause for `n` milliseconds.

    \ 500 ms           \ wait half a second

## ms@ ( -- n )
A free-running millisecond counter — read it twice and subtract to time an
operation.

    \ ms@  ... work ...  ms@ swap -  .   \ elapsed ms

## key_up key_down key_left key_right key_escape ( -- code )
Constants for the abstract key codes `key` returns for the arrow keys (the
platform layer parses their escape sequences into single codes: 129–132) and
Escape (27). The game-loop idiom:

    : steer  key? if key case
        key_up    of  go-up     endof
        key_left  of  go-left   endof
        key_escape of quit-game endof
      endcase then ;

## See Also

- `help printing` — `.`, `.s`, and friends for printing numbers.
- `help strings` — `type` and `."` for printing text.
- docs/Platform_Layer.md — how these map to terminal/syscall operations.
