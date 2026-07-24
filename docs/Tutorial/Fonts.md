# Fonts — Words on the Screen

You can draw shapes and sprites. Now draw *text* — a score, a title, a
"GAME OVER". A letter turns out to be nothing new: it's a 1-bit sprite, so
the word you already know, `stamp`, is doing all the work underneath.

Do the `Bitmaps` lesson first if you haven't. This one assumes you know
`stamp` and the frame sandwich (`sdl-frame` ... `sdl-show`).

`next` continues, `back` re-reads, `end-tutorial` stops. Type `next` to begin.

## Set the stage

A window, the font, and the two helpers from the graphics lessons:

    require sdl3.fs   require font-terminus-8x16.fs
    4 to sdl-scale
    320 180 sdl-open
    : f  sdl-frame  black clear ;
    : s  sdl-show ;

`require font-terminus-8x16.fs` pulls in `graphics.fs` too, so that's the only new line.
As before, the window grabs the keyboard when it opens — click back on your
BasicForth terminal before typing on.

## Your first word

    f  white s" HELLO" 100 80 text  s

`HELLO` in white, its top-left corner at pixel 100,80. `text` takes the same
`color` a shape does, then the string (`c-addr u`, which `s"` gives you), then
where to put it. The color comes first so it reads left to right: *white,
this text, here*.

Try another color and spot — `f  cyan s" FORTH" 10 10 text  s`.

## It's just stamps

Nothing new is happening. A single character is a 1-bit sprite, and there's a
word to draw one:

    f  yellow char A  150 80 glyph  s

`glyph` is `stamp` with the bitmap looked up for you: `( color ch x y -- )`.
Note `char A` — that's the standard word that hands you a character's code
(65 for `A`). The drawing word is `glyph`, *not* `char`, precisely so `char`
stays free for getting the code.

`text` is just a loop over `glyph`, advancing 8 pixels each time. That's all.

## Everything lines up

The font is **fixed-width**: every glyph is `font-w` wide and `font-h` tall.

    f  white s" 12345678" 0 0 text
       white s" ABCDEFGH" 0 16 text  s

The second row sits at y = 16 = `font-h`, directly under the first, and the
digits line up with the letters because each cell is `font-w` = 8 wide. Column
`c`, row `r` is always at `c font-w *  r font-h *` — layout is arithmetic, no
measuring.

## One string, any color

Because the color is chosen at draw time (just like `stamp`), the same text is
whatever color you ask for:

    f  red    s" RED" 40 40 text
       green  s" GREEN" 40 60 text
       cyan   s" CYAN" 40 80 text  s

Handy for a health bar in green that turns red, or a highlighted menu row —
no second copy of the text, just a different color word.

## A live score

Text earns its keep in a loop. Here's a counter ticking up each frame:

    variable sc
    : show# ( color n x y -- )              \ draw n as 6 zero-padded digits
       >r >r  0 <# # # # # # # #>  r> r> text ;
    : score ( -- )
       0 sc !
       200 0 do
         f
         white s" SCORE" 8 8 text
         green sc @ 8 24 show#
         s
         5 sc +!  30 ms
       loop ;

Run `score`. The label stays put while the number climbs, each frame redrawn
from scratch on its own black background. `show#` turns the count into six
digits with pictured numeric output (`help pictured`) — the same fixed-width
trick a real score line uses so the digits don't jump around.

## Frames and boxes

The font is full **CP437**, so the box-drawing characters are in there. Their
codes are easiest as `$` hex — `$DA` is the top-left corner, `$C4` a
horizontal, `$BF` top-right:

    f
    white $DA 20 20 glyph
    white $C4 28 20 glyph   white $C4 36 20 glyph
    white $BF 44 20 glyph
    s

Three glyphs make the top of a frame: corner, two bars, corner. A short word
that loops the bar would draw a panel of any width — a natural next exercise.

## Multiple lines

A newline character (10) in the string drops `text` to the next row and back
to the start column, so one call can lay out several lines — useful when the
text comes from a file or is built up in a buffer:

    create msg  char G c, char O c, 10 c, char ! c,
    f  white msg 4  8 40 text  s

`G`, `O`, then a newline, then `!` — so `GO` sits on the first row and `!`
drops to the second. (A carriage return, 13, is skipped, so text pasted with
`\r\n` endings still lines up.)

## Where to go next

A glyph is a 1-bit sprite; `text` is a loop over `stamp`; layout is
multiplication by `font-w` and `font-h`. That's the whole idea — everything
else is arranging characters.

- **A framed panel**: a word that draws a box of any width and height from the
  CP437 corners and bars, then `text` inside it.
- **A typewriter**: reveal a string one glyph per frame for dialogue.
- **Bigger headings**: `stamp-scale` (coming) will draw the same glyphs at 2×
  or 3× without a second font.

`help fonts` is the reference for `text`, `glyph`, and the cell size. The font
itself is Terminus (`fonts/OFL.txt`), turned into BasicForth source by
`tools/psf2font.py`.
