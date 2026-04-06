# BasicForth — Compiler

The compiler lets users define new words with `: NAME ... ;`.  In compile
mode, the outer interpreter emits native machine code into dictionary space
instead of executing words immediately.  This is the core of Forth's
extensibility — every user-defined word becomes a first-class citizen,
indistinguishable from built-in primitives.

## Subroutine Threaded Code (STC)

BasicForth uses STC — compiled words are sequences of native CALL (x86) or
BL (ARM64) instructions.  Each call targets the code address of the word
being compiled:

```
x86-64:                     ARM64:
  call forth_dup              stp x29, x30, [sp, #-16]!   (prolog)
  call forth_add              bl  forth_dup
  ret                         bl  forth_add
                              ldp x29, x30, [sp], #16     (epilog)
                              ret
```

ARM64 compiled words have a prolog/epilog to save and restore the link
register (X30), because BL overwrites it.  On x86, CALL pushes the return
address onto the hardware stack, so no prolog is needed.

### Instruction Sizes

| Architecture | CALL/BL | RET           | Literal (CALL LIT + value) |
|--------------|---------|---------------|----------------------------|
| x86-64       | 5 bytes | 1 byte        | 13 bytes                   |
| ARM64        | 4 bytes | 4 bytes       | 12 bytes                   |

ARM64 prolog (STP) and epilog (LDP + RET) add 4 + 8 = 12 bytes of overhead
per compiled word.

## STATE Variable

The `state` variable (in `.data`) controls the outer interpreter's behavior:

| Value    | Mode        | Behavior                              |
|----------|-------------|---------------------------------------|
| 0        | Interpreting | Words execute, numbers push to stack |
| non-zero | Compiling    | Words are compiled, numbers become literals |

Only `:` sets state to compiling.  `;` and the error handler reset it to
interpreting.

## Compile-Mode Dispatch

When the outer interpreter finds a word (via FIND), the dispatch depends on
both STATE and the word's IMMEDIATE flag:

```
FIND returns ( xt flag ):
  flag == 0    not found        try NUMBER
  flag != 0    found:
    STATE == 0?                 EXECUTE (always, when interpreting)
    flag == 1  (IMMEDIATE)?     EXECUTE (even in compile mode)
    flag == -1 (normal)?        compile_call (emit CALL/BL to xt)
```

For numbers:

```
NUMBER returns ( n true ):
  STATE == 0?     leave n on stack (interpreting)
  STATE != 0?     compile_literal (emit CALL LIT + inline value)
```

## Defining a Word: `:` and `;`

### COLON (`:`)

When `:` executes, it:

1. Saves LATEST and HERE for error recovery
2. Parses the next word (the new word's name)
3. Aligns HERE to 8 bytes
4. Builds a dictionary header at HERE:
   - Link pointer (8 bytes) = current LATEST
   - Flags+len byte (1 byte) with F_HIDDEN set
   - Name, lowercased (N bytes)
   - Alignment padding to 8 bytes
   - Code pointer (8 bytes) = address where code will start
   - Code length placeholder (4 bytes, filled by `;`)
5. On ARM64: compiles the prolog (`STP X29, X30, [SP, #-16]!`)
6. Updates LATEST to the new entry
7. Sets STATE = compiling

The HIDDEN flag prevents the partially-defined word from being found by
FIND during its own definition.

### SEMICOLON (`;`) — IMMEDIATE

When `;` executes (it runs even in compile mode because it is IMMEDIATE):

1. Guards against use outside compile mode (no-op if STATE == 0)
2. Compiles the epilog:
   - x86: RET (1 byte)
   - ARM64: LDP + RET (8 bytes)
3. Calculates code length = HERE - code start
4. Writes code length to the placeholder reserved by `:`
5. Clears F_HIDDEN on the new entry (makes it findable)
6. Sets STATE = 0 (back to interpreting)

## Inline Literals: LIT

Numbers inside a definition are compiled as inline data using the LIT
primitive.  `compile_literal` emits a CALL/BL to `forth_lit` followed by
the 8-byte value:

```
x86-64 (13 bytes):          ARM64 (12 bytes):
  call forth_lit               bl  forth_lit
  .quad <value>                .quad <value>
```

At runtime, `forth_lit`:

- **x86**: pops the return address (which points to the inline value), reads
  the 8-byte value, pushes it to the data stack, then jumps past the value
  to continue execution.
- **ARM64**: reads the value from X30 (LR points past the BL to the inline
  data), pushes it, advances X30 by 8, and returns to the updated address.

`forth_lit` is marked F_HIDDEN in the dictionary so it cannot be called
directly from the REPL (which would crash, since there is no inline value
to read).

## Execution Token and TICK (`'`)

`'` (TICK) is IMMEDIATE and dual-mode:

- **Interpret mode**: parses the next word, looks it up, pushes its xt
  (code address) to the data stack.
- **Compile mode**: parses the next word at compile time and compiles its
  xt as an inline literal.  This is equivalent to standard Forth's `[']`.

Example:

```
' dup execute       \ interpret: push dup's xt, then execute it
: run-dup ' dup execute ;   \ compile: dup's xt compiled as literal
5 run-dup .         \ prints 5 (dup duplicated 5, then . printed one copy)
```

## Error Recovery

If an error occurs during compilation (e.g., an unknown word), the outer
interpreter:

1. Prints the error message (`? token`)
2. Resets STATE to 0 (interpreting)
3. Restores LATEST and HERE to the values saved by `:` before it started
   building the header

This per-definition rollback ensures that:

- The partial definition is fully discarded (LATEST and HERE rewind)
- Earlier completed definitions on the same line are preserved
- The user returns to a clean interpret-mode prompt

Example:

```
: FOO 42 ; : BAR typo
```

FOO completes successfully.  BAR hits `? typo`, rolls back BAR only.
FOO survives and is callable.

## RWX Segments

Compiled code lives in `dict_space` (`.bss`), which is normally not
executable.  The linker flag `ld -N` (OMAGIC) creates a binary where all
segments are RWX, allowing execution of compiled code.

A future improvement is to use `mprotect` at startup to add PROT_EXEC to
only the dict_space pages, leaving the rest of the binary properly
protected.  See BareMetalForth Lesson 37 for background on memory
protection and JIT compilation.

## Dictionary Chain

The static dictionary includes these compiler-related entries:

| Entry          | Word        | Flags     | Purpose                        |
|----------------|-------------|-----------|--------------------------------|
| dict_lit       | lit         | HIDDEN    | Runtime literal (not callable) |
| dict_colon     | :           | (none)    | Start a new definition         |
| dict_semicolon | ;           | IMMEDIATE | End a definition               |
| dict_immediate | immediate   | (none)    | Mark latest word as immediate  |
| dict_tick      | '           | IMMEDIATE | Find xt / compile xt           |

These are chained after `dict_bye` at the end of the built-in dictionary.

## Compiler Variables

| Variable             | Purpose                                          |
|----------------------|--------------------------------------------------|
| `state`              | 0 = interpreting, non-zero = compiling           |
| `colon_code_len_addr`| Address of code_len field to fill when `;` runs  |
| `saved_latest`       | LATEST before current `:` (for error recovery)   |
| `saved_here`         | HERE before current `:` (for error recovery)     |

## Internal Helpers

These are not in the dictionary — they are called by the compiler
internally:

| Helper            | x86-64        | ARM64         | Purpose                    |
|-------------------|---------------|---------------|----------------------------|
| `compile_call`    | 5 bytes/call  | 4 bytes/call  | Emit CALL/BL at HERE       |
| `compile_ret`     | 1 byte        | 8 bytes       | Emit RET or LDP+RET epilog |
| `compile_literal` | 13 bytes      | 12 bytes      | Emit CALL LIT + 8-byte value |
| `compile_prolog`  | n/a           | 4 bytes       | Emit STP prolog (ARM64 only) |
