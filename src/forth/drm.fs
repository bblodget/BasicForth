\ BasicForth drm.fs -- DRM/KMS display backend (software 2D)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Direct modern-display access via /dev/dri/cardN ioctls (no libdrm). Requires
\ graphics.fs (set-surface). Load:  include graphics.fs   include drm.fs
\
\   drm-open   ( -- )  open the card, pick the connected display, allocate a dumb
\                      framebuffer, map it, and point the graphics surface at it.
\                      Works as a non-master client (e.g. under X) for drawing.
\   drm-show   ( -- )  become DRM master and scan the framebuffer out to the
\                      screen (SETCRTC). Needs master — run from a text VT or the
\                      board, not under a running compositor.
\   drm-close  ( -- )  drop master and close the card.
\
\ Struct offsets/ioctl numbers are from <drm/drm_mode.h> (see tools/drmoff.c).

\ --- ioctl request numbers (arch-independent) ---
$c04064a0 constant DRM_GETRES
$c05064a7 constant DRM_GETCONN
$c01464a6 constant DRM_GETENC
$c02064b2 constant DRM_CREATE_DUMB
$c01064b3 constant DRM_MAP_DUMB
$c01c64ae constant DRM_ADDFB
$c06864a2 constant DRM_SETCRTC
$641e     constant DRM_SET_MASTER
$641f     constant DRM_DROP_MASTER

variable (drm-fd)
variable (drm-w)     variable (drm-h)     variable (drm-pitch)  variable (drm-size)
variable (drm-handle) variable (drm-fb)   variable (drm-crtc)   variable (drm-conn)
variable (enc-id)    variable (drm-found)
variable (conn-ids)  variable (crtc-ids)  variable (n-conn)     variable (n-crtc)
variable (modes)     variable (n-modes)

\ struct scratch (zeroed before each ioctl)
create res     64 allot
create conn    80 allot
create enc     20 allot
create dumb    32 allot
create mapd    16 allot
create fbc     28 allot
create crtcblk 104 allot
create modebuf 68 allot          \ saved copy of the chosen modeinfo
create connbuf 4 allot           \ one connector id, for SETCRTC's connector list

\ ioctl on the open card: ( argp request -- ret )
: (io)  ( argp request -- ret )  swap (drm-fd) @ -rot (ioctl) ;

\ GETRESOURCES (two phase: counts, then fill the id arrays)
: (get-res) ( -- )
    res 64 erase
    res DRM_GETRES (io) drop
    res 40 + l@ (n-conn) !
    res 36 + l@ (n-crtc) !
    (n-conn) @ 4 * allocate drop (conn-ids) !
    (n-crtc) @ 4 * allocate drop (crtc-ids) !
    res 64 erase
    (conn-ids) @ res 16 + !          \ connector_id_ptr (8-byte user pointer)
    (crtc-ids) @ res  8 + !          \ crtc_id_ptr
    (n-conn) @  res 40 + l!          \ count_connectors
    (n-crtc) @  res 36 + l!          \ count_crtcs
    res DRM_GETRES (io) drop ;

\ Try one connector id. If connected with modes, save mode[0] + ids; flag true.
: (try-conn) ( id -- flag )
    >r
    conn 80 erase
    r@ conn 48 + l!                  \ connector_id (input)
    conn DRM_GETCONN (io) drop       \ phase 1: connection + counts
    conn 60 + l@ 1 <> if  r> drop false exit  then    \ not connected
    conn 32 + l@ dup 0= if  drop r> drop false exit  then  \ no modes
    (n-modes) !
    (n-modes) @ 68 * allocate drop (modes) !
    conn 80 erase
    r> conn 48 + l!                  \ connector_id again
    (modes) @ conn 8 + !             \ modes_ptr
    (n-modes) @ conn 32 + l!         \ count_modes
    conn DRM_GETCONN (io) drop       \ phase 2: fills modes + encoder_id
    (modes) @ modebuf 68 cmove       \ keep mode[0]
    modebuf 4 + w@ (drm-w) !         \ hdisplay (u16)
    modebuf 14 + w@ (drm-h) !        \ vdisplay (u16)
    conn 48 + l@ (drm-conn) !
    conn 44 + l@ (enc-id) !
    true ;

\ Resolve the CRTC for the chosen connector's encoder (fall back to crtc[0]).
: (get-crtc) ( -- )
    enc 20 erase
    (enc-id) @ enc l!                \ encoder_id @0
    enc DRM_GETENC (io) drop
    enc 8 + l@ dup if  (drm-crtc) !
    else  drop (crtc-ids) @ l@ (drm-crtc) !  then ;

: (create-dumb) ( -- )
    dumb 32 erase
    (drm-h) @ dumb     l!            \ height @0
    (drm-w) @ dumb 4 + l!            \ width  @4
    32        dumb 8 + l!            \ bpp    @8
    dumb DRM_CREATE_DUMB (io) drop
    dumb 16 + l@ (drm-handle) !      \ handle @16
    dumb 20 + l@ (drm-pitch)  !      \ pitch  @20
    dumb 24 + @  (drm-size)   ! ;    \ size   @24 (u64)

: (addfb) ( -- )
    fbc 28 erase
    (drm-w) @     fbc  4 + l!        \ width  @4
    (drm-h) @     fbc  8 + l!        \ height @8
    (drm-pitch) @ fbc 12 + l!        \ pitch  @12
    32            fbc 16 + l!        \ bpp    @16
    24            fbc 20 + l!        \ depth  @20
    (drm-handle) @ fbc 24 + l!       \ handle @24
    fbc DRM_ADDFB (io) drop
    fbc l@ (drm-fb) ! ;              \ fb_id @0

: (map-dumb) ( -- )
    mapd 16 erase
    (drm-handle) @ mapd l!           \ handle @0
    mapd DRM_MAP_DUMB (io) drop
    (drm-fd) @  mapd 8 + @  (drm-size) @  (mmap-dev)   ( base )
    (drm-w) @ (drm-h) @ (drm-pitch) @ set-surface ;

: drm-open ( -- )
    s" /dev/dri/card1" r/w open-file
    if  ." drm: cannot open /dev/dri/card1" cr drop exit  then
    (drm-fd) !
    (get-res)
    false (drm-found) !
    (n-conn) @ 0 ?do
        (drm-found) @ 0= if
            (conn-ids) @ i 4 * + l@ (try-conn)
            if  true (drm-found) !  then
        then
    loop
    (drm-found) @ 0= if  ." drm: no connected display found" cr exit  then
    (get-crtc) (create-dumb) (addfb) (map-dumb) ;

\ Scan the framebuffer out to the display. Returns the SETCRTC result on the
\ stack (0 ok; negative errno, e.g. -13 EACCES, if not DRM master). Needs master.
: drm-show ( -- ret )
    (drm-fd) @ DRM_SET_MASTER 0 (ioctl) drop
    crtcblk 104 erase
    (drm-conn) @ connbuf l!          \ the one connector id
    connbuf       crtcblk      !     \ set_connectors_ptr @0 (8-byte)
    1             crtcblk  8 + l!    \ count_connectors @8
    (drm-crtc) @  crtcblk 12 + l!    \ crtc_id @12
    (drm-fb)   @  crtcblk 16 + l!    \ fb_id   @16
    0 crtcblk 20 + l!  0 crtcblk 24 + l!   \ x, y
    1            crtcblk 32 + l!     \ mode_valid @32
    modebuf crtcblk 36 + 68 cmove    \ mode @36 (68-byte modeinfo)
    crtcblk DRM_SETCRTC (io) ;

: drm-close ( -- )
    (drm-fd) @ DRM_DROP_MASTER 0 (ioctl) drop
    (drm-fd) @ close-file drop ;

\ A demo: blue background with two filled rectangles. Run drm-show to display.
: drm-demo ( -- )
    drm-open
    blue clear
    red    100 100 300 200 fill-rect
    green  450 100 300 200 fill-rect
    white   60  60 760  20 fill-rect ;
