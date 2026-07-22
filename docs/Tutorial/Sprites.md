# Sprites — Pixel Art That Moves

A sprite is a little picture you stamp onto the screen — a ship, an alien, a
ball. In this lesson you'll grab one off the screen, type one in by hand,
make it transparent, and march a row of them across the window.

Do the `Graphics` lesson first if you haven't: this one assumes you know the
frame sandwich (`sdl-frame` ... `sdl-show`) and the drawing words.

`next` continues, `back` re-reads, `end-tutorial` stops. Type `next` to begin.

## Set the stage

Same opening as the Graphics lesson — window, plus the two helpers that save
typing:

    require sdl3.fs
    4 to sdl-scale
    320 180 sdl-open
    : f  sdl-frame  black clear ;
    : s  sdl-show ;

`f` starts a blank frame, `s` presents it. Everything below goes between them.

## A sprite is just memory

There's no sprite type and no file format. A sprite is `w*h` pixels, 4 bytes
each, packed row after row — nothing else. So you can make one with plain
memory:

    16 16 * 4 * allocate throw value ball

That's 16x16 pixels at 4 bytes = 1024 bytes of heap. `allocate` returns the
address *and* an error code; `throw` raises that code if it's non-zero (out
of memory) and does nothing when it's zero, so on success `value` just names
the address `ball`. (`throw` is the standard way to pass an error up — see
`tutorial Exceptions`.)

The block arrives zeroed — the kernel always hands over fresh memory that
way — and a zero pixel is black, so `ball` is a 16x16 black square right now.
`ball 1024 dump` will show you.

## Grab one off the screen

The easy way to make a sprite is to draw it with the shape words and take a
copy. `grab` is `blit` in reverse:

    f  yellow 8 8 7 fill-circle  ball 0 0 16 16 grab  s

Note *where* the `grab` sits: inside the sandwich. Between `f` and `s` the
surface points at the window's live pixels — that's the only moment there's
anything to copy. After `s` the surface is gone until the next `f`.

## Stamp it anywhere

Now `ball` is a picture you can put down as many times as you like:

    : row  f  10 0 do  ball  i 30 *  80  16 16 blit  loop  s ;
    row

Ten balls in one frame. `blit` takes `src x y w h` — the buffer, then where
its top-left corner goes, then its size. (The loop lives in a definition
because `do` and `loop` are compile-only — they can't run straight from the
prompt.)

## Type your own art

The other way to make a sprite is to type it. Give your colors two-character
names so a row of pixels lines up as a row of text:

    magenta constant __
    green   constant GG
    : inv-art
      __ l, __ l, GG l, GG l, __ l, __ l,
      __ l, GG l, GG l, GG l, GG l, __ l,
      GG l, __ l, GG l, GG l, __ l, GG l,
      GG l, GG l, GG l, GG l, GG l, GG l,
      __ l, GG l, __ l, __ l, GG l, __ l,
      GG l, __ l, __ l, __ l, __ l, GG l, ;
    create inv inv-art

You can see the little alien in the source. `l,` writes one pixel — it's the
32-bit version of `,`, because a pixel is 4 bytes but a cell is 8. The art
lives in a word, and `create inv inv-art` runs it to lay those pixels down.

Writing the rows straight after `create inv` would draw the same alien, but
it wouldn't survive `save`: the module log records *definitions*, and a row
of `l,` defines nothing — you'd reload to a bare `create inv` with no art.
Wrapped in a word, the art is a definition, so it saves and reloads intact.

## The box problem

Stamp it over something and the flaw shows up:

    f  red 0 0 320 60 fill-rect  inv 40 20 6 6 blit  s

A magenta box with an alien in it. `blit` copies *every* pixel, background
included — sprites are rectangles, but pictures aren't.

## Transparency

Name one color as "skip this pixel" and the box disappears:

    f  red 0 0 320 60 fill-rect  magenta inv 40 20 6 6 blit-key  s

`blit-key` takes the key color first, then the same arguments as `blit`. Any
pixel matching the key is left alone, so the red shows through. Magenta is
the traditional key because almost nothing is that color by accident.

## Off the edge is fine

Sprites clip like every other drawing word — you never have to check bounds:

    f  magenta inv -3 20 6 6 blit-key  magenta inv 317 20 6 6 blit-key  s

Half an alien on each edge. Negative coordinates, coordinates past the far
side, partly-off corners: all fine, nothing to guard against.

## Two frames make it alive

Animation is a second picture and a way to choose between them. Same alien,
legs out:

    : inv2-art
      __ l, __ l, GG l, GG l, __ l, __ l,
      __ l, GG l, GG l, GG l, GG l, __ l,
      GG l, __ l, GG l, GG l, __ l, GG l,
      GG l, GG l, GG l, GG l, GG l, GG l,
      __ l, GG l, __ l, __ l, GG l, __ l,
      __ l, GG l, __ l, __ l, GG l, __ l, ;
    create inv2 inv2-art

Only the last row differs. Now flip between them every 8 frames:

    : bob  240 0 do  f  magenta  i 8 / 2 mod if inv2 else inv then
        60 20 6 6 blit-key  s  loop ;
    bob

`i 8 / 2 mod` is 0,0,0...1,1,1... — the frame counter divided down, then
alternating. That `if inv2 else inv then` just leaves one address on the
stack for `blit-key` to use.

## Make it move

Animating in place and moving are the same loop — one picks the sprite, the
other picks the position:

    : walk  320 0 do  f  magenta  i 8 / 2 mod if inv2 else inv then
        i 80 6 6 blit-key  s  loop ;
    walk

The loop index is now doing double duty: `i 8 / 2 mod` chooses the frame and
`i` is the x coordinate. It waddles across in about five seconds — `sdl-show`
holds the pace at `sdl-fps`.

## An invasion

One more loop inside the frame and you have a formation. The outer index `j`
is the frame counter, the inner `i` is which alien:

    : army  240 0 do  f  6 0 do
        magenta  j 8 / 2 mod if inv2 else inv then
        i 40 * 20 +  80  6 6 blit-key
      loop  s  loop ;
    army

Six aliens marching in step, all from two hand-typed pictures. That is the
whole of 1978 arcade graphics.

## Closing time

    sdl-close
    ball free drop

`sdl-close` takes the window down. `ball` came from `allocate`, so `free`
hands it back (it returns an error code — `drop` it). Sprites made with
`create` are part of your program and need no cleanup.

## Where to go next

You now have the whole sprite model: a sprite is packed pixels, `grab` makes
one from the screen and `l,` makes one by hand, `blit` stamps it, `blit-key`
makes it transparent, and picking between pictures each frame animates it.

There's a second kind of sprite worth knowing about: `stamp` draws a
*one-bit* sprite in a color you pick at draw time, so the same shape can be
red one frame and cyan the next. The art is written a row per byte —
`%00111100 c,` is literally the row it draws — and takes 32x less space. See
`help stamp`.

In the reference, `help graphics` has every drawing word, `help sdl3` covers
the window and keyboard, and `help memory` explains `allocate`/`free`. Then
read `examples/bounce.fs` — a complete game loop with input and sound — and
try replacing its ball with an alien.
