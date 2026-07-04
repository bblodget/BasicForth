\ BasicForth — Game Template (a starting point for your own game)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ The Chase tutorial's skeleton, generalized: a frame loop with every seam
\ deferred, and runnable stubs installed so `game` works out of the box —
\ a blank frame loop that exits on any key. Fill the seams with your game.
\
\ Usage:  basicforth game-template.fs
\         save mygame.fs      \ FIRST: save-as, so this template stays clean
\         game                \ blank loop; press any key to stop
\
\ Replace a seam live:    :noname ... ; is update
\ Bake it when settled:   : update ... ;  (or edit update)

120 value FRAME          \ ms per frame — tune live with: 90 to FRAME

: draw ( x y char -- )  >r at-xy r> emit ;

\ --- The seams: every frame game fills these eight ---
defer setup       \ ( -- )     clear screen, init state, first draw
defer finish      \ ( -- )     restore terminal, final message
defer input       \ ( -- )     read keys, set intent
defer erase       \ ( -- )     un-draw the moving actors
defer update      \ ( -- )     advance the world one step
defer render      \ ( -- )     draw actors in their new places
defer frame-wait  \ ( t0 -- )  hold the frame to FRAME ms
defer done?       \ ( -- f )   true when the game is over

\ --- The engine: the same loop as Chase, Snake, Pac-Man... ---
: play  begin  ms@  input erase update render  frame-wait  done?  until ;
: game  setup play finish ;

\ --- Runnable stubs — replace them one seam at a time ---
:noname  page cursor-off ;                          is setup
:noname  cursor-on  0 2 at-xy ." done." cr ;        is finish
:noname  ;                                          is input
:noname  ;                                          is erase
:noname  ;                                          is update
:noname  ;                                          is render
:noname  ms@ swap -  FRAME swap -  dup 0> if ms else drop then ;  is frame-wait
:noname  key? dup if key drop then ;                is done?
