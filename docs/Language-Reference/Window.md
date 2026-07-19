# Window — The SDL3 Display Backend

Puts the `graphics.fs` surface on screen: a desktop window, or the raw console
(KMSDRM) on a system with no desktop. It requires its own dependencies (the
FFI and the drawing surface), so one line loads everything:

    require sdl3.fs

A frame is: `sdl-frame` (surface now points at the window's pixels), draw with
the graphics words, `sdl-show` (present, paced by vsync). The texture is
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
    sdl-scale      ( -- n )          pixel size (value; set before sdl-open)
    sdl-frame      ( -- )            start a frame: surface -> window pixels
    sdl-show       ( -- )            present the frame (vsync)
    sdl-close      ( -- )            tear it all down
    sdl-poll       ( -- flag )       poll one event
    sdl-event-type ( -- u )          type of the polled event
    sdl-key        ( -- keycode )    keycode of a key event
    ev-quit ev-close ev-keydown ev-keyup   ( -- u )    event types
    key-esc key-space key-q key-left key-right key-up key-down ( -- u )

## sdl-open ( w h -- )
Open a window with a w-by-h pixel drawing surface. With `sdl-scale` above 1
the window is scale times larger than the surface — each logical pixel shows
as a chunky block. Aborts with the SDL error message on failure. The window
skips the window manager's liveness ping, so sitting at the REPL between
frames doesn't trigger "not responding" dialogs — draw interactively at
your own pace.

    \ 640 360 sdl-open
    \ 4 to sdl-scale  320 180 sdl-open   ( 1280x720 window )

## sdl-scale ( -- n )
The pixel size, a `value` (change with `to`) read by `sdl-open`: the window is
`w*scale` by `h*scale` while the drawing surface stays w by h. Retro chunky
pixels, and far fewer of them to draw — 320x180 at scale 4 fills a 1280x720
window with 1/16 the pixels. Scaling is done by the GPU (nearest-neighbor,
crisp and free). Default 1; sticky until you change it.

    \ 2 to sdl-scale  480 270 sdl-open   ( 960x540 window )

## sdl-frame ( -- )
Begin a frame: lock the window texture and point the drawing surface at its
pixels. The previous frame's contents are NOT preserved — draw everything,
starting with `clear`.

## sdl-show ( -- )
End the frame: present it, blocking until the display refresh (vsync), which
paces a game loop to the monitor. The surface is invalid until the next
`sdl-frame`.

## sdl-close ( -- )
Destroy the texture, renderer, and window and quit SDL. (If sound is open,
`snd-close` first — `sdl-close` shuts down all of SDL, audio included.)

## sdl-poll ( -- flag )
Poll one pending event into the event buffer; false when the queue is empty.
Drain the queue every frame:

    \ begin sdl-poll while ( inspect it ) repeat

## sdl-event-type ( -- u )
The type of the last polled event. Compare against `ev-quit`, `ev-close`,
`ev-keydown`, `ev-keyup`.

## sdl-key ( -- keycode )
The keycode of the last polled key event. Compare against the `key-*`
constants (`key-esc`, `key-left`, ...); printable keys are their ASCII code
(`char a` matches the A key).

## ev-quit ev-close ev-keydown ev-keyup ( -- u )
Event-type constants: application quit, window close button, key press
(includes auto-repeat), key release.

## key-esc key-space key-q key-left key-right key-up key-down ( -- u )
Keycode constants for the common game keys.

    \ sdl-key key-esc = if ... then

## See Also

- `help graphics` — the drawing words used between `sdl-frame` and `sdl-show`.
- `help sound` — SDL3 audio (`snd-open`, `tone`); one library, no extra setup.
- examples/bounce.fs — a complete game loop with events and sound.
- docs/Graphics.md — how the surface and the window fit together.
