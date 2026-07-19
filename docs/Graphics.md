# Graphics — Software 2D on an SDL3 Window

BasicForth draws with its own software 2D renderer over an abstract *surface*:
a flat 32-bpp pixel buffer described by a base address, width, height, and
stride (bytes per row). Drawing words operate on the current surface and don't
care where the pixels live — heap memory for tests, or the SDL3 streaming
texture that reaches the screen.

The display backend is **SDL3** (`sdl3.fs` over the FFI): a desktop window on
the laptop, or the display directly (SDL's KMSDRM driver) on a console-only
system like the Pumpkin board. Frames present vsync'd. See the **Graphics
Direction** design decision in [Planning.md](Planning.md) for how this fits
the project philosophy and the path to GPU/3D via SDL_GPU.

> History: the first display backend (v0.8.0) talked to DRM/KMS directly via
> `ioctl` — no libraries at all. It worked (validated on real hardware), but a
> desktop compositor owns the display, so it could never show a window on a
> normal desktop; it was removed in the SDL pivot. It lives in git history
> (`src/forth/drm.fs`, `tools/drmoff.c` before the pivot).

Everything loads **on demand** (not at startup), and each library `require`s
its own dependencies, so one line brings up the whole stack:

```
require sdl3.fs       \ pulls in graphics.fs (surface) and ffi.fs (FFI) itself
```

(`require` loads a file only if it isn't already loaded; `include` always
loads — see `help require`.)

## The surface (graphics.fs)

| Word | Stack | Meaning |
|------|-------|---------|
| `set-surface` | ( base w h stride -- ) | point drawing at a pixel buffer |
| `pixel` | ( color x y -- ) | plot one pixel (clipped) |
| `line` | ( color x0 y0 x1 y1 -- ) | line between two points (Bresenham) |
| `rect` | ( color x y w h -- ) | outline rectangle |
| `fill-rect` | ( color x y w h -- ) | filled rectangle (clipped) |
| `circle` | ( color cx cy r -- ) | outline circle (midpoint) |
| `fill-circle` | ( color cx cy r -- ) | filled circle |
| `clear` | ( color -- ) | fill the whole surface |
| `blit` | ( src x y w h -- ) | copy a sprite block onto the surface |
| `blit-key` | ( key src x y w h -- ) | sprite copy, `key`-colored pixels skipped |
| `grab` | ( dst x y w h -- ) | copy a surface region into a buffer |
| `pixel-addr` | ( x y -- addr ) | byte address of a pixel (no clip) |

Everything clips: endpoints, rectangles, circles, and sprites may hang off
any edge (or lie fully outside) and only the visible part draws. Horizontal
and vertical `line`s, `fill-rect` rows, and `fill-circle` spans all fill in
`fill32` bursts; the general `line`/`circle` paths go pixel-by-pixel.

A **sprite** is nothing but a packed 32-bpp pixel block: w×h 32-bit pixels
row after row (stride w×4), identified by its base address — `allocate` a
buffer and fill it, or draw with the shape words and `grab` it off the
surface. `blit-key` is the transparency mechanism: pick a color the art
doesn't use (magenta, classically) and pixels of that value are skipped,
so non-rectangular sprites sit over any background:

```
16 16 * 4 * allocate drop value ship        \ 16x16 sprite buffer
... fill ship with art, magenta where transparent ...
magenta ship 100 50 16 16 blit-key          \ draw it at (100,50)
```

Colors are packed `0x00RRGGBB`. Named colors: `black white red green blue yellow
cyan magenta`.

Pixels are 32-bit, so drawing uses the `l!`/`l@` (32-bit) memory primitives;
`w!`/`w@` (16-bit) and the byte words `c!`/`c@` are also available. `fill-rect`
clips the rectangle once (negative coordinates and overhang are fine), then
fills each visible row with a single `fill32` burst — a full-screen `clear` is
effectively instant.

| Primitive | Stack | Meaning |
|-----------|-------|---------|
| `fill32` | ( value addr count -- ) | store COUNT copies of the 32-bit VALUE from ADDR |

## The SDL3 backend (sdl3.fs)

| Word | Stack | Meaning |
|------|-------|---------|
| `sdl-open` | ( w h -- ) | window + renderer (vsync) + streaming texture |
| `sdl-frame` | ( -- ) | lock the texture, point the surface at its pixels |
| `sdl-show` | ( -- ) | unlock + present; blocks until the display refresh |
| `sdl-close` | ( -- ) | tear everything down |
| `sdl-poll` | ( -- flag ) | poll one event into the event buffer |
| `sdl-event-type` | ( -- u ) | type of the polled event |
| `sdl-key` | ( -- keycode ) | keycode of a polled key event |
| `sdl-scale` | ( -- n ) | pixel size (a `value`; set with `to` before `sdl-open`) |

**Pixel size** (`sdl-scale`, default 1): with `4 to sdl-scale`, `320 180
sdl-open` opens a 1280×720 window whose drawing surface is 320×180 — every
logical pixel shows as a crisp 4×4 block (GPU-stretched, nearest-neighbor,
free). That's the retro look, and 1/16 the pixels to draw per frame, which is
what keeps software rendering fast: prefer a small scaled surface over a big
1:1 one. All drawing words and events stay in logical coordinates.

Event-type constants: `ev-quit`, `ev-close`, `ev-keydown`, `ev-keyup`.
Keycodes: `key-esc key-space key-q key-left key-right key-up key-down`.
(Values verified against the SDL3 headers by `tools/sdl3off.c`.)

A frame goes: `sdl-frame` → draw with graphics.fs words → `sdl-show`. The
texture is streaming/**write-only**: after `sdl-show` its contents are gone,
so draw each frame from scratch (`clear` + draw — both are fast). `sdl-show`
returns after the display refresh (vsync), so the frame loop needs no timer.
The event loop is a poll:

```
begin sdl-poll while
    sdl-event-type case
        ev-quit    of ... endof
        ev-keydown of sdl-key ... endof
    endcase
repeat
```

## The demo (examples/bounce.fs)

```
include examples/bounce.fs    \ requires sdl3.fs + sound.fs itself
bounce                        \ ESC, q, or close the window to quit
```

A yellow ball (`fill-circle`) bouncing inside `rect` walls on a 320×180
surface shown 4× in a 1280×720 window, one step per display refresh.
`bounce-frames ( n -- )` runs a fixed number of frames and exits (for
automated tests).

## Testing

The drawing words are verified by **reading the pixel buffer back** — point
the surface at a heap buffer, draw, and `l@` the bytes. The SDL3 backend is
tested the same way using SDL's **dummy video driver** (`SDL_VIDEODRIVER=dummy`),
so no display is needed: open, lock, draw, read back, close. See the Graphics
and FFI sections of `tests/test_integration.sh`. The QEMU run skips the SDL
test (no aarch64 libSDL3 in the qemu sysroot); on the board, SDL3 must be in
the Pumpkian image (built from source — bookworm has no libsdl3 package).

## Troubleshooting

**`sdl-open` freezes and no window appears** (the prompt just hangs, no
error): almost certainly a wedged X input method. On X11 desktops,
`SDL_Init` connects to the input-method server named by `XMODIFIERS`
(usually ibus) using the XIM protocol; if `ibus-x11` is hung, that
handshake never completes and *every* SDL program freezes at startup —
this is environmental, not BasicForth (a minimal C SDL3 program hangs the
same way). Diagnose: `ps -o time -C ibus-x11` showing large CPU time is
the tell. Fix: `ibus restart` (or log out and in). Workaround without
touching ibus: start with the input method disabled —

```
XMODIFIERS=@im=none basicforth
```

To escape the frozen session: Ctrl+C won't work (raw mode), so
`pkill basicforth` from another terminal, then `reset` if the echo
looks odd.

**"Application is not responding" dialogs** (historical): the window
manager pings each window and SDL only answers while events are being
pumped (`sdl-poll`) — and an idle REPL pumps nothing, so the WM used to
declare a perfectly healthy prompt hung. `sdl-open` now disables the ping
(`SDL_VIDEO_X11_NET_WM_PING=0`) so interactive windows sit quietly at the
prompt. The flip side: a *genuinely* wedged program won't be offered a
Force Quit dialog either — `pkill basicforth` is the way out.

## Scope and what's next

Current state: 32-bpp only; pixels, lines, rectangles, circles, and
color-keyed sprites, presented via SDL3 with integer pixel scaling
(`sdl-scale`). Audio shipped separately (docs/Sound.md). Next, per the
roadmap in [Planning.md](Planning.md) and
[Graphics_Planning.md](Graphics_Planning.md): font/text rendering, then
GPU-accelerated 2D/3D via SDL_GPU (and the float support it needs).
