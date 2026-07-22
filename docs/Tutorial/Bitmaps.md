# Bitmaps — Sprites You Type in Binary

There's a second kind of sprite: one bit per pixel, with the color chosen
when you draw it. You type the shape yourself — first as binary numbers, then
as rows of dots and hashes that look exactly like what they draw. Graph
paper, in your source.

Along the way you'll save your work to a file and read it back, so this is
also a first look at keeping a session.

The `Sprites` lesson is a good warm-up but not required; you do need a
display, and the frame sandwich from `Graphics` (`sdl-frame` … `sdl-show`).

`next` continues, `back` re-reads, `end-tutorial` stops. Type `next` to begin.

## Set the stage

Window plus the two helpers that save typing:

    require sdl3.fs
    4 to sdl-scale
    320 180 sdl-open
    : f  sdl-frame  black clear ;
    : s  sdl-show ;

## A different kind of sprite

A full-color sprite stores a color for every pixel — 4 bytes each. A bitmap
stores one *bit* per pixel: 1 means draw, 0 means leave it alone. There's no
color in the data at all — you supply it at draw time, which is why the word
is `stamp ( color src x y w h -- )` with the color out front.

So one shape can be red now and cyan later, with nothing copied or converted.
That's the whole idea; the rest of this lesson is consequences.

## Type your first shape

Eight bits fit in a byte, so an 8-wide row is one byte and `c,` compiles it.
Write the rows in binary with `%` and you can see what you're making:

    : bar-art
      %00111100 c,     \ ..####..
      %01111110 c,     \ .######.
      %11111111 c, ;   \ ########
    create bar bar-art
    f  cyan bar 40 40 8 3 stamp  s

Three rows of a shape, and there it is on screen. Leftmost pixel is the high
bit, so the picture never comes out mirrored.

The art lives in a word for a reason: rows of `c,` define nothing on their
own, so writing them straight after `create bar` would vanish when you save.
As a word it's a definition, so it survives — which we're about to rely on.

## Save your work

Everything you've defined is being remembered. Write it to a file:

    save bitmaps.fs

That creates `bitmaps.fs` in whatever directory you started BasicForth in —
a real file, so pick a directory you don't mind writing to. From here on,
`save` on its own rewrites that same file, and `list` shows what's in it.

## A more readable way

Counting ones and zeros gets old fast. `row,` takes the picture as a string:
`.`, space and `0` leave a pixel clear, anything else sets it.

    : inv-art
      s" ..####.." row,
      s" .######." row,
      s" ##.##.##" row,
      s" ########" row,
      s" ..#..#.." row,
      s" .#.##.#." row,
      s" #......#" row,
      s" .#....#." row, ;
    create inv inv-art

Now the source *is* the picture. And it isn't a second format — check:

    inv c@ .

`60`, the very byte `%00111100` gave you for the top of `bar`. `row,`
compiles exactly what you were typing by hand; you just stopped counting
bits. Strings from here on.

Curious what the bits look like? `binary inv c@ . decimal` shows `111100` —
`.` prints the shortest form, so the two leading zeros of `00111100` don't
appear. The row is always 8 bits wide even when the number doesn't look it.

## Stamp it

    f  green inv 40 40 8 8 stamp  s

An alien, eight pixels square — 32 screen pixels at `sdl-scale 4`. After the
color comes the art, then where it goes, then how big it is.

## One shape, any color

Here's what full-color sprites can't do. Same eight bytes, six colors:

    create palette  red , green , blue , yellow , cyan , magenta ,
    : row6  f  6 0 do
        palette i cells + @  inv  i 45 * 20 +  80  8 8 stamp
      loop  s ;
    row6

Six aliens, one piece of art, no copies. To recolor a full-color sprite you'd
rewrite its pixels; here the color was never in the sprite to begin with.

## Zero bits let the background through

Nothing is written where a bit is 0 — not black, *nothing*:

    f  blue 0 0 320 90 fill-rect  yellow inv 40 40 8 8 stamp  s

The alien sits on the blue band with no box around it. Transparency comes
free, because a bitmap only ever says where to draw.

## Wider than eight

Nothing ties you to 8. The string's length is the width, and `row,` uses as
many bytes as it needs — two for anything up to 16 wide, each row starting a
fresh byte:

    : ship-art
      s" .......##......." row,
      s" .....#######...." row,
      s" ...###########.." row,
      s" .##############." row,
      s" ################" row,
      s" ..##........##.." row, ;
    create ship ship-art
    f  cyan ship 150 60 16 6 stamp  s

That saucer is 12 bytes. In full color it would be 384, and a 16x16 bitmap is
32 bytes against 1024 — **32 times smaller**. Which is why this art lives in
the dictionary instead of needing `allocate`: a hundred shapes is a few
kilobytes. Art becomes part of your program text rather than something you
manage.

## Two shapes make it move

A second pattern and a way to pick between them — legs together, legs apart:

    : inv2-art
      s" ..####.." row,
      s" .######." row,
      s" ##.##.##" row,
      s" ########" row,
      s" ..#..#.." row,
      s" .#.##.#." row,
      s" .#....#." row,
      s" #.#..#.#" row, ;
    create inv2 inv2-art
    : bob  240 0 do  f  green
        i 8 / 2 mod if inv2 else inv then  60 40 8 8 stamp  s  loop ;
    bob

`i 8 / 2 mod` counts 0,0,0…1,1,1… — the frame number divided down, then
alternating. The `if … else … then` just leaves one address for `stamp`.

## An invasion in color

Put it together: a marching row, every alien a different color.

    : army  240 0 do  f  6 0 do
        palette i cells + @
        j 8 / 2 mod if inv2 else inv then
        i 45 * 20 +  80  8 8 stamp
      loop  s  loop ;
    army

Six colors and two frames of animation, out of 16 bytes of art.

## stamp or blit?

Both have their place:

- **`stamp`** — one color per shape, tiny, recolorable, transparency free.
  Aliens, ships, bullets, letters, icons, anything you'd have drawn on graph
  paper. Most simple games never need more.
- **`blit` / `blit-key`** — many colors in one sprite, and a straight memory
  copy per row rather than a test per pixel. Reach for it when a shape needs
  shading, or when you grabbed the art off the screen with `grab`.

They share a surface, so mix them freely in one frame.

## Save and see what you made

    save
    list

There's your whole session: `require`, both aliens, the saucer, the palette,
and every word you defined — in order, with the art laid out exactly as you
typed it. Notice the art *is* there. That's the payoff for putting it inside
`: inv-art … ;` words back at the start; loose rows of `row,` would have been
dropped and you'd have reloaded to empty sprites.

`bitmaps.fs` is an ordinary source file. `include bitmaps.fs` in a fresh
session brings it all back.

## Changing a shape later

    sdl-close

Window gone, session intact. Now suppose the alien's legs bother you. You
don't retype the file — you retype the word:

    :e inv-art
      s" ..####.." row,
      s" .######." row,
      s" ##.##.##" row,
      s" ########" row,
      s" ..#..#.." row,
      s" .#.##.#." row,
      s" #......#" row,
      s" #......#" row, ;
    list

`:e` replaces `inv-art` *where it stands* in the file — look at the listing,
there's still exactly one `inv-art`, with the new legs. A plain `:`
redefinition would have appended a second copy instead. `edit inv-art` does
the same thing through your `$EDITOR` if you'd rather not retype it.

Notice we closed the window first. `:e` doesn't just patch the word in
memory — it rewrites the file and **reloads it**, so your live state becomes
whatever the file rebuilds. Definitions come back; things you set at the
prompt mostly come back too, because a direct `to` is recorded. But an open
window isn't in the file — `sdl-open` set that up from inside a word — so a
reload leaves it stranded. Close it first, edit, then open again.

That's the trade for a module you can edit a word at a time: the file is the
truth, and reloading replays it.

## Where to go next

A bitmap is one bit per pixel, MSB first, rows in reading order, colored when
drawn — and `row,` turns a picture you can read into exactly those bytes.

Worth knowing: a bitmap plus a color is also exactly what a text character
is. A 96-character 8x8 font is 768 bytes, the same shape of data you just
typed by hand.

    help stamp         \ the reference entry
    help graphics      \ every drawing word
    help modules       \ save, list, :e, edit
    tutorial Sprites   \ the full-color model
    tutorials          \ or pick another
