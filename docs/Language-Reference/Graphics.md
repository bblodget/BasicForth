# Graphics — 2D Drawing

Software 2D drawing on the current *surface*: a 32-bpp pixel buffer set up by
`set-surface` (usually by the SDL3 window backend — see `help sdl3`). Load
with `require graphics.fs` — or just `require sdl3.fs`, which pulls in these
drawing words along with the window. Coordinates are pixels, (0,0) top-left;
colors are packed `$RRGGBB`. Everything clips: shapes may hang off any edge
freely.

    require sdl3.fs
    320 180 sdl-open
    sdl-frame  black clear
    red 10 10 100 60 fill-rect  white 10 10 100 60 rect
    yellow 160 90 40 circle    green 0 0 319 179 line
    sdl-show

At a glance:

    set-surface ( base w h stride -- )     point drawing at a pixel buffer
    pixel       ( color x y -- )           plot one pixel
    line        ( color x0 y0 x1 y1 -- )   line between two points
    rect        ( color x y w h -- )       outline rectangle
    fill-rect   ( color x y w h -- )       filled rectangle
    circle      ( color cx cy r -- )       outline circle
    fill-circle ( color cx cy r -- )       filled circle
    clear       ( color -- )               fill the whole surface
    blit        ( src x y w h -- )         copy a sprite onto the surface
    blit-key    ( key src x y w h -- )     sprite copy with transparency
    grab        ( dst x y w h -- )         copy surface region to a buffer
    pixel-addr  ( x y -- addr )            address of a pixel (no clip)
    gr-base gr-width gr-height gr-stride ( -- a-addr )  surface variables
    black white red green blue yellow cyan magenta ( -- color )

## set-surface ( base w h stride -- )
Point the drawing words at a pixel buffer: base address, width and height in
pixels, stride in bytes per row (>= w*4). The SDL3 backend calls this for you
each `sdl-frame`; call it yourself to draw into your own memory (for tests,
sprite-building, or off-screen composition).

    \ 64x48 off-screen buffer:
    \ 64 48 * 4 * allocate throw  64 48  64 4 *  set-surface

## pixel ( color x y -- )
Plot one pixel. Off-surface coordinates are silently ignored.

    \ red 10 20 pixel

## line ( color x0 y0 x1 y1 -- )
Draw a one-pixel line between two points (any octant, endpoints included).
Either endpoint may be off the surface — the visible part draws. Horizontal
and vertical lines take a fast block-fill path.

    \ white 0 0 319 179 line

## rect ( color x y w h -- )
Outline rectangle: top-left corner (x,y), w by h pixels, one pixel thick.
`w` or `h` under 1 draws nothing.

    \ white 10 10 100 60 rect

## fill-rect ( color x y w h -- )
Filled rectangle. Clips once, then fills each visible row in a single burst —
large fills are fast.

    \ red 10 10 100 60 fill-rect

## circle ( color cx cy r -- )
Outline circle, center (cx,cy), radius r (midpoint algorithm — matches
`fill-circle` exactly). `r` 0 is a single pixel; negative draws nothing.

    \ yellow 160 90 40 circle

## fill-circle ( color cx cy r -- )
Filled circle (disc).

    \ yellow 160 90 40 fill-circle

## clear ( color -- )
Fill the whole surface with one color.

    \ black clear

## blit ( src x y w h -- )
Copy a w-by-h sprite from the packed pixel block at `src` onto the surface
with its top-left corner at (x,y). A sprite is just memory: w*h 32-bit pixels,
row after row (stride w*4) — `allocate` one and fill it, or `grab` one off the
surface. Clips on all edges.

    \ ship 100 50 16 16 blit

## blit-key ( key src x y w h -- )
Like `blit`, but sprite pixels whose value equals `key` are skipped —
transparent. Pick any color you don't use as the key (the classic choice is
magenta).

    \ magenta ship 100 50 16 16 blit-key

## grab ( dst x y w h -- )
The reverse of `blit`: copy the w-by-h surface region at (x,y) into the buffer
at `dst` (w*h*4 bytes). Save the background before drawing a sprite over it,
or draw art with the shape words and grab it as a sprite. Only the on-surface
part of the region is copied.

    \ 16 16 * 4 * allocate throw value saved
    \ saved 100 50 16 16 grab

## pixel-addr ( x y -- addr )
The byte address of pixel (x,y) on the surface — no bounds check. For tight
loops that do their own clipping; read and write with `l@` / `l!`.

## gr-base gr-width gr-height gr-stride ( -- a-addr )
The variables describing the current surface, set by `set-surface`: pixel
buffer base address, width and height in pixels, stride in bytes per row.
Read them to size drawing to whatever surface is current — a full-width
loop is `gr-width @ 0 do ... loop` — or to hand the raw buffer to code of
your own.

    \ : center ( -- x y )  gr-width @ 2/  gr-height @ 2/ ;

## black white red green blue yellow cyan magenta ( -- color )
The named colors, as packed `$RRGGBB` constants. Any 24-bit number works as a
color: `$FF8000` is orange.

    \ $FF8000 0 0 pixel

## See Also

- `help sdl3` — the SDL3 window these pixels appear in (`sdl-open`,
  `sdl-frame`/`sdl-show`, `sdl-scale`, events).
- `help memory` — `allocate` for sprite and off-screen buffers, `l@`/`l!`.
- docs/Graphics.md — the surface design; docs/Graphics_Planning.md — the GPU
  road ahead.
