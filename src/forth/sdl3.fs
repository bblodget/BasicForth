\ BasicForth sdl3.fs -- SDL3 display backend (window, present, events)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Presents the graphics.fs software 2D surface in a desktop window (or on the
\ raw console via SDL's KMSDRM driver), vsync'd. Pulls in its own
\ dependencies -- just:
\
\   require sdl3.fs
\
\ A frame goes:  sdl-frame  (lock texture, point the surface at its pixels)
\                ... draw with graphics.fs words ...
\                sdl-show   (unlock + present; vsync paces the loop)
\
\ The texture is streaming/write-only: after sdl-show its contents are gone,
\ so draw every frame from scratch (clear + draw). Events are polled:
\   begin sdl-poll while sdl-event-type ... repeat
\
\ Constants and struct offsets verified against the SDL3 headers by
\ tools/sdl3off.c (SDL 3.4.12).

require ffi.fs
require graphics.fs

\ --- library ---
\ The strings live in one binding word that runs at include time (bottom of
\ this section) so a re-run can rebind after the library state changes.
0 value (sdl3)
0 value (SDL_Init)            0 value (SDL_Quit)
0 value (SDL_GetError)
0 value (SDL_CreateWindow)    0 value (SDL_DestroyWindow)
0 value (SDL_CreateRenderer)  0 value (SDL_DestroyRenderer)
0 value (SDL_SetRenderVSync)
0 value (SDL_CreateTexture)   0 value (SDL_DestroyTexture)
0 value (SDL_LockTexture)     0 value (SDL_UnlockTexture)
0 value (SDL_RenderTexture)   0 value (SDL_RenderPresent)
0 value (SDL_PollEvent)       0 value (SDL_SetTextureScaleMode)
0 value (SDL_SetHint)         0 value (SDL_PumpEvents)

: (sdl-bind) ( -- )
    s" libSDL3.so.0" dlopen to (sdl3)
    (sdl3) s" SDL_Init"            dlsym to (SDL_Init)
    (sdl3) s" SDL_Quit"            dlsym to (SDL_Quit)
    (sdl3) s" SDL_GetError"        dlsym to (SDL_GetError)
    (sdl3) s" SDL_CreateWindow"    dlsym to (SDL_CreateWindow)
    (sdl3) s" SDL_DestroyWindow"   dlsym to (SDL_DestroyWindow)
    (sdl3) s" SDL_CreateRenderer"  dlsym to (SDL_CreateRenderer)
    (sdl3) s" SDL_DestroyRenderer" dlsym to (SDL_DestroyRenderer)
    (sdl3) s" SDL_SetRenderVSync"  dlsym to (SDL_SetRenderVSync)
    (sdl3) s" SDL_CreateTexture"   dlsym to (SDL_CreateTexture)
    (sdl3) s" SDL_DestroyTexture"  dlsym to (SDL_DestroyTexture)
    (sdl3) s" SDL_LockTexture"     dlsym to (SDL_LockTexture)
    (sdl3) s" SDL_UnlockTexture"   dlsym to (SDL_UnlockTexture)
    (sdl3) s" SDL_RenderTexture"   dlsym to (SDL_RenderTexture)
    (sdl3) s" SDL_RenderPresent"   dlsym to (SDL_RenderPresent)
    (sdl3) s" SDL_PollEvent"       dlsym to (SDL_PollEvent)
    (sdl3) s" SDL_SetTextureScaleMode" dlsym to (SDL_SetTextureScaleMode)
    (sdl3) s" SDL_SetHint"         dlsym to (SDL_SetHint)
    (sdl3) s" SDL_PumpEvents"      dlsym to (SDL_PumpEvents) ;
(sdl-bind)

\ --- constants (see tools/sdl3off.c) ---
$20       constant SDL_INIT_VIDEO
$16161804 constant XRGB8888          \ SDL_PIXELFORMAT_XRGB8888
1         constant TEX_STREAMING     \ SDL_TEXTUREACCESS_STREAMING
0         constant SCALE_NEAREST     \ SDL_SCALEMODE_NEAREST (crisp pixels)

$100 constant ev-quit                \ SDL_EVENT_QUIT
$210 constant ev-close               \ SDL_EVENT_WINDOW_CLOSE_REQUESTED
$300 constant ev-keydown             \ SDL_EVENT_KEY_DOWN
$301 constant ev-keyup               \ SDL_EVENT_KEY_UP

$1b       constant key-esc           \ SDLK_* keycodes
$20       constant key-space
$71       constant key-q
$40000050 constant key-left
$4000004f constant key-right
$40000052 constant key-up
$40000051 constant key-down

\ --- state ---
0 value sdl-win    0 value sdl-ren    0 value sdl-tex
0 value sdl-width  0 value sdl-height

\ Pixel size: set BEFORE sdl-open. The drawing surface stays w x h (logical
\ pixels) while the window is w*scale x h*scale -- each logical pixel shows
\ as a chunky scale x scale block (GPU-stretched, nearest-neighbor, free).
\ A 320x180 surface at scale 4 fills a 1280x720 window with 1/16 the pixels
\ to draw. Sticky across sdl-close; 1 = one-to-one (the default).
1 value sdl-scale
variable (sdl-px)     \ SDL_LockTexture out: pixel base (8 bytes)
variable (sdl-pitch)  \ SDL_LockTexture out: pitch (4 bytes; read with l@)
create sdl-event 128 allot   \ SDL_Event (type is a 32-bit int at offset 0)

\ C bool comes back in the low 8 bits of the return register; the rest is
\ undefined, so mask before testing.
: (c-bool) ( raw -- flag )  $FF and 0<> ;

\ SDL_SetHint needs two C strings at once, but >z has a single scratch
\ buffer -- so these live as static NUL-terminated strings in the dictionary.
create (z-wm-ping)  s" SDL_VIDEO_X11_NET_WM_PING" here over allot swap cmove 0 c,
create (z-off)      char 0 c,  0 c,

: sdl-error ( -- )  ." sdl: " 0 (SDL_GetError) (ccall) ztype cr abort ;

\ --- open / close ---
: sdl-open ( w h -- )
    to sdl-height  to sdl-width
    \ Skip the window manager's liveness ping (_NET_WM_PING): an idle REPL
    \ doesn't pump events, so the WM would pop "not responding" dialogs at a
    \ perfectly healthy prompt. Must be set before the window is created.
    (z-wm-ping) (z-off) 2 (SDL_SetHint) (ccall) drop
    SDL_INIT_VIDEO 1 (SDL_Init) (ccall) (c-bool) 0= if sdl-error then
    s" BasicForth" >z  sdl-width sdl-scale *  sdl-height sdl-scale *  0
    4 (SDL_CreateWindow) (ccall)  dup 0= if sdl-error then  to sdl-win
    sdl-win 0  2 (SDL_CreateRenderer) (ccall)
    dup 0= if sdl-error then  to sdl-ren
    sdl-ren 1  2 (SDL_SetRenderVSync) (ccall) drop   \ best effort (dummy driver has no vsync)
    sdl-ren XRGB8888 TEX_STREAMING sdl-width sdl-height
    5 (SDL_CreateTexture) (ccall)  dup 0= if sdl-error then  to sdl-tex
    \ default texture filtering is linear (blurry when scaled up)
    sdl-tex SCALE_NEAREST 2 (SDL_SetTextureScaleMode) (ccall) drop ;

: sdl-close ( -- )
    sdl-tex ?dup if 1 (SDL_DestroyTexture)  (ccall) drop  0 to sdl-tex then
    sdl-ren ?dup if 1 (SDL_DestroyRenderer) (ccall) drop  0 to sdl-ren then
    sdl-win ?dup if 1 (SDL_DestroyWindow)   (ccall) drop  0 to sdl-win then
    0 (SDL_Quit) (ccall) drop
    0 0 0 0 set-surface ;

\ --- frame cycle ---
: sdl-frame ( -- )
    sdl-tex 0 (sdl-px) (sdl-pitch)
    4 (SDL_LockTexture) (ccall) (c-bool) 0= if sdl-error then
    (sdl-px) @  sdl-width sdl-height  (sdl-pitch) l@  set-surface ;

: sdl-show ( -- )
    \ Pump the event queue every frame: a window whose events are never read
    \ gets frame-throttled (or declared hung) by a compositing desktop. Pump
    \ moves OS events into SDL's queue without consuming them — sdl-poll
    \ still sees everything. A pure draw loop needs no event code at all.
    0 (SDL_PumpEvents) (ccall) drop
    sdl-tex 1 (SDL_UnlockTexture) (ccall) drop
    sdl-ren sdl-tex 0 0  4 (SDL_RenderTexture) (ccall) drop
    sdl-ren 1 (SDL_RenderPresent) (ccall) drop
    0 0 0 0 set-surface ;   \ pixels invalid until the next sdl-frame

\ --- events ---
: sdl-poll ( -- flag )  sdl-event 1 (SDL_PollEvent) (ccall) (c-bool) ;
: sdl-event-type ( -- u )  sdl-event l@ ;
: sdl-key ( -- keycode )  sdl-event 28 + l@ ;   \ SDL_KeyboardEvent.key
