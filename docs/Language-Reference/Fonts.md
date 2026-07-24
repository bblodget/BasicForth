# Fonts — Text on the Framebuffer

Draw text onto a graphics surface. A glyph is a 1-bit bitmap and the color is
chosen at draw time, so `text` is a thin loop over `stamp` (see `help
graphics`). Load with `require font-terminus-8x16.fs`, which pulls in `graphics.fs` too.
The font is fixed-width **8×16**, 256 glyphs in **CP437** order — printable
ASCII plus box-drawing, block shading and accented letters.

    require sdl3.fs   require font-terminus-8x16.fs
    320 180 sdl-open
    sdl-frame  black clear
    white s" SCORE 1200" 8 8 text
    cyan  char A 8 30 glyph
    sdl-show

At a glance:

    text    ( color c-addr u x y -- )   draw a string at pixel x,y
    glyph   ( color ch x y -- )         draw one character
    >glyph  ( ch -- addr )              address of a character's bitmap
    font-w  ( -- 8 )                    glyph width in pixels
    font-h  ( -- 16 )                   glyph height in pixels

The glyph bitmaps are Terminus Font (SIL OFL 1.1); see `fonts/OFL.txt`.

## text ( color c-addr u x y -- )
Draw the string `c-addr u` in `color`, top-left at pixel `x y`, advancing
`font-w` pixels per character. A newline (character 10) returns to the start
column and drops down `font-h`; a carriage return (13) is ignored. Glyphs are
drawn with `stamp`, so 0-bits are transparent (the background shows through)
and anything off the surface clips.

    white s" HELLO" 20 20 text            \ one line
    green s" LINE 1" 0 0 text             \ or place lines yourself:
    green s" LINE 2" 0 16 text            \ next row is y + font-h

Because it is fixed-width, layout is arithmetic: column `c`, row `r` is at
`c font-w *  r font-h *`.

## glyph ( color ch x y -- )
Draw a single character `ch` (0–255, CP437) in `color`, top-left at `x y`.
The building block `text` loops over. It is **not** named `char` — that is the
standard word `char ( "name" -- c )`, which is how you get a character code to
pass here:

    yellow char Q  100 50 glyph           \ draw a "Q"
    red $DB 8 8 glyph                      \ $DB = full block █ (CP437)

## >glyph ( ch -- addr )
The address of character `ch`'s 16-byte bitmap inside the font table. Useful to
`stamp` a glyph yourself (e.g. at a different size once `stamp-scale` lands) or
to inspect it:

    char A >glyph  8 dump                  \ the 'A' bitmap, one byte per row

## font-w ( -- n ) · font-h ( -- n )
The glyph cell size in pixels — `8` and `16`. Use them for layout rather than
hard-coding, so text keeps lining up if the font is ever regenerated at another
size.

## See Also

- `help graphics` — `stamp`, `row,`, and the drawing surface `text` builds on.
- `help sdl3` — opening a window and presenting frames.
- `tutorial Fonts` — build a score display and a box-framed panel step by step.
- The font is generated from a PSF console font by `tools/psf2font.py`.
