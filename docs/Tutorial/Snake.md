# Snake — Build Your First Game

Welcome! By the end of this tutorial you'll have a playable Snake game running
in your terminal — and along the way you'll touch nearly every part of
BasicForth: the stack, your own words, variables, constants, arrays, loops,
the keyboard, the screen, timing, and randomness.

This is hands-on. After each step BasicForth returns to the prompt so you can
**type the examples yourself** and watch them run. When you're ready for the
next piece, type `next` (or `back` to re-read a step). You build the game one
small word at a time, and each word stays defined for the rest of the session,
so the snake grows under your fingers.

Type `bye` whenever you want to stop; your definitions live until you quit.
Ready? Type `next` to begin.

## The stack — Forth's workspace

Forth keeps numbers on a *stack*. You push numbers, then operators act on
them. The operator comes *after* the numbers (this is Reverse Polish Notation):

    1 2 + .           \ prints 3

Read it as: push `1`, push `2`, `+` adds the top two, `.` prints the result.
Peek at the stack any time with `.s` — it never changes anything:

    10 20 .s          \ prints <2> 10 20
    + .               \ prints 30

Our snake lives on a grid, so we'll be pushing x/y coordinates around all the
time. Getting comfortable here is the whole game. Type `next` when ready.

## Teaching Forth new words

You extend Forth by defining *words*. A definition starts with `:`, then the
name, then what it does, then `;`:

    : square  dup * ;
    5 square .        \ prints 25

`dup` duplicates the top number, `*` multiplies. Words can print text, too —
`." ..."` prints a string and `cr` starts a new line:

    : hello  ." Hi there!" cr ;
    hello

The entire Snake game is just small words like these, each built from the ones
before it. Let's start building.

## The board — constants

Some numbers never change: the size of the board, the speed, the longest the
snake can get. A `constant` gives a number a name:

    22 constant W           \ board width  (play area is columns 1..W)
    16 constant H           \ board height (rows 1..H)
    150 constant FRAME      \ milliseconds per frame (lower = faster)
    300 constant MAXLEN     \ longest the snake can grow

Now the names stand for the numbers:

    W .               \ prints 22
    W H * .           \ prints 352  (cells on the board)

Type those four `constant` lines — we'll use them throughout.

## The game's memory — variables

A `variable` is a named box you can change. Store into it with `!` ("store")
and read it back with `@` ("fetch"):

    variable score
    0 score !         \ put 0 in score
    score @ .         \ prints 0
    5 score +!        \ add 5 to it
    score @ .         \ prints 5

The snake needs a handful of these. Define them all now:

    variable dx  variable dy        \ direction we're moving (-1, 0, or 1)
    variable hx  variable hy        \ the head's position
    variable nx  variable ny        \ where the head is about to move
    variable fx  variable fy        \ the food's position
    variable len                    \ how long the snake is
    variable hd                     \ index of the head in the body (next step)
    variable gameover               \ true when we've crashed

## The snake's body — arrays in memory

A variable holds one number; the snake's body is *many* positions. `create`
makes a named block of memory and `allot` reserves space in it. `cells` turns
a count into bytes (one cell holds one number):

    create bx MAXLEN cells allot    \ x position of each body segment
    create by MAXLEN cells allot    \ y position of each body segment

To reach segment number `idx`, step `idx` cells into the block, then `!`/`@`.
Let's wrap that in four little words:

    : bx! ( x idx -- )  cells bx + ! ;
    : by! ( y idx -- )  cells by + ! ;
    : bx@ ( idx -- x )  cells bx + @ ;
    : by@ ( idx -- y )  cells by + @ ;

Try storing and reading a segment:

    7 0 bx!   0 bx@ .     \ stores 7 at segment 0, prints 7

We treat the body as a *ring*: the head index walks forward and wraps around
with `mod`. The tail is `len` segments behind the head:

    : tail-i ( -- idx )  hd @ len @ 1- - MAXLEN + MAXLEN mod ;

## Drawing on the screen

Time to see something. `page` clears the screen, `at-xy` moves the cursor to a
column/row, and `emit` prints one character by its code. `cursor-off` hides the
blinking cursor (`cursor-on` brings it back). Let's make a word that draws one
character at a spot:

    : draw ( x y char -- )  >r at-xy r> emit ;

`>r` and `r>` tuck the character aside while `at-xy` uses the x and y. Try it:

    5 3 char X draw       \ an X appears at column 5, row 3

`char X` pushes the code for `X`. (Inside a definition you'd write `[char] X`;
`char` is its interpret-at-the-prompt twin.) Now the board's border, drawn with two
`do ... loop` counted loops — one for the top/bottom, one for the sides:

    : draw-border
        W 2 + 0 do  i 0 [char] # draw   i H 1+ [char] # draw  loop
        H 2 + 0 do  0 i [char] # draw   W 1+ i [char] # draw  loop ;

See the arena (this draws over the screen — that's fine, type `next` after):

    page draw-border

## Dropping food at random

The snake needs something to eat. `rnd` gives a random number: `n rnd` is
0..n-1. So `W rnd 1+` is a column from 1 to W:

    W rnd 1+ .        \ a random column (run it a few times)

`place-food` picks a spot and draws an `F` there:

    : place-food
        W rnd 1+ fx !  H rnd 1+ fy !
        fx @ fy @ [char] F draw ;

Try it (you'll see an F somewhere on the board):

    place-food

## Placing the snake

`init-snake` sets the starting state: head in the middle, moving right, length
3, and the three starting body segments laid out in a row. It also clears the
`gameover` flag:

    : init-snake
        W 2 / hx !  H 2 / hy !
        1 dx !  0 dy !
        3 len !  2 hd !  false gameover !
        hx @ 2 - 0 bx!  hy @ 0 by!
        hx @ 1 - 1 bx!  hy @ 1 by!
        hx @     2 bx!  hy @ 2 by! ;

Run it, then peek at the state:

    init-snake
    hx @ .  hy @ .    \ head near the middle: 11 8
    len @ .           \ 3

## Reading the keyboard

We steer with the arrow keys. `key?` tells you whether a key is waiting (so the
game never blocks), and `key` reads it. The arrow keys come back as the
constants `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT`. A `case` statement
picks the matching branch:

    : go ( dx dy -- )  dy !  dx ! ;
    : input
        key? if
            key case
                KEY_UP    of  0 -1 go endof
                KEY_DOWN  of  0  1 go endof
                KEY_LEFT  of -1  0 go endof
                KEY_RIGHT of  1  0 go endof
                [char] q  of  true gameover ! endof
            endcase
        then ;

`go` stores a direction (e.g. `0 -1` means "up": x unchanged, y decreasing).
Unmatched keys are simply ignored. We'll feel this work once the loop runs.

## Looking ahead

Before moving, we compute where the head *would* go — current position plus the
direction — and stash it in `nx`/`ny`:

    : ahead   hx @ dx @ + nx !   hy @ dy @ + ny ! ;

Check it with the snake moving right (dx=1) from the last step:

    init-snake  ahead
    nx @ .  ny @ .    \ one step right of the head: 12 8

## Hitting things — collisions

The game ends if the head leaves the board or runs into the snake's own body.
`wall?` compares the next position against the edges using `<`, `>`, and `or`:

    : wall? ( -- f )
        nx @ 1 <  nx @ W >  or
        ny @ 1 <  ny @ H >  or  or ;

`hits-body?` asks "is the next head cell one of the body cells?" and `or`s the
answers together. There's a subtlety: as the snake advances, its tail moves out
of the way, so the head is *allowed* to follow into the tail's old cell — unless
the snake is **eating**, because then it grows and the tail stays put. So
`hits-body?` takes a flag, `keep-tail?`: true checks the whole body (`len`
segments), false skips the tail (`len-1`):

    : hits-body? ( keep-tail? -- f )
        if len @ else len @ 1- then
        false swap 0 ?do
            hd @ i - MAXLEN + MAXLEN mod
            dup bx@ nx @ =  swap by@ ny @ =  and
            or
        loop ;

Test the checks (the snake from the last step is moving right):

    init-snake  ahead  wall? .              \ 0   still on the board
    0 nx !  wall? .                         \ -1  off the left edge
    init-snake  ahead  false hits-body? .   \ 0   the cell ahead is empty

## One turn of the game

`advance-head` moves the head forward in the ring and records its new spot.
`tick` is one whole turn: look ahead, check for a crash, eat-or-move, then draw
the head:

    : advance-head
        hd @ 1+ MAXLEN mod hd !
        nx @ hd @ bx!   ny @ hd @ by!
        nx @ hx !  ny @ hy ! ;

    : tick
        ahead
        nx @ fx @ =  ny @ fy @ =  and       \ are we eating this move?
        dup hits-body?  wall? or            \ keep the tail in the check iff eating
        if  drop  true gameover !  exit  then
        if    len @ 1+ MAXLEN min len !  place-food
        else  tail-i dup bx@ swap by@ bl draw
        then
        advance-head
        nx @ ny @ [char] O draw ;

`tick` first works out whether this move lands on the food, and reuses that
answer twice: it tells `hits-body?` whether the tail counts, and it decides what
happens next. If we're eating, the snake grows and new food appears; otherwise
we erase the old tail (drawing a `bl`, a blank) so the snake appears to slither.

## Drawing the snake and timing the frame

`draw-snake` draws every segment (used once at startup). `frame-wait` keeps the
game at a steady speed: `ms@` reads a millisecond clock, and `ms` pauses for a
given number of milliseconds, so each frame takes about `FRAME` ms:

    : draw-snake
        len @ 0 ?do
            hd @ i - MAXLEN + MAXLEN mod
            dup bx@ swap by@ [char] O draw
        loop ;

    : frame-wait ( t0 -- )
        ms@ swap -  FRAME swap -  dup 0> if ms else drop then ;

(`t0` is the time the frame started; we sleep for whatever's left of `FRAME`.)

## The game loop — putting it together

`setup` clears the screen and draws the starting board. `play` is the heart of
the game: a `begin ... until` loop that repeats each frame until `gameover`
becomes true. `finish` cleans up and shows your score:

    : setup
        page cursor-off
        init-snake  draw-border  draw-snake  place-food ;

    : play
        begin
            ms@  input  tick  frame-wait  gameover @
        until ;

    : finish
        cursor-on
        0 H 3 + at-xy
        ." Game over!  Score: "  len @ 3 - .  cr ;

## Launch!

One last word ties the three together — and that's the whole game:

    : snake   setup play finish ;

Now play it — arrow keys to steer, `q` to quit:

    snake

The snake starts moving right; steer it onto the `F` to grow. Crash into a wall
or your own tail and it's game over. Type `next` for ideas on making it yours.

## Make it your own

You built a game! Everything is just words you can change. A few ideas:

- Change `FRAME` to `80` for a faster game, or `W`/`H` for a bigger board, then
  run `snake` again. (Re-type the `constant` line to change it.)
- Use a different character for the snake or the food in `tick`/`draw-snake`.
- Make the walls wrap around instead of ending the game (hint: `mod` in
  `advance-head`).

To study a richer version with a score line and increasing speed:

    man snake          \ if you've added examples to BASICFORTH_DOCS

The finished program is in `examples/snake-mini.fs`, and a fuller version in
`examples/snake.fs`. For details on any word used here, the Language Reference
has a page per topic — try `man Loops`, `man Memory`, or `man Terminal-IO`.
Type `back` to revisit any step. Happy hacking!
