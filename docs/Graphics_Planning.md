# Graphics Planning — GPU Acceleration and the Float Boundary

Forward-looking design notes for the next stage of BasicForth graphics: moving
from the software 2D surface (shipped — see [Graphics.md](Graphics.md)) to
**GPU-accelerated 2D and 3D**, and the floating-point support that crossing the
GPU boundary requires.

This document captures decisions and rationale so the work can be planned and
staged. It complements:

- [Planning.md](Planning.md) — "Graphics Direction" design decision (the
  dependency-boundary philosophy this builds on)
- [Graphics.md](Graphics.md) — the current software surface + SDL3 present layer
- [FFI.md](FFI.md) — `dlopen`/`dlsym`/`ccall`, the mechanism the GPU rides on

## Goal

A core aim of BasicForth is to give the user **the full power of the machine**,
and on a modern machine that emphatically includes the GPU — for both 2D and 3D
acceleration. The end state we are designing toward: a beginner writes a 2D
shooter in a screen of code; an intermediate user flies a camera around a 3D
scene — both running on the real GPU, both pokeable live at the REPL. No other
environment we know of pairs BASIC-level immediacy with explicit modern-GPU
access; that is the distinctive thing to build.

## Library decision — SDL3 (not raylib), and why

The question that prompted this doc: now that SDL3 is the present layer, would
**raylib** be a better fit for a project that wants shapes, text, sprites,
spritesheets, and rotations for game-making?

The honest framing is **three** options, not two:

1. **Software renderer (today).** `graphics.fs` owns the pixels; SDL only
   presents them. Integer FFI only. We write every primitive (rotated blit,
   bitmap font) ourselves in asm/Forth.
2. **SDL3's own renderer API.** `SDL_RenderGeometry` (triangles),
   `SDL_RenderTextureRotated` (textured quads with rotation/scale/flip),
   `SDL_RenderLine`/`FillRect`. GPU-accelerated 2D from the library we already
   ship. No text (add a bitmap font or `SDL_ttf`).
3. **raylib.** The richest batteries-included 2D/3D API: shapes, a built-in
   font (`DrawText` with zero setup), `DrawTexturePro` (atlas + rotation +
   origin + tint in one call), immediate-mode 3D.

raylib is a genuinely nice library, and the instinct that it would save us
writing drawing routines is correct on its face. But it is the wrong fit **for
this project**, for reasons that are specific to how BasicForth is built:

- **We use a graphics library as a present/input boundary, not a renderer.**
  The architecture (Planning.md "backend-agnostic surface API") is *we own the
  pixels*. raylib's whole value is *being* the renderer; adopting it means
  importing a large library to use ~5% of it while its headline features — the
  drawing API we deliberately chose to write ourselves — go unused.
- **raylib fights our hand-rolled FFI; SDL cooperates with it.** raylib passes
  structs **by value** everywhere (`Color`, `Vector2`, `Rectangle`,
  `Texture2D`). `DrawTexturePro` alone passes ~4 by-value structs plus a float.
  Our `ccall` marshals integer/pointer args only; by-value struct decomposition
  is classified into integer *and* vector registers by SysV/AAPCS rules that
  differ between x86-64 and ARM64 — exactly the marshalling we chose SDL to
  avoid. SDL keeps everything as opaque pointers and ints (`SDL_FRect*`, not
  `SDL_FRect`), which our FFI already handles.
- **Console/appliance mode.** SDL selects its video driver at **runtime** — the
  same binary shows a window on the desktop or takes the raw console via
  KMSDRM (the boot-to-Forth appliance model, Phase 7). raylib's DRM path is a
  **compile-time** build variant (GLFW vs. DRM/EGL), so we'd lose that runtime
  flexibility and maintain two builds.
- **Audio comes free.** SDL3 covers audio with no new dependency; Planning.md
  already banks on this.
- **Philosophy fit.** Our dependency boundary rule accepts a library only where
  a capability is sealed above/below the kernel (compositor, audio, GPU blobs).
  SDL sits exactly on that boundary and stays out of our renderer. raylib
  crosses it.

**Decision: stay on SDL3, and grow *upward* into its renderer and GPU APIs.**
The one idea worth borrowing from raylib is its **function-based input polling**
(`IsKeyDown`-style) — friendlier than `SDL_Event` offset-poking; we can wrap our
own `key-down? ( keycode -- flag )` over `SDL_GetKeyboardState` without leaving
SDL.

### 2D acceleration path

For accelerated 2D specifically, **SDL3's renderer (option 2) gets ~90% of what
raylib offers** — triangles, textured sprites, rotation, scale, flip — for a
much cheaper FFI upgrade (floats only; structs stay pointers), from the library
we already ship. What it lacks versus raylib is text/fonts and circles, which we
add ourselves (bitmap font; circles from triangles). This is the pragmatic 2D
target; full GPU 3D (below) is the larger effort behind the same surface idea.

## The load-bearing insight — the GPU float boundary is *memory buffers*, not arguments

The natural fear is: "the GPU means floats, our stack is 64-bit integers, so we
need a full floating-point system *before* we can touch the GPU." For an
**immediate-mode** API (raylib's `DrawLine(float, float, …)`) that would be
true — floats go in registers on every call. But **SDL_GPU (and Vulkan beneath
it) is buffer/struct-based**, which is a completely different boundary:

- **Vertex data** → fill an array of `float32` *in memory*, then
  `SDL_UploadToGPUBuffer(copypass, source*, dest*, cycle)` — **pointers and
  ints**. Today's `ccall` already does this.
- **Uniforms / matrices** → `SDL_PushGPUVertexUniformData(cmdbuf, slot, data*,
  length)` — a **pointer + int**. A 4×4 model-view-projection matrix is 64 bytes
  of float handed over by address.
- **Pipeline / render setup** → fill big `SDL_GPU*CreateInfo` structs in memory,
  pass a **pointer** — the same skill as our ioctl structs.

So the floats live in buffers *we* build; the GPU reads them by address. The
number of SDL_GPU functions that take a bare `float`/`double` in a register is
small (viewport, blend constants — mostly structs anyway). **We can draw a
spinning 3D triangle with the integer `ccall` we have today.** The only
genuinely new requirement for a first frame is *producing the float byte
patterns* to put in those buffers — and for static geometry those can be baked
as literals.

## Three separable problems (don't conflate them)

| # | Problem | What it takes | When it's needed |
|---|---------|---------------|------------------|
| **A** | **Float *arguments* across the ABI** — a C function taking `float` in XMM0/V0 | Extend `ccall` to route args by type into the vector registers | Only for the *few* GPU calls that take scalar floats; **not** for the buffer/struct path |
| **B** | **Float *bytes* in memory** — vertex arrays, matrices, uniforms | A way to turn a number into an IEEE-754 bit pattern and store it | Needed for the **first** triangle |
| **C** | **Float *arithmetic* in Forth** — user writes `1.5 2.0 f* fsin` | A floating-point stack + vocabulary | Needed when vertices/matrices are **computed at runtime** (rotation, physics) |

The happy consequence: **A is mostly optional, B has a cheap first version, and
C is the big lift that can be staged.** A static cube's 8 corners are 24 constant
floats — bake the bit patterns as literals (problem B, trivial) and render before
writing a single float-math word. Rotation is what forces C.

### Problem A — float arguments in `ccall`

`forth_ccall` (see `src/arch/x86/core.s`, `src/arch/arm64/core.s`) today loads
integer args into `RDI…R9` / `X0…X7`, sets `AL = 0` ("no vector args"), and
returns `RAX` / `X0`. Integer-only. The ABI reality for floats:

- **x86-64 SysV** — integer/pointer args in `RDI…R9`; float/double args in
  **`XMM0–XMM7`**, counted *independently*; `AL` = number of XMM regs used (for
  varargs); float return in `XMM0`.
- **ARM64 AAPCS** — integer/pointer in `X0–X7`; float/double in **`V0–V7`**,
  counted independently; return in `V0`.

The catch: an integer *count* is no longer enough — `ccall` must know each arg's
*type* to route it to the next integer register or the next FP register. So a
float-aware FFI needs a small **signature** (a per-arg type mask), not just
`nargs`; e.g. `(ccall-typed) ( args… sig fnptr -- ret )` where `sig` encodes
which args are float and whether the return is float/double. Bounded and
well-understood; build it only when a buffer-free call forces it.

### Problem B — float bytes in memory

Before any float math exists, get IEEE-754 patterns into memory by either:

- teaching the interpreter to recognize a float literal (`3.14e0`, `1e9`) and
  store the encoded pattern, or
- storing the raw pattern directly (`$40490FDB` is `3.14159f`) for static data.

Static geometry needs nothing more than this.

### Problem C — floating-point arithmetic

The stack question — **how do floats/doubles fit a 64-bit integer stack?** Three
options, with the decision:

1. **Separate floating-point stack (Forth-2012 standard) — CHOSEN.** Floats live
   on their own stack with their own words (`f+ f* fsqrt fsin f@ f! sf! s>f
   f>s`) and the standard notation `( F: r1 r2 -- r3 )`. The integer data stack
   and all existing code stay **completely untouched**. It is what every Forth
   programmer expects, and it maps cleanly onto our design: implement the FP
   stack exactly like the data stack — a dedicated memory region with a pointer,
   **TOS-in-memory** (matching the "pure memory stack, no TOS-in-register"
   choice). The arithmetic uses the hardware FP/SIMD registers as *scratch*
   (load two doubles into `xmm0/xmm1` or `d0/d1`, `addsd`/`fadd`, store back), so
   no register needs to be permanently reserved and the existing allocation
   (`R15/R13/R12`, `X19/X21/X22`) is unaffected.
2. **Floats on the data stack (one 64-bit cell = one double).** Simpler, but
   `dup`/`swap` no longer know a cell's type, stack comments stop telling the
   truth, and mixed int/float code becomes error-prone. Fights Forth idiom.
3. **Fixed-point on the integer stack (e.g. 16.16).** No FPU, deterministic,
   great for 2D gameplay logic — but the GPU wants real IEEE floats in its
   buffers, so this is a *supplement* (fast gameplay math) not the answer to the
   GPU boundary.

Two details that matter at the GPU boundary:

- **Double internally, float32 at the buffer.** Forth FP is conventionally
  double precision, but GPU vertex/uniform data is almost always `float32`.
  Compute in double on the FP stack, then narrow when packing into a GPU
  buffer — one instruction (`cvtsd2ss` on x86, `fcvt s,d` on ARM64). Hence a
  `sf!` ("store single float") word alongside `f!`.
- **Math library is real work.** `perspective`/`look-at`/`mat4*`/quaternions are
  a vocabulary we write and test in Forth on top of the FP stack. It is the bulk
  of the 3D effort and what makes 3D pleasant to use.

## Staged roadmap

Each step is independently shippable and testable, and the scary "support floats
and doubles" work (step 2) is **decoupled from first GPU contact** (step 1) — we
learn whether the SDL_GPU binding is sound before investing in the FP system.

1. **First triangle — integer FFI only.** Static vertex bytes (problem B, as
   literals), all SDL_GPU setup through the current pointer/int `ccall`. Proves
   the pipeline end-to-end with **zero** new float infrastructure. Highest
   information per unit of work; internally a static triangle on screen.
2. **Separate FP stack + core arithmetic (problem C).** `f+ f- f* f/ fsqrt fsin
   fcos f@ f! sf! s>f f>s`, float-literal parsing. Now vertices and matrices are
   *computed* — real rotation, projection, animation become writable.
3. **Typed float `ccall` (problem A).** Only when a GPU (or other lib) call takes
   scalar floats / returns a float and cannot be routed through a buffer.
4. **Forth-level math + game vocabulary.** `mat4*`, `perspective`, `look-at`,
   `rotate-y`, vector words — built *in Forth* on step 2, so they stay
   `see`-able and hackable. The user-facing `game.fs` / `gl3d.fs` layer.

Accelerated 2D (SDL renderer, option 2 above) slots in alongside: it needs
step 2's floats (for `SDL_FRect` coordinates and rotation angles) but not the
full 3D math of step 4, so it can land as soon as the FP stack exists.

## What the user gets — `game.fs` / `gl3d.fs`

The user never sees the FFI, the FP stack, or command buffers — that is what we
build. They see a small, friendly vocabulary, written *in Forth* on top of the
lower layers (so `see draw-mesh` reads the source). Three layers, user lives at
the top:

```
game.fs / gl3d.fs   -- sprite, draw-mesh, look-at, draw-text   <- USER
  fp stack + f* fsin ...   -- the math that makes transforms possible
    ccall + SDL_GPU          -- the boundary we engineered
```

### 2D — a sprite with rotation, text, input, game loop

```forth
include game.fs                       \ window, sprites, text, sound, input

640 360 game-window
s" ship.png" load-sprite value ship   \ PNG -> GPU texture

variable ship-x   variable ship-y
fvariable heading                     \ radians, on the float stack

: draw-ship ( -- )
    ship  ship-x @  ship-y @   heading f@  1.0e  draw-sprite-ex ;
    \                          F: angle  scale

: play ( -- )
    begin
        poll-input
        key-left?  if heading f@ 0.1e f-  heading f! then
        key-right? if heading f@ 0.1e f+  heading f! then
        frame                         \ begin GPU frame
            black clear
            draw-ship
            s" SCORE 0"  10 10  draw-text
        show                          \ present, vsync-paced
    key-esc? until ;
play
```

Exercises sprite loading, spritesheet sub-rects (`draw-sprite-ex` takes a source
rect), rotation/scale via the FP stack, text, keyboard input, and a vsync game
loop — all GPU-accelerated, so hundreds or thousands of sprites stay smooth.

### 3D — a spinning cube (the FP stack earns its keep)

```forth
include gl3d.fs

640 360 game-window
s" cube.mesh" load-mesh value cube

fvariable spin

: draw-scene ( -- )
    frame
        black  clear-depth            \ color + depth buffer
        60.0e aspect 0.1e 100.0e  perspective  set-projection
        \   F: fov  (aspect) near far
        0e 0e 5e   0e 0e 0e   0e 1e 0e   look-at  set-view
        \   eye        target     up
        spin f@   rotate-y   set-model
        cube draw-mesh
    show
    spin f@  0.02e f+  spin f! ;       \ advance the angle

: run  begin draw-scene  key-esc? until ;
run
```

`perspective`, `look-at`, `rotate-y` are Forth words over `f* fsin fcos` and a
`mat4*` — impossible without step 2, the reason the FP stack exists.

### Capability summary

| Capability | 2D | 3D |
|------------|----|----|
| Window + vsync loop | yes | yes |
| Input (keyboard/mouse/gamepad) | yes | yes |
| Shapes (tri/rect/line/circle/poly) | yes | — |
| Sprites + spritesheets + rotate/scale/tint | yes | (billboards) |
| Text / fonts | yes | yes (HUD) |
| Vectors & matrices, transforms | (for rotation) | core |
| Camera (perspective, look-at, move/turn) | — | yes |
| Meshes: vertices/indices -> GPU, draw | (batched quads) | yes |
| Depth buffer, textured/lit surfaces | — | yes |
| Sound | yes | yes |

### REPL immediacy — the uniquely-ours part

Because it is Forth at a live prompt, the user can poke a *running* game — the
"boot up and start coding" promise applied to hardware 3D:

```forth
5.0e camera-z f!        \ pull the camera back while it renders
: draw-ship  ...  ;      \ redefine a word; next frame uses the new one
spin f@ f.               \ inspect the current angle
```

Change geometry, redefine `draw-scene`, tweak a color, read a variable — no
recompile, no restart. Rare, and the thing that makes BasicForth *feel* like a
BASIC rather than a toolchain.

## Honest boundaries (so the plan doesn't oversell)

- **Shaders are SPIR-V, compiled offline.** Users won't write shaders in Forth.
  Ship a *small set of built-in shaders* (flat, textured, simple-lit) and expose
  their **uniforms** as Forth words (`set-light`, `tint`). "Write a custom
  shader" is an advanced escape hatch, not the default.
- **Asset decoding needs a decoder.** PNG/mesh loading means either a tiny FFI to
  `stb_image` or dead-simple native formats we define. Decide early which.
- **Performance is per-call-bound, not GPU-bound.** STC Forth issuing one
  `draw-sprite` per object is fine for hundreds–low thousands; for
  tens-of-thousands, expose a `batch` word that fills one vertex buffer. Good
  default plus an escape hatch.
- **Raw Vulkan stays possible.** SDL_GPU is the chosen 3D backend, but the same
  FFI can reach raw Vulkan if SDL_GPU ever proves limiting (Planning.md).

## Open questions

- Float-literal syntax and the recognizer: adopt Forth-2012 (`1.0e0`, `1e9`)
  exactly, or a friendlier BASIC-ish form (`1.0`, `3.14`)? The standard form
  disambiguates from integers cleanly; a bare `3.14` needs the recognizer to
  distinguish it from `3 . 14`-style tokens and from hex.
- FP stack depth, guard-page strategy, and whether it shares the data stack's
  underflow/overflow machinery.
- Asset pipeline: FFI `stb_image` vs. a minimal native sprite/mesh format.
- Where the 2D accelerated renderer (SDL renderer API) and the software surface
  coexist: does the software surface remain the default 2D path (with GPU 2D as
  opt-in), or does GPU 2D become primary once it lands?
- Signature encoding for `(ccall-typed)` and whether it supersedes the current
  integer `ccall` or sits beside it.
