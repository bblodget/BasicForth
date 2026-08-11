# SDL3 — Window, Events, and Input

Puts the `graphics.fs` surface on screen: a desktop window, or the raw console
(KMSDRM) on a system with no desktop. It requires its own dependencies (the
FFI and the drawing surface), so one line loads everything:

    require sdl3.fs

A frame is: `sdl-frame` (surface now points at the window's pixels), draw with
the graphics words, `sdl-show` (present, paced to `sdl-fps`). The texture is
write-only and its contents vanish at `sdl-show`, so every frame draws from
scratch — `clear` first.

    4 to sdl-scale  320 180 sdl-open
    begin
        sdl-frame  black clear  red 160 90 40 fill-circle  sdl-show
        begin sdl-poll while sdl-event-type ev-keydown = if ... then repeat
    ... until
    sdl-close

At a glance:

    sdl-open       ( w h -- )        open window + renderer + texture
    sdl-title      ( c-addr u -- )   name the window (before or after open)
    sdl-scale      ( -- n )          pixel size (value; set before sdl-open)
    sdl-fps        ( -- n )          frame-rate cap sdl-show holds (value)
    sdl-frame      ( -- )            start a frame: surface -> window pixels
    sdl-show       ( -- )            present the frame, paced to sdl-fps
    sdl-close      ( -- )            tear it all down
    sdl-poll       ( -- flag )       poll one event
    sdl-event-type ( -- u )          type of the polled event
    sdl-key        ( -- keycode )    keycode of a key event
    ev-quit ev-close ev-keydown ev-keyup   ( -- u )    event types
    key-enter key-esc key-space key-tab key-backspace ( -- u )
    key-q key-left key-right key-up key-down          ( -- u )

## sdl-open ( w h -- )
Open a window with a w-by-h pixel drawing surface. With `sdl-scale` above 1
the window is scale times larger than the surface — each logical pixel shows
as a chunky block. Aborts with the SDL error message on failure. The window
skips the window manager's liveness ping, so sitting at the REPL between
frames doesn't trigger "not responding" dialogs — draw interactively at
your own pace.

    \ 640 360 sdl-open
    \ 4 to sdl-scale  320 180 sdl-open   ( 1280x720 window )

## sdl-title ( c-addr u -- )
Name the window. Works **before or after** `sdl-open`: set it first and the
next window opens with that name, set it while a window is up and the title
bar changes immediately. Default `BasicForth`, and sticky like `sdl-scale` —
it survives `sdl-close`, so every window you open keeps the name until you
change it.

    \ s" Invaders" sdl-title  320 180 sdl-open
    \ s" Invaders - paused" sdl-title      ( retitles the live window )

Worth doing in anything that reopens its window (a module with an `on-start`
hook, say): every BasicForth window is called `BasicForth` otherwise, and two
of them on one desktop are impossible to tell apart. Names longer than 127
characters are truncated rather than refused — a title is cosmetic and
shouldn't abort a game's startup.

## sdl-scale ( -- n )
The pixel size, a `value` (change with `to`) read by `sdl-open`: the window is
`w*scale` by `h*scale` while the drawing surface stays w by h. Retro chunky
pixels, and far fewer of them to draw — 320x180 at scale 4 fills a 1280x720
window with 1/16 the pixels. Scaling is done by the GPU (nearest-neighbor,
crisp and free). Default 1; sticky until you change it.

    \ 2 to sdl-scale  480 270 sdl-open   ( 960x540 window )

## sdl-fps ( -- n )
The frame-rate cap `sdl-show` holds, a `value` (change with `to`). Default
60. A draw loop calling `sdl-show` each frame runs at this rate no matter how
fast the machine draws — `sdl-show` sleeps off the rest of each frame's time
budget (a frame that overran just doesn't sleep). Set it any time; `0`
disables pacing (the loop runs flat out, spinning the CPU).

    \ 120 to sdl-fps      ( match a 120 Hz panel )
    \ 30  to sdl-fps      ( half-rate )

Pacing is a millisecond timer, not vsync: `SDL_SetRenderVSync` blocks the
present under a compositing desktop (the window throttles to a crawl once it
settles) and doesn't exist on a bare-metal target, so a timer paces the same
everywhere. Under a compositor the final output is still vsync'd, so nothing
tears.

## sdl-frame ( -- )
Begin a frame: lock the window texture and point the drawing surface at its
pixels. The previous frame's contents are NOT preserved — draw everything,
starting with `clear`.

## sdl-show ( -- )
End the frame: present it and pace to `sdl-fps` (sleep off the rest of the
frame's time budget). The surface is invalid until the next `sdl-frame`.
Also pumps the window's event queue (without consuming it — `sdl-poll` sees
everything), so a pure drawing loop stays responsive to the desktop even if
it never reads events.

## sdl-close ( -- )
Destroy the texture, renderer, and window, and shut down SDL's video
subsystem — only video, so a sound stream opened by `sound.fs` keeps playing
and `snd-close` can be called whenever it suits you, in either order. Safe to
call when no window was opened, which is what makes it a one-liner in an
`on-stop` hook.

## sdl-poll ( -- flag )
Poll one pending event into the event buffer; false when the queue is empty.
Drain the queue every frame:

    \ begin sdl-poll while ( inspect it ) repeat

## sdl-event-type ( -- u )
The type of the last polled event. Compare against `ev-quit`, `ev-close`,
`ev-keydown`, `ev-keyup`.

## sdl-key ( -- keycode )
The keycode of the last polled key event. A printable key is its ASCII code,
so compare with `[char] a` directly; the `key-*` constants below name the ones
that have no character — `key-enter`, `key-esc`, the arrows.

## ev-quit ev-close ev-keydown ev-keyup ( -- u )
Event-type constants: application quit, window close button, key press
(includes auto-repeat), key release.

## key-backspace key-tab key-enter key-esc key-space key-q key-left key-right key-up key-down ( -- u )
Keycode constants for keys that have no character to name them by.

    \ sdl-key key-enter = if fire then

**A printable key needs no constant.** SDL's keycode for it *is* its ASCII
code, so `[char] w` names the W key directly and `key-q` is only `[char] q`
spelled the long way:

    \ sdl-key case
    \   [char] w of  up     endof
    \   [char] a of  left   endof
    \   key-enter of  fire  endof
    \ endcase

The arrows are the exception the list exists for: they have no ASCII value, so
SDL gives them keycodes in a high range (`$4000004f` and up) that you can only
reach by name or by number.

## sdl-width sdl-height ( -- n )
The size of the drawing surface in **logical** pixels — the `w h` you passed
to `sdl-open`, not the window's size on screen (that is these times
`sdl-scale`). Zero before the first `sdl-open`.

Every drawing word works in these coordinates, so this is what a game clamps
against rather than a number it wrote down:

    \ : clamp-x ( x -- x' )  0 max  sdl-width 1- min ;

## sdl-event ( -- addr )
The 128-byte buffer `sdl-poll` decodes into. `sdl-event-type` and `sdl-key`
read it for you; this is the raw address, for reading a field of an event
BasicForth does not wrap yet.

You need SDL's own struct layout to use it, and that layout is per event type
— which is why the offsets belong in a library rather than at a call site.
`pad.fs` is the worked example:

    \ : pad-ev-which  ( -- id )  sdl-event 16 + l@ ;

The buffer is reused, so read what you need before the next `sdl-poll`.

## sdl-error ( -- )
Print SDL's message for the last failed call and `abort`. This is what the
bindings here call when a window, renderer or texture cannot be created; it is
public so that your own `(ccall)` bindings can fail the same way, with SDL's
own text rather than a bare abort.

It never returns, so it is the tail of a failure branch, not something to test
after:

    \ ... 4 (SDL_CreateWindow) (ccall)  dup 0= if sdl-error then

## See Also

- `help graphics` — the drawing words used between `sdl-frame` and `sdl-show`.
- `help pad` — game controllers; their events arrive through `sdl-poll` too.
- `help sound` — SDL3 audio (`snd-open`, `tone`); one library, no extra setup.
- examples/bounce.fs — a complete game loop with events and sound.
- docs/Graphics.md — how the surface and the window fit together.
