// BasicForth — Core ASM Primitives (ARM64)
// Copyright (C) 2026 Brandon Blodget
// SPDX-License-Identifier: GPL-2.0-only
//
// Platform-independent ARM64 assembly. Requires platform_linux.s (or equivalent).
//
// Register allocation:
//   X19 = Data stack pointer (DSP) — points to top item on stack
//         (equals sp0 when stack is empty)
//   X20 = scratch (available — no longer used for TOS)
//   X21 = HERE pointer (dictionary free space)
//   X22 = LATEST pointer (most recent dictionary entry)
//   SP  = Return stack
//
// Pure memory stack: all data stack items live in memory.
// DSP (X19) points to the topmost item. Push = decrement X19, store.
// Pop = load from X19, increment X19. Depth = (sp0 - DSP) / CELL.
//
// X19-X28 are callee-saved in the AAPCS64 ABI,
// so C functions won't clobber them.

.equ CELL, 8                    // 64-bit cells
.equ DATA_STACK_SIZE, 4096      // 512 cells

// ---------- Dictionary Entry Layout ----------
// [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4]
//
// Flags byte: bit 7 = IMMEDIATE, bit 6 = HIDDEN, bits 0-5 = name length
.equ F_IMMEDIATE,   0x80
.equ F_HIDDEN,      0x40
.equ F_COMPILE_ONLY,0x20
.equ F_LENMASK,     0x1F


// CHECK_DICT n: verify HERE + n bytes fits in dict_space.
// Always active — dictionary has no guard page.  Clobbers X9, X10.
.macro CHECK_DICT n
    ADR X9, dict_space_end
    ADD X10, X21, #\n
    CMP X10, X9
    B.HI dict_full
.endm

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


    LDR X9, [X19]
    STR X9, [X19, #-CELL]!
    RET

// DROP ( a -- )
.global forth_drop
forth_drop:
    LDR X9, [X19]              // touch top item (triggers guard page if empty)
    ADD X19, X19, #CELL
    RET

// SWAP ( a b -- b a )
.global forth_swap
forth_swap:

    LDR X9, [X19]              // b (top)
    LDR X10, [X19, #CELL]     // a (second)
    STR X10, [X19]             // top = a
    STR X9, [X19, #CELL]      // second = b
    RET

// OVER ( a b -- a b a )
.global forth_over
forth_over:


    LDR X9, [X19, #CELL]      // a (second item)
    STR X9, [X19, #-CELL]!    // push a
    RET

// ROT ( a b c -- b c a )
.global forth_rot
forth_rot:

    LDR X9, [X19]              // X9 = c
    LDR X10, [X19, #CELL]      // X10 = b
    LDR X11, [X19, #2*CELL]    // X11 = a
    STR X10, [X19, #2*CELL]    // bottom = b
    STR X9, [X19, #CELL]       // middle = c
    STR X11, [X19]             // top = a
    RET

// NIP ( a b -- b )
.global forth_nip
forth_nip:

    LDR X9, [X19], #CELL       // pop b
    STR X9, [X19]              // top = b
    RET

// TUCK ( a b -- b a b )
.global forth_tuck
forth_tuck:

    LDR X9, [X19]              // X9 = b
    LDR X10, [X19, #CELL]      // X10 = a
    STR X9, [X19, #CELL]       // second = b (will become bottom)
    SUB X19, X19, #CELL         // make room
    STR X9, [X19]              // top = b
    STR X10, [X19, #CELL]      // middle = a
    RET

// 2DUP ( a b -- a b a b )
.global forth_two_dup
forth_two_dup:

    LDR X9, [X19]              // X9 = b
    LDR X10, [X19, #CELL]      // X10 = a
    SUB X19, X19, #2*CELL       // make room for 2
    STR X9, [X19]              // top = b
    STR X10, [X19, #CELL]      // second = a
    RET

// 2DROP ( a b -- )
.global forth_two_drop
forth_two_drop:

    LDR X9, [X19]              // touch top (guard page trigger)
    LDR X9, [X19, #CELL]       // touch second (guard page trigger)
    ADD X19, X19, #2*CELL
    RET

// DEPTH ( -- n )
.global forth_depth
forth_depth:

    ADR X9, sp0
    LDR X9, [X9]               // X9 = sp0
    SUB X9, X9, X19            // X9 = sp0 - DSP (bytes)
    ASR X9, X9, #3             // X9 = depth (cells)
    STR X9, [X19, #-CELL]!     // push depth
    RET

// ?DUP ( x -- x x | 0 )
.global forth_question_dup
forth_question_dup:

    LDR X9, [X19]
    CBZ X9, 1f
    STR X9, [X19, #-CELL]!     // push copy if non-zero
1:  RET

// >R ( x -- ) ( R: -- x )
// Move top of data stack to return stack.
// ARM64: BL puts return address in X30, not on SP, so we can push directly.
// Uses 16-byte slots to maintain SP alignment.
// Marked F_COMPILE_ONLY — outer interpreter rejects in interpret mode.
.global forth_to_r
forth_to_r:

    LDR X9, [X19], #CELL       // pop x from data stack
    STR X9, [SP, #-16]!        // push x to return stack (16-byte aligned)
    RET

// R> ( -- x ) ( R: x -- )
// Move top of return stack to data stack.
.global forth_r_from
forth_r_from:

    LDR X9, [SP], #16          // pop x from return stack
    STR X9, [X19, #-CELL]!     // push x to data stack
    RET

// R@ ( -- x ) ( R: x -- x )
// Copy top of return stack to data stack (non-destructive).
.global forth_r_fetch
forth_r_fetch:

    LDR X9, [SP]               // peek x from return stack
    STR X9, [X19, #-CELL]!     // push x to data stack
    RET

// + ( a b -- a+b )
.global forth_add
forth_add:

    LDR X9, [X19], #CELL      // pop b
    LDR X10, [X19]             // a
    ADD X10, X10, X9
    STR X10, [X19]             // top = a+b
    RET

// - ( a b -- a-b )
.global forth_sub
forth_sub:

    LDR X9, [X19], #CELL      // pop b
    LDR X10, [X19]             // a
    SUB X10, X10, X9
    STR X10, [X19]             // top = a-b
    RET

// NEGATE ( a -- -a )
.global forth_negate
forth_negate:

    LDR X9, [X19]
    NEG X9, X9
    STR X9, [X19]
    RET

// * ( a b -- a*b )
.global forth_mul
forth_mul:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    MUL X10, X10, X9
    STR X10, [X19]              // top = a*b
    RET

// /MOD ( a b -- rem quot )
// Division by zero returns 0 0.
.global forth_divmod
forth_divmod:

    LDR X9, [X19]              // X9 = b (divisor)
    CBZ X9, .Ldivmod_zero
    LDR X10, [X19, #CELL]      // X10 = a (dividend)
    SDIV X11, X10, X9           // X11 = quot = a / b
    MSUB X12, X11, X9, X10     // X12 = rem = a - quot*b
    STR X12, [X19, #CELL]      // second = rem
    STR X11, [X19]             // top = quot
    RET
.Ldivmod_zero:
    STR XZR, [X19, #CELL]      // rem = 0
    STR XZR, [X19]             // quot = 0
    RET

// 1+ ( a -- a+1 )
.global forth_one_plus
forth_one_plus:

    LDR X9, [X19]
    ADD X9, X9, #1
    STR X9, [X19]
    RET

// 1- ( a -- a-1 )
.global forth_one_minus
forth_one_minus:

    LDR X9, [X19]
    SUB X9, X9, #1
    STR X9, [X19]
    RET

// ABS ( n -- |n| )
.global forth_abs
forth_abs:

    LDR X9, [X19]
    CMP X9, #0
    CNEG X9, X9, LT            // negate if negative
    STR X9, [X19]
    RET

// MIN ( a b -- min )
.global forth_min
forth_min:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    CMP X10, X9
    CSEL X10, X10, X9, LE      // X10 = (a <= b) ? a : b
    STR X10, [X19]
    RET

// MAX ( a b -- max )
.global forth_max
forth_max:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    CMP X10, X9
    CSEL X10, X10, X9, GE      // X10 = (a >= b) ? a : b
    STR X10, [X19]
    RET

// = ( a b -- flag )
.global forth_equal
forth_equal:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    CMP X10, X9
    CSETM X10, EQ              // -1 if equal, 0 otherwise
    STR X10, [X19]
    RET

// < ( a b -- flag )
.global forth_less
forth_less:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    CMP X10, X9
    CSETM X10, LT              // -1 if a < b, 0 otherwise
    STR X10, [X19]
    RET

// > ( a b -- flag )
.global forth_greater
forth_greater:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    CMP X10, X9
    CSETM X10, GT              // -1 if a > b, 0 otherwise
    STR X10, [X19]
    RET

// 0= ( a -- flag )
.global forth_zero_equal
forth_zero_equal:

    LDR X9, [X19]
    CMP X9, #0
    CSETM X9, EQ               // -1 if zero, 0 otherwise
    STR X9, [X19]
    RET

// 0< ( a -- flag )
.global forth_zero_less
forth_zero_less:

    LDR X9, [X19]
    ASR X9, X9, #63            // -1 if negative, 0 if non-negative
    STR X9, [X19]
    RET

// AND ( a b -- a&b )
.global forth_and
forth_and:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    AND X10, X10, X9
    STR X10, [X19]
    RET

// OR ( a b -- a|b )
.global forth_or
forth_or:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    ORR X10, X10, X9
    STR X10, [X19]
    RET

// XOR ( a b -- a^b )
.global forth_xor
forth_xor:

    LDR X9, [X19], #CELL       // pop b
    LDR X10, [X19]              // a
    EOR X10, X10, X9
    STR X10, [X19]
    RET

// INVERT ( a -- ~a )
.global forth_invert
forth_invert:

    LDR X9, [X19]
    MVN X9, X9
    STR X9, [X19]
    RET

// ---------- Memory ----------

// @ (fetch) ( addr -- x )
// Read 8-byte cell from address
.global forth_fetch
forth_fetch:

    LDR X9, [X19]              // addr
    LDR X9, [X9]               // [addr]
    STR X9, [X19]              // replace top
    RET

// ! (store) ( x addr -- )
// Write 8-byte cell to address
.global forth_store
forth_store:

    LDR X9, [X19], #CELL      // pop addr
    LDR X10, [X19], #CELL     // pop x
    STR X10, [X9]              // [addr] = x
    RET

// C@ (char fetch) ( addr -- byte )
// Read 1 byte from address, zero-extended
.global forth_cfetch
forth_cfetch:

    LDR X9, [X19]
    LDRB W9, [X9]
    STR X9, [X19]
    RET

// C! (char store) ( byte addr -- )
// Write 1 byte to address
.global forth_cstore
forth_cstore:

    LDR X9, [X19], #CELL      // pop addr
    LDR X10, [X19], #CELL     // pop byte
    STRB W10, [X9]
    RET

// ---------- EMIT (Forth-level) ----------
// ( char -- )
.global forth_emit
forth_emit:

    LDR X0, [X19], #CELL      // pop char
    B platform_emit            // tail call

// ---------- KEY (Forth-level) ----------
// ( -- char )
.global forth_key
forth_key:

    STP X29, X30, [SP, #-16]!
    BL platform_key            // X0 = character
    STR X0, [X19, #-CELL]!    // push char
    LDP X29, X30, [SP], #16
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

    // Pop args from data stack: top = max_len, second = buf_addr
    LDR X24, [X19], #CELL      // X24 = max_len (top)
    LDR X23, [X19], #CELL      // X23 = buf_addr (second)
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

    // Push result: count
    STR X25, [X19, #-CELL]!

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

    // Pop args: top = len, second = addr
    LDR X24, [X19], #CELL      // X24 = len (top)
    LDR X23, [X19], #CELL      // X23 = addr (second)
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
    STR X25, [X19, #-CELL]!    // push n
    MOV X9, #-1
    STR X9, [X19, #-CELL]!     // push true (-1)
    B .Lnum_exit

.Lnum_fail:
    // Push c-addr, u, and false: ( -- c-addr u false )
    STR X27, [X19, #-CELL]!    // push c-addr
    STR X28, [X19, #-CELL]!    // push u
    STR XZR, [X19, #-CELL]!    // push false (0)

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

    // Pop args: top = u (length), second = c-addr
    LDR X24, [X19], #CELL      // X24 = search length (top)
    LDR X23, [X19], #CELL      // X23 = search c-addr (second)

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
    // Push xt and flag
    LDR X9, [X25, X9]           // X9 = xt
    STR X9, [X19, #-CELL]!      // push xt
    // Check flags: IMMEDIATE, COMPILE_ONLY, or normal
    TST W26, #F_IMMEDIATE
    B.NE .Lfind_immediate
    TST W26, #F_COMPILE_ONLY
    B.NE .Lfind_compile_only
    MOV X9, #-1
    STR X9, [X19, #-CELL]!      // push -1 (normal)
    B .Lfind_done
.Lfind_immediate:
    MOV X9, #1
    STR X9, [X19, #-CELL]!      // push 1 (immediate)
    B .Lfind_done
.Lfind_compile_only:
    MOV X9, #-2
    STR X9, [X19, #-CELL]!      // push -2 (compile-only)
    B .Lfind_done

.Lfind_next:
    LDR X25, [X25]              // follow link
    B .Lfind_loop

.Lfind_not_found:
    // Return original c-addr u 0
    STR X23, [X19, #-CELL]!     // push c-addr
    STR X24, [X19, #-CELL]!     // push u
    STR XZR, [X19, #-CELL]!     // push 0

.Lfind_done:
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- PARSE-WORD (Forth-level) ----------
// ( -- c-addr u )
// Extract next space-delimited token from the input buffer.
// Reads source_addr, source_len, to_in globals.
// Returns 0 0 if no more tokens.
.global forth_parse_word
forth_parse_word:

    // Load globals
    ADR X9, source_addr
    LDR X10, [X9]                // X10 = buffer base
    ADR X9, source_len
    LDR X11, [X9]                // X11 = total length
    ADR X9, to_in
    LDR X12, [X9]                // X12 = current offset

    // Skip leading spaces
.Lpw_skip:
    CMP X12, X11
    B.GE .Lpw_empty
    LDRB W13, [X10, X12]
    CMP W13, #' '
    B.NE .Lpw_found
    ADD X12, X12, #1
    B .Lpw_skip

.Lpw_empty:
    ADR X9, to_in
    STR X12, [X9]
    // Push 0 0
    STR XZR, [X19, #-CELL]!      // c-addr = 0
    STR XZR, [X19, #-CELL]!      // u = 0
    RET

.Lpw_found:
    ADD X14, X10, X12             // X14 = start of word

    // Scan to end of word
.Lpw_scan:
    CMP X12, X11
    B.GE .Lpw_done
    LDRB W13, [X10, X12]
    CMP W13, #' '
    B.EQ .Lpw_done
    ADD X12, X12, #1
    B .Lpw_scan

.Lpw_done:
    ADR X9, to_in
    STR X12, [X9]                 // update to_in
    // len = current position - start
    ADD X15, X10, X12
    SUB X15, X15, X14             // X15 = length
    // Push c-addr and u (c-addr second, u on top)
    STR X14, [X19, #-CELL]!       // push c-addr
    STR X15, [X19, #-CELL]!       // push u (on top)
    RET

// ---------- EXECUTE (Forth-level) ----------
// ( xt -- )
// Call the execution token. Tail-call: word's RET returns to our caller.
.global forth_execute
forth_execute:

    LDR X9, [X19], #CELL         // pop xt
    BR X9                         // tail-call

// ---------- print_signed (internal helper) ----------
// Print signed 64-bit integer from X0 to stdout.
// Uses stack buffer. Clobbers X0-X4, X9-X15.
// Caller must save X30 if needed.
.Lprint_signed:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #32             // digit buffer

    MOV X9, X0                  // X9 = number

    // Handle negative
    MOV X11, #0                 // sign flag
    CMP X9, #0
    B.GE .Lps_positive
    NEG X9, X9
    MOV X11, #1
.Lps_positive:

    // Build digits right-to-left
    ADD X12, SP, #31            // X12 = end of buffer
    MOV X13, X12                // X13 = current position
    MOV X14, #10                // divisor

    // Handle zero
    CBNZ X9, .Lps_divloop
    SUB X13, X13, #1
    MOV W10, #'0'
    STRB W10, [X13]
    B .Lps_sign

.Lps_divloop:
    CBZ X9, .Lps_sign
    UDIV X10, X9, X14           // X10 = quotient
    MSUB X15, X10, X14, X9      // X15 = remainder
    ADD W15, W15, #'0'
    SUB X13, X13, #1
    STRB W15, [X13]
    MOV X9, X10
    B .Lps_divloop

.Lps_sign:
    CBZ X11, .Lps_print
    SUB X13, X13, #1
    MOV W10, #'-'
    STRB W10, [X13]

.Lps_print:
    // Print via platform_write(buf, len)
    MOV X0, X13                 // buf = start
    SUB X1, X12, X13            // len = end - start
    BL platform_write

    ADD SP, SP, #32
    LDP X29, X30, [SP], #16
    RET

// ---------- DOT (Forth-level) ----------
// ( n -- )
// Print top of stack as signed decimal with trailing space.
.global forth_dot
forth_dot:

    STP X29, X30, [SP, #-16]!
    LDR X0, [X19], #CELL       // pop n
    BL .Lprint_signed
    MOV X0, #' '
    BL platform_emit
    LDP X29, X30, [SP], #16
    RET

// ---------- DOT-S (Forth-level) ----------
// ( -- )
// Print stack contents non-destructively as <depth> item1 item2 ...
.global forth_dot_s
forth_dot_s:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!

    // Compute depth = (sp0 - DSP) / CELL
    ADR X9, sp0
    LDR X23, [X9]               // X23 = sp0
    SUB X23, X23, X19           // X23 = sp0 - DSP (byte diff)
    ASR X23, X23, #3            // X23 = depth

    // Print '<'
    MOV X0, #'<'
    BL platform_emit

    // Print depth
    MOV X0, X23
    BL .Lprint_signed

    // Print '> '
    MOV X0, #'>'
    BL platform_emit
    MOV X0, #' '
    BL platform_emit

    // If depth <= 0, nothing to print
    CMP X23, #0
    B.LE .Lds_done

    // Walk from bottom (DSP + (depth-1)*CELL) to top (DSP)
    SUB X24, X23, #1
    LSL X24, X24, #3            // X24 = (depth-1)*CELL
    ADD X24, X19, X24           // X24 = bottom item address

.Lds_loop:
    CMP X24, X19                // X24 >= DSP?
    B.LO .Lds_done
    LDR X0, [X24]               // load stack item
    BL .Lprint_signed
    MOV X0, #' '
    BL platform_emit
    SUB X24, X24, #CELL
    B .Lds_loop

.Lds_done:
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- BYE (Forth-level) ----------
// ( -- )
// Restore terminal and exit.
.global forth_bye
forth_bye:
    ADR X0, bye_msg
    MOV X1, #bye_len
    BL platform_write
    B platform_bye

.section .rodata
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg
.text

// ---------- LIT (runtime) ----------
// Pushes the inline 8-byte value that follows the BL to forth_lit.
// At runtime, X30 (LR) points to the inline data.  We read the value,
// advance past it, and continue.
//
// Compiled code layout:
//   BL forth_lit        (4 bytes)
//   .quad <value>       (8 bytes)
//   <next instruction>
//
.global forth_lit
forth_lit:

    LDR X9, [X30]                  // inline value (LR points to it)
    STR X9, [X19, #-CELL]!        // push to stack
    ADD X30, X30, #CELL            // skip past value
    RET                            // continue execution (jumps to updated LR)

// ---------- compile_call (internal) ----------
// Compile a BL instruction at HERE to the address in X0.
// Advances HERE (X21) by 4 bytes.
// Clobbers X9, X10.
.global compile_call
compile_call:
    CHECK_DICT 4
    SUB X9, X0, X21                // X9 = offset in bytes
    ASR X9, X9, #2                 // X9 = offset in words (BL uses word offset)
    AND X9, X9, #0x3FFFFFF         // mask to 26 bits
    MOV X10, #0x94000000           // BL opcode
    ORR X10, X10, X9               // BL with offset
    STR W10, [X21]                 // write instruction at HERE
    ADD X21, X21, #4               // advance HERE
    RET

// ---------- compile_prolog (internal) ----------
// Compile STP X29, X30, [SP, #-16]! at HERE.  Advances HERE by 4 bytes.
// This saves the link register so BL instructions within the compiled
// word don't clobber the return address.
// Clobbers X9.
.global compile_prolog
compile_prolog:
    CHECK_DICT 4
    // STP X29, X30, [SP, #-16]! = 0xA9BF7BFD
    MOV W9, #0x7BFD
    MOVK W9, #0xA9BF, LSL #16
    STR W9, [X21]
    ADD X21, X21, #4
    RET

// ---------- compile_ret (internal) ----------
// Compile the epilog: LDP X29, X30, [SP], #16 + RET.
// Advances HERE by 8 bytes.
// Clobbers X9.
.global compile_ret
compile_ret:
    CHECK_DICT 8
    // LDP X29, X30, [SP], #16 = 0xA8C17BFD
    MOV W9, #0x7BFD
    MOVK W9, #0xA8C1, LSL #16
    STR W9, [X21]
    ADD X21, X21, #4
    // RET = 0xD65F03C0
    MOV W9, #0x03C0
    MOVK W9, #0xD65F, LSL #16
    STR W9, [X21]
    ADD X21, X21, #4
    RET

// ---------- compile_literal (internal) ----------
// Compile a BL to forth_lit followed by an 8-byte inline value.
// Value is taken from X0.  Advances HERE by 12 bytes.
// Clobbers X9, X10.
.global compile_literal
compile_literal:
    CHECK_DICT 12
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    MOV X23, X0                    // save the literal value (callee-saved)
    ADR X0, forth_lit              // target = forth_lit
    BL compile_call                // emit BL forth_lit (4 bytes)
    STR X23, [X21]                 // emit inline 8-byte value
    ADD X21, X21, #CELL            // advance HERE past value
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- COLON (Forth-level) ----------
// ( -- )
// Parse the next word, create a dictionary header at HERE, and enter
// compile mode.  The new entry is marked HIDDEN until ; completes it.
//
// Dictionary entry layout built here:
//   [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4] [pad to 4]
//   Then HERE points to where compiled code will go.
//
.global forth_colon
forth_colon:
    // Save LATEST and HERE for error recovery before modifying anything
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Parse name
    BL forth_parse_word             // ( -- c-addr u )
    // Pop c-addr and u from stack
    LDR X24, [X19], #CELL          // X24 = u (name length, on top)
    LDR X23, [X19], #CELL          // X23 = c-addr (second)

    CBZ X24, .Lcolon_err            // empty name — bail

    // Check dictionary space (need ~128 bytes for header)
    ADR X9, dict_space_end
    ADD X10, X21, #128
    CMP X10, X9
    B.HI .Lcolon_dict_full

    // Clamp name length to F_LENMASK (31) max
    CMP X24, #F_LENMASK
    B.LS .Lcolon_len_ok
    MOV X24, #F_LENMASK
.Lcolon_len_ok:

    // X21 = HERE, X22 = LATEST
    // Align HERE to 8 before starting new entry
    ADD X21, X21, #7
    AND X21, X21, #~7

    // Write link pointer (8 bytes) — points to old LATEST
    STR X22, [X21]
    MOV X25, X21                    // X25 = new entry address (for LATEST)
    ADD X21, X21, #CELL

    // Write flags+len byte (HIDDEN | length)
    MOV W9, W24
    ORR W9, W9, #F_HIDDEN
    STRB W9, [X21]
    ADD X21, X21, #1

    // Write name (lowercase)
    MOV X26, X24                    // X26 = name length (loop counter)
.Lcolon_name:
    CBZ X26, .Lcolon_name_done
    LDRB W9, [X23], #1
    // Lowercase: if 'A'-'Z', add 0x20
    CMP W9, #'A'
    B.LO .Lcolon_store
    CMP W9, #'Z'
    B.HI .Lcolon_store
    ADD W9, W9, #0x20
.Lcolon_store:
    STRB W9, [X21], #1
    SUB X26, X26, #1
    B .Lcolon_name

.Lcolon_name_done:
    // Align HERE to 8
    ADD X21, X21, #7
    AND X21, X21, #~7

    // Write code pointer — will point just past code_len field
    ADD X9, X21, #12                // code starts after CodePtr(8)+CodeLen(4)
    STR X9, [X21]
    ADD X21, X21, #CELL             // past CodePtr

    // Write code_len placeholder (0), save its address for ;
    ADR X9, colon_code_len_addr
    STR X21, [X9]
    STR WZR, [X21]
    ADD X21, X21, #4                // past CodeLen

    // Compile prolog (STP X29, X30, [SP, #-16]!) as first instruction
    BL compile_prolog

    // Update LATEST and STATE
    MOV X22, X25                    // LATEST = new entry
    ADR X9, state
    MOV X10, #1
    STR X10, [X9]                   // STATE = compiling

    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lcolon_dict_full:
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    B dict_full

.Lcolon_err:
    // No name given — just return without doing anything
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- SEMICOLON (Forth-level, IMMEDIATE) ----------
// ( -- )
// End a colon definition: compile RET, fill code_len, clear HIDDEN,
// return to interpret mode.
//
.global forth_semicolon
forth_semicolon:
    // Guard: must be in compile mode
    ADR X9, state
    LDR X9, [X9]
    CBZ X9, .Lsemi_err

    STP X29, X30, [SP, #-16]!

    // Compile RET
    BL compile_ret

    // Calculate code length and write it
    ADR X9, colon_code_len_addr
    LDR X9, [X9]                    // X9 = code_len field address
    ADD X10, X9, #4                 // X10 = code start (right after field)
    SUB X11, X21, X10               // X11 = code length
    STR W11, [X9]                   // write code_len (32-bit)

    // Flush I-cache for compiled code (I-cache/D-cache not coherent on ARM64)
    MOV X0, X10                     // start = code start
    MOV X1, X21                     // end = HERE
    BL platform_flush_icache

    // Clear HIDDEN flag on new entry (LATEST + 8 is flags byte)
    LDRB W9, [X22, #8]
    AND W9, W9, #~F_HIDDEN
    STRB W9, [X22, #8]

    // Return to interpret mode
    ADR X9, state
    STR XZR, [X9]

    LDP X29, X30, [SP], #16
    RET

.Lsemi_err:
    // ; outside compile mode — silently ignore
    RET

// ---------- IMMEDIATE (Forth-level) ----------
// ( -- )
// Set the IMMEDIATE flag on the most recent dictionary entry.
.global forth_immediate
forth_immediate:
    LDRB W9, [X22, #8]
    ORR W9, W9, #F_IMMEDIATE
    STRB W9, [X22, #8]
    RET

// ---------- TICK (Forth-level, IMMEDIATE) ----------
// ( "<spaces>name" -- xt )
// Parse the next word and look it up in the dictionary.
// In interpret mode: pushes xt to stack.
// In compile mode: compiles xt as a literal (acts like ['] in std Forth).
.global forth_tick
forth_tick:
    STP X29, X30, [SP, #-16]!
    BL forth_parse_word             // ( -- c-addr u )
    BL forth_find                   // ( c-addr u -- xt flag | c-addr u 0 )

    // Check if found (flag != 0)
    LDR X9, [X19]                  // X9 = flag (top)
    CBZ X9, .Ltick_not_found

    // Found — drop flag, leave xt on top
    ADD X19, X19, #CELL            // drop flag, xt is now on top

    // If compiling, compile xt as a literal
    ADR X9, state
    LDR X9, [X9]
    CBZ X9, .Ltick_done             // interpreting -> leave on stack

    // Compiling — pop xt and compile as literal
    LDR X0, [X19], #CELL
    BL compile_literal
.Ltick_done:
    LDP X29, X30, [SP], #16
    RET

.Ltick_not_found:
    // Not found — drop flag, u, c-addr; push 0 as error
    ADD X19, X19, #3*CELL           // drop flag, u, c-addr
    STR XZR, [X19, #-CELL]!        // push 0 (invalid xt)
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
DEFWORD dict_find,       "find",       forth_find,       dict_number
DEFWORD dict_parse_word, "parse-word", forth_parse_word, dict_find
DEFWORD dict_execute,    "execute",    forth_execute,    dict_parse_word
DEFWORD dict_dot,        ".",          forth_dot,        dict_execute
DEFWORD dict_dot_s,      ".s",         forth_dot_s,      dict_dot
DEFWORD dict_bye,        "bye",        forth_bye,        dict_dot_s
DEFWORD dict_lit,        "lit",        forth_lit,        dict_bye, F_HIDDEN
DEFWORD dict_colon,      ":",          forth_colon,      dict_lit
DEFWORD dict_semicolon,  ";",          forth_semicolon,  dict_colon, F_IMMEDIATE
DEFWORD dict_immediate,  "immediate",  forth_immediate,  dict_semicolon
DEFWORD dict_mul,        "*",          forth_mul,         dict_immediate
DEFWORD dict_divmod,     "/mod",       forth_divmod,      dict_mul
DEFWORD dict_one_plus,   "1+",         forth_one_plus,    dict_divmod
DEFWORD dict_one_minus,  "1-",         forth_one_minus,   dict_one_plus
DEFWORD dict_abs,        "abs",        forth_abs,         dict_one_minus
DEFWORD dict_min,        "min",        forth_min,         dict_abs
DEFWORD dict_max,        "max",        forth_max,         dict_min
DEFWORD dict_equal,      "=",          forth_equal,       dict_max
DEFWORD dict_less,       "<",          forth_less,        dict_equal
DEFWORD dict_greater,    ">",          forth_greater,     dict_less
DEFWORD dict_zero_equal, "0=",         forth_zero_equal,  dict_greater
DEFWORD dict_zero_less,  "0<",         forth_zero_less,   dict_zero_equal
DEFWORD dict_and,        "and",        forth_and,         dict_zero_less
DEFWORD dict_or,         "or",         forth_or,          dict_and
DEFWORD dict_xor,        "xor",        forth_xor,         dict_or
DEFWORD dict_invert,     "invert",     forth_invert,      dict_xor
DEFWORD dict_rot,        "rot",        forth_rot,         dict_invert
DEFWORD dict_nip,        "nip",        forth_nip,         dict_rot
DEFWORD dict_tuck,       "tuck",       forth_tuck,        dict_nip
DEFWORD dict_two_dup,    "2dup",       forth_two_dup,     dict_tuck
DEFWORD dict_two_drop,   "2drop",      forth_two_drop,    dict_two_dup
DEFWORD dict_depth,      "depth",      forth_depth,       dict_two_drop
DEFWORD dict_question_dup, "?dup",     forth_question_dup, dict_depth
DEFWORD dict_to_r,       ">r",         forth_to_r,        dict_question_dup, F_COMPILE_ONLY
DEFWORD dict_r_from,     "r>",         forth_r_from,      dict_to_r, F_COMPILE_ONLY
DEFWORD dict_r_fetch,    "r@",         forth_r_fetch,     dict_r_from, F_COMPILE_ONLY
DEFWORD dict_tick,       "'",          forth_tick,        dict_r_fetch, F_IMMEDIATE
.global dict_tick

// ---------- Data Stack Memory ----------
// Layout (grows downward):
//   guard_page_underflow  4096 bytes — mprotect PROT_NONE at startup
//   data_stack_top (sp0)  page-aligned
//   data_stack            4096 bytes (512 cells)
//   data_stack_bottom     page-aligned
//   guard_page_overflow   4096 bytes — mprotect PROT_NONE at startup
.bss
.balign 4096
.global guard_page_overflow
guard_page_overflow:
    .space 4096
.global data_stack_bottom
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:
.global guard_page_underflow
guard_page_underflow:
    .space 4096

// ---------- Dictionary Space ----------
.equ DICT_SPACE_SIZE, 65536     // 64KB
.balign 8
.global dict_space
dict_space:
    .space DICT_SPACE_SIZE
dict_space_end:

// ---------- Variables ----------
.data
.align 3
.global base
base:                               // NUMBER base (default decimal)
    .quad 10
.global source_addr
source_addr:                        // PARSE-WORD: pointer to input buffer
    .quad 0
.global source_len
source_len:                         // PARSE-WORD: total length of input
    .quad 0
.global to_in
to_in:                              // PARSE-WORD: current parse offset
    .quad 0
.global sp0
sp0:                                // Initial DSP value (for .S depth)
    .quad 0
.global state
state:                              // Compiler state (0=interpret, non-zero=compile)
    .quad 0
.global colon_code_len_addr
colon_code_len_addr:                // Saved code_len field address for ; to fill
    .quad 0
.global saved_latest
saved_latest:                       // LATEST before current : for error recovery
    .quad 0
.global saved_here
saved_here:                         // HERE before current : for error recovery
    .quad 0
.global rp0
rp0:                                // Return stack pointer at repl_loop entry
    .quad 0
