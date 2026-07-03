\ BasicForth graphics.fs -- backend-agnostic 2D drawing surface
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded on demand (include graphics.fs), NOT at startup. Provides software 2D
\ drawing over an abstract "surface": a flat 32bpp pixel buffer described by a
\ base address, width, height, and stride (bytes per row). A backend (DRM now,
\ Vulkan later) points the surface at real video memory with set-surface; the
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

\ Named colors (0x00RRGGBB)
$000000 constant black
$FFFFFF constant white
$FF0000 constant red
$00FF00 constant green
$0000FF constant blue
$FFFF00 constant yellow
$00FFFF constant cyan
$FF00FF constant magenta
