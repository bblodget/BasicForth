\ BasicForth core.fs -- Forth-defined words
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded automatically at startup. These words build on the
\ ASM primitives in core.s.

\ Output helpers
: CR    10 emit ;
: SPACE 32 emit ;
: BL    32 ;

\ Boolean constants
: TRUE  -1 ;
: FALSE  0 ;

\ Arithmetic helpers
: MOD   /mod drop ;
: /     /mod nip ;

\ Stack helpers
: CELL+ 8 + ;
: CELLS 8 * ;

\ Comparison
: <>    = invert ;
: 0<>   0= invert ;
