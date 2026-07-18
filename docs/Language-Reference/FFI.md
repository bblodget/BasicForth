# FFI — Calling C Libraries

Load a shared C library and call its functions directly from Forth. Load the
wrappers first: `include ffi.fs`. Strings passed to C must be NUL-terminated
(`>z` does the copy); arguments are integers/pointers, up to 6 per call.

At a glance:

    dlopen   ( c-addr u -- handle )            load a shared library
    dlsym    ( handle c-addr u -- fnptr )      look up a function
    (ccall)  ( args.. nargs fnptr -- ret )     call it (up to 6 args)
    >z       ( c-addr u -- zaddr )             NUL-terminate a string for C
    (dlopen) ( zaddr -- handle )               raw primitive behind dlopen
    (dlsym)  ( handle zaddr -- fnptr )         raw primitive behind dlsym

A complete example — the process id via libc:

    include ffi.fs
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
return value is pushed. Integer/pointer arguments only — no floats yet.

    \ long labs(long n)
    : labs-test ( -- ) s" libc.so.6" dlopen s" labs" dlsym
        >r -42 1 r> (ccall) . ;   \ 42

C code runs with no safety net: a bad pointer or wrong argument count can
crash BasicForth. Check stack pictures against the C prototype.

## >z ( c-addr u -- zaddr )
Copy a Forth string to a scratch buffer and NUL-terminate it, for C functions
that take strings. One shared buffer: consume the result before the next `>z`.

## (dlopen) ( zaddr -- handle )
## (dlsym) ( handle zaddr -- fnptr )
The raw primitives under `dlopen`/`dlsym`: same jobs, NUL-terminated string
addresses in, `0` back on failure instead of aborting.
