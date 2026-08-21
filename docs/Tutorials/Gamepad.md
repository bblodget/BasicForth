# Gamepad — Reading a Game Controller

Sixteen buttons and four axes, and a program that asks what they're doing
right now. You'll open a controller, watch a stick lie about being centred,
and end with the one word that turns all of it into "left, right, or neither".

**Plug a controller in now if you have one.** If you haven't, keep going: every
*query* below answers zero, and every *open* reports a failure you can read.
That is exactly what your game gets on a machine with no pad, and handling it
is half of what this lesson teaches.

No window needed, unlike the graphics lessons. Everything happens at the
prompt.

`next` continues, `back` re-reads, `end-tutorial` stops. Type `next` to begin.

## Plug one in

    require pad.fs
    pads .

How many controllers are attached this second. You never call `sdl-open` —
reading a pad has nothing to do with having a window.

Open the first one:

    0 pad-open .

`0` means it worked. Anything else means it didn't, and nothing stopped: "no
controller" is an ordinary state of the world, not a failure. That `0`-is-good
convention is an **ior**, the same answer `snd-open` and `allocate` give.

    pad-name type

## Nothing arrives on its own

Hold down the bottom face button — under your right thumb — and while holding
it, type:

    pad-update  pad-south pad-held? .

`-1` while held, `0` otherwise. Now try it *without* `pad-update` a few times,
pressing and releasing between: the answer sticks.

A gamepad is not the keyboard. Nothing is delivered to you; the pad's state
sits in the driver until something fetches it, and `pad-update` is that fetch.
Every reading below is preceded by one. A game calls it once per frame, then
asks as many questions as it likes.

## Buttons are named by where they are

That bottom button is printed **A** on an Xbox pad, **B** on a Nintendo one,
**✕** on a PlayStation one. Any letter is a lie on two pads out of three, so
the name says where your thumb goes:

    pad-update  pad-north pad-held? .
    pad-update  pad-east  pad-held? .

`pad-south` `pad-east` `pad-west` `pad-north` are the face buttons, clockwise
from the bottom. The d-pad is `pad-up` `pad-down` `pad-left` `pad-right`; the
shoulders are `pad-lshoulder` and `pad-rshoulder`. Press a few and watch.

The d-pad is *buttons*, not a stick — four switches, each down or not.

## A stick is not a switch

Hands off the controller entirely, then read the left stick:

    pad-update  pad-leftx pad-axis .

With a controller attached you will not get `0` — you'll get something small
and untidy, `128` or `-129`, whatever your stick rests at. (No controller
gives a true `0`; read on, this is the problem the dead zone exists to fix.)
Read it twice more:

    pad-update  pad-leftx pad-axis .
    pad-update  pad-leftx pad-axis .

Probably the same number. It isn't noise, it's an *offset*: the stick's
mechanical centre and its electrical centre aren't the same place, and no two
pads are off by the same amount. (Worn sticks add drift on top.)

Push the stick fully left, then right, reading each time. The range is
`-32768` to `32767`, and `pad-lefty` is positive **downward**, matching screen
coordinates.

## The dead zone

That resting offset is why `pad-axis 0 <` is not a test for "pushed left". The
fix is to ignore everything near the middle — the *dead zone*, a `value` you
can read and change:

    pad-dead .

8000 by default, about a quarter of full travel. `pad-dir` applies it:

    pad-update  pad-leftx pad-dir .

`-1`, `0` or `1`. Hands off it's `0`, however untidy the raw number was. Push
the stick and it commits.

## No dead zone at all

Take the band away entirely, hands completely off the controller:

    0 to pad-dead
    pad-update  pad-leftx pad-dir .
    pad-update  pad-lefty pad-dir .

Never `0` — but read that as the rule, not as your stick. `abs n < pad-dead`
cannot be true when `pad-dead` is zero, so *every* reading is a direction:
your resting offset if a pad is attached, a true `0` if not.

That is what shipping the raw axis does to a game: the player sets the
controller down and their character walks into a wall forever.

## Why the default is a value

Put it back, and check:

    8000 to pad-dead
    pad-update  pad-leftx pad-dir .

`0` again.

Zero was the extreme, but any dead zone below your stick's resting offset does
the same thing, just less obviously. That is why 8000 is only a default: a worn
pad may genuinely need a *larger* one, and being able to type a new figure
mid-game is the whole reason this is a `value` and not a constant.

## One answer for the left hand

Most games only want to know which way the player is pushing:

    pad-update  pad-dx .
    pad-update  pad-dy .

`-1`, `0` or `1`, dead zone applied, **d-pad and left stick merged into one
answer**. Push the stick left, then press d-pad left — same `-1`. A player
using either control works with no extra code:

    \ pad-update
    \ pad-dx  player-x +!
    \ pad-dy  player-y +!

## When they disagree

One case had to be decided for you: d-pad left while the stick is pushed
right. **The d-pad wins.**

The tempting answer is to add them so they cancel. That would mean a worn
stick resting just past the dead zone could silently swallow every d-pad
press, with nothing on screen to explain why — a rule you can see beats a rule
that hides.

## Not every pad has every control

Some pads have no guide button, some have digital triggers, some have no right
stick. Ask before relying on one:

    pad-update
    pad-guide pad-has? .
    pad-rtrigger pad-hasaxis? .

Reading a control the pad doesn't have is not an error — you get `0` forever,
which looks exactly like a player pressing nothing.

Triggers are *axes*, not buttons: they rest at `0` and climb to `32767` rather
than swinging both ways.

    pad-update  pad-ltrigger pad-axis .

## When there is no controller

Try a slot with nothing in it — slot 3, the fourth one, almost certainly
empty:

    3 pad-open .
    pad-why type

Unless you have four or more controllers plugged in, slot 3 is empty, so you
got a non-zero number and a reason printed after it.

Don't read the number itself. It only says *whether* the open failed — test it
as zero or non-zero, never for a particular value — and `pad-why` says why.
Here that's "no controller at that index"; for a pad SDL has no mapping for
it's SDL's own complaint, and `pad-map` is the way in.

## Three ways to care

Because `0` means success, each way of reacting reads straight:

    3 pad-open drop
    : warn 3 pad-open if ." no pad" cr then ;   warn
    3 pad-open abort" no controller in slot 3"

Ignore it, handle it, or refuse to continue — and not one `0=` between them.
That is why this is an ior and not a flag: with true meaning success,
`abort"` would fire exactly when the pad opened *fine*. `sound.fs` shipped
that mistake once, which is why neither library now spells an opener with `?`.

## One place decides where input comes from

A game opens once and remembers what it got:

    0 value using-pad?
    0 pad-open drop  pad? to using-pad?
    using-pad? .

`drop` because here we don't care *why* it failed; `pad?` then asks the real
question — is a controller actually attached. After that, one word decides:

    \ : dx ( -- -1|0|1 )
    \     using-pad? if  pad-update pad-dx  else  key-dx  then ;

Everything else calls `dx` and never learns which it was.

A slot that cannot exist is still different: `9 pad-open` stops the program,
because that isn't a missing controller, it's a bug in your code.

## Pulling the plug

Controllers get unplugged mid-game. Ask whether one is really there:

    pad-update  pad? .

`pad?` is not "did I open one". A handle stays valid after its controller is
yanked out, so a game can notice and recover rather than crash — so only SDL
can say if anything is still on the other end.

If you have a pad plugged in, **unplug it now** and run that line again.

## Plugging it back in

Plug it back in, then:

    0 pad-open drop
    pad-update  pad? .

A returning controller is a *new* device as far as the system is concerned, so
it needs opening again — and a retry that finds nothing is just `0`, which is
why this is one line you can run every frame until it takes.

Plugging and unplugging are noticed only while the event queue is pumped, so a
program that never pumps never finds out. `pad-update` pumps; in a game with a
window, `sdl-show` does it for you.

## Two players

Four controllers can be open at once, in slots 0 to 3. Two `0`s means two pads
opened; a `1` is a slot with nothing in it:

    0 pad-open .  1 pad-open .

`pad` chooses which slot every question is about:

    0 pad  pad-update  pad-dx .
    1 pad  pad-update  pad-dx .

Select a slot, ask, select the other. One `pad-update` refreshes them all, so
one call per frame covers every player.

## Which pad is which player

    0 pad  pad-name type
    1 pad  pad-name type

Two identical controllers give two identical names — `pad-name` tells you the
*model*, not which one is which. Slots distinguish players, and the slot a pad
landed in is decided by the order they were plugged in.

    0 pad

## Tidy up

Closing is optional — leaving controllers open harms nothing — but it's what a
game's shutdown does:

    pad-closeall

Now the important part. Everything still works, it just answers `0`:

    pad-update  pad-dx .

That's the shape of the whole library, and why this lesson is useful to a
reader with no controller at all. No pad, a closed pad, or one pulled out
mid-frame — every question still answers. Nothing you write needs wrapping in
a check.

## Where to go next

- **A live readout**: `examples/gamepad.fs` puts every button and axis on
  screen at once. Load it and type `gamepad`.
- **Move something**: do the `Sprites` lesson, then drive its ship with
  `pad-dx` and `pad-dy` instead of the keyboard.
- **Edges, not state**: everything here asks "is it down *now*". For "was it
  just pressed", `ev-pad-down` and `ev-pad-up` arrive through `sdl-poll`
  alongside the keyboard events — see `help pad`.

`help pad` is the reference, and it covers controllers with a mode switch —
the first thing to check when a d-pad mysteriously does nothing.
