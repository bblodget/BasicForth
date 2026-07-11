# BasicForth — String Words

BasicForth provides string output and inline string literals. TYPE is
an ASM primitive that writes strings to stdout. Inside a definition,
S" and ." embed string data inline in the compiled code, using a
runtime helper to skip past the data and push the address and length.
At the interpreter prompt (and at the top level of included files) they
also work directly: S" returns the string in a transient buffer and ."
types it immediately (see "Interpreted S" and ."" below).

## TYPE

`TYPE ( c-addr u -- )`

Pops a string address and length from the data stack, writes the string
to stdout via `platform_write`. This is the fundamental string output
word — all other string printing builds on it.

## S" — String Literal

`S" ( -- c-addr u )` — IMMEDIATE (STATE-smart)

When compiling, S" parses the input buffer for the closing `"` and
compiles the string data inline in the definition. At runtime, it pushes
the address and length of the inline string onto the data stack. When
interpreting, it returns the string in a transient buffer (see
"Interpreted S" and ."" below).

The ASM primitive handles the compile path; a STATE-smart wrapper in
core.fs (which shadows it) adds the interpretation semantics and
delegates compilation to the primitive, so compiled code is identical
either way.

### Compiled Output

For `: test s" Hello" type ;`:

**x86-64:**
```
CALL forth_s_quote_runtime   ; 5 bytes
.quad 5                       ; 8 bytes — string length
Hello                         ; 5 bytes — string data
CALL forth_type              ; 5 bytes — (compiled by subsequent TYPE)
```

**ARM64:**
```
BL forth_s_quote_runtime     ; 4 bytes
.quad 5                       ; 8 bytes — string length
Hello                         ; 5 bytes — string data
.align 4                      ; 0-3 bytes padding to instruction boundary
BL forth_type                ; 4 bytes
```

### Runtime Helper: forth_s_quote_runtime

Works like `forth_lit` but for strings. Called via CALL/BL, it reads
the inline length and string data after the return address:

1. Read the 8-byte length from the return address
2. Compute c-addr = return address + 8 (past the length field)
3. Push c-addr and length onto the data stack
4. Adjust the return address to skip past the string data
5. On ARM64: align the adjusted address to a 4-byte boundary

The caller never executes the inline data — the return address
adjustment skips over it, just like `forth_lit` skips its inline value.

### ARM64 Alignment

On ARM64, instructions must be 4-byte aligned. Since string data can
be any length, the compiler pads the string to a 4-byte boundary.
The runtime helper also aligns the adjusted return address:

```
ADD X30, X30, #3
AND X30, X30, #~3
```

x86-64 has no alignment requirement for instructions.

## ." — Print String Literal

`." ( -- )` — IMMEDIATE (STATE-smart)

Like S" but also compiles a call to TYPE after the string data. The
string is printed at runtime without leaving anything on the stack.
When interpreting, ." types the string immediately.

For `: greet ." Hello!" ;`:

**x86-64:**
```
CALL forth_s_quote_runtime   ; 5 bytes
.quad 6                       ; 8 bytes — length of "Hello!"
Hello!                        ; 6 bytes — string data
CALL forth_type              ; 5 bytes — prints the string
```

Both S" and ." share the same compile-time helper (`compile_s_quote`)
that parses the input and emits the inline data. ." simply adds an
extra `CALL/BL forth_type` at the end.

## Interpreted S" and ."

Outside a definition — at the prompt, at the top level of an included
file, or in an EVALUATE'd string — S" and ." work directly:

```forth
s" hello.txt" included        \ no colon definition needed
." Loading..." cr
```

This is implemented by STATE-smart wrappers in core.fs that shadow the
ASM primitives. When STATE is compiling they EXECUTE the primitive
(which parses and compiles the inline string exactly as before); when
interpreting:

- **S"** parses to the closing `"` and copies the string into one of
  **two alternating transient buffers** of 256 bytes each, then pushes
  the buffer address and length. Per ANS Forth 2012, the string remains
  valid until the *second-next* interpreted S" — so two strings can be
  live at once (`s" abc" s" def" compare`), but the third reuses the
  first buffer. Copying matters because the input buffer itself is
  overwritten by the next line.
- **."** parses to the closing `"` and TYPEs it immediately, straight
  from the input buffer (no copy needed).

A string longer than 256 characters aborts with
`interpreted string too long`. ABORT" remains compile-only (ANS leaves
its interpretation semantics undefined).

## COUNT

`COUNT ( c-addr -- c-addr+1 u )`

Converts a counted string (where the first byte is the length) into
an address-length pair suitable for TYPE. Defined in core.fs:

```forth
: COUNT  dup 1+ swap c@ ;
```

## PICK

`PICK ( xu ... x1 x0 u -- xu ... x1 x0 xu )`

Copy the u-th item from the stack (0-indexed: `0 pick` is equivalent
to `dup`). Implemented as an ASM primitive since it requires direct
stack-relative addressing.

Used by 2OVER in core.fs: `: 2OVER 3 pick 3 pick ;`

## Bounds Checking

The `compile_s_quote` helper checks that the total space needed fits
in dict_space before writing: CALL/BL size + 8-byte length field +
string bytes (+ alignment padding on ARM64). If the string would
overflow the dictionary, `dict_full` is triggered.

## Word Reference

### TYPE ( c-addr u -- )
Write u characters starting at c-addr to stdout.

### S" ( -- c-addr u )
Compiling: parse to closing `"`, compile inline string data; at runtime
push string address and length. Interpreting: parse to closing `"`,
return the string in a transient buffer (two alternate, 256 bytes each).

### ." ( -- )
Compiling: parse to closing `"`, compile inline string data + TYPE; the
string prints at runtime. Interpreting: type the string immediately.

### COUNT ( c-addr -- c-addr+1 u )
Convert counted string to address-length pair. Defined in core.fs.

### PICK ( xu ... x1 x0 u -- xu ... x1 x0 xu )
Copy the u-th stack item. 0 pick = dup.

## Examples

```forth
\ Print a greeting
: greet  ." Hello, World!" cr ;
greet   \ prints: Hello, World!

\ Build a string and print it
: test  s" BasicForth" type ;
test    \ prints: BasicForth

\ Interpreted use — no colon definition needed
s" BasicForth" type      \ prints: BasicForth
." Hello from the prompt" cr

\ Multiple strings in one definition
: banner  ." *** " ." Welcome " ." ***" cr ;
banner  \ prints: *** Welcome ***

\ Counted string
create msg  5 c, 72 c, 101 c, 108 c, 108 c, 111 c,
msg count type   \ prints: Hello

\ PICK for deep stack access
1 2 3 4 5  3 pick .   \ prints: 2
```
