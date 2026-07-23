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
    f s

`f` starts a blank frame, `s` presents it — so that last line wipes the window
to black. A brand-new window shows whatever garbage was in memory until you
present something; run `f s` and you have a clean slate to draw on.

Heads up on the third line: when the window appears your desktop gives it the
keyboard, so click back on the terminal running BasicForth before typing the
rest. The window doesn't take input — it just draws — and it stays put while
you work.

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

    create bar
      %00111100 c,     \ ..####..
      %01111110 c,     \ .######.
      %11111111 c,     \ ########
    f  cyan bar 40 40 8 3 stamp  s

Three rows of a shape, and there it is on screen. Leftmost pixel is the high
bit, so the picture never comes out mirrored.

`create bar` names the spot; each `c,` lays one byte down after it. Nothing
here is a definition — the rows just fill dictionary space — but `save` keeps
them anyway, because filling the dictionary *is* a change to your program.
You'll see them in the file later.

## Save your work

Everything you've defined is being remembered. Write it to a file:

    save bitmaps.fs

That creates `bitmaps.fs` in whatever directory you started BasicForth in —
a real file, so pick a directory you don't mind writing to. From here on,
`save` on its own rewrites that same file, and `list` shows what's in it.

## A more readable way

Counting ones and zeros gets old fast. `row,` takes the picture as a
string: `.`, space and `0` leave a pixel clear, anything else sets it.
This one goes in a **word** — the shape we use from here on, because a
name is something you can go back and change. The last step of this
lesson retypes `inv-art` to fix the alien's legs.

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

## Same bytes underneath

The source *is* the picture now — but it isn't a second format. A row is
8 bits wide, so print the first one 8 wide:

    binary inv c@ #8 u.0r decimal

`00111100`, the row you just typed, bit for bit. `row,` compiles exactly
what you were counting out by hand. (`#` marks a number as decimal: once
you are in binary, `8` has no reading.)

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
typed it. `bar`'s loose `c,` rows are there too, right where you typed them.

What's *not* there is `f  cyan bar 40 40 8 3 stamp  s` and every other line
that just drew something. `save` keeps what changed your program — a
definition, or a line that filled dictionary space — and drops what merely
happened. That's what stops a module file turning into a transcript.

When you want one of those dropped lines anyway, end it with `keep`:

    variable hi-score
    1000 hi-score !  keep

`variable hi-score` is a definition and would be saved regardless; the `1000
hi-score !` moved no dictionary at all, so without `keep` your high score
would reload as zero.

`bitmaps.fs` is an ordinary source file. `include bitmaps.fs` in a fresh
session brings it all back.

## Teach the module to start and stop itself

One thing is missing from that listing: `320 180 sdl-open`. It opened your
window, but it defined nothing, so `save` never recorded it — reload this file
tomorrow and you get the words with no window.

Give the module two words and it handles itself:

    : on-start  s" Invaders" sdl-title  320 180 sdl-open ;
    : on-stop   sdl-close ;
    save

These aren't words you call. BasicForth looks them up: `on-start` runs whenever
the module is loaded, `on-stop` just before its words are thrown away. Your
file now knows how to bring its own window up — and how to put it down.

`sdl-title` names the window while we're here. Every BasicForth window is
called `BasicForth` by default, which is fine until you have two of them and
can't tell which is which.

(`4 to sdl-scale` is already in the file — a direct `to` gets recorded — and it
replays before `on-start` runs, so the hook only needs the line that was
missing.)

## Changing a shape later

Now suppose the alien's legs bother you. You don't retype the file — you
retype the word:

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

## Why the window blinked

`:e` doesn't just patch the word in memory — it rewrites the file and
**reloads it**, so your live state becomes whatever the file rebuilds.
That's why the window blinked. Stamp the alien again to see the new legs:

    f  green inv 40 40 8 8 stamp  s

The reload is also why `on-stop` and `on-start` matter. Without them it
would forget `sdl-win` while the window itself kept existing, and that
`stamp` would have failed with `Parameter 'texture' is invalid` — a window
on screen that nothing could draw to or close. Instead `on-stop` closed it
properly on the way down and `on-start` opened a fresh one on the way back
up.

That's the deal with a module you can edit a word at a time: the file is the
truth, reloading replays it, and the two hooks are how anything *outside*
the file gets handed over cleanly.

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
