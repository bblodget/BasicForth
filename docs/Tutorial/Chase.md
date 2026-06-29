# Chase — Design a Game from the Top Down

In the Snake tutorial you built a game *bottom-up*: small words first, then
bigger words made from them, until the last word was the whole game. That's a
great way to learn the language.

This time we'll work the other way — *top-down*. We'll write the **whole game's
shape first**, as a handful of names that don't exist yet, run that empty shell
to prove the structure, and only then fill in the parts. The tool that makes
this possible is `defer`: it lets you *name* a word before you've written it.

The game is **Chase**: you're `@`, you roam a walled arena scooping up gold
`$`, and monsters `M` hunt you down. By the end, each monster will have its own
*brain* — one chases, one ambushes, one drifts — Pac-Man style.

This is hands-on. After each step BasicForth returns to the prompt so you can
**type the examples yourself**. Type `next` for the next step, `back` to
re-read one, `bye` to stop. Ready? Type `next` to begin.

## Top-down — sketch the shape first

Before writing any code, decompose the game out loud. A game is three things in
a row:

    setup   play   finish

`setup` builds the starting board, `play` runs until you lose, `finish` shows
your score. And `play` itself is a loop — every frame it does the same handful
of jobs:

    input    \ read the keyboard
    erase    \ blank the old player/monster cells
    update   \ move everything, check for gold and crashes
    render   \ draw everything at its new spot
    wait     \ hold the frame to a steady speed

That list — a few named jobs — *is* the design. We haven't written one of them,
but we already know the program's whole shape. The plan is to **write that shape
down as real code now**, before the parts exist, and run it. For that we need a
way to use a word's name before we've defined it. Type `next`.

## defer — naming a word before you write it

Normally a word must exist before you can use it. `defer` breaks that rule: it
creates a word whose *behavior is filled in later*. Try it:

    defer greet
    greet                  \ aborts: "uninitialized deferred word"

`greet` exists, but it has no body yet, so running it is an error. Now give it
one with `is`:

    :noname  ." Hello!" cr ;  is greet
    greet                  \ prints Hello!

`:noname ... ;` defines a word with no name and leaves its *execution token* on
the stack; `is greet` installs that token as `greet`'s behavior. The magic part
is that you can change it **live**, without recompiling anything that calls it:

    :noname  ." Hi again!" cr ;  is greet
    greet                  \ now prints Hi again!

That's the whole trick behind top-down design: every part of the game starts as
a deferred name, and we swap real behavior in as we go. Type `next`.

## The skeleton — write the top words as comments first

Here's how we want to start the game — the highest-level word, written exactly
as we think of it:

    \ : chase   setup play finish ;

We write it as a *comment* for now, because `setup`, `play`, and `finish` don't
exist yet. But seeing it spelled out tells us precisely what to build next.

`play` is the game loop. Let's sketch it the same way — a comment that says, in
order: note the start time (`ms@`), read the keyboard, erase the old frame,
update positions, draw the new frame, hold the pace, and stop when we're done:

    \ : play   begin  ms@  input erase update render  frame-wait  done?  until ;

Two comments, and the entire program is on the page. Reading them off, the
words that don't exist yet are: `setup`, `finish`, `input`, `erase`, `update`,
`render`, `frame-wait`, and `done?`. (`ms@` is built in.) That list of gaps is
exactly what we'll `defer` next. Type `next`.

## Defer the gaps, then run the empty skeleton

We discovered the missing words by writing the high-level words first. Now name
them all with `defer` — *then* the real `chase` and `play` will compile:

    defer setup  defer finish
    defer input  defer erase  defer update  defer render
    defer frame-wait  defer done?

With every gap named, un-comment the two structural words and define them for
real:

    : play   begin  ms@  input erase update render  frame-wait  done?  until ;
    : chase  setup play finish ;

Read `chase` as the design, verbatim: set up, play, finish. Now run it:

    chase                  \ aborts on an uninitialized deferred word

The whole program *runs* — and stops at the first empty part (`setup`). That's
the top-down payoff: the structure is real and proven before a single job is
written. Type `next`.

## Make the skeleton breathe — stubs

Let's give every gap a throwaway stub so the skeleton runs end to end. A stub is
just a `:noname` that does the least possible thing:

    :noname  page ;                       is setup
    :noname ;                             is input
    :noname ;                             is erase
    :noname ;                             is update
    :noname  10 5 at-xy [char] @ emit ;   is render    \ draw @ at a fixed spot
    :noname  drop ;                       is frame-wait \ ignore the time
    :noname  key? ;                       is done?      \ stop on any key
    :noname ;                             is finish

Now run the shell:

    chase                  \ clears screen, draws @, exits when you press a key

It does almost nothing — but it *loops*, draws, and quits cleanly. The design is
alive end to end. From here we replace stubs with the real thing, one job at a
time, **defining each variable the moment we first need it**. Type `next`.

## The board and the player

Time for real graphics. The arena is `W` columns by `H` rows; the player has a
position and a heading; `caught` ends the game. Define them now, as we reach
for them:

    40 constant W            \ arena width  (columns 1..W)
    20 constant H            \ arena height (rows 1..H)

    variable px  variable py         \ player position
    variable pdx variable pdy        \ player heading (-1, 0, or 1 each)
    variable caught                  \ true when a monster gets you

`draw` puts one character at a spot; `draw-border` frames the arena with `#`
using two counted loops (top/bottom, then sides), exactly as in Snake:

    : draw ( x y char -- )  >r at-xy r> emit ;
    : draw-border
        W 2 + 0 do  i 0 [char] # draw   i H 1+ [char] # draw  loop
        H 2 + 0 do  0 i [char] # draw   W 1+ i [char] # draw  loop ;

`new-game` puts the player in the middle, standing still. Then we fill the
**real** `setup`: hide the cursor, start a new game, draw the walls:

    : new-game
        W 2 / px !  H 2 / py !  0 pdx !  0 pdy !  false caught ! ;
    :noname  page cursor-off  new-game  draw-border ;  is setup

Run it on its own to admire the arena (the player joins once the loop draws it):

    setup

Type `next`.

## Moving — input, stepping, and the real frame

Now steering. `input` reads an arrow key and sets the *heading* (`pdx`/`pdy`);
the player keeps moving that way every frame until you change it. `q` ends the
game. Unmatched keys are ignored:

    : go ( dx dy -- )  pdy !  pdx ! ;
    :noname
        key? if
            key case
                KEY_UP    of  0 -1 go endof
                KEY_DOWN  of  0  1 go endof
                KEY_LEFT  of -1  0 go endof
                KEY_RIGHT of  1  0 go endof
                [char] q  of  true caught ! endof
            endcase
        then ;  is input

`step-player` advances by the heading, clamped so you can't cross a wall
(`1 max W min` keeps the column in `1..W`). The real `erase` and `render` are a
pair: erase blanks the player's *old* cell, render draws the *new* one — that
split is why the player leaves no trail:

    : step-player
        px @ pdx @ + 1 max W min px !
        py @ pdy @ + 1 max H min py ! ;

    :noname  px @ py @ bl draw ;               is erase
    :noname  px @ py @ [char] @ draw ;         is render

Last, give `frame-wait` its real body so the game runs at a steady speed: `ms@`
reads a millisecond clock and `ms` pauses, so each frame lasts about `FRAME` ms:

    120 constant FRAME       \ milliseconds per frame
    :noname ( t0 -- )  ms@ swap -  FRAME swap -  dup 0> if ms else drop then ;
        is frame-wait

`update` still does nothing, so the player won't move in-game yet. We wire that
up with the gold next. Type `next`.

## Gold

Gold sits still; stepping onto it scores a point and a new piece appears. Define
its state as we use it:

    variable gx  variable gy         \ gold position
    variable score

    : spawn-gold   W rnd 1+ gx !  H rnd 1+ gy ! ;
    : eat?
        px @ gx @ =  py @ gy @ =  and
        if  1 score +!  spawn-gold  then ;

Teach `new-game` to zero the score and drop the first gold, draw the gold in
`render`, and fill the first real `update` (move the player, check for gold) and
the real `done?` (we're done when `caught`):

    : new-game
        W 2 / px !  H 2 / py !  0 pdx !  0 pdy !
        false caught !  0 score !  spawn-gold ;
    :noname  gx @ gy @ [char] $ draw  px @ py @ [char] @ draw ;  is render
    :noname  step-player  eat? ;  is update
    :noname  caught @ ;           is done?

Play the (monsterless) game — walk onto the `$` and watch your score climb, `q`
to quit:

    chase

It's a real game already, and we still haven't touched a monster. Curious what
you've built? At the prompt, type `.session` — it lists just the words *you've*
defined (skipping the ~330 built-ins), so you can watch your vocabulary grow as
you fill in seams. Type `next`.

## A table of monsters

Monsters need positions too — but we'll have *several*, so instead of a pair of
variables we keep a **table**: parallel arrays indexed by monster number, just
like Snake's body ring. `mcount` says how many are live:

    8  constant MAXM                 \ most monsters the table can hold
    variable mcount
    create mxs  MAXM cells allot     \ x of each monster
    create mys  MAXM cells allot     \ y of each monster

    : mx@ ( i -- x )  cells mxs + @ ;
    : my@ ( i -- y )  cells mys + @ ;
    : mx! ( x i -- )  cells mxs + ! ;
    : my! ( y i -- )  cells mys + ! ;

`nudge-x` / `nudge-y` move monster `i` one step on an axis, clamped to the arena
so a monster can't climb the wall:

    : nudge-x ( i step -- )  over mx@ + 1 max W min swap mx! ;
    : nudge-y ( i step -- )  over my@ + 1 max H min swap my! ;

`place-monster` scatters monster `i` to a corner, `draw-monsters` paints them
all, and `new-game` fields one monster for now:

    : place-monster ( i -- )
        dup 2 mod    if W 1- else 2 then  over mx!
        dup 2 / 2 mod if H 1- else 2 then  swap my! ;
    : draw-monsters  mcount @ 0 ?do  i mx@ i my@ [char] M draw  loop ;

    : new-game
        W 2 / px !  H 2 / py !  0 pdx !  0 pdy !
        false caught !  0 score !
        1 mcount !  0 place-monster  spawn-gold ;

Type `next` to give that monster a brain.

## The brain — a deferred seam

A *brain* is a word that takes a monster's index and moves it one step. Our
first brain, `hunt`, steps toward the player on each axis. `toward` returns the
sign of `target - current` — that's `-1`, `0`, or `+1`:

    : sgn ( n -- -1|0|1 )   dup 0> if drop 1 else 0< if -1 else 0 then then ;
    : toward ( cur target -- step )  swap - sgn ;

    : hunt ( i -- )
        dup  dup mx@ px @ toward  nudge-x
        dup my@ py @ toward  nudge-y ;

Here's the design move. We don't call `hunt` from the game directly — we drive
the monsters through a *deferred* `monster-brain`, so we can swap their mind
later. Defer it (the last gap, discovered now that we need it), have
`step-monsters` run the current brain on every monster, and install `hunt`:

    defer monster-brain
    : step-monsters  mcount @ 0 ?do  i monster-brain  loop ;
    ' hunt is monster-brain

`monster-brain` is one shared seam — every monster runs the same one — and
that's exactly the knob we'll turn shortly. The monsters don't move yet, because
`update` doesn't call `step-monsters`. Let's finish that wiring, with
collisions, next. Type `next`.

## Finishing the loop — collisions

A monster catching you ends the game. `collide?` checks the player against every
monster; `erase` and `render` grow to cover the monsters; `update` now steps
them; `finish` shows your score:

    : collide?
        mcount @ 0 ?do
            px @ i mx@ =  py @ i my@ =  and
            if true caught ! then
        loop ;

    :noname  px @ py @ bl draw
             mcount @ 0 ?do  i mx@ i my@ bl draw  loop ;   is erase
    :noname  gx @ gy @ [char] $ draw
             px @ py @ [char] @ draw  draw-monsters ;       is render
    :noname  step-player  step-monsters  eat?  collide? ;   is update

    :noname  cursor-on  0 H 3 + at-xy
             ." Caught!  Score: "  score @ .  cr ;          is finish

Now it's a complete game: one monster hunting you across the arena. Play it —
arrow keys to run, `q` to give up:

    chase

Type `next` to meet the reason we built it this way.

## Swap the brain, live

The monster runs through `monster-brain`, a deferred word — so we can replace
its mind *without recompiling the game*. Define a lazier brain that drifts at
random:

    : drift ( i -- )
        dup 3 rnd 1- nudge-x
        3 rnd 1- nudge-y ;

Now swap it in and play again — same `chase`, completely different monster:

    ' drift is monster-brain
    chase                  \ easy mode: the monster wanders

Swap back to `' hunt is monster-brain` for hard mode. *This* is what top-down
design with `defer` buys you: the seam between "the game" and "the monster's
mind" is a live knob you can turn any time. Type `next`.

## The limit of defer — many monsters, many minds

`monster-brain` is *one* binding shared by every monster. Add a second monster
and they'd think with the same brain — both hunt, or both drift, never one of
each. To give **each monster its own mind**, we can't use a single deferred
word; we need to store a brain *per monster* and run the right one for each.

The tool is the **execution token**. `'` (tick) fetches a word's token, and
`execute` runs a token. Try it at the prompt:

    ' hunt .               \ prints a number — hunt's execution token
    3 4  ' + execute  .    \ fetch +'s token and run it: prints 7

If we keep a token *in a variable*, we can change which word runs by changing
the variable — and an array of tokens gives every monster its own. Type `next`.

## A brain for every monster

Add a third parallel array — one token per monster — and a way to read and write
it:

    create mbrain  MAXM cells allot      \ execution token of each monster's brain
    : brain@ ( i -- xt )   cells mbrain + @ ;
    : brain! ( xt i -- )   cells mbrain + ! ;

Now `step-monsters` runs **each monster's own** brain. For monster `i` it pushes
`i` (the argument), fetches that monster's token, and `execute`s it:

    : step-monsters  mcount @ 0 ?do  i  i brain@  execute  loop ;

Give us a second personality — `ambush` aims a few cells *ahead* of the player,
to cut you off:

    : ambush ( i -- )
        dup  dup mx@  px @ pdx @ 3 * +  toward  nudge-x
        dup my@  py @ pdy @ 3 * +  toward  nudge-y ;

`install-brains` hands each monster a different mind, and `new-game` now fields
three of them:

    : install-brains
        ' hunt   0 brain!
        ' ambush 1 brain!
        ' drift  2 brain! ;

    : new-game
        W 2 / px !  H 2 / py !  0 pdx !  0 pdy !
        false caught !  0 score !
        3 mcount !  mcount @ 0 ?do i place-monster loop
        install-brains  spawn-gold ;

Play it — three monsters, three minds, all from one table of tokens:

    chase

That's the Pac-Man trick: each ghost is the same code with a different brain in
its slot. Type `next`.

## Bake the design

The deferred seams were scaffolding for *building* the game top-down. Once a
design has settled, you can **bake** it: replace a `:noname ... is foo` seam
with an ordinary definition, which is a hair faster (no token lookup) and reads
straight through. For example the now-final `update`:

    : update  step-player  step-monsters  eat?  collide? ;

The finished program in `examples/chase.fs` is fully baked — every seam is a
plain `:` definition, and the only token indirection left is the per-monster
`mbrain` table, because *that one is the feature*, not scaffolding.

Two notes for when you `save` your work (and check `.session` to see everything
you've defined):

- An ordinary word you redefine interactively is captured by `redo`/`reload`.
- A live `is`/`to` is saved **only** when you typed it straight at the prompt —
  an `is` buried inside another word isn't replayed. So keep your final brain
  assignments (`' hunt 0 brain!` …) at the top level, or fold them into
  `new-game` as we did. Type `next` for where to take it.

## Make it your own — toward Pac-Man

You designed a game top-down, and gave its monsters swappable minds. Now bend
it:

- **More monsters:** bump the count in `new-game` (up to `MAXM`) and hand each a
  brain in `install-brains`.
- **New brains:** write a `patrol` that paces a row, or a `flee` that runs from
  you — each is just a `( i -- )` word you drop into a `mbrain` slot.
- **Tune the chase:** lower `FRAME` for speed, or move monsters every *other*
  frame so they're beatable.
- **Toward Pac-Man:** add **walls** inside the arena and have brains route
  around them. That's real maze pathfinding — the natural next project.

The finished program is `examples/chase.fs`. For any word used here, the
Language Reference has a page per topic — try `man defer`, `man execute`, or
`man Loops`. Type `back` to revisit any step. Happy hacking!
