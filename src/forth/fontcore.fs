\ fontcore.fs -- the bitmap-text engine: `text`, `glyph`, and the "current
\ font" that both draw with.  A font *data* file (e.g. font-terminus-8x16.fs)
\ requires this, lays down its glyph table, and calls `font!` to select itself.
\ Keeping the engine here means each font file is just data + a selector, so
\ fonts don't redefine each other and several can be loaded and switched
\ between.
\
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only

require graphics.fs                         \ glyphs are drawn with `stamp-scale`

\ The current font, as values a selector word sets (sticky, like `sdl-scale`).
\ A glyph table is 1 bit per pixel, MSB = leftmost, rows in reading order,
\ `font-stride` bytes per row (= ceil(w/8)) -- exactly what `stamp` reads.
0 value font-w                              \ glyph cell width  in pixels
0 value font-h                              \ glyph cell height in pixels
0 value font-stride                         \ bytes per glyph row = ceil(w/8)
0 value font-data                           \ base address of the glyph table

\ Text magnification, sticky like `sdl-scale`: 1 = native, 3 = a glyph three
\ times as big (integer scales only). Set once and every `glyph`/`text` that
\ follows honors it -- advance included, so scaled text never overlaps.
1 value font-scale

\ A font selects itself: register its table base and pixel cell size. The row
\ stride follows from the width, so a font wider than 8 works without more info.
: font! ( data w h -- )
    to font-h  to font-w  to font-data
    font-w 7 + 8 /  to font-stride ;

\ Address of a glyph's bitmap in the current font (byte offset = ch * bytes
\ per glyph, and bytes per glyph = font-h rows * font-stride bytes/row).
: >glyph ( ch -- addr )  255 and  font-h font-stride *  *  font-data + ;

\ Draw one glyph in `color` with its top-left at pixel x,y, magnified by the
\ current `font-scale`.  0-bits are transparent (it is a `stamp-scale`), so
\ glyphs compose over anything drawn.
\ Not named `char`: that is the standard word ( "name" -- c ).
: glyph ( color ch x y -- )
    >r >r                                   \ R: x y  ( x on top )
    >glyph                                  ( color src )
    r> r>                                   ( color src x y )
    font-w font-h  font-scale  stamp-scale ;

variable (t-col)  variable (t-adr)          \ text pen state: color, string,
variable (t-x)    variable (t-y)  variable (t-x0)   \ pen x/y, and line start x

\ Draw a string with its top-left at x,y, one glyph every font-w*font-scale
\ pixels. A newline (10) returns to the start column and drops down
\ font-h*font-scale; a carriage return (13) is ignored. Off-screen glyphs
\ clip, via `stamp-scale`.
: text ( color c-addr u x y -- )
    (t-y) !  dup (t-x0) !  (t-x) !          ( color c-addr u )
    >r  (t-adr) !  (t-col) !                \ empty; R: u
    r> 0 ?do
        (t-adr) @ i + c@                    ( ch )
        dup 10 = if   drop
            (t-x0) @ (t-x) !  font-h font-scale * (t-y) +!
        else dup 13 = if  drop
        else
            (t-col) @ swap (t-x) @ (t-y) @ glyph
            font-w font-scale * (t-x) +!
        then then
    loop ;

\ Character cell -> pixel corner, for laying text out on a grid instead of
\ counting pixels: `0 19 >xy text` puts a string at column 0 of row 19. The
\ cell is the same one `text` advances by, `font-scale` included, so a layout
\ written this way survives both a font switch and a scale change.
: >xy ( col row -- x y )
    font-h font-scale * *  swap
    font-w font-scale * *  swap ;
