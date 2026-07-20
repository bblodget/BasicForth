# Graphics — Draw on a Real Window

In the next ten minutes you'll open a window, plot pixels, draw shapes,
compose a scene, and animate it — all live from the prompt, watching every
step appear on screen. You need a display for this one: a desktop, or the
console on a board.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it — the window waits patiently while you read. Type
`next` to continue, `back` to re-read, and `end-tutorial` to stop.

Type `next` to begin.

## One line loads everything

The graphics words live in libraries loaded on demand. One line:

    require sdl3.fs

`require` loads a file only if it isn't already loaded — and `sdl3.fs`
requires its own dependencies (the C-library bridge, the drawing words), so
that single line brings up the whole stack. Run it twice if you like: the
second is a no-op. Type it, then `next`.

## Open a window

    4 to sdl-scale
    320 180 sdl-open

A window appears — and stays while you keep typing. It's 1280×720 on your
desktop, but *your* surface is 320×180: `sdl-scale 4` shows each of your
pixels as a fat 4×4 block. Chunky retro pixels, and 1/16 the drawing work —
that trade is what makes software rendering fast.

## The frame sandwich

The window is still showing garbage — you haven't drawn a frame. A frame is
a sandwich: start it, draw, present it:

    sdl-frame  black clear  sdl-show

The window turns black. `sdl-frame` points the drawing words at the
window's pixels; `sdl-show` presents what you drew. All drawing happens
between the two.

## Frames start blank

One rule surprises everyone: the next `sdl-frame` starts from scratch —
your previous pixels are gone, not remembered. So every frame clears and
redraws everything. That's a lot of typing at a prompt, so make two
helpers:

    : f  sdl-frame  black clear ;
    : s  sdl-show ;

From here on: `f` ...draw... `s`.

## Your first pixel

    f  white 160 90 pixel  s

One white dot (well — one fat 4×4 block), dead center. The color comes
first, then x and y: (0,0) is the top-left corner and y grows *downward*,
so 160,90 is the middle of a 320×180 surface.

## Rectangles

    f  yellow 20 20 120 70 fill-rect  s
    f  yellow 20 20 120 70 fill-rect  white 20 20 120 70 rect  s

Both take `color x y w h` — corner, then size. `fill-rect` paints the box,
`rect` draws its one-pixel outline; the second line puts a white frame
around the yellow slab.

## Lines

    f  green 0 0 319 179 line  red 319 0 0 179 line  s

`line` takes two endpoints — `color x0 y0 x1 y1` — any direction. And
nothing needs to stay on screen:

    f  blue -100 90 500 60 line  s

Off-surface coordinates simply clip. Every drawing word does this: draw
freely, the surface takes what's visible.

## Circles

    f  cyan 160 90 70 circle  magenta 160 90 35 fill-circle  s

Center, then radius: `color cx cy r`. `circle` is the ring, `fill-circle`
the disc. A radius of 0 is a single pixel.

## Colors

You've been using named constants — `black white red green blue yellow
cyan magenta`. A color is just a number, `$RRGGBB` (hex: red, green, blue,
one byte each), so you can mix your own:

    $FF8000 constant orange
    f  orange 160 90 40 fill-circle  s

## A scene of your own

Drawing words compose like any Forth words. A picture is a definition:

    : scene  f
        yellow 270 30 18 fill-circle       \ a sun
        $1060A0 0 130 320 50 fill-rect     \ the sea
        s ;
    scene

Now improve it — redefine `scene` with a bigger sun (the `redefined scene`
message is normal), run it again. You're editing a picture the way you
edit any program: change the word, run the word.

## Animation

An animation is just frames in a loop. `sdl-show` paces the loop to a steady
frame rate (`sdl-fps`, 60 by default), so it runs the same speed on any
machine — no timer of your own:

    : slide  320 0 do  f  yellow i 90 10 fill-circle  s  loop ;
    slide

The loop index `i` is the x coordinate: one frame, one pixel, so the ball
crosses in a few seconds (320 frames at 60 fps ≈ 5 s). Try `120 to sdl-fps`
before running it again — twice as fast. Every game loop you'll write is
this shape: clear, draw at new positions, show, repeat.

## Closing time

    sdl-close

Window gone, session intact — `sdl-open` brings it back any time.

## Where to go next

You now hold the whole model: a surface of pixels, drawing words that
clip, and the frame loop. In the reference, `help graphics` covers every
drawing word (including sprites — `blit` and friends, a future lesson) and
`help sdl3` the window, events, and keys. The bouncing-ball demo is the
natural next read — a complete game loop with keyboard and sound in ~60
lines:

    include bounce.fs
    bounce             \ ESC quits
    tutorials          \ pick your next lesson

Type `end-tutorial` to wrap up. Happy drawing!
