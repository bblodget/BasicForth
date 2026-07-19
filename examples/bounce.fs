\ BasicForth — Bouncing ball in an SDL window
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ The desktop-window graphics demo: a yellow ball bouncing inside a walled
\ court, one frame per display refresh (vsync), with a blip on every wall
\ hit. Retro chunky pixels: the surface is 320x180 logical pixels shown 4x
\ (sdl-scale) in a 1280x720 window. ESC, q, or closing the window quits.
\
\ Usage: include bounce.fs   (dependencies load themselves)
\        bounce
\ or from a shell:  basicforth bounce.fs  then type bounce

require sdl3.fs
require sound.fs

320 constant b-w          \ logical surface size (window is 4x)
180 constant b-h
10  constant b-r          \ ball radius
b-r 2* constant b-size    \ ball bounding-box side

variable b-x   variable b-y
variable b-dx  variable b-dy
variable b-done

: b-blip ( -- )  660 30 tone ;          \ no-op if the audio device isn't open

\ Advance one axis: pos += d, bouncing off 0 and max-b-size.
: (b-axis) ( d-var pos-var max -- )
    >r  dup @  2 pick @ +               ( d-var pos-var new ) ( r: max )
    dup 0 <  over b-size + r> > or if   \ off either edge: flip d, stay put
        drop drop  dup @ negate swap !  b-blip
    else
        swap !  drop
    then ;

: b-step ( -- )
    b-dx b-x b-w (b-axis)
    b-dy b-y b-h (b-axis) ;

: b-frame ( -- )
    sdl-frame
    $102040 clear                        \ dark blue background
    white  0 0 b-w b-h rect              \ court walls
    yellow  b-x @ b-r +  b-y @ b-r +  b-r fill-circle
    sdl-show ;

: b-events ( -- )
    begin sdl-poll while
        sdl-event-type case
            ev-quit    of  true b-done !  endof
            ev-close   of  true b-done !  endof
            ev-keydown of  sdl-key dup key-esc = swap key-q = or
                           if true b-done ! then  endof
        endcase
    repeat ;

: bounce ( -- )
    4 to sdl-scale  b-w b-h sdl-open
    snd-open? drop                     \ no audio -> blips are no-ops
    40 b-x !  30 b-y !  4 b-dx !  3 b-dy !
    false b-done !
    begin  b-frame  b-events  b-step  b-done @  until
    snd-close  sdl-close ;   \ sound first: sdl-close's SDL_Quit ends audio too

\ Fixed-frame variant for automated tests (no events, then clean close).
: bounce-frames ( n -- )
    4 to sdl-scale  b-w b-h sdl-open
    40 b-x !  30 b-y !  4 b-dx !  3 b-dy !
    0 ?do  b-frame  b-step  loop
    sdl-close ;
