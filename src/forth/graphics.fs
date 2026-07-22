\ BasicForth graphics.fs -- backend-agnostic 2D drawing surface
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded on demand (require graphics.fs), NOT at startup. Provides software 2D
\ drawing over an abstract "surface": a flat 32bpp pixel buffer described by a
\ base address, width, height, and stride (bytes per row). A display backend
\ (SDL3) points the surface at real presentation memory with set-surface; the
\ drawing words below are oblivious to where that memory lives.
\
\ Colors are packed 0x00RRGGBB (XRGB8888): $FF0000 red, $00FF00 green, etc.
\ 32 bits per pixel only in this version.

variable gr-base    \ pixel buffer base address
variable gr-width   \ width in pixels
variable gr-height  \ height in pixels
variable gr-stride  \ bytes per row (>= width*4)

: set-surface ( base width height stride -- )
    gr-stride !  gr-height !  gr-width !  gr-base ! ;

\ Byte address of pixel (x,y). No bounds check — callers clip (see pixel).
: pixel-addr ( x y -- addr )  gr-stride @ *  swap 4 * +  gr-base @ + ;

\ Plot one pixel, clipped to the surface. (x u< w) is true only for 0<=x<w:
\ a negative coordinate is a huge unsigned value, so one U< covers both edges.
: pixel ( color x y -- )
    dup  gr-height @ u< 0= if  2drop drop exit  then   \ y outside [0,height)
    over gr-width  @ u< 0= if  2drop drop exit  then   \ x outside [0,width)
    pixel-addr l! ;                                    \ 32-bit store (1 pixel)

\ Filled rectangle, clipped to the surface. The visible region is computed once
\ (signed min/max clamps each edge, so negative coords and overhang both work),
\ then each visible row is filled in one fill32 burst instead of pixel-by-pixel.
\ Inputs/intermediates live in variables to keep the row loop readable.
variable (fr-x)  variable (fr-y)  variable (fr-w)  variable (fr-h)
variable (fr-x0) variable (fr-x1) variable (fr-y0) variable (fr-y1)
variable (fr-col) variable (fr-run)
: fill-rect ( color x y w h -- )
    (fr-h) !  (fr-w) !  (fr-y) !  (fr-x) !  (fr-col) !
    (fr-x) @ 0 max                        (fr-x0) !   \ left  clamped to [0,..)
    (fr-x) @ (fr-w) @ +  gr-width  @ min  (fr-x1) !   \ right clamped to width
    (fr-y) @ 0 max                        (fr-y0) !   \ top
    (fr-y) @ (fr-h) @ +  gr-height @ min  (fr-y1) !   \ bottom clamped to height
    (fr-x1) @ (fr-x0) @ >  (fr-y1) @ (fr-y0) @ >  and 0= if exit then  \ fully clipped
    (fr-x1) @ (fr-x0) @ -  (fr-run) !                 \ pixels per visible row
    (fr-y1) @ (fr-y0) @ ?do
        (fr-col) @  (fr-x0) @ i pixel-addr  (fr-run) @  fill32
    loop ;

: clear ( color -- )  0 0  gr-width @ gr-height @  fill-rect ;

\ Outline rectangle: four thin fill-rects (each clips itself). Needs its own
\ variables because fill-rect reuses (fr-*) on every call.
variable (rc-x) variable (rc-y) variable (rc-w) variable (rc-h) variable (rc-col)
: rect ( color x y w h -- )
    (rc-h) !  (rc-w) !  (rc-y) !  (rc-x) !  (rc-col) !
    (rc-w) @ 1 <  (rc-h) @ 1 <  or if exit then       \ degenerate: nothing
    (rc-col) @  (rc-x) @  (rc-y) @                  (rc-w) @ 1 fill-rect  \ top
    (rc-col) @  (rc-x) @  (rc-y) @ (rc-h) @ + 1-    (rc-w) @ 1 fill-rect  \ bottom
    (rc-col) @  (rc-x) @  (rc-y) @                  1 (rc-h) @ fill-rect  \ left
    (rc-col) @  (rc-x) @ (rc-w) @ + 1-  (rc-y) @    1 (rc-h) @ fill-rect ;

\ Line: integer Bresenham, all octants, plotted through pixel so any part of
\ the line (or both endpoints) may lie off the surface. Purely horizontal or
\ vertical lines short-circuit to a single clipped fill-rect burst.
variable (ln-x)  variable (ln-y)  variable (ln-x1) variable (ln-y1)
variable (ln-dx) variable (ln-dy) variable (ln-sx) variable (ln-sy)
variable (ln-err) variable (ln-col)
: line ( color x0 y0 x1 y1 -- )
    (ln-y1) !  (ln-x1) !  (ln-y) !  (ln-x) !  (ln-col) !
    (ln-y) @ (ln-y1) @ = if                            \ horizontal fast path
        (ln-col) @  (ln-x) @ (ln-x1) @ min  (ln-y) @
        (ln-x1) @ (ln-x) @ - abs 1+  1  fill-rect exit then
    (ln-x) @ (ln-x1) @ = if                            \ vertical fast path
        (ln-col) @  (ln-x) @  (ln-y) @ (ln-y1) @ min
        1  (ln-y1) @ (ln-y) @ - abs 1+  fill-rect exit then
    (ln-x1) @ (ln-x) @ - abs         (ln-dx) !
    (ln-y1) @ (ln-y) @ - abs negate  (ln-dy) !
    (ln-x) @ (ln-x1) @ < if 1 else -1 then (ln-sx) !
    (ln-y) @ (ln-y1) @ < if 1 else -1 then (ln-sy) !
    (ln-dx) @ (ln-dy) @ + (ln-err) !
    begin
        (ln-col) @ (ln-x) @ (ln-y) @ pixel
        (ln-x) @ (ln-x1) @ =  (ln-y) @ (ln-y1) @ =  and 0=
    while
        (ln-err) @ 2*                                  \ e2 = 2*err
        dup (ln-dy) @ < 0= if                          \ e2 >= dy: step x
            (ln-dy) @ (ln-err) +!  (ln-sx) @ (ln-x) +!  then
        (ln-dx) @ > 0= if                              \ e2 <= dx: step y
            (ln-dx) @ (ln-err) +!  (ln-sy) @ (ln-y) +!  then
    repeat ;

\ Circles: midpoint algorithm walking one octant (y from 0 up to x==y); each
\ step emits all symmetric points. The walk is shared -- (ci-op) holds the
\ per-step word: 8 pixels for the outline, 4 one-row fill-rect spans (which
\ clip and fill32-burst themselves) for the filled disc. r < 0 draws nothing;
\ r = 0 is a single pixel.
variable (ci-cx) variable (ci-cy) variable (ci-x) variable (ci-y)
variable (ci-d)  variable (ci-col) variable (ci-op)
: (octants) ( -- )
    (ci-col) @  (ci-cx) @ (ci-x) @ +  (ci-cy) @ (ci-y) @ +  pixel
    (ci-col) @  (ci-cx) @ (ci-x) @ -  (ci-cy) @ (ci-y) @ +  pixel
    (ci-col) @  (ci-cx) @ (ci-x) @ +  (ci-cy) @ (ci-y) @ -  pixel
    (ci-col) @  (ci-cx) @ (ci-x) @ -  (ci-cy) @ (ci-y) @ -  pixel
    (ci-col) @  (ci-cx) @ (ci-y) @ +  (ci-cy) @ (ci-x) @ +  pixel
    (ci-col) @  (ci-cx) @ (ci-y) @ -  (ci-cy) @ (ci-x) @ +  pixel
    (ci-col) @  (ci-cx) @ (ci-y) @ +  (ci-cy) @ (ci-x) @ -  pixel
    (ci-col) @  (ci-cx) @ (ci-y) @ -  (ci-cy) @ (ci-x) @ -  pixel ;
: (spans) ( -- )
    (ci-col) @  (ci-cx) @ (ci-x) @ -  (ci-cy) @ (ci-y) @ -  (ci-x) @ 2* 1+  1 fill-rect
    (ci-col) @  (ci-cx) @ (ci-x) @ -  (ci-cy) @ (ci-y) @ +  (ci-x) @ 2* 1+  1 fill-rect
    (ci-col) @  (ci-cx) @ (ci-y) @ -  (ci-cy) @ (ci-x) @ -  (ci-y) @ 2* 1+  1 fill-rect
    (ci-col) @  (ci-cx) @ (ci-y) @ -  (ci-cy) @ (ci-x) @ +  (ci-y) @ 2* 1+  1 fill-rect ;
: (circle) ( color cx cy r -- )
    (ci-x) !  (ci-cy) !  (ci-cx) !  (ci-col) !
    0 (ci-y) !  1 (ci-x) @ - (ci-d) !
    begin (ci-y) @ (ci-x) @ > 0= while                 \ while y <= x
        (ci-op) @ execute
        1 (ci-y) +!
        (ci-d) @ 0< if
            (ci-y) @ 2* 1+ (ci-d) +!
        else
            -1 (ci-x) +!
            (ci-y) @ (ci-x) @ - 2* 1+ (ci-d) +!
        then
    repeat ;
: circle      ( color cx cy r -- )  ['] (octants) (ci-op) !  (circle) ;
: fill-circle ( color cx cy r -- )  ['] (spans)   (ci-op) !  (circle) ;

\ Sprites. A sprite is just a packed 32bpp pixel block: base address, width,
\ height, stride = w*4 (allocate w h * 4 * bytes and fill it, or grab one off
\ the surface). Blits clip like fill-rect: the visible window is computed
\ once and the sprite's start corner shifts by whatever was clipped away.

\ Compile one pixel into the dictionary -- the 32-bit counterpart of `,`, for
\ typing sprite art in as a create-table. Cells are 64-bit, so `,` would lay
\ down two pixels' worth of space per entry. Leaves HERE 4-byte aligned, which
\ is all the next definition needs (colon definitions align themselves).
: l, ( x -- )  here 4 allot l! ;
variable (bl-src) variable (bl-x) variable (bl-y) variable (bl-w) variable (bl-h)
variable (bl-x0) variable (bl-x1) variable (bl-y0) variable (bl-y1)
variable (bl-run) variable (bl-key)
: (bl-clip) ( -- visible? )
    (bl-x) @ 0 max                        (bl-x0) !
    (bl-x) @ (bl-w) @ +  gr-width  @ min  (bl-x1) !
    (bl-y) @ 0 max                        (bl-y0) !
    (bl-y) @ (bl-h) @ +  gr-height @ min  (bl-y1) !
    (bl-x1) @ (bl-x0) @ -  (bl-run) !
    (bl-run) @ 0>  (bl-y1) @ (bl-y0) @ >  and ;
\ Sprite-buffer address of the first visible pixel in surface row i.
: (bl-row) ( i -- addr )
    (bl-y) @ -  (bl-w) @ *  (bl-x0) @ (bl-x) @ -  +  4 *  (bl-src) @ + ;

: blit ( src x y w h -- )
    (bl-h) !  (bl-w) !  (bl-y) !  (bl-x) !  (bl-src) !
    (bl-clip) 0= if exit then
    (bl-y1) @ (bl-y0) @ ?do
        i (bl-row)  (bl-x0) @ i pixel-addr  (bl-run) @ 4 *  cmove
    loop ;

\ Color-keyed blit: sprite pixels equal to KEY are transparent (skipped).
: blit-key ( key src x y w h -- )
    (bl-h) !  (bl-w) !  (bl-y) !  (bl-x) !  (bl-src) !  (bl-key) !
    (bl-clip) 0= if exit then
    (bl-y1) @ (bl-y0) @ ?do
        (bl-x1) @ (bl-x0) @ ?do
            (bl-src) @  j (bl-y) @ - (bl-w) @ *  i (bl-x) @ -  +  4 *  +  l@
            dup (bl-key) @ = if drop else  i j pixel-addr l!  then
        loop
    loop ;

\ The inverse of blit: copy a surface region into a sprite buffer (save the
\ background before drawing over it, or turn drawn art into a sprite). Only
\ the on-surface part of the region is written; clipped rows/columns of the
\ buffer are left untouched.
: grab ( dst x y w h -- )
    (bl-h) !  (bl-w) !  (bl-y) !  (bl-x) !  (bl-src) !
    (bl-clip) 0= if exit then
    (bl-y1) @ (bl-y0) @ ?do
        (bl-x0) @ i pixel-addr  i (bl-row)  (bl-run) @ 4 *  cmove
    loop ;

\ Binary (1-bit) sprites. Here a sprite is a MONOCHROME bitmap and the color
\ is supplied at draw time -- the TI-99/4A model, where a sprite is a bit
\ pattern with a separate color attribute. One bit per pixel, MSB first, so a
\ binary literal reads exactly as the picture looks:
\
\   create ship
\     %00111100 c,   \ ..####..
\     %01000010 c,   \ .#....#.
\
\ Rows are in plain reading order, stride = ceil(w/8) bytes; bits past w in
\ the last byte of a row are ignored. 0-bits are transparent (nothing is
\ written), so stamping never disturbs the background. 32x smaller than the
\ same art in full color -- a 16x16 is 32 bytes vs 1024 -- which is why art
\ can live in the dictionary instead of needing ALLOCATE.
variable (st-src) variable (st-x) variable (st-y) variable (st-w)
variable (st-h) variable (st-col) variable (st-stride)

\ Is bit (i,j) of the sprite set?  MSB first: column 0 is bit 7 of byte 0.
: (st-bit?) ( i j -- flag )
    (st-stride) @ *  (st-src) @ +        ( i rowaddr )
    over 8 / +  c@                       ( i byte )
    swap 7 and  7 swap -  rshift  1 and  0<> ;

\ Plot through `pixel`, which already clips -- so a stamp hanging off any
\ edge (or entirely off-surface) costs nothing but the loop.
: stamp ( color src x y w h -- )
    (st-h) !  (st-w) !  (st-y) !  (st-x) !  (st-src) !  (st-col) !
    (st-w) @ 7 +  8 /  (st-stride) !
    (st-h) @ 0 ?do
        (st-w) @ 0 ?do
            i j (st-bit?) if
                (st-col) @  (st-x) @ i +  (st-y) @ j +  pixel
            then
        loop
    loop ;

\ Compile one row of bitmap art from a string, so the source looks like the
\ picture:  s" ..####.." row,  is the same two bytes as %00111100 c, would be
\ for an 8-wide row. '.', space and '0' leave the pixel clear; anything else
\ ('#', '*', 'X', '1', ...) sets it. Bits pack MSB first and each row starts a
\ fresh byte, matching what `stamp` reads: a row of u characters compiles
\ ceil(u/8) bytes, and the spare bits of a partial last byte are zero. Rows of
\ a sprite must all be the same length -- that length is the w you pass stamp.
variable (rw-acc)  variable (rw-n)
: (rw-on?) ( c -- 0|1 )
    dup [char] . =  over bl = or  swap [char] 0 = or  0= 1 and ;
: (rw-bit) ( n -- )
    (rw-acc) @ 2* or  (rw-acc) !
    (rw-n) @ 1+ dup (rw-n) !
    8 = if  (rw-acc) @ c,  0 (rw-acc) !  0 (rw-n) !  then ;
: row, ( c-addr u -- )
    0 (rw-acc) !  0 (rw-n) !
    over + swap ?do  i c@ (rw-on?) (rw-bit)  loop
    (rw-n) @ ?dup if                       \ left-align a partial last byte
        8 swap -  (rw-acc) @ swap lshift  c,
        0 (rw-acc) !  0 (rw-n) !
    then ;

\ Named colors (0x00RRGGBB)
$000000 constant black
$FFFFFF constant white
$FF0000 constant red
$00FF00 constant green
$0000FF constant blue
$FFFF00 constant yellow
$00FFFF constant cyan
$FF00FF constant magenta
