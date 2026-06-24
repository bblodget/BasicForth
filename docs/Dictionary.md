# BasicForth — Dictionary

The dictionary is a linked list of word entries that maps names to executable
code. It is the central data structure in a Forth system — every defined word
lives here, from primitives like `DUP` and `+` to user-defined words.

## Entry Layout

Each dictionary entry has a fixed header with variable-length name:

```
Offset    Size    Field
------    ----    -----
0         8       Link        Pointer to previous entry (0 = end of list)
8         1       Flags+Len   Flags (bits 7-5) + name length (bits 4-0)
9         N       Name        Word name (N = length from Flags+Len, max 31 chars)
9+N       pad     Padding     .balign 8 (zero bytes to next 8-byte boundary)
aligned   8       CodePtr     Execution token — address of the code to run
aligned+8 4       CodeLen     Length of code in bytes (0 for ASM primitives)
```

### Alignment

The name is variable-length, so padding is inserted after it to align the
CodePtr field to an 8-byte boundary. This ensures:

- 8-byte pointer loads are naturally aligned on both architectures
- ARM64 code (if inline) starts on a 4-byte boundary (instructions must be
  aligned)

### Flags Byte

```
Bit 7 (0x80)  IMMEDIATE      Word executes during compilation instead of being compiled
Bit 6 (0x40)  HIDDEN         Word is invisible to FIND (used during definition)
Bit 5 (0x20)  COMPILE_ONLY   Word can only be used inside a definition (: ... ;)
Bits 0-4      Length          Name length (0-31 characters)
```

Words can combine flags. For example, IF is both IMMEDIATE and
COMPILE_ONLY — it executes at compile time (not compiled as a call)
and is rejected if used outside a definition.

## Engine Registers

Two dedicated registers track dictionary state:

| Register     | ARM64 | x86-64 | Purpose                            |
|--------------|-------|--------|------------------------------------|
| **LATEST**   | X22   | R12    | Points to most recent dictionary entry |
| **HERE**     | X21   | R13    | Points to next free byte in dictionary space |

Both are callee-saved registers, preserved across C function calls.

## Dictionary Space

A 64KB block of zeroed memory (`dict_space`) is allocated in `.bss` for
user-defined words. HERE starts at the beginning of this space and advances
as new definitions are compiled.

Static (built-in) primitives live in `.data` and are not in the dictionary
space — they are assembled at build time and linked into the binary.

## DEFWORD Macro

Static dictionary entries are created at assembly time using the `DEFWORD`
macro:

```
DEFWORD entry, "name", label, link, flags
```

| Parameter | Description                                      |
|-----------|--------------------------------------------------|
| `entry`   | Assembly label for this entry (e.g., `dict_dup`) |
| `name`    | Forth name string, lowercase (e.g., `"dup"`)     |
| `label`   | Code address (e.g., `forth_dup`)                 |
| `link`    | Previous entry label, or `0` for end of chain    |
| `flags`   | Optional flags byte (default 0)                  |

Entries are chained newest-first. The last entry defined is the head of the
list, pointed to by LATEST.

### Example

```
DEFWORD dict_dup,     "dup",     forth_dup,     0
DEFWORD dict_drop,    "drop",    forth_drop,    dict_dup
DEFWORD dict_swap,    "swap",    forth_swap,    dict_drop
```

This creates three entries: `dict_swap` → `dict_drop` → `dict_dup` → 0.

## Built-in Words

The static dictionary includes entries for all assembly primitives,
chained newest-first via DEFWORD macros in core.s. The chain starts
at `dict_dup` (tail, link=0) and ends at the last DEFWORD entry
(head, pointed to by LATEST). Categories include:

- **Stack**: dup, drop, swap, over, rot, nip, tuck, 2dup, 2drop, depth, ?dup, pick
- **Arithmetic**: +, -, negate, *, /mod, 1+, 1-, abs, min, max
- **Comparison**: =, <, >, 0=, 0<
- **Logic**: and, or, xor, invert
- **Memory**: @, !, c@, c!
- **I/O**: emit, key, accept, type, .", s", write-file
- **File access**: open-file, create-file, close-file, read-file, file-size
- **Return stack**: >r, r>, r@ (COMPILE_ONLY)
- **Compiler**: :, ;, immediate, ', evaluate, included
- **Control flow**: if, then, else, begin, until, again, while, repeat, recurse, do, loop, +loop, i, j, unloop, leave (IMMEDIATE+COMPILE_ONLY)
- **Defining**: here, allot, , (comma), c,, create, constant, does>
- **Scripting**: argc, argv, arg, next-arg, shift-args, bye-code
- **Other**: find, parse-word, execute, ., .s, bye, number, lit (HIDDEN)

See docs/Forth_Core_Words.md for the complete vocabulary with stack effects.

## FIND

`FIND` searches the dictionary for a word by name.

### Stack Effect

```
( c-addr u -- xt flag | c-addr u 0 )
```

| Flag | Meaning                          | Outer interpreter action          |
|------|----------------------------------|-----------------------------------|
|  1   | IMMEDIATE                        | Execute in both modes             |
| -1   | Normal word                      | Execute (interpret) or compile    |
|  2   | IMMEDIATE + COMPILE_ONLY         | Execute in compile mode, reject in interpret mode |
| -2   | COMPILE_ONLY (non-immediate)     | Compile only, reject in interpret mode |
|  0   | Not found                        | Try NUMBER, then error            |

### Algorithm

1. Start at LATEST (head of linked list)
2. For each entry:
   - Skip if HIDDEN flag is set
   - Compare name lengths (masked with 0x1F)
   - If lengths match, compare names character by character,
     converting both to lowercase (case-insensitive)
3. On match: compute CodePtr offset as `align8(9 + name_len)` from entry
   start, load the execution token, and return it with the appropriate flag
   (checks both IMMEDIATE and COMPILE_ONLY bits to determine flag value)
4. On miss: follow the link pointer to the previous entry
5. If link is 0: return 0 with original `c-addr u` preserved

Returning the original string on failure allows the outer interpreter to
fall through to NUMBER parsing — the same pattern NUMBER uses when it
fails (returning the original `c-addr u` for error reporting).

### CodePtr Offset Calculation

Given an entry at address `E` with name length `N`:

```
CodePtr address = E + align8(9 + N)
                = E + ((9 + N + 7) & ~7)
```

The `9` accounts for the 8-byte link field plus the 1-byte flags+len field.

## Execution Tokens

An execution token (xt) is the address stored in the CodePtr field. For
assembly primitives, it points directly to the code in `.text`. For future
compiled words, it will point to inline STC code in the dictionary space.

To execute an xt: load it into a register and call it (`call *%rax` on
x86-64, `BLR X9` on ARM64).
