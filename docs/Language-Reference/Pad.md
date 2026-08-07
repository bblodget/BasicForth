# Pad — Game Controllers

Reads game controllers through SDL's *gamepad* layer. SDL ships a mapping
database covering hundreds of pads, plus native drivers for Xbox,
DualShock/DualSense, Switch Pro and Steam controllers, and normalises every
one of them to the same shape. An Xbox pad, a DualSense and a Switch Pro all
answer the same words. It pulls in its own dependencies:

    require pad.fs

    pads .              \ how many are plugged in
    0 pad-open          \ open the first one
    pad-name type       \ Logitech Gamepad F310

A game loop asks what is held right now, rather than waiting for events:

    begin
        sdl-frame  black clear
        pad-dx player +!            \ -1, 0 or 1 — d-pad or left stick
        pad-south pad-held? if fire then
        sdl-show
    pad-start pad-held? until

With no controller attached every query answers 0 or false, so the same code
runs keyboard-only on a machine with no pad.

At a glance:

    pads         ( -- n )          controllers currently connected
    pad-open     ( n -- )          open the nth connected one, and select it
    pad          ( n -- )          select which open slot queries act on
    pad?         ( -- flag )       is a controller attached to this slot
    pad-name     ( -- c-addr u )   its name ("" if none)
    pad-close    ( -- )            close the selected one
    pad-closeall ( -- )            close them all, stop the subsystem
    pad-update   ( -- )            refresh state + notice (un)plugs
    pad-held?    ( button -- flag ) is that button down now
    pad-has?     ( button -- flag ) does this pad even have that button
    pad-hasaxis? ( axis -- flag )
    pad-axis     ( axis -- n )     raw, -32768..32767
    pad-dir      ( axis -- -1|0|1 ) any axis, dead zone applied
    pad-dx       ( -- -1|0|1 )     left hand: d-pad or left stick
    pad-dy       ( -- -1|0|1 )     ...positive DOWNWARD
    pad-dead     ( -- n )          dead zone (value, default 8000)
    pad-map      ( c-addr u -- )   teach SDL an unknown controller
    #pads        ( -- n )          how many can be open at once (4)

    pad-south pad-east pad-west pad-north            ( -- u )  face buttons
    pad-up pad-down pad-left pad-right               ( -- u )  d-pad
    pad-lshoulder pad-rshoulder pad-lstick pad-rstick ( -- u )
    pad-back pad-start pad-guide                     ( -- u )
    pad-leftx pad-lefty pad-rightx pad-righty        ( -- u )  axes
    pad-ltrigger pad-rtrigger                        ( -- u )
    ev-pad-down ev-pad-up ev-pad-axis                ( -- u )  event types
    ev-pad-added ev-pad-removed                      ( -- u )
    pad-ev-which pad-ev-button pad-ev-axis pad-ev-value

`examples/gamepad.fs` is a live readout of every control — the quickest way to
check a new pad is mapped the way you expect.

## Buttons are named by position

The bottom face button is `pad-south` on every controller. It is printed **A**
on an Xbox pad, **B** on a Nintendo one and **✕** on a PlayStation one, so no
letter is true of all three — but the position is. `pad-east` is the right-hand
face button, `pad-west` the left, `pad-north` the top.

This is why the compass names are worth the moment of unfamiliarity: a game
written against `pad-south` behaves the way the player expects on hardware you
have never seen. SDL renamed these for the same reason.

## pads ( -- n )
How many controllers are connected right now. Starts SDL's gamepad subsystem
on first use; no window is needed, so a controller-only program works fine.
Recount whenever you like — it is a fresh query, not a cached number.

## pad-open ( n -- )
Open the nth *connected* controller (0 is the first) into slot n, and select
it. Aborts if the slot is out of range, if no controller is at that index, or
if SDL knows the device but has no gamepad mapping for it — see `pad-map`.

Re-opening a slot is fine, and is how you recover after a controller is
unplugged and pushed back in: whatever was in the slot is closed first, so its
handle is never stranded. The old one is closed only *after* the new open
succeeds, so a re-open that fails — the pad was pulled out again — leaves the
working controller in place rather than emptying the slot on the way past.

## pad ( n -- )
Choose which open slot the queries act on. Slots are numbered 0 to `#pads`-1.
This is what makes two players work:

    0 pad-open  1 pad-open          \ two controllers

    0 pad  pad-dx p1-walk
    1 pad  pad-dx p2-walk

Selecting an empty slot is not an error; the queries simply answer 0.

## pad? ( -- flag )
True when a controller is *actually attached* to the selected slot. Not quite
the same as "we opened one": a handle stays valid after its controller is
pulled out, so that a game can notice and recover rather than crash. `pad?`
asks SDL whether the device is still there, so it goes false on an unplug.

Worth checking at startup so a game can say "player 2: no controller" rather
than silently ignoring someone, and worth checking in a pause menu so it can
say "controller disconnected" mid-game.

It only goes false after something has run `pad-update` — see Hotplug below.

## pad-name ( -- c-addr u )
The controller's name, as SDL knows it. Zero length when nothing is open, so
it is always safe to `type`.

It names the *model*, not the individual: two identical controllers give the
same string. Slots are what tell players apart — don't try to identify a
player by name.

## pad-close ( -- ) / pad-closeall ( -- )
Close the selected controller, or all of them. `pad-closeall` also stops the
gamepad subsystem. Like `sdl-close`, it stops only what it started — a blanket
`SDL_Quit` would tear down the window `sdl3.fs` opened and the audio device
`sound.fs` is playing through.

## pad-update ( -- )
Refresh controller state, *and* notice controllers plugged in or pulled out.

A program with a window gets this for free — `sdl-show` pumps the event queue
every frame, and that is where SDL does its device detection. A program with no
window has nothing else pumping, so it must call `pad-update` itself: at the
top of its loop, or before asking `pads` (which calls it for you).

## Hotplug
SDL learns about controllers appearing and disappearing from the event queue,
not from the device list — so nothing notices an unplug until something pumps.
`pads` and `pad-update` both pump; `sdl-show` does too. Without one of them a
controller pulled out and pushed back in is never seen again.

Recovering is `pad-open` on the same slot:

    pad? 0= if                    \ after a pad-update
        pads 0> if 0 pad-open then
    then

A replugged controller gets a *new* instance id, so this really is a fresh
open — but `pad-open` closes the stale handle in that slot first, so nothing is
stranded. See `pad-open`.

`ev-pad-added` and `ev-pad-removed` arrive through `sdl-poll` if you would
rather react to the moment than poll for it. Neither opens or closes anything
by itself.

## pad-held? ( button -- flag )
True while that button is down. This is state, not an edge — it answers "is it
down now", so holding the button reads true every frame. For edges, watch
`ev-pad-down` / `ev-pad-up` through `sdl-poll`.

## pad-has? ( button -- flag ) / pad-hasaxis? ( axis -- flag )
Not every controller has every control: no guide button, no right stick,
digital-only triggers. Ask rather than reading a phantom 0, so a game can
offer a different binding instead of a control that never responds.

## pad-axis ( axis -- n )
The raw position, −32768 to 32767. Sticks swing both ways; triggers run 0 to
32767 (and on a pad with digital triggers, only ever 0 or 32767). **Y is
positive downward**, matching screen coordinates — pushing the stick *up*
gives a *negative* number.

Use this when you want real analog: a walk that gets faster the further the
stick goes, a trigger that is a throttle rather than a button.

## pad-dir ( axis -- -1|0|1 )
Any axis reduced to a direction, with the dead zone applied. The right stick
and the triggers have no d-pad to merge with, so they come through here:

    pad-rightx pad-dir      \ -1, 0 or 1 — aim left, centre, right

## pad-dx ( -- -1|0|1 ) / pad-dy ( -- -1|0|1 )
The left hand as one answer, whether the player uses the d-pad or the left
stick. This is what a grid game wants: `pad-dx` is −1 for left, 0 for centred,
1 for right; `pad-dy` is −1 for up, 1 for down (positive downward, like the
axis and like the screen).

**When the two disagree, the d-pad wins.** Hold d-pad left while pushing the
stick right and the answer is −1. A d-pad press is deliberate and
unambiguous, where a stick can rest off centre, drift with wear, or be
knocked. If the two were summed instead, a worn stick sitting at +9000 would
silently cancel the player's genuine presses — the worst possible failure, and
an invisible one. Both d-pad buttons down at once really is 0.

## pad-dead ( -- n )
How far a stick must leave centre before it counts as pushed. A stick at rest
does not read 0 — it jitters, and a worn one can sit some way off. The default
8000 is the traditional XInput figure, about a quarter of full travel. Exactly
`pad-dead` counts as pushed; anything nearer centre does not.

It is a value, so a tired controller can be tuned without editing anything:

    12000 to pad-dead       \ ignore more drift on a well-loved pad

Only `pad-dir`, `pad-dx` and `pad-dy` consult it; `pad-axis` is always raw.

## Events
Controller events arrive through `sdl-poll` alongside the keyboard ones, for
programs that want edges rather than held state — a menu, or a "press any
button to join" screen.

    begin sdl-poll while
        sdl-event-type ev-pad-down = if pad-ev-button . then
    repeat

`pad-ev-which` is the controller's instance id (all pad events), `pad-ev-button`
the button for `ev-pad-down`/`ev-pad-up`, `pad-ev-axis` and `pad-ev-value` the
axis and its new position for `ev-pad-axis`. `ev-pad-added` and
`ev-pad-removed` fire when a controller is plugged in or pulled out; neither
opens or closes anything by itself, so a game decides what to do about it.

## pad-map ( c-addr u -- )
Teach SDL a controller it does not recognise. An unknown device opens as a raw
joystick but not as a gamepad, and `pad-open` refuses it rather than guessing
at a layout. A mapping line — the community `gamecontrollerdb.txt` format —
fixes that:

    s" 030000005e040000e002000003090000,Xbox Wireless,a:b0,b:b1,..." pad-map
    0 pad-open

Aborts if the mapping string is malformed.

## Controllers with a mode switch
Some pads rearrange themselves in hardware. A Logitech F310 has a **MODE**
button that swaps the d-pad and the left stick: with its green light on, the
d-pad reports as full-deflection stick axes and the stick sends d-pad buttons.
SDL never sees the mode button — the controller's own firmware does it.

Code reading `pad-dx` and `pad-dy` is unaffected, because the merge already
watches both sources: a d-pad press arriving as ±32767 sails past the dead
zone and still gives ±1. Only code reading `pad-axis` directly notices, which
is one more reason to reach for the merged words in a game that only needs
directions.

## See also
- `help sdl3` — the window these controls usually drive, and the event loop
  gamepad events share.
- `help graphics` — drawing the game they play.
- `examples/gamepad.fs` — live readout of every control on an attached pad.
