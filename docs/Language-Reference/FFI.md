# FFI — Calling C Libraries

Load a shared C library and call its functions directly from Forth. Load the
wrappers first: `require ffi.fs`. Arguments are integers/pointers, up to 6
per call.

Two string formats meet at this border. A Forth string is an address/length
pair — the `c-addr` in stack comments means *character address* (nothing to
do with C). A C string has no length; it ends at a NUL byte, and by Forth
convention its address is called a `zaddr` (*zero-terminated*). Cross over
with `>z` going out and `ztype` coming back.

At a glance:

    dlopen   ( c-addr u -- handle )            load a shared library
    dlsym    ( handle c-addr u -- fnptr )      look up a function
    (ccall)  ( args.. nargs fnptr -- ret )     call it (up to 6 args)
    >z       ( c-addr u -- zaddr )             NUL-terminate a string for C
    (dlopen) ( zaddr -- handle )               raw primitive behind dlopen
    (dlsym)  ( handle zaddr -- fnptr )         raw primitive behind dlsym

A complete example — the process id via libc:

    require ffi.fs
    : pid ( -- n )
        s" libc.so.6" dlopen  s" getpid" dlsym  >r 0 r> (ccall) ;
    pid .

`s"` also works at the prompt, so one-off calls need no colon definition:

    s" libc.so.6" dlopen s" getpid" dlsym 0 swap (ccall) .

## dlopen ( c-addr u -- handle )
Load a shared library by name (searched on the system library path) or by
absolute path. Aborts with a message if the library cannot be loaded.

    : sdl ( -- h ) s" libSDL3.so.0" dlopen ;

## dlsym ( handle c-addr u -- fnptr )
Resolve a function name in an open library to a callable pointer. Aborts if
the symbol is not found.

    : getpid-fn ( -- fn ) s" libc.so.6" dlopen s" getpid" dlsym ;

## (ccall) ( arg1 .. argN nargs fnptr -- ret )
Call a C function. Push the arguments in C parameter order (first parameter
first), then the argument count (0–6), then the function pointer. The C
return value is pushed. Integer and pointer arguments; see `(ccallf)` for
functions that take a float.

    \ long labs(long n)
    : labs-test ( -- ) s" libc.so.6" dlopen s" labs" dlsym
        >r -42 1 r> (ccall) . ;   \ 42

C code runs with no safety net: a bad pointer or wrong argument count can
crash BasicForth. Check stack pictures against the C prototype.

## (ccallf) ( iargs.. fargs.. nint nfloat fnptr -- ret )
## (ccallf>f) ( iargs.. fargs.. nint nfloat fnptr -- fbits )
Call a C function that takes **float** parameters. Push the integer arguments
in C order, then the float arguments in C order, then the two counts, then the
function pointer. `(ccallf)` returns the integer result; `(ccallf>f)` returns
a float result as bits.

Grouping the floats after the integers is not a restriction. Both ABIs give
float parameters their own registers, filled in their own order regardless of
how they interleave with the integers in the prototype — so the two groups can
be handed over separately and still land correctly.

    \ float ldexpf(float x, int exp)      -- C interleaves them
    : ldexpf-test ( -- fbits )  s" libm.so.6" dlopen s" ldexpf" dlsym
        >r  2  3 1 >f32  1 1 r> (ccallf>f) ;   \ 3.0 * 2^2 = 12.0

    \ bool SDL_SetAudioStreamGain(SDL_AudioStream *stream, float gain)
    stream  1 2 >f32  1 1 setgain (ccallf) drop      \ half volume

Limits: 6 integer arguments on x86-64, 8 on ARM64, and 8 float arguments on
both.

## >f32 ( n d -- bits )
The IEEE-754 single-precision bit pattern of `n/d`, as an ordinary integer —
what `(ccallf)` wants for a float argument.

    1 1 >f32 .      \ 1065353216   (1.0)
    1 2 >f32 .      \ 1056964608   (0.5)
    3 4 >f32 .      \ 0.75

The Forth stack never holds a float, only its bits; nothing here can do
arithmetic on them. `d` of zero gives `0` rather than an infinity, so a bad
ratio is silence and not a value that poisons what consumes it.

## >z ( c-addr u -- zaddr )
Copy a Forth string to a scratch buffer and NUL-terminate it, for C functions
that take strings. One shared buffer: consume the result before the next `>z`.

## ztype ( zaddr -- )
The other direction: print a NUL-terminated C string, as returned by many C
functions (error messages, version strings).

    \ 0 (SDL_GetError) (ccall) ztype

## (dlopen) ( zaddr -- handle )
## (dlsym) ( handle zaddr -- fnptr )
The raw primitives under `dlopen`/`dlsym`: same jobs, NUL-terminated string
addresses in, `0` back on failure instead of aborting.
