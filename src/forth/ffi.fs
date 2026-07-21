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

: dlopen ( c-addr u -- handle )  >z (dlopen)
    dup 0= abort" dlopen: cannot load library" ;

: dlsym ( handle c-addr u -- fnptr )  >z (dlsym)
    dup 0= abort" dlsym: symbol not found" ;
