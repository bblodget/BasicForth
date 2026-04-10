# BasicForth — Defining Words

Defining words create new dictionary entries with compiled code.
BasicForth follows the Subroutine Threaded Code (STC) approach — each
defining word compiles real machine code into the dictionary entry, so
calling the defined word executes native instructions directly.

## Dictionary Entry Layout

Every word in the dictionary has this layout:

```
[Link:8][Flags+Len:1][Name:N][align8][CodePtr:8][CodeLen:4][...code...]
```

| Field    | Size    | Description                                       |
|----------|---------|---------------------------------------------------|
| Link     | 8 bytes | Pointer to previous dictionary entry (or 0)       |
| Flags+Len| 1 byte  | Upper bits = flags, lower 5 bits = name length    |
| Name     | N bytes | Word name (case-preserved, lookup case-insensitive)|
| align    | 0-7     | Padding to 8-byte boundary                        |
| CodePtr  | 8 bytes | Pointer to the start of compiled code              |
| CodeLen  | 4 bytes | Length of compiled code in bytes                   |
| code     | varies  | The compiled machine code                          |

The `build_header` helper creates this structure. It is shared by `:`,
CREATE, and CONSTANT — each calls `build_header` then compiles different
code into the entry.

## CREATE

`CREATE ( "name" -- )`

Parse a name, build a dictionary header, and compile code that pushes
the **data field address** at runtime. Does not enter compile mode.

### Compiled Code

**x86-64** (18 bytes):
```
Offset 0:  CALL forth_lit    ; 5 bytes — push inline value
Offset 5:  .quad data_addr   ; 8 bytes — the data field address
Offset 13: RET               ; 1 byte
Offset 14: NOP NOP NOP NOP   ; 4 bytes — reserved for DOES>
```

**ARM64** (24 bytes):
```
Offset 0:  STP X29, X30, [SP, #-16]!   ; 4 bytes — prolog
Offset 4:  BL forth_lit                  ; 4 bytes — push inline value
Offset 8:  .quad data_addr              ; 8 bytes — the data field address
Offset 16: LDP X29, X30, [SP], #16     ; 4 bytes — epilog
Offset 20: RET                          ; 4 bytes
```

After the code, HERE is aligned to 8 bytes, and the data field begins.
The `data_addr` literal is initially compiled as a placeholder (0), then
patched with the actual aligned address after alignment.

### Data Field Alignment

CREATE compiles its code with a placeholder literal, emits RET (and NOPs
on x86), aligns HERE to a cell boundary, then patches the literal with
the actual aligned address. This ensures the data field is always
8-byte aligned regardless of name length.

## CONSTANT

`CONSTANT ( x "name" -- )`

Pop a value from the stack, parse a name, build a dictionary header,
and compile code that pushes the value at runtime.

### Compiled Code

**x86-64** (14 bytes):
```
Offset 0:  CALL forth_lit    ; 5 bytes
Offset 5:  .quad value       ; 8 bytes — the constant value
Offset 13: RET               ; 1 byte
```

**ARM64** (24 bytes):
```
Offset 0:  STP X29, X30, [SP, #-16]!   ; 4 bytes
Offset 4:  BL forth_lit                  ; 4 bytes
Offset 8:  .quad value                  ; 8 bytes
Offset 16: LDP X29, X30, [SP], #16     ; 4 bytes
Offset 20: RET                          ; 4 bytes
```

CONSTANT has no data field — the value is embedded directly in the code.

## VARIABLE

`VARIABLE ( "name" -- )`

Defined in `core.fs` as:

```forth
: variable  create 1 cells allot ;
```

Creates a word via CREATE with one cell (8 bytes) of uninitialized data
space. At runtime, the word pushes the address of that cell.

## DOES>

`DOES> ( -- )` — IMMEDIATE, COMPILE_ONLY

Attaches custom runtime behavior to words made by CREATE. Used inside
defining words to specify what the defined word does when executed.

### Two-Phase Behavior

**Phase 1 — Compile time** (when the defining word is compiled):

DOES> is IMMEDIATE, so it executes during compilation. It:

1. Compiles `CALL/BL forth_does_runtime` — the runtime patching helper
2. Compiles epilog+RET — ends the defining word's normal code path
3. On ARM64: compiles a prolog (STP) for the does-body
4. Returns — subsequent words compile into the does-body
5. `;` closes the does-body with its own epilog+RET

**Phase 2 — Run time** (when the defining word executes):

The `(does>)` runtime helper:

1. Calculates the does-body address from its return address
2. Finds the most recently CREATE'd word's code via `colon_code_len_addr`
3. Patches the CREATE'd word's code: replaces RET with JMP/B to does-body
4. Returns normally to the defining word's caller

### Compiled Code for a Defining Word

For `: myconst CREATE , DOES> @ ;`:

**x86-64:**
```
CALL forth_create         ; CREATE
CALL forth_comma          ; ,
CALL forth_does_runtime   ; (DOES>) runtime helper
RET                       ; end of defining word's normal path
; ---- does-body starts here ----
CALL forth_fetch          ; @
RET                       ; compiled by ;
```

**ARM64:**
```
STP X29, X30, [SP, #-16]!   ; defining word prolog
BL forth_create               ; CREATE
BL forth_comma                ; ,
BL forth_does_runtime         ; (DOES>) runtime helper
LDP X29, X30, [SP], #16     ; defining word epilog
RET                           ; end of defining word's normal path
; ---- does-body starts here ----
STP X29, X30, [SP, #-16]!   ; does-body prolog
BL forth_fetch                ; @
LDP X29, X30, [SP], #16     ; does-body epilog
RET                           ; compiled by ;
```

### DOES> Patching

When `42 myconst answer` runs, `(does>)` patches `answer`'s code:

**x86-64 — before patching:**
```
Offset 13: C3 90 90 90 90    ; RET + 4 NOPs
```

**x86-64 — after patching:**
```
Offset 13: E9 xx xx xx xx    ; JMP does_body (5 bytes)
```

**ARM64 — before patching:**
```
Offset 20: D65F03C0          ; RET
```

**ARM64 — after patching:**
```
Offset 20: 14xxxxxx          ; B does_body
```

### Execution Flow After Patching

When `answer` is called:

1. `CALL forth_lit` pushes the data field address onto the stack
2. `JMP/B does_body` transfers to the does-body (no return address pushed)
3. The does-body executes `@` — fetching the value from the data field
4. The does-body's RET returns to `answer`'s caller

The does-body is a standalone subroutine. On ARM64, the CREATE'd word's
LDP (offset 16) restores X30 before the branch, so the does-body
receives the correct return address and can save/restore it with its
own prolog/epilog.

## Word Reference

### CREATE ( "name" -- )
Parse name, build dictionary header, compile code that pushes the data
field address at runtime. The data field starts immediately after the
compiled code (aligned to 8 bytes).

### CONSTANT ( x "name" -- )
Pop value, parse name, build dictionary header, compile code that pushes
the value at runtime. No data field — value is embedded in the code.

### VARIABLE ( "name" -- )
Defined in core.fs. Equivalent to `CREATE 1 CELLS ALLOT`. The word
pushes the address of one uninitialized cell.

### DOES> ( -- )
Compile-time: end the defining word's code path, begin compiling the
does-body. Runtime: patch the most recently CREATE'd word to jump to
the does-body after pushing its data field address.

### HERE ( -- addr )
Push the current dictionary free-space pointer.

### ALLOT ( n -- )
Reserve n bytes of dictionary space. Bounds-checked in both directions.

### , ( x -- )
Compile a cell (8 bytes) into dictionary space at HERE.

### C, ( c -- )
Compile a byte into dictionary space at HERE.

## Examples

```forth
\ CONSTANT is built in, but could be defined with DOES>:
: my-constant  create , does> @ ;
42 my-constant answer
answer .   \ prints 42

\ Array defining word
: array  create cells allot does> swap cells + ;
5 array data
10 0 data !   20 1 data !   30 2 data !
0 data @ .    \ prints 10
1 data @ .    \ prints 20

\ Simple VARIABLE could also use DOES>:
: my-var  create 0 , does> ;
my-var counter
42 counter !
counter @ .   \ prints 42

\ Sized buffer
: buffer:  create allot does> + ;
256 buffer: line
0 line c@ .   \ access first byte
```
