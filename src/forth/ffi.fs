\ BasicForth ffi.fs -- calling C libraries (dlopen/dlsym/ccall)
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Loaded on demand (require ffi.fs), NOT at startup. Thin Forth layer over the
\ FFI primitives:
\
\   (dlopen) ( zaddr -- handle )            load a shared library (0 = failed)
\   (dlsym)  ( handle zaddr -- fnptr )      resolve a symbol      (0 = failed)
\   (ccall)  ( arg1 .. argN nargs fnptr -- ret )   call a C function
\
\ (ccall) passes up to 6 integer/pointer args in C parameter order: arg1 is
\ pushed first, so a call reads left-to-right like C source. Example:
\
\   s" libc.so.6" dlopen value libc
\   libc s" getpid" dlsym value getpid
\   0 getpid (ccall) .          \ prints the process id
\
\ FLOAT ARGUMENTS. Forth has no floats, but plenty of C functions want one --
\ a gain, a speed, a scale. Both ABIs put float parameters in their own
\ register file (XMM0-7 / V0-V7), assigned in their own order no matter how
\ they interleave with the integers, so the two groups can be passed
\ separately:
\
\   (ccallf)   ( iargs.. fargs.. nint nfloat fnptr -- ret )    integer result
\   (ccallf>f) ( iargs.. fargs.. nint nfloat fnptr -- fbits )  float result
\   >f32       ( n d -- bits )   the f32 bit pattern of n/d
\
\ A float argument is a BIT PATTERN, not a float: the stack still only ever
\ holds integers. Group the float parameters after the integer ones, whatever
\ order the C prototype uses.
\
\   s" libSDL3.so.0" dlopen value sdl
\   sdl s" SDL_SetAudioStreamGain" dlsym value setgain
\   \ bool SDL_SetAudioStreamGain(SDL_AudioStream *stream, float gain)
\   stream  1 2 >f32   1 1 setgain (ccallf) drop     \ half volume
\
\ C strings are NUL-terminated; >z copies a Forth string into a scratch buffer
\ and appends the NUL. The buffer is reused by every >z (and by dlopen/dlsym),
\ so consume the zaddr before making another.

256 constant (z-max)
create (zbuf) (z-max) 1+ allot

: >z ( c-addr u -- zaddr )
    dup (z-max) > abort" >z: string too long"
    dup >r  (zbuf) swap cmove  0 (zbuf) r> + c!  (zbuf) ;

\ The other direction: print a NUL-terminated C string (error messages,
\ version strings, anything a C function hands back by address).
: ztype ( zaddr -- )  begin dup c@ ?dup while emit 1+ repeat drop ;

\ A file that declared `needs-lib libfoo.so.1` already has it open, and the
\ probe kept the handle -- so the usual dep-block-then-bind pair costs one
\ dlopen, not two. Beyond saving the call, it guarantees the two agree: the
\ library the load was checked against is the library that gets bound.
\
\ The failure names the library, because "cannot load library" in a session
\ that has required three of them says nothing. NEEDS-LIB says more still,
\ which is the reason to declare one.
: dlopen ( c-addr u -- handle )
    2dup (lib-probed) ?dup if  nip nip exit  then
    2dup >z (dlopen) ?dup 0= if
        ." dlopen: cannot load " type cr  -2 throw  then
    nip nip ;

: dlsym ( handle c-addr u -- fnptr )  >z (dlsym)
    dup 0= abort" dlsym: symbol not found" ;
