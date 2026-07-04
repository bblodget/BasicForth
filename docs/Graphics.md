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

Everything loads **on demand** (not at startup), in this order:

```
include graphics.fs   \ the drawing surface + 2D primitives
include ffi.fs        \ dlopen/dlsym/ccall (see docs/FFI.md)
include sdl3.fs       \ the SDL3 window/present/event backend
```

## The surface (graphics.fs)

| Word | Stack | Meaning |
|------|-------|---------|
| `set-surface` | ( base w h stride -- ) | point drawing at a pixel buffer |
| `pixel` | ( color x y -- ) | plot one pixel (clipped) |
| `fill-rect` | ( color x y w h -- ) | filled rectangle (clipped) |
| `clear` | ( color -- ) | fill the whole surface |
| `pixel-addr` | ( x y -- addr ) | byte address of a pixel (no clip) |

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
include graphics.fs  include ffi.fs  include sdl3.fs
include examples/bounce.fs
bounce                \ ESC, q, or close the window to quit
```

A yellow square bouncing in a 640×360 window, one step per display refresh.
`bounce-frames ( n -- )` runs a fixed number of frames and exits (used by the
automated test).

## Testing

The drawing words are verified by **reading the pixel buffer back** — point
the surface at a heap buffer, draw, and `l@` the bytes. The SDL3 backend is
tested the same way using SDL's **dummy video driver** (`SDL_VIDEODRIVER=dummy`),
so no display is needed: open, lock, draw, read back, close. See the Graphics
and FFI sections of `tests/test_integration.sh`. The QEMU run skips the SDL
test (no aarch64 libSDL3 in the qemu sysroot); on the board, SDL3 must be in
the Pumpkian image (built from source — bookworm has no libsdl3 package).

## Scope and what's next

Current state: 32-bpp only; `pixel`/`fill-rect`/`clear` presented via SDL3.
Next, per the roadmap in [Planning.md](Planning.md): more 2D primitives
(lines, circles, blit/sprites), text rendering, audio via SDL3, and GPU/3D
via SDL_GPU.
