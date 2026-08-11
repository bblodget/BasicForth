\ BasicForth pad.fs -- game controllers (SDL3 gamepad API)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Reads game controllers through SDL's *gamepad* layer rather than its raw
\ joystick layer. SDL ships a mapping database covering hundreds of pads (and
\ native drivers for Xbox, DualShock/DualSense, Switch Pro, Steam), and
\ normalises every one of them to the same shape: four face buttons, a d-pad,
\ two sticks, two triggers, two shoulders, start/back/guide. An Xbox pad, a
\ DualSense and a Switch Pro all answer the same words.
\
\   require pad.fs
\   pads .                     \ how many are plugged in
\   0 pad-open drop            \ open the first one (drop the ior)
\   begin  pad-update  pad-dx . pad-dy . cr  key? until
\
\ Buttons are named by POSITION, not by letter: the bottom face button is
\ pad-south on every controller, where it is printed A on an Xbox pad, B on a
\ Nintendo one and X on a PlayStation one. Naming it pad-a would be a lie on
\ two pads out of three.
\
\ Up to #pads controllers can be open at once, in slots 0 to #pads-1 (four
\ slots as shipped). Queries act on the SELECTED slot, so a two-player loop
\ reads:
\
\   0 pad  pad-dx p1-move
\   1 pad  pad-dx p2-move
\
\ With no pad open every query answers 0 or false rather than failing, so a
\ game runs keyboard-only on a machine with no controller attached. pad-open
\ returns an IOR (0 = opened) rather than aborting, because nothing plugged in
\ is a normal state of the world:
\
\   0 pad-open drop  pad? to using-pad?
\
\ Constants and struct offsets verified against the SDL3 headers by
\ tools/sdl3off.c (SDL 3.4.12).

require sdl3.fs

\ --- library ---
\ Bound in one word that runs at include time, like sdl3.fs, so a re-run can
\ rebind. The library handle (sdl3) and the (ccall)/(c-bool)/sdl-error helpers
\ all come from sdl3.fs -- this file only adds the gamepad entry points.
0 value (SDL_GetGamepads)     0 value (SDL_OpenGamepad)
0 value (SDL_CloseGamepad)    0 value (SDL_GetGamepadName)
0 value (SDL_GetGamepadButton)  0 value (SDL_GetGamepadAxis)
0 value (SDL_GamepadHasButton)  0 value (SDL_GamepadHasAxis)
0 value (SDL_UpdateGamepads)  0 value (SDL_AddGamepadMapping)
0 value (SDL_GamepadConnected)  0 value (SDL_WasInit)
0 value (SDL_free)          0 value (SDL_ClearError)

: (pad-bind) ( -- )
    (sdl3) s" SDL_GetGamepads"      dlsym to (SDL_GetGamepads)
    (sdl3) s" SDL_OpenGamepad"      dlsym to (SDL_OpenGamepad)
    (sdl3) s" SDL_CloseGamepad"     dlsym to (SDL_CloseGamepad)
    (sdl3) s" SDL_GetGamepadName"   dlsym to (SDL_GetGamepadName)
    (sdl3) s" SDL_GetGamepadButton" dlsym to (SDL_GetGamepadButton)
    (sdl3) s" SDL_GetGamepadAxis"   dlsym to (SDL_GetGamepadAxis)
    (sdl3) s" SDL_GamepadHasButton" dlsym to (SDL_GamepadHasButton)
    (sdl3) s" SDL_GamepadHasAxis"   dlsym to (SDL_GamepadHasAxis)
    (sdl3) s" SDL_UpdateGamepads"   dlsym to (SDL_UpdateGamepads)
    (sdl3) s" SDL_AddGamepadMapping" dlsym to (SDL_AddGamepadMapping)
    (sdl3) s" SDL_GamepadConnected" dlsym to (SDL_GamepadConnected)
    (sdl3) s" SDL_WasInit"          dlsym to (SDL_WasInit)
    (sdl3) s" SDL_free"             dlsym to (SDL_free)
    (sdl3) s" SDL_ClearError"       dlsym to (SDL_ClearError) ;
(pad-bind)

\ --- constants (see tools/sdl3off.c) ---
$2000 constant (SDL_INIT_GAMEPAD)

\ Face buttons, by position on the pad. See the header comment.
0  constant pad-south       \ bottom  (A on Xbox, B on Nintendo, X on PlayStation)
1  constant pad-east        \ right   (B on Xbox)
2  constant pad-west        \ left    (X on Xbox)
3  constant pad-north       \ top     (Y on Xbox)
4  constant pad-back
5  constant pad-guide       \ the big logo button; not present on every pad
6  constant pad-start
7  constant pad-lstick      \ pressing the left stick IN
8  constant pad-rstick
9  constant pad-lshoulder
10 constant pad-rshoulder
11 constant pad-up          \ d-pad
12 constant pad-down
13 constant pad-left
14 constant pad-right

\ Axes. Sticks read -32768..32767; triggers read 0..32767 (and on pads with
\ digital triggers, only ever 0 or 32767). Y is positive DOWNWARD, matching
\ screen coordinates.
0 constant pad-leftx        1 constant pad-lefty
2 constant pad-rightx       3 constant pad-righty
4 constant pad-ltrigger     5 constant pad-rtrigger

\ Event types, for programs that want edges rather than held state. These
\ arrive through sdl-poll alongside the keyboard events.
$650 constant ev-pad-axis
$651 constant ev-pad-down
$652 constant ev-pad-up
$653 constant ev-pad-added      \ a controller was plugged in
$654 constant ev-pad-removed    \ ...or unplugged

\ --- state ---
4 constant #pads                     \ slots; raise if you need more players
create (pad-tab) #pads cells allot   \ SDL_Gamepad* per slot, 0 = empty
(pad-tab) #pads cells erase

0 value (pad-cur)     \ selected slot
0 value (pad-init)    \ has (SDL_INIT_GAMEPAD) been started?

\ How far a stick must leave centre before pad-dir/pad-dx/pad-dy call it a
\ direction. A stick at rest does not read 0 -- it jitters, and a worn one can
\ sit some way off centre. 8000 is the traditional XInput figure, about a
\ quarter of full travel. A value, so a tired pad can be tuned at the prompt.
8000 value pad-dead

variable (pad-n)      \ SDL_GetGamepads out: count (4 bytes; read with l@)
variable (pad-list)   \ SDL_GetGamepads out: malloc'd SDL_JoystickID array

\ C returns narrower than a cell arrive with the high bits undefined, so mask
\ to width and then sign-extend by hand.
: (s16) ( u -- n )  $FFFF and  dup $8000 and if $10000 - then ;
: (s32) ( u -- n )  $FFFFFFFF and  dup $80000000 and if $100000000 - then ;

\ --- why the last open failed ---
\ pad-open's ior says THAT it failed; this says why, the same way snd-why does.
\ The two failures want different responses -- nothing plugged in is worth
\ retrying next frame, an unmapped controller never will be until pad-map runs
\ -- so the detail has to survive somewhere, and a string beats a magic number.
\
\ Recorded at the moment of failure. SDL_GetError's string is only good until
\ the next SDL call, so reading it lazily would hand back whatever SDL last had
\ to say rather than what went wrong here.
128 constant (pad-why-max)
create (pad-why-buf) (pad-why-max) allot
variable (pad-why-len)

: (pad-why$) ( c-addr u -- )           \ record a reason of our own, truncating
    (pad-why-max) min  dup (pad-why-len) !
    (pad-why-buf) swap cmove ;

: (pad-why!) ( -- )                    \ snapshot SDL's error, truncating
    0 (pad-why-len) !
    0 (SDL_GetError) (ccall) ?dup 0= if exit then      ( zaddr )
    (pad-why-max) 0 ?do
        dup c@ 0= if unloop drop exit then             \ NUL ends it
        dup c@ (pad-why-buf) i + c!                    ( zaddr )
        1+  i 1+ (pad-why-len) !
    loop drop ;

\ Wipe SDL's error slate, so that whatever is read after the next call was
\ set BY that call. SDL_GetError is not cleared by success -- its own header
\ says so, and warns against using it to decide whether anything went wrong.
\ Without this, an unrelated failure the program already handled (a texture
\ op, an audio device) is still sitting there, and pad-why would report it as
\ the reason a controller would not open.
: (pad-err-clear) ( -- )  0 (SDL_ClearError) (ccall) drop ;

\ SDL's own reason, falling back to a literal when it has nothing to say.
\ Every failure has to leave SOMETHING here: a non-zero ior and an empty
\ pad-why would send a caller looking for a reason that never arrives.
: (pad-why-sdl) ( c-addr u -- )
    (pad-why!)
    (pad-why-len) @ 0= if  (pad-why$)  else  2drop  then ;

\ Empty after a successful open, so it never reports a stale reason.
: pad-why ( -- c-addr u )  (pad-why-buf) (pad-why-len) @ ;

\ Start the gamepad subsystem the first time it is needed. (SDL_INIT_GAMEPAD)
\ implies JOYSTICK and EVENTS, so this is all a controller-only program needs
\ -- no window required.
\ Two spellings, because the callers differ in what they can say. A word that
\ returns an ior has to be able to REPORT a subsystem that would not start;
\ only a word with nothing to return may abort over it.
: (pad-init?) ( -- ok? )
    (pad-init) if true exit then
    (pad-err-clear)
    (SDL_INIT_GAMEPAD) 1 (SDL_Init) (ccall) (c-bool)
    dup if true to (pad-init) then ;

: (pad-init!) ( -- )                   \ ...the aborting form
    (pad-init?) 0= if sdl-error then ;

\ Is the gamepad subsystem up, as SDL sees it -- not merely as our own
\ (pad-init) flag believes. The two can disagree: anything calling SDL_Quit()
\ tears down every subsystem behind our back, and our flag would not know.
: (pad-up?) ( -- flag )
    (SDL_INIT_GAMEPAD) 1 (SDL_WasInit) (ccall) $FFFFFFFF and 0<> ;

\ SDL_GetGamepads hands back a malloc'd array that is ours to release.
: (pad-drop-list) ( -- )
    (pad-list) @ ?dup if  1 (SDL_free) (ccall) drop  then
    0 (pad-list) ! ;

: (pad@) ( -- handle )  (pad-cur) cells (pad-tab) + @ ;

\ Close whatever is in one slot and empty it. Closing an already-empty slot is
\ a no-op, so this is safe to call on any slot at any time.
: (pad-shut) ( slot -- )
    cells (pad-tab) +  dup @ ?dup if
        1 (SDL_CloseGamepad) (ccall) drop  0 swap !
    else drop then ;

\ The instance id of the nth CONNECTED controller, or 0 if there is no such
\ index (SDL ids start at 1, so 0 is a safe "none").
\
\ One SDL_GetGamepads call, and the bounds check uses THAT call's count. An
\ earlier version asked `pads` for the count and then called SDL_GetGamepads
\ again to index it -- a time-of-check/time-of-use gap: unplug a controller
\ in between and the second array is shorter than the count we validated
\ against, so the index reads off the end of it. The list is also released
\ before this returns, so no caller's abort path can leak it.
: (pad-id) ( n -- id|0 )
    0 (pad-n) !
    (pad-n) 1 (SDL_GetGamepads) (ccall) (pad-list) !
    (pad-list) @ 0= if  drop 0 exit  then
    dup (pad-n) l@ <  if  4 * (pad-list) @ + l@  else  drop 0  then
    (pad-drop-list) ;

\ --- open / select / close ---
\ Refresh controller state AND notice controllers plugged in or pulled out.
\
\ Both halves matter, and they are different calls. SDL_UpdateGamepads only
\ refreshes pads that are ALREADY open; device add/remove is detected by the
\ event loop, which is why this pumps as well. Without the pump a controller
\ unplugged and pushed back in is never seen again -- `pads` answers 0 forever
\ and pad-open cannot find it.
\
\ A program with a window gets this free: sdl-show pumps every frame. One
\ without a window has nothing else pumping, which is exactly where the
\ missing pump hid: every test passed, and a game loop would have worked.
: pad-update ( -- )
    (pad-init) 0= if exit then
    0 (SDL_PumpEvents) (ccall) drop
    0 (SDL_UpdateGamepads) (ccall) drop ;

\ 0 rather than an abort when the subsystem will not start: a game that asks
\ how many controllers are attached should hear "none" and carry on, the same
\ way every other query answers 0 with no pad open.
: pads ( -- n )
    (pad-init?) 0= if 0 exit then
    pad-update                  \ else a replugged controller is never noticed
    0 (pad-n) !
    (pad-n) 1 (SDL_GetGamepads) (ccall) (pad-list) !
    (pad-list) @ 0= if 0 exit then
    (pad-n) l@  (pad-drop-list) ;

\ Open the nth CONNECTED controller into slot n and select it. Re-opening a
\ slot is allowed and is the normal way to recover after a hotplug: the
\ controller already in it is closed first, so its handle is never stranded.
\
\ The old one is closed only AFTER the new open succeeds, so a re-open that
\ fails -- the pad was pulled out again between the two calls -- leaves the
\ working controller in place instead of emptying the slot on the way past.
\
\ An IOR, not a flag, and not an abort. 0 is success, like every other ior, so
\ the three things a caller might want all read straight with no 0= anywhere:
\
\   0 pad-open drop                     \ don't care; run keyboard-only
\   0 pad-open abort" no controller"    \ a pad is required
\   0 pad-open if pad-why type cr then  \ handle it, with the reason
\
\ A flag would invert one of those: with true meaning success,
\ `abort" no controller"` fires exactly when the pad opens. sound.fs shipped
\ that shape as snd-open? and it bit us, which is why both libraries now
\ return an ior and neither spells an opener with a `?`.
\
\ The magnitude is opaque -- test zero/non-zero and read pad-why for detail.
\
\ A bad SLOT aborts rather than returning an ior, because it is a different
\ kind of failure: no controller at slot 1 is the everyday case this word
\ exists to report, while slot 9 does not exist on any machine and never will.
\ Folding it into the same non-zero would bury a caller's bug in the branch
\ written to shrug failure off.
\
\ Unlike snd-open, this is NOT idempotent: re-opening a live slot re-opens it,
\ because that is the documented way to recover from a hotplug.
: pad-open ( n -- ior )
    dup 0 #pads within 0= abort" pad-open: slot out of range"
    \ A subsystem that will not start is a failure to REPORT, not to abort on:
    \ this word promises an ior, and sdl-error would break that promise.
    (pad-init?) 0= if
        drop  s" gamepad subsystem would not start" (pad-why-sdl)  3 exit
    then
    \ Pump first: SDL notices a plugged-in controller in the event queue, not
    \ in SDL_GetGamepads, so opening without this can miss a pad that is
    \ physically attached. Opening is not a per-frame operation -- the cost of
    \ being right here is nothing.
    pad-update
    dup (pad-id)  dup 0= if
        2drop  s" no controller at that index" (pad-why$)  1 exit
    then
    (pad-err-clear)
    1 (SDL_OpenGamepad) (ccall)         ( n handle )
    \ A controller SDL has no mapping for opens as a joystick but not as a
    \ gamepad. pad-map is the way back in -- see help pad.
    dup 0= if
        2drop  s" unmapped controller -- see pad-map" (pad-why-sdl)  2 exit
    then
    over (pad-shut)                     ( n handle )
    over cells (pad-tab) + !            ( n )
    to (pad-cur)
    0 (pad-why-len) !                   \ success leaves no stale reason
    0 ;

: pad ( n -- )
    dup 0 #pads within 0= abort" pad: slot out of range"
    to (pad-cur) ;

\ Is a controller really there? A handle stays open after its controller is
\ pulled out -- SDL keeps it valid so a game can notice and recover -- so
\ "we hold a handle" is a different question from "a controller is attached",
\ and only SDL can answer the second. Pair it with pad-update, which is what
\ makes SDL notice the unplug in the first place.
: pad? ( -- flag )
    (pad@) ?dup 0= if false exit then
    1 (SDL_GamepadConnected) (ccall) (c-bool) ;

\ The guard the queries below use: do we hold a handle at all. Cheaper than
\ pad? (no FFI call) and the right question for them -- reading a disconnected
\ pad is harmless and answers 0, where reading a null one is not.
\
\ Two questions, kept apart on purpose: pad? asks SDL whether a controller is
\ attached, this one only inspects the slot table. There is deliberately no
\ third, public, handle predicate -- pad? is the one a game wants, and a second
\ near-identical name is what this library just spent a rename getting rid of.
: (pad-have?) ( -- flag )  (pad@) 0<> ;

: pad-close ( -- )  (pad-cur) (pad-shut) ;

\ Quit only the subsystem we started. SDL_Quit() would end EVERY subsystem,
\ tearing down the window sdl3.fs opened and the audio device sound.fs is
\ playing through -- see the same warning in sdl-close.
: pad-closeall ( -- )
    #pads 0 do i (pad-shut) loop
    (pad-init) if
        (SDL_INIT_GAMEPAD) 1 (SDL_QuitSubSystem) (ccall) drop
        false to (pad-init)
    then
    0 to (pad-cur) ;

\ --- queries ---
: (zlen) ( zaddr -- u )  dup begin dup c@ while 1+ repeat swap - ;

: pad-name ( -- c-addr u )
    (pad-have?) 0= if 0 0 exit then
    (pad@) 1 (SDL_GetGamepadName) (ccall)
    dup 0= if drop 0 0 exit then
    dup (zlen) ;

: pad-held? ( button -- flag )
    (pad-have?) 0= if drop false exit then
    (pad@) swap 2 (SDL_GetGamepadButton) (ccall) (c-bool) ;

\ Not every pad has every control -- no guide button, no right stick, no
\ analog triggers. Ask, rather than reading a phantom 0.
: pad-has? ( button -- flag )
    (pad-have?) 0= if drop false exit then
    (pad@) swap 2 (SDL_GamepadHasButton) (ccall) (c-bool) ;

: pad-hasaxis? ( axis -- flag )
    (pad-have?) 0= if drop false exit then
    (pad@) swap 2 (SDL_GamepadHasAxis) (ccall) (c-bool) ;

: pad-axis ( axis -- n )
    (pad-have?) 0= if drop 0 exit then
    (pad@) swap 2 (SDL_GetGamepadAxis) (ccall) (s16) ;

\ --- directions ---
\ The dead-zone rule, kept separate from the hardware so it can be tested:
\ anything nearer centre than pad-dead is "not pushed". A stick exactly at
\ pad-dead counts as pushed.
: (dz) ( n -- -1|0|1 )
    dup abs pad-dead < if drop 0 exit then
    0< if -1 else 1 then ;

\ Merge one d-pad pair with one stick axis. If EITHER d-pad button is down the
\ d-pad decides and the stick is ignored entirely: a d-pad press is deliberate
\ and unambiguous, where a stick can rest off centre, drift with wear, or be
\ knocked. Summing them instead would let a worn stick resting at +9000
\ silently cancel the player's genuine d-pad presses -- the worst failure
\ mode, and an invisible one. Both buttons down at once really is 0.
\ Flags are canonical (0 or -1), so neg - pos gives -1 / 0 / +1 directly.
: (merge) ( neg? pos? stick -- -1|0|1 )
    >r                                   ( neg? pos?   R: stick )
    2dup or if  r> drop  -  exit  then
    2drop  r> (dz) ;

\ Any axis as a direction, dead zone applied. The right stick and the triggers
\ have no d-pad to merge with, so they come through here:
\   pad-rightx pad-dir     ( -- -1|0|1 )
: pad-dir ( axis -- -1|0|1 )  pad-axis (dz) ;

\ The left hand as one answer: d-pad or left stick, whichever the player uses.
\ pad-dy is positive DOWNWARD, like the axis and like screen coordinates.
: pad-dx ( -- -1|0|1 )
    pad-left pad-held?  pad-right pad-held?  pad-leftx pad-axis  (merge) ;

: pad-dy ( -- -1|0|1 )
    pad-up pad-held?  pad-down pad-held?  pad-lefty pad-axis  (merge) ;

\ --- events ---
\ Field accessors for the gamepad events that arrive through sdl-poll. Which
\ one applies depends on sdl-event-type.
: pad-ev-which  ( -- id )  sdl-event 16 + l@ ;   \ instance id, all pad events
: pad-ev-button ( -- b )   sdl-event 20 + c@ ;   \ ev-pad-down / ev-pad-up
: pad-ev-axis   ( -- a )   sdl-event 20 + c@ ;   \ ev-pad-axis
: pad-ev-value  ( -- n )   sdl-event 24 + w@ (s16) ;

\ --- mappings ---
\ A controller SDL does not recognise opens as a joystick but not as a gamepad,
\ and pad-open refuses it. Paste in a mapping line (the community
\ gamecontrollerdb.txt format) and try again.
: pad-map ( c-addr u -- )
    (pad-init!)
    >z 1 (SDL_AddGamepadMapping) (ccall) (s32)
    0< abort" pad-map: bad mapping string" ;
