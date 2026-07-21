# FFI — Foreign Function Interface

BasicForth can load shared C libraries and call their functions. This is the
gateway to the capabilities that are sealed behind libraries rather than
syscalls — SDL3 for display/input/audio first, SDL_GPU for 3D later, and any
other C library after that (see "Graphics Direction" in
[Planning.md](Planning.md)).

## The words

Primitives (built in, both architectures):

| Word | Stack | Meaning |
|------|-------|---------|
| `(dlopen)` | ( zaddr -- handle ) | load a shared library; 0 on failure |
| `(dlsym)` | ( handle zaddr -- fnptr ) | resolve a symbol; 0 on failure |
| `(ccall)` | ( arg1 .. argN nargs fnptr -- ret ) | call a C function |

Forth wrappers (`require ffi.fs`, on demand):

| Word | Stack | Meaning |
|------|-------|---------|
| `>z` | ( c-addr u -- zaddr ) | copy to a scratch buffer, NUL-terminate |
| `dlopen` | ( c-addr u -- handle ) | `>z (dlopen)`, aborts on failure |
| `dlsym` | ( handle c-addr u -- fnptr ) | `>z (dlsym)`, aborts on failure |

Example:

```
require ffi.fs
: libc ( -- h ) s" libc.so.6" dlopen ;
: pid ( -- n ) libc s" getpid" dlsym  >r 0 r> (ccall) ;
pid .
```

## Argument marshalling

`(ccall)` passes up to **6 integer/pointer arguments** in the platform C ABI
registers (x86-64 SysV: RDI RSI RDX RCX R8 R9; ARM64 AAPCS64: X0–X5).
Arguments are pushed in **C parameter order** — arg1 first (deepest), so a
call site reads left-to-right like the C prototype:

```
\ int snprintf(char *buf, size_t n, const char *fmt, ...)
buf 68 fmt 9876 4 snprintf-fn (ccall)
```

The C return value (RAX / X0) is pushed on the data stack. On x86-64, AL is
zeroed before the call, so variadic functions (printf-family) work.

Current limits, by design (extend when a binding needs it):
- No floating-point arguments or returns.
- No arguments past the sixth (none of the SDL 2D surface needs more).
- No callbacks (C calling back into Forth). SDL3 is poll-based, so none are
  needed for the graphics/input/audio roadmap.

**No safety net:** C code trusts the arguments. A wrong count, a Forth string
where C expects NUL-terminated, or a bad pointer will crash or corrupt the
process. Keep the C prototype next to the binding.

## How it works underneath

- The binary is **dynamically linked** (`gcc -nostartfiles -no-pie`, keeping
  our own `_start`): the kernel maps `ld.so`, which loads `libc`, runs its
  initializers, and only then jumps to `_start`. That initialization is what
  makes `dlopen`/`dlsym` (and everything a loaded library needs — `malloc`,
  TLS, `pthread`) work. The platform layer still makes raw syscalls for all
  OS work; libc is bypassed except `dlopen`/`dlsym`.
- `platform_dlopen`/`platform_dlsym` are the only platform functions that
  call libc. They align the stack to 16 bytes around the call, as the C ABI
  requires (the Forth return stack carries no such guarantee).
- The engine registers (DSP/HERE/LATEST) live in callee-saved registers
  (R15/R13/R12 on x86-64, X19/X21/X22 on ARM64) precisely so they survive
  any C call unscathed.
- Dynamic linking cost one build change elsewhere: the old `ld -N` link put
  the whole binary in one RWX segment, which is what made the STC dictionary
  executable. Now `.bss` is mapped read-write only, so startup `mprotect`s
  the (page-aligned) dictionary to RWX — see `platform_init_guard_pages`.

## Testing

The FFI is exercised against libc in `tests/test_integration.sh` (getpid,
labs, snprintf with 4 args, and failure paths) — no display or special
environment needed, and it runs under QEMU (the emulated ld.so resolves
libraries inside the `-L` sysroot).
