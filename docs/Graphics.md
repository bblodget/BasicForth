# Graphics — Software 2D Surface

BasicForth draws with its own software 2D renderer over an abstract *surface*:
a flat 32-bpp pixel buffer described by a base address, width, height, and
stride (bytes per row). Drawing words operate on the current surface and don't
care where the pixels live — heap memory for tests, or real presentation memory
supplied by a display backend.

The display backend is **SDL3** (in progress): it opens a desktop window (or,
on a console-only system like the Pumpkin board, drives the display directly
via SDL's KMSDRM driver), hands the surface a pixel buffer, and presents frames
vsync'd. See the **Graphics Direction** design decision in
[Planning.md](Planning.md) for how this fits the project philosophy and the
path to GPU/3D via SDL_GPU.

> History: the first display backend (v0.8.0) talked to DRM/KMS directly via
> `ioctl` — no libraries at all. It worked (validated on real hardware), but a
> desktop compositor owns the display, so it could never show a window on a
> normal desktop; it was removed in the SDL pivot. It lives in git history
> (`src/forth/drm.fs`, `tools/drmoff.c` before the pivot).

The surface layer is loaded **on demand** (not at startup):

```
include graphics.fs   \ the drawing surface + 2D primitives
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

## Testing

The drawing words are verified by **reading the pixel buffer back** — point the
surface at a heap buffer, draw, and `l@` the bytes. No display needed; see the
Graphics section of `tests/test_integration.sh`.

## Scope and what's next

Current state: 32-bpp only; `pixel`/`fill-rect`/`clear`. Next, per the roadmap
in [Planning.md](Planning.md): the FFI (dynamic linking + `ccall`), the SDL3
backend (window/present/input) behind this same surface API, then more 2D
primitives (lines, circles, blit/sprites), text rendering, audio, and GPU/3D
via SDL_GPU.
