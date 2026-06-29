# Graphics — Software 2D over DRM/KMS

BasicForth draws to the screen by talking to the kernel's modern display
interface (DRM/KMS) directly through `ioctl`, with no `libdrm`, no X/Wayland, and
no GPU library. This is the first step of the graphics roadmap in
[Planning.md](Planning.md): direct, library-free display + software 2D, with a
backend-agnostic surface API that a Vulkan GPU backend can later sit behind.

Both layers are loaded **on demand** (not at startup):

```
include graphics.fs   \ the drawing surface + 2D primitives
include drm.fs        \ the DRM/KMS backend (needs graphics.fs)
```

## The surface (graphics.fs)

A *surface* is a flat 32-bpp pixel buffer described by a base address, width,
height, and stride (bytes per row). Drawing words operate on the current surface
and don't care where the pixels live — heap memory for tests, or a real DRM dumb
buffer for display.

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
`w!`/`w@` (16-bit) and the byte words `c!`/`c@` are also available.

## The DRM backend (drm.fs)

| Word | Meaning |
|------|---------|
| `drm-open` | open `/dev/dri/card1`, find the connected display + its mode, allocate a dumb framebuffer, map it, and point the surface at it |
| `drm-show` | become DRM master and scan the framebuffer out to the screen (SETCRTC); returns the result (0 ok) |
| `drm-close` | drop master and close the card |
| `drm-demo` | `drm-open` then draw a demo (blue background + rectangles) |

`drm-open` needs no special privilege — it works as an ordinary client (even
under a running desktop), which is what makes the drawing pipeline testable
anywhere. `drm-show` performs the mode-set, which requires **DRM master**: only
one program can be master at a time, and a running compositor (X/Wayland) holds
it. So `drm-show` only displays from a **text VT or a console-only system**.

### Seeing it (manual)

Under X11/Wayland, `drm-open`/drawing/read-back all work but nothing appears on
screen (the compositor owns the display). To actually see pixels:

1. Switch to a text VT: **Ctrl+Alt+F3** (log in), or run on the Pumpkin board
   booted to a console.
2. Run BasicForth so it can find `core.fs`, `graphics.fs`, `drm.fs`:
   ```
   BASICFORTH_PATH=src/forth ./src/arch/x86/basicforth
   ```
3. At the prompt:
   ```
   include graphics.fs   include drm.fs
   drm-demo  drm-show .      \ expect 0 (success); the screen shows the demo
   drm-close
   ```
   `drm-show` should print `0`. If it prints a negative number you are not DRM
   master (e.g. still under a compositor) — switch to a VT.

## Testing

The drawing words and the whole `drm-open` pipeline are verified by **reading the
buffer back** — no display required. `drm-open` maps a real dumb buffer (no
master needed), so the integration suite clears it blue and reads the pixel back.
That DRM test runs on a real DRM host and is skipped under QEMU (which cannot
emulate DRM ioctls) and where there is no card node. Only `drm-show`/SETCRTC
needs a VT/board and is the manual step above.

## Scope and what's next

This is step 1: 32-bpp only, single display, single buffer (no double-buffering
yet), `pixel`/`fill-rect`/`clear`. Deferred: page-flip/double-buffering (no
tearing), lines/circles/blit/sprites, text rendering, non-32-bpp formats, and —
the big one — the Vulkan GPU/3D backend behind this same surface API. See
[Planning.md](Planning.md).
