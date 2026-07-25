# Fonts — Text on the Framebuffer

Draw text onto a graphics surface. A glyph is a 1-bit bitmap and the color is
chosen at draw time, so `text` is a thin loop over `stamp-scale` (see `help
graphics`). Load a font with `require font-terminus-8x16.fs`; that pulls in the
shared engine `fontcore.fs` (which holds `text`/`glyph`/`font-scale`) and
`graphics.fs`, and selects the font. Terminus is fixed-width **8×16**, 256
glyphs in **CP437** order — printable ASCII plus box-drawing, block shading and
accented letters.

    require sdl3.fs   require font-terminus-8x16.fs
    320 180 sdl-open
    sdl-frame  black clear
    white s" SCORE 1200" 8 8 text
    cyan  char A 8 30 glyph
    sdl-show

At a glance:

    text        ( color c-addr u x y -- )  draw a string at pixel x,y
    glyph       ( color ch x y -- )        draw one character
    >glyph      ( ch -- addr )             address of a character's bitmap
    font-w      ( -- 8 )                   glyph width in pixels
    font-h      ( -- 16 )                  glyph height in pixels
    font-scale  ( -- n )                   text magnification (a value, default 1)

The glyph bitmaps are Terminus Font (SIL OFL 1.1); see `fonts/OFL.txt`.

## text ( color c-addr u x y -- )
Draw the string `c-addr u` in `color`, top-left at pixel `x y`, advancing
`font-w * font-scale` pixels per character. A newline (character 10) returns to
the start column and drops down `font-h * font-scale`; a carriage return (13) is
ignored. Glyphs are drawn with `stamp-scale`, so 0-bits are transparent (the
background shows through) and anything off the surface clips.

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
The address of character `ch`'s bitmap inside the current font's table
(`font-h * font-stride` bytes — 16 for Terminus). Useful to `stamp`/`stamp-scale`
a glyph yourself, or to inspect it:

    char A >glyph  8 dump                  \ the 'A' bitmap, one byte per row

## font-w ( -- n ) · font-h ( -- n )
The glyph cell size in pixels — `8` and `16`. Use them for layout rather than
hard-coding, so text keeps lining up if the font is ever regenerated at another
size.

## font-scale ( -- n )
Text magnification, a `value` (not a stack argument) that `text` and `glyph`
both read — sticky like `sdl-scale`. Set it once with `to` and everything
drawn afterward is that many times larger, advance included; `1` is native
8×16. Integer scales only.

    3 to font-scale
    white s" BIG" 8 8 text                 \ 24×48 letters
    1 to font-scale                        \ back to native

It rides on `stamp-scale`, so scaling is opt-in and costs nothing at `1`. For
a whole-window zoom instead, `sdl-scale` stretches every pixel at present time;
the two compose (a `3` font in a `2×` window is 6× on screen).

## font! ( data w h -- ) · font-stride · font-data

The font engine — switching and adding fonts.
`text`/`glyph`/`font-scale`/`>glyph`/`font-w`/`font-h` live in **`fontcore.fs`**,
not in any one font file. They draw the **current font**, held as values that a
font selects into. So several fonts can be loaded at once and you switch between
them with a word:

    require font-terminus-8x16.fs         \ engine + Terminus, Terminus current
    require font-something-6x8.fs         \ another font, now current
    terminus-8x16                         \ switch back — just a word

A font *data* file is only its glyph table plus a **selector word** named after
the font, which registers itself with `font!`:

    font!  ( data w h -- )                \ engine: select a font by table+size

`font!` records the table base and cell size and derives the row stride
(`font-stride`, `ceil(w/8)` bytes), so a font wider than 8 pixels needs no extra
information. To add your own font, generate a data file with `tools/psf2font.py`
(it emits the table, the `require fontcore.fs`, and the selector) — the file name
`font-<family>-<size>.fs` gives the selector its name.

## See Also

- `help graphics` — `stamp`/`stamp-scale`, `row,`, and the drawing surface `text` builds on.
- `help sdl3` — opening a window and presenting frames.
- `tutorial Fonts` — build a score display and a box-framed panel step by step.
- The font is generated from a PSF console font by `tools/psf2font.py`.
