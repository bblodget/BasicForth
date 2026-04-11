# BasicForth — Pictured Numeric Output

Pictured numeric output is the ANS Forth standard mechanism for
converting numbers to strings. It builds strings **right to left**
in a scratch buffer (PAD), extracting digits by repeated division
by BASE.

## Double-Cell Arithmetic Foundation

Pictured output operates on double-cell (128-bit) unsigned numbers.
BasicForth provides these ASM primitives:

| Word     | Stack Effect            | Description                          |
|----------|-------------------------|--------------------------------------|
| S>D      | ( n -- d )              | Sign-extend single to double         |
| UM*      | ( u1 u2 -- ud )         | Unsigned 128-bit multiply            |
| M*       | ( n1 n2 -- d )          | Signed 128-bit multiply              |
| UM/MOD   | ( ud u -- rem quot )    | Unsigned 128/64 divide               |
| SM/REM   | ( d n -- rem quot )     | Symmetric (truncating) signed divide |
| FM/MOD   | ( d n -- rem quot )     | Floored signed divide                |

### Double-Cell Stack Order

The **high** (more significant) word is on **top**, the low word is
deeper:

```
( d-lo d-hi )   where d-hi is TOS
```

So `42 S>D` produces `( 42 0 )` — low=42 deeper, high=0 on top.

### Hardware Support

**x86-64**: All operations use native instructions. `MUL`/`IMUL`
produce 128-bit results in RDX:RAX. `DIV`/`IDIV` divide RDX:RAX
by a 64-bit divisor.

**ARM64**: Multiply uses `MUL` + `UMULH`/`SMULH` (two instructions
for full 128-bit result). Division uses a software binary long
division loop (128 iterations) since ARM64 lacks a 128/64 divide
instruction. A fast path uses hardware `UDIV` when the high word
is zero.

## The PAD Buffer

A 68-byte scratch buffer (`pad`) holds the formatted string. The
`hld` variable points to the current insertion position.

Pictured output builds strings right-to-left: `<#` sets `hld` to
the end of the buffer, and each `HOLD` or `#` decrements `hld`
and stores a character.

## Pictured Output Words

All defined in core.fs:

| Word   | Stack Effect         | Description                              |
|--------|----------------------|------------------------------------------|
| <#     | ( -- )               | Begin conversion: set hld to end of PAD  |
| #      | ( ud -- ud' )        | Extract one digit, HOLD it               |
| #S     | ( ud -- 0 0 )        | Extract all remaining digits             |
| #>     | ( ud -- c-addr u )   | End conversion: return string addr+len   |
| HOLD   | ( char -- )          | Insert character at current position     |
| SIGN   | ( n -- )             | If n < 0, HOLD a minus sign              |
| >DIGIT | ( n -- char )        | Convert 0-35 to ASCII digit (0-9, A-Z)   |

### How # Works

`#` divides a double-cell number by BASE in two steps:

1. Divide the high word by BASE (using `0 ud-hi BASE UM/MOD`)
   → produces `quot-hi` and `rem-hi`
2. Combine `rem-hi` with the low word and divide by BASE
   (using `ud-lo rem-hi BASE UM/MOD`)
   → produces `quot-lo` and the digit remainder

The digit is converted to ASCII via `>DIGIT` and stored via `HOLD`.
The quotient double `( quot-lo quot-hi )` is left on the stack for
the next `#` call.

`#S` loops `#` until the double is zero.

## Formatted Output Words

| Word   | Stack Effect         | Description                              |
|--------|----------------------|------------------------------------------|
| U.     | ( u -- )             | Print unsigned: `0 <# #S #> TYPE SPACE`  |
| .      | ( n -- )             | Print signed using DABS and SIGN         |
| .R     | ( n width -- )       | Right-justified signed print             |
| */MOD  | ( n1 n2 n3 -- r q )  | `M* FM/MOD` (double-width intermediate)  |
| */     | ( n1 n2 n3 -- q )    | `*/MOD NIP`                              |

### Signed Output

`.` and `.R` use `S>D` then `DABS` (double-cell absolute value)
to handle negative numbers, including INT64_MIN which has no
single-cell positive representation. `SIGN` prepends the minus
sign after digit conversion.

```forth
: .   dup >r s>d dabs <# #S r> sign #> type space ;
: .R  >r dup >r s>d dabs <# #S r> sign #> r> over - spaces type ;
```

## Number Base

| Word    | Stack Effect  | Description                       |
|---------|---------------|-----------------------------------|
| BASE    | ( -- addr )   | Push address of BASE variable     |
| DECIMAL | ( -- )        | Set BASE to 10 (uses `#10`)       |
| HEX     | ( -- )        | Set BASE to 16 (uses `$10`)       |

Both DECIMAL and HEX use prefix literals to avoid depending on the
current BASE value.

Input prefixes override BASE for number parsing:
- `$FF` — hexadecimal
- `%1010` — binary
- `#99` — forced decimal

## Examples

```forth
\ Basic output
42 u.              \ 42
-7 .               \ -7

\ Right-justified
42 5 .r            \    42
-42 6 .r           \    -42

\ Hex mode
hex #255 . decimal \ FF

\ Custom formatting — phone number
: .phone  0 <# # # # # 45 hold # # # 45 hold # # # #> type ;
5551234567 .phone  \ 555-123-4567

\ Custom formatting — dollars and cents
: .dollars  0 <# # # 46 hold #S 36 hold #> type ;
12345 .dollars     \ $123.45

\ Leading zeros
: .02  0 <# # # #> type ;
5 .02              \ 05

\ Binary output
: bin 2 base ! ;
bin #42 . decimal  \ 101010
```
