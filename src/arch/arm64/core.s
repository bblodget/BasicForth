// BasicForth — Core ASM Primitives (ARM64)
// Platform-independent ARM64 assembly. Requires platform_linux.s (or equivalent).
//
// Register allocation:
//   X19 = Data stack pointer (DSP) — points to second item on stack
//   X20 = Top of stack (TOS) — always holds the top value
//   X21 = HERE pointer (dictionary free space) — future
//   X22 = LATEST pointer (most recent dictionary entry) — future
//   SP  = Return stack
//
// TOS-in-register invariant: X20 always holds the top of the data stack.
// DSP (X19) points to the second item. Push = store X20 to memory, set X20.
// Pop = move X20 out, load next from memory into X20.

.equ CELL, 8                    // 64-bit cells
.equ DATA_STACK_SIZE, 4096      // 512 cells

// ---------- Dictionary Entry Layout ----------
// [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4]
//
// Flags byte: bit 7 = IMMEDIATE, bit 6 = HIDDEN, bits 0-5 = name length
.equ F_IMMEDIATE, 0x80
.equ F_HIDDEN,    0x40
.equ F_LENMASK,   0x3F

// DEFWORD entry, name, label, link, flags
//   entry: label for this dictionary entry
//   name:  the Forth name string (lowercase)
//   label: the assembly code address
//   link:  label of previous entry (0 for first)
//   flags: optional flags byte (default 0)
.macro DEFWORD entry, name, label, link, flags=0
.section .data
.balign 8
\entry:
    .quad \link
\entry\()_flags:
    .byte ((\entry\()_name_end - \entry\()_name_start) | \flags)
\entry\()_name_start:
    .ascii "\name"
\entry\()_name_end:
    .balign 8
\entry\()_xt:
    .quad \label
\entry\()_codelen:
    .long 0
    .balign 4
.text
.endm

// ---------- Primitives ----------

// DUP ( a -- a a )
.global forth_dup
forth_dup:
    STR X20, [X19, #-CELL]!    // push TOS to memory
    RET                         // TOS unchanged

// DROP ( a -- )
.global forth_drop
forth_drop:
    LDR X20, [X19], #CELL      // pop next into TOS
    RET

// SWAP ( a b -- b a )
// TOS=b, [DSP]=a → TOS=a, [DSP]=b
.global forth_swap
forth_swap:
    LDR X9, [X19]              // X9 = a
    STR X20, [X19]             // [DSP] = b
    MOV X20, X9                // TOS = a
    RET

// OVER ( a b -- a b a )
// TOS=b, [DSP]=a → push b, TOS=a
.global forth_over
forth_over:
    STR X20, [X19, #-CELL]!   // push b to memory
    LDR X20, [X19, #CELL]     // TOS = a (one cell below new DSP)
    RET

// + ( a b -- a+b )
// TOS=b, [DSP]=a → TOS=a+b
.global forth_add
forth_add:
    LDR X9, [X19], #CELL      // X9 = a, pop
    ADD X20, X9, X20           // TOS = a + b
    RET

// - ( a b -- a-b )
// TOS=b, [DSP]=a → TOS=a-b
.global forth_sub
forth_sub:
    LDR X9, [X19], #CELL      // X9 = a, pop
    SUB X20, X9, X20           // TOS = a - b
    RET

// NEGATE ( a -- -a )
.global forth_negate
forth_negate:
    NEG X20, X20               // negate TOS
    RET

// ---------- Memory ----------

// @ (fetch) ( addr -- x )
// Read 8-byte cell from address
.global forth_fetch
forth_fetch:
    LDR X20, [X20]              // TOS = [TOS]
    RET

// ! (store) ( x addr -- )
// Write 8-byte cell to address
.global forth_store
forth_store:
    LDR X9, [X19], #CELL        // X9 = x, pop
    STR X9, [X20]               // [addr] = x
    LDR X20, [X19], #CELL       // pop new TOS
    RET

// C@ (char fetch) ( addr -- byte )
// Read 1 byte from address, zero-extended
.global forth_cfetch
forth_cfetch:
    LDRB W9, [X20]              // W9 = byte (zero-extended)
    MOV X20, X9                 // TOS = byte
    RET

// C! (char store) ( byte addr -- )
// Write 1 byte to address
.global forth_cstore
forth_cstore:
    LDR X9, [X19], #CELL        // X9 = byte, pop
    STRB W9, [X20]              // [addr] = low byte
    LDR X20, [X19], #CELL       // pop new TOS
    RET

// ---------- EMIT (Forth-level) ----------
// ( char -- )
// TOS = char. Pass to platform_emit, pop new TOS.
.global forth_emit
forth_emit:
    MOV X0, X20                // X0 = char (from TOS)
    LDR X20, [X19], #CELL     // pop new TOS
    B platform_emit            // tail call (X30 untouched)

// ---------- KEY (Forth-level) ----------
// ( -- char )
// Push old TOS, call platform_key, TOS = result.
.global forth_key
forth_key:
    STR X30, [SP, #-16]!      // save return address
    STR X20, [X19, #-CELL]!   // push old TOS to memory
    BL platform_key            // X0 = character
    MOV X20, X0                // TOS = char
    LDR X30, [SP], #16        // restore return address
    RET

// ---------- ACCEPT (Forth-level) ----------
// ( c-addr +n1 -- +n2 )
// Read a line from stdin into buffer at c-addr, max n1 chars.
// Handles backspace editing and echo. Returns actual count.
// Calls platform_key and platform_emit directly (register level).
.global forth_accept
forth_accept:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Pop args from data stack: TOS = max_len, [DSP] = buf_addr
    MOV X24, X20                // X24 = max_len
    LDR X23, [X19], #CELL      // X23 = buf_addr
    MOV X25, #0                 // X25 = count

.Laccept_loop:
    BL platform_key             // X0 = char

    // Check for LF (Enter)
    CMP X0, #10
    B.EQ .Laccept_done

    // Check for BS (8) or DEL (127)
    CMP X0, #8
    B.EQ .Laccept_bs
    CMP X0, #127
    B.EQ .Laccept_bs

    // Ignore non-printable (< 32 or > 126)
    CMP X0, #32
    B.LO .Laccept_loop
    CMP X0, #126
    B.HI .Laccept_loop

    // Buffer full?
    CMP X25, X24
    B.GE .Laccept_loop

    // Store char and echo
    STRB W0, [X23, X25]        // buf[count] = char
    ADD X25, X25, #1            // count++
    BL platform_emit            // echo (X0 still has char)
    B .Laccept_loop

.Laccept_bs:
    // Ignore backspace if buffer empty
    CBZ X25, .Laccept_loop
    SUB X25, X25, #1            // count--
    // Erase on screen: \b space \b
    MOV X0, #8
    BL platform_emit
    MOV X0, #32
    BL platform_emit
    MOV X0, #8
    BL platform_emit
    B .Laccept_loop

.Laccept_done:
    // Echo the newline
    MOV X0, #10
    BL platform_emit

    // Push result: TOS = count
    MOV X20, X25

    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- NUMBER (Forth-level) ----------
// ( c-addr u -- n true | c-addr u false )
// Try to parse string as a number. Supports:
//   - Decimal (default, or # prefix)
//   - Hex ($ prefix)
//   - Binary (% prefix)
//   - Negative sign before or after prefix (-$FF or $-FF)
//   - Case-insensitive hex digits (a-f, A-F)
// Uses BASE variable for default base.
.global forth_number
forth_number:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    STP X27, X28, [SP, #-16]!

    // Pop args: TOS = len, [DSP] = addr
    MOV X24, X20                // X24 = len
    LDR X23, [X19], #CELL      // X23 = addr
    // Save original addr/len for failure case
    MOV X27, X23                // X27 = orig addr
    MOV X28, X24                // X28 = orig len

    // Empty string is not a number
    CBZ X24, .Lnum_fail

    MOV X25, #0                 // X25 = result
    MOV X26, #0                 // X26 = negate flag
    ADR X9, base
    LDR X10, [X9]               // X10 = base

    // Check for leading '-'
    LDRB W9, [X23]
    CMP W9, #'-'
    B.NE .Lnum_check_prefix
    ADD X23, X23, #1
    SUB X24, X24, #1
    MOV X26, #1                 // set negate flag
    CBZ X24, .Lnum_fail

.Lnum_check_prefix:
    LDRB W9, [X23]
    CMP W9, #'$'
    B.EQ .Lnum_hex
    CMP W9, #'#'
    B.EQ .Lnum_decimal
    CMP W9, #'%'
    B.EQ .Lnum_binary
    B .Lnum_check_sign_after

.Lnum_hex:
    MOV X10, #16
    B .Lnum_consume_prefix
.Lnum_decimal:
    MOV X10, #10
    B .Lnum_consume_prefix
.Lnum_binary:
    MOV X10, #2
.Lnum_consume_prefix:
    ADD X23, X23, #1
    SUB X24, X24, #1
    CBZ X24, .Lnum_fail

.Lnum_check_sign_after:
    // Check for '-' after prefix (e.g., $-FF)
    CBNZ X26, .Lnum_parse       // already have sign
    LDRB W9, [X23]
    CMP W9, #'-'
    B.NE .Lnum_parse
    ADD X23, X23, #1
    SUB X24, X24, #1
    MOV X26, #1
    CBZ X24, .Lnum_fail

.Lnum_parse:
    // X23 = current char ptr, X24 = remaining len
    // X25 = result, X10 = base, X26 = negate flag
.Lnum_loop:
    CBZ X24, .Lnum_done
    LDRB W9, [X23]

    // Convert char to digit value
    CMP W9, #'0'
    B.LO .Lnum_fail
    CMP W9, #'9'
    B.LS .Lnum_digit_09

    CMP W9, #'A'
    B.LO .Lnum_fail
    CMP W9, #'Z'
    B.LS .Lnum_letter_upper

    CMP W9, #'a'
    B.LO .Lnum_fail
    CMP W9, #'z'
    B.HI .Lnum_fail

    // Lowercase letter
    SUB W9, W9, #('a' - 10)
    B .Lnum_check_digit

.Lnum_letter_upper:
    SUB W9, W9, #('A' - 10)
    B .Lnum_check_digit

.Lnum_digit_09:
    SUB W9, W9, #'0'

.Lnum_check_digit:
    // Check digit < base
    CMP X9, X10
    B.GE .Lnum_fail

    // result = result * base + digit
    MUL X25, X25, X10
    ADD X25, X25, X9

    ADD X23, X23, #1
    SUB X24, X24, #1
    B .Lnum_loop

.Lnum_done:
    // Apply negate
    CBZ X26, .Lnum_success
    NEG X25, X25

.Lnum_success:
    // Push n and true: ( -- n true )
    STR X25, [X19, #-CELL]!    // push n to memory
    MOV X20, #-1                // TOS = true (-1)
    B .Lnum_exit

.Lnum_fail:
    // Push c-addr, u, and false: ( -- c-addr u false )
    STR X27, [X19, #-CELL]!    // push c-addr
    STR X28, [X19, #-CELL]!    // push u
    MOV X20, #0                 // TOS = false

.Lnum_exit:
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- FIND (Forth-level) ----------
// ( c-addr u -- xt 1 | xt -1 | c-addr u 0 )
// Search dictionary for word by name. Case-insensitive.
// Returns: xt and 1 (immediate), xt and -1 (normal), or
//          original c-addr u and 0 (not found).
.global forth_find
forth_find:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Pop args: TOS = u (length), [DSP] = c-addr
    MOV X24, X20                // X24 = search length
    LDR X23, [X19], #CELL      // X23 = search c-addr

    MOV X25, X22                // X25 = current entry (start at LATEST)

.Lfind_loop:
    CBZ X25, .Lfind_not_found

    // Check HIDDEN flag
    LDRB W9, [X25, #8]          // flags+len byte (offset 8 past link)
    TST W9, #F_HIDDEN
    B.NE .Lfind_next

    // Save flags byte for IMMEDIATE check on match
    MOV W26, W9                  // W26 = flags+len byte

    // Compare lengths
    AND W10, W9, #F_LENMASK     // W10 = entry name length
    CMP X10, X24
    B.NE .Lfind_next

    // Lengths match — compare names case-insensitively
    ADD X11, X25, #9             // X11 = entry name ptr
    MOV X12, X23                 // X12 = search name ptr
    MOV X13, X24                 // X13 = remaining count

.Lfind_cmp:
    CBZ X13, .Lfind_match

    LDRB W14, [X12], #1         // search char (post-increment)
    CMP W14, #'A'
    B.LO .Lfind_s_done
    CMP W14, #'Z'
    B.HI .Lfind_s_done
    ADD W14, W14, #32
.Lfind_s_done:

    LDRB W15, [X11], #1         // entry char (post-increment)
    CMP W15, #'A'
    B.LO .Lfind_e_done
    CMP W15, #'Z'
    B.HI .Lfind_e_done
    ADD W15, W15, #32
.Lfind_e_done:

    CMP W14, W15
    B.NE .Lfind_next

    SUB X13, X13, #1
    B .Lfind_cmp

.Lfind_match:
    // CodePtr is at offset align8(9 + name_len) from entry start
    ADD X9, X24, #(9 + 7)       // 9 + len + 7
    AND X9, X9, #~7             // round down to 8-byte boundary
    // Push xt, set TOS to immediate flag
    LDR X9, [X25, X9]           // X9 = xt
    STR X9, [X19, #-CELL]!      // push xt to memory
    // Check IMMEDIATE flag
    TST W26, #F_IMMEDIATE
    B.EQ .Lfind_normal
    MOV X20, #1                  // TOS = 1 (immediate)
    B .Lfind_done
.Lfind_normal:
    MOV X20, #-1                 // TOS = -1 (normal, using MOV with inverted)
    B .Lfind_done

.Lfind_next:
    LDR X25, [X25]              // follow link
    B .Lfind_loop

.Lfind_not_found:
    // Return original c-addr u 0: push c-addr and u back, TOS = 0
    STR X23, [X19, #-CELL]!     // push c-addr
    STR X24, [X19, #-CELL]!     // push u
    MOV X20, #0                  // TOS = 0

.Lfind_done:
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- Static Dictionary ----------

DEFWORD dict_dup,     "dup",     forth_dup,     0
DEFWORD dict_drop,    "drop",    forth_drop,    dict_dup
DEFWORD dict_swap,    "swap",    forth_swap,    dict_drop
DEFWORD dict_over,    "over",    forth_over,    dict_swap
DEFWORD dict_add,     "+",       forth_add,     dict_over
DEFWORD dict_sub,     "-",       forth_sub,     dict_add
DEFWORD dict_negate,  "negate",  forth_negate,  dict_sub
DEFWORD dict_fetch,   "@",       forth_fetch,   dict_negate
DEFWORD dict_store,   "!",       forth_store,   dict_fetch
DEFWORD dict_cfetch,  "c@",      forth_cfetch,  dict_store
DEFWORD dict_cstore,  "c!",      forth_cstore,  dict_cfetch
DEFWORD dict_emit,    "emit",    forth_emit,    dict_cstore
DEFWORD dict_key,     "key",     forth_key,     dict_emit
DEFWORD dict_accept,  "accept",  forth_accept,  dict_key
DEFWORD dict_number,  "number",  forth_number,  dict_accept
DEFWORD dict_find,    "find",    forth_find,    dict_number
.global dict_find

// ---------- Data Stack Memory ----------
.bss
.align 4
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:

// ---------- Dictionary Space ----------
.equ DICT_SPACE_SIZE, 65536     // 64KB
.balign 8
.global dict_space
dict_space:
    .space DICT_SPACE_SIZE

// ---------- Variables ----------
.data
.align 3
.global base
base:
    .quad 10
.global source_addr
source_addr:
    .quad 0
.global source_len
source_len:
    .quad 0
.global to_in
to_in:
    .quad 0
.global sp0
sp0:
    .quad 0
