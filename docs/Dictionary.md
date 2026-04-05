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
8         1       Flags+Len   Bit 7 = IMMEDIATE, bit 6 = HIDDEN, bits 0-5 = name length
9         N       Name        Word name (N = length from Flags+Len, max 63 chars)
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
Bit 7 (0x80)  IMMEDIATE   Word executes during compilation instead of being compiled
Bit 6 (0x40)  HIDDEN      Word is invisible to FIND (used during definition)
Bits 0-5      Length       Name length (0-63 characters)
```

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

The static dictionary includes entries for all assembly primitives:

| Entry         | Name     | Code Address   |
|---------------|----------|----------------|
| `dict_dup`    | `dup`    | `forth_dup`    |
| `dict_drop`   | `drop`   | `forth_drop`   |
| `dict_swap`   | `swap`   | `forth_swap`   |
| `dict_over`   | `over`   | `forth_over`   |
| `dict_add`    | `+`      | `forth_add`    |
| `dict_sub`    | `-`      | `forth_sub`    |
| `dict_negate` | `negate` | `forth_negate` |
| `dict_fetch`  | `@`      | `forth_fetch`  |
| `dict_store`  | `!`      | `forth_store`  |
| `dict_cfetch` | `c@`     | `forth_cfetch` |
| `dict_cstore` | `c!`     | `forth_cstore` |
| `dict_emit`   | `emit`   | `forth_emit`   |
| `dict_key`    | `key`    | `forth_key`    |
| `dict_accept` | `accept` | `forth_accept` |
| `dict_number` | `number` | `forth_number` |
| `dict_find`   | `find`   | `forth_find`   |

## FIND

`FIND` searches the dictionary for a word by name.

### Stack Effect

```
( c-addr u -- xt 1 | xt -1 | c-addr u 0 )
```

| Result                 | Stack after        | Meaning               |
|------------------------|--------------------|-----------------------|
| Found, immediate word  | `xt 1`             | Execute even in compile mode |
| Found, normal word     | `xt -1`            | Compile or execute    |
| Not found              | `c-addr u 0`       | Original string preserved |

### Algorithm

1. Start at LATEST (head of linked list)
2. For each entry:
   - Skip if HIDDEN flag is set
   - Compare name lengths (masked with 0x3F)
   - If lengths match, compare names character by character,
     converting both to lowercase (case-insensitive)
3. On match: compute CodePtr offset as `align8(9 + name_len)` from entry
   start, load the execution token, and return it with the IMMEDIATE flag
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
