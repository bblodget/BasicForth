#! /usr/bin/env basicforth
\ BasicForth examples/gamepad.fs -- live game controller readout
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Shows every control on an attached controller as you move it, so you can
\ check that a pad is mapped the way you expect before wiring it into a game.
\
\   basicforth examples/gamepad.fs      then type:  gamepad
\   require gamepad.fs                  from a running session
\
\ Press a key on the KEYBOARD to stop. See `help pad` for the words used here.

require pad.fs

\ The buttons, in the order they are drawn, with a short label each.
create (btns)
    pad-south    c,  pad-east     c,  pad-west      c,  pad-north     c,
    pad-up       c,  pad-down     c,  pad-left      c,  pad-right     c,
    pad-lshoulder c, pad-rshoulder c, pad-lstick    c,  pad-rstick    c,
    pad-back     c,  pad-start    c,  pad-guide     c,
here (btns) - constant #btns

: (label) ( i -- c-addr u )
    case
        0 of s" S"  endof     1 of s" E"  endof
        2 of s" W"  endof     3 of s" N"  endof
        4 of s" up" endof     5 of s" dn" endof
        6 of s" lt" endof     7 of s" rt" endof
        8 of s" LB" endof     9 of s" RB" endof
       10 of s" LS" endof    11 of s" RS" endof
       12 of s" bk" endof    13 of s" st" endof
       14 of s" gd" endof
        s" ?" rot
    endcase ;

\ A button reads as its label when held, dots when not, and blanks when the
\ controller hasn't got it at all -- so a missing guide button looks different
\ from an unpressed one.
: (.btn) ( i -- )
    dup (btns) + c@                       ( i button )
    dup pad-has? 0= if  2drop ."     "  exit  then
    pad-held? if  (label) type space
    else  (label) nip 0 ?do ." ." loop space  then ;

: (.axis) ( axis -- )  pad-axis 7 .r ;

: (.bar) ( -- )
    ."  dx " pad-dx 2 .r  ."   dy " pad-dy 2 .r ;

: (frame) ( -- )
    pad-update
    0 0 at-xy
    ." pad: " pad-name type
    pad? if ."   (connected)   " else ."   (UNPLUGGED)   " then cr cr
    ." buttons  " #btns 0 do i (.btn) loop cr cr
    ." L stick " pad-leftx (.axis) pad-lefty (.axis)
    ."     R stick " pad-rightx (.axis) pad-righty (.axis) cr
    ." triggers" pad-ltrigger (.axis) pad-rtrigger (.axis) cr cr
    ." merged  " (.bar) ."      (d-pad wins over the stick)" cr cr
    ." press a keyboard key to stop" cr ;

: gamepad ( -- )
    0 pad-open if
        ." no controller found -- plug one in and try again" cr exit
    then
    page
    begin  (frame)  20 ms  key? until
    key drop
    pad-closeall
    page ." done" cr ;

\ Loaded, not launched: printing this instead of starting the loop keeps the
\ file usable from a pipe (and testable), the same way examples/dice.fs does.
." gamepad.fs loaded -- type  gamepad  to start the readout" cr
