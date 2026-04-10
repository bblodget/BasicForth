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

// ---------- Double-Cell Arithmetic ----------

// S>D ( n -- d )  Sign-extend single to double.
// Double-cell: high word on top, low word below.
.global forth_s_to_d
forth_s_to_d:
    LDR X9, [X19]               // n
    ASR X10, X9, #63            // high = sign extension
    SUB X19, X19, #CELL         // make room
    STR X9, [X19, #CELL]        // low word (second)
    STR X10, [X19]              // high word (top)
    RET

// UM* ( u1 u2 -- ud )  Unsigned multiply, 128-bit result.
// Double-cell result: high word on top, low word below.
.global forth_um_star
forth_um_star:
    LDR X9, [X19]               // u2
    LDR X10, [X19, #CELL]       // u1
    MUL X11, X10, X9            // low 64 bits
    UMULH X12, X10, X9          // high 64 bits (unsigned)
    STR X11, [X19, #CELL]       // low word (second)
    STR X12, [X19]              // high word (top)
    RET

// M* ( n1 n2 -- d )  Signed multiply, 128-bit result.
// Double-cell result: high word on top, low word below.
.global forth_m_star
forth_m_star:
    LDR X9, [X19]               // n2
    LDR X10, [X19, #CELL]       // n1
    MUL X11, X10, X9            // low 64 bits
    SMULH X12, X10, X9          // high 64 bits (signed)
    STR X11, [X19, #CELL]       // low word (second)
    STR X12, [X19]              // high word (top)
    RET

// UM/MOD ( ud u1 -- u2 u3 )  Unsigned double / single → remainder quotient.
// u2 = remainder, u3 = quotient.
// Division by zero returns 0 0.
// ARM64 has no 128/64 divide — use software binary long division.
.global forth_um_divmod
forth_um_divmod:
    LDR X11, [X19]              // divisor
    CBZ X11, .Lum_divmod_zero
    LDR X10, [X19, #CELL]       // ud-high (on top after divisor)
    LDR X9, [X19, #2*CELL]      // ud-low (deepest)
    // Fast path: if high word is 0, use hardware UDIV
    CBNZ X10, .Lum_divmod_full
    UDIV X12, X9, X11           // quotient = low / divisor
    MSUB X13, X12, X11, X9     // remainder = low - quot*divisor
    ADD X19, X19, #CELL         // drop one (3 in, 2 out)
    STR X13, [X19, #CELL]       // remainder (second)
    STR X12, [X19]              // quotient (top)
    RET
.Lum_divmod_full:
    // Full 128/64 binary long division
    // X9 = ud-low, X10 = ud-high, X11 = divisor
    // Algorithm: process 64 bits of ud-low through remainder
    // Start with remainder = ud-high (the partial remainder from high word)
    MOV X13, #0                 // remainder = 0
    MOV X12, #0                 // quotient = 0
    // First process the high word: 64 iterations
    MOV X14, #64                // counter
.Lum_div_hi_loop:
    // Shift remainder left by 1, pull top bit from ud-high
    LSL X13, X13, #1
    TST X10, #(1 << 63)
    B.EQ .Lum_div_hi_nobit
    ORR X13, X13, #1
.Lum_div_hi_nobit:
    LSL X10, X10, #1
    LSL X12, X12, #1
    CMP X13, X11
    B.LO .Lum_div_hi_skip
    SUB X13, X13, X11
    ORR X12, X12, #1
.Lum_div_hi_skip:
    SUBS X14, X14, #1
    B.NE .Lum_div_hi_loop
    // Now process the low word: 64 more iterations
    // X12 has partial quotient from high word (should be 0 if result fits in 64 bits)
    // Reset quotient for low word processing, keeping remainder
    MOV X12, #0
    MOV X14, #64
.Lum_div_lo_loop:
    LSL X13, X13, #1
    TST X9, #(1 << 63)
    B.EQ .Lum_div_lo_nobit
    ORR X13, X13, #1
.Lum_div_lo_nobit:
    LSL X9, X9, #1
    LSL X12, X12, #1
    CMP X13, X11
    B.LO .Lum_div_lo_skip
    SUB X13, X13, X11
    ORR X12, X12, #1
.Lum_div_lo_skip:
    SUBS X14, X14, #1
    B.NE .Lum_div_lo_loop
    // X12 = quotient, X13 = remainder
    ADD X19, X19, #CELL
    STR X13, [X19, #CELL]       // remainder (second)
    STR X12, [X19]              // quotient (top)
    RET
.Lum_divmod_zero:
    ADD X19, X19, #CELL
    STR XZR, [X19, #CELL]
    STR XZR, [X19]
    RET

// SM/REM ( d n1 -- n2 n3 )  Symmetric (truncating) signed divide.
// Implemented via UM/MOD with sign handling.
.global forth_sm_rem
forth_sm_rem:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    LDR X23, [X19]              // divisor (n1)
    CBZ X23, .Lsm_rem_zero
    LDR X24, [X19, #CELL]       // d-high
    LDR X25, [X19, #2*CELL]     // d-low
    // Save signs: X26 = sign of dividend (d-high), X23 sign already in X23
    MOV X26, X24                // save d-high for sign
    // Make dividend positive
    TST X24, X24
    B.GE .Lsm_rem_pos_d
    // Negate 128-bit: ~(hi:lo) + 1
    MVN X25, X25
    MVN X24, X24
    ADDS X25, X25, #1
    ADC X24, X24, XZR
.Lsm_rem_pos_d:
    // Make divisor positive
    MOV X9, X23
    CMP X23, #0
    B.GE .Lsm_rem_pos_n
    NEG X9, X23
.Lsm_rem_pos_n:
    // Do unsigned divide: (X25:X24) / X9
    STR X25, [X19, #2*CELL]     // ud-low
    STR X24, [X19, #CELL]       // ud-high
    STR X9, [X19]               // divisor (positive)
    BL forth_um_divmod           // ( rem quot )
    LDR X9, [X19]               // quotient
    LDR X10, [X19, #CELL]       // remainder
    // Fix signs: remainder has sign of dividend, quotient negative if signs differ
    // If dividend was negative, negate remainder
    TST X26, X26
    B.GE .Lsm_rem_rem_ok
    NEG X10, X10
.Lsm_rem_rem_ok:
    // If signs of dividend and divisor differ, negate quotient
    EOR X11, X26, X23
    TST X11, X11
    B.GE .Lsm_rem_quot_ok
    NEG X9, X9
.Lsm_rem_quot_ok:
    STR X10, [X19, #CELL]       // remainder
    STR X9, [X19]               // quotient
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET
.Lsm_rem_zero:
    ADD X19, X19, #CELL
    STR XZR, [X19, #CELL]
    STR XZR, [X19]
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// FM/MOD ( d n1 -- n2 n3 )  Floored signed divide.
// Like SM/REM but adjusts when remainder and divisor have different signs.
.global forth_fm_mod
forth_fm_mod:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    LDR X23, [X19]              // divisor (n1)
    CBZ X23, .Lfm_mod_zero
    LDR X24, [X19, #CELL]       // d-high
    LDR X25, [X19, #2*CELL]     // d-low
    MOV X26, X24                // save d-high for sign
    // Make dividend positive
    TST X24, X24
    B.GE .Lfm_pos_d
    MVN X25, X25
    MVN X24, X24
    ADDS X25, X25, #1
    ADC X24, X24, XZR
.Lfm_pos_d:
    // Make divisor positive
    MOV X9, X23
    CMP X23, #0
    B.GE .Lfm_pos_n
    NEG X9, X23
.Lfm_pos_n:
    // Unsigned divide: (X25:X24) / X9
    STR X25, [X19, #2*CELL]
    STR X24, [X19, #CELL]
    STR X9, [X19]
    BL forth_um_divmod
    LDR X9, [X19]               // quotient
    LDR X10, [X19, #CELL]       // remainder
    // Fix signs (same as SM/REM first)
    TST X26, X26
    B.GE .Lfm_rem_ok
    NEG X10, X10
.Lfm_rem_ok:
    EOR X11, X26, X23
    TST X11, X11
    B.GE .Lfm_quot_ok
    NEG X9, X9
.Lfm_quot_ok:
    // Floor adjustment: if remainder != 0 and signs of remainder and divisor differ
    CBZ X10, .Lfm_done
    EOR X11, X10, X23           // sign bits of remainder vs divisor
    TST X11, X11
    B.GE .Lfm_done              // same sign → no adjustment
    ADD X10, X10, X23           // remainder += divisor
    SUB X9, X9, #1              // quotient -= 1
.Lfm_done:
    STR X10, [X19, #CELL]
    STR X9, [X19]
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET
.Lfm_mod_zero:
    ADD X19, X19, #CELL
    STR XZR, [X19, #CELL]
    STR XZR, [X19]
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET
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
    STP X27, X28, [SP, #-16]!

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
    // Flag encoding:  1 = IMMEDIATE
    //                -1 = normal
    //                -2 = COMPILE_ONLY (non-immediate)
    //                 2 = IMMEDIATE + COMPILE_ONLY
    MOV W27, #(F_IMMEDIATE | F_COMPILE_ONLY)
    AND W28, W26, W27
    CMP W28, W27
    B.EQ .Lfind_imm_co
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
.Lfind_imm_co:
    MOV X9, #2
    STR X9, [X19, #-CELL]!      // push 2 (immediate + compile-only)
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
    LDP X27, X28, [SP], #16
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
msg_compile_only: .ascii "compile only\n"
.equ msg_compile_only_len, . - msg_compile_only
msg_unbalanced: .ascii "unresolved control flow\n"
.equ msg_unbalanced_len, . - msg_unbalanced
msg_cf_mismatch: .ascii "mismatched control flow\n"
.equ msg_cf_mismatch_len, . - msg_cf_mismatch
cf_mismatch_name: .ascii "mismatched-control-flow"
.equ cf_mismatch_name_len, . - cf_mismatch_name
sq_unterminated_name: .ascii "unterminated string"
.equ sq_unterminated_name_len, . - sq_unterminated_name
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

// ---------- Branch Compile Helpers ----------
// Internal routines for control flow words. Not exposed as Forth words.
//
// 0branch emits 8 bytes:
//   LDR X9, [X19], #8    pop flag     (0xF8408669)
//   CBZ X9, +0            branch if 0  (0xB4000009)
//
// branch emits 4 bytes:
//   B +0                  unconditional (0x14000000)
//
// ARM64 offset encoding:
//   B:   26-bit signed word offset in bits [25:0]
//   CBZ: 19-bit signed word offset in bits [23:5]

.equ INSN_LDR_X9_X19_POST8, 0xF8408669
.equ INSN_CBZ_X9,            0xB4000009
.equ INSN_B,                 0x14000000

// compile_0branch — emit forward conditional branch with placeholder.
// Returns: X0 = address of the CBZ instruction (for patching).
compile_0branch:
    CHECK_DICT 8
    MOV W9, #0x8669
    MOVK W9, #0xF840, LSL #16     // LDR X9, [X19], #8
    STR W9, [X21]
    ADD X21, X21, #4
    MOV W9, #0x0009
    MOVK W9, #0xB400, LSL #16     // CBZ X9, +0 (placeholder)
    MOV X0, X21                    // X0 = address of CBZ instruction
    STR W9, [X21]
    ADD X21, X21, #4
    RET

// compile_branch — emit forward unconditional branch with placeholder.
// Returns: X0 = address of the B instruction (for patching).
compile_branch:
    CHECK_DICT 4
    MOV W9, #0x0000
    MOVK W9, #0x1400, LSL #16     // B +0 (placeholder)
    MOV X0, X21                    // X0 = address of B instruction
    STR W9, [X21]
    ADD X21, X21, #4
    RET

// patch_forward — patch a forward branch to jump to current HERE.
// Input: X0 = address of the branch instruction to patch.
// Detects instruction type:
//   B (unconditional): bits [31:29] = 000 → 26-bit offset in [25:0]
//   CBZ / B.cond:      everything else    → 19-bit offset in [23:5]
patch_forward:
    LDR W9, [X0]                   // read instruction
    SUB X10, X21, X0               // byte offset = HERE - instr_addr
    ASR X10, X10, #2               // word offset = byte_offset / 4
    // Check for B (unconditional): bits [31:29] = 000
    LSR W11, W9, #29               // W11 = top 3 bits
    CBNZ W11, .Lpf_19bit           // non-zero → B.cond or CBZ
    // B: 26-bit offset in bits [25:0]
    AND W10, W10, #0x3FFFFFF        // mask to 26 bits
    BIC W9, W9, #0x3FFFFFF          // clear old offset
    ORR W9, W9, W10                 // insert new offset
    STR W9, [X0]
    RET
.Lpf_19bit:
    // CBZ or B.cond: 19-bit offset in bits [23:5]
    AND X10, X10, #0x7FFFF         // mask to 19 bits
    BIC W9, W9, #(0x7FFFF << 5)    // clear old offset bits
    ORR W9, W9, W10, LSL #5        // insert new offset
    STR W9, [X0]
    RET

// compile_0branch_back — emit conditional backward branch to known target.
// Input: X0 = target address.
compile_0branch_back:
    CHECK_DICT 8
    MOV X10, X0                    // X10 = target
    MOV W9, #0x8669
    MOVK W9, #0xF840, LSL #16     // LDR X9, [X19], #8
    STR W9, [X21]
    ADD X21, X21, #4
    // Calculate offset: (target - cbz_addr) / 4
    SUB X10, X10, X21              // byte offset = target - cbz_addr
    ASR X10, X10, #2               // word offset
    AND X10, X10, #0x7FFFF         // mask to 19 bits
    MOV W9, #0x0009
    MOVK W9, #0xB400, LSL #16     // CBZ X9 base
    ORR W9, W9, W10, LSL #5        // insert offset
    STR W9, [X21]
    ADD X21, X21, #4
    RET

// compile_branch_back — emit unconditional backward branch to known target.
// Input: X0 = target address.
compile_branch_back:
    CHECK_DICT 4
    SUB X10, X0, X21               // byte offset = target - b_addr
    ASR X10, X10, #2               // word offset
    AND W10, W10, #0x3FFFFFF        // mask to 26 bits
    MOV W9, #0x0000
    MOVK W9, #0x1400, LSL #16     // B base
    ORR W9, W9, W10                 // insert offset
    STR W9, [X21]
    ADD X21, X21, #4
    RET

// ---------- build_header (internal helper) ----------
// Parse the next word and create a dictionary header at HERE.
// Saves LATEST/HERE for error recovery, updates LATEST to new entry.
// Entry is marked HIDDEN — caller must clear it when done.
// On return: HERE points to code area, X22 = new entry (LATEST).
// Uses X23-X26 internally (caller must save if needed).
// Returns: X0=0 on success, X0=1 on error (empty name or dict full).
//
// Dictionary entry layout:
//   [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4]
build_header:
    STP X29, X30, [SP, #-16]!

    // Save LATEST and HERE for error recovery
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

    // Parse name
    BL forth_parse_word             // ( -- c-addr u )
    LDR X24, [X19], #CELL          // X24 = u (name length)
    LDR X23, [X19], #CELL          // X23 = c-addr

    CBZ X24, .Lbh_err

    // Check dictionary space
    ADR X9, dict_space_end
    ADD X10, X21, #128
    CMP X10, X9
    B.HI .Lbh_dict_full

    // Clamp name length
    CMP X24, #F_LENMASK
    B.LS .Lbh_len_ok
    MOV X24, #F_LENMASK
.Lbh_len_ok:

    // Align HERE to 8
    ADD X21, X21, #7
    AND X21, X21, #~7

    // Write link pointer
    STR X22, [X21]
    MOV X25, X21                    // X25 = new entry address
    ADD X21, X21, #CELL

    // Write flags+len byte (HIDDEN | length)
    MOV W9, W24
    ORR W9, W9, #F_HIDDEN
    STRB W9, [X21]
    ADD X21, X21, #1

    // Write name (lowercase)
    MOV X26, X24
.Lbh_name:
    CBZ X26, .Lbh_name_done
    LDRB W9, [X23], #1
    CMP W9, #'A'
    B.LO .Lbh_store
    CMP W9, #'Z'
    B.HI .Lbh_store
    ADD W9, W9, #0x20
.Lbh_store:
    STRB W9, [X21], #1
    SUB X26, X26, #1
    B .Lbh_name

.Lbh_name_done:
    // Align HERE to 8
    ADD X21, X21, #7
    AND X21, X21, #~7

    // Write code pointer
    ADD X9, X21, #12               // code starts after CodePtr(8)+CodeLen(4)
    STR X9, [X21]
    ADD X21, X21, #CELL

    // Write code_len placeholder (0), save its address
    ADR X9, colon_code_len_addr
    STR X21, [X9]
    STR WZR, [X21]
    ADD X21, X21, #4               // HERE now at code area

    // Update LATEST
    MOV X22, X25                   // LATEST = new entry (still HIDDEN)

    MOV X0, #0                     // success
    LDP X29, X30, [SP], #16
    RET

.Lbh_dict_full:
    LDP X29, X30, [SP], #16
    B dict_full

.Lbh_err:
    MOV X0, #1                     // error
    LDP X29, X30, [SP], #16
    RET

// ---------- COLON (Forth-level) ----------
// ( -- )
// Parse the next word, create a dictionary header at HERE, and enter
// compile mode.  The new entry is marked HIDDEN until ; completes it.
.global forth_colon
forth_colon:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    BL build_header
    CBNZ X0, .Lcolon_done          // error → bail

    // Compile prolog (STP X29, X30, [SP, #-16]!)
    BL compile_prolog

    // Save data stack depth for control-flow balance check in ;
    ADR X9, colon_dsp
    STR X19, [X9]

    // Enter compile mode
    ADR X9, state
    MOV X10, #1
    STR X10, [X9]

.Lcolon_done:
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

    // Check control-flow stack balance: DSP must match what : saved
    ADR X9, colon_dsp
    LDR X9, [X9]
    CMP X19, X9
    B.NE .Lsemi_unbalanced

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

.Lsemi_unbalanced:
    // Unresolved control flow — roll back the definition
    STP X29, X30, [SP, #-16]!
    ADR X0, msg_unbalanced
    MOV X1, #msg_unbalanced_len
    BL platform_write
    // Restore stack, LATEST, HERE, STATE
    ADR X9, colon_dsp
    LDR X19, [X9]
    ADR X9, saved_latest
    LDR X22, [X9]
    ADR X9, saved_here
    LDR X21, [X9]
    ADR X9, state
    STR XZR, [X9]
    ADR X9, do_depth
    STR XZR, [X9]
    ADR X9, leave_count
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

// ---------- INTERPRET-LINE ----------
// ( -- ) Returns status in X0: 0=success, 1=error
// Caller must set source_addr, source_len, to_in before calling.
// On error: saves offending token in err_token_addr/err_token_len,
//           resets STATE and restores LATEST/HERE if compiling.
// On success: cleans up stack, returns 0.
.global forth_interpret_line
forth_interpret_line:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    STP X27, X28, [SP, #-16]!
    // Save previous il_sp for nesting (EVALUATE inside INCLUDED etc.)
    ADR X9, il_sp
    LDR X10, [X9]                   // X10 = old il_sp
    STP X10, XZR, [SP, #-16]!      // push old il_sp (+ padding for alignment)
    MOV X10, SP
    STR X10, [X9]                   // il_sp = current SP

.Lil_loop:
    BL forth_parse_word             // ( -- c-addr u )

    // End of line? (u == 0)
    LDR X9, [X19]                   // u is on top
    CBZ X9, .Lil_done

    // FIND ( c-addr u -- xt flag | c-addr u 0 )
    BL forth_find

    // Found? (flag != 0)
    LDR X9, [X19]                   // flag is on top
    CBZ X9, .Lil_try_number

    // Found — top = flag, second = xt
    // Flags: 1=IMMEDIATE, -1=normal, -2=COMPILE_ONLY, 2=IMMEDIATE+COMPILE_ONLY
    // If interpreting (STATE==0): execute, but reject compile-only (flag==-2 or 2)
    // If compiling: IMMEDIATE (flag==1 or 2) → execute, else compile
    ADR X10, state
    LDR X10, [X10]
    CBZ X10, .Lil_found_interpret   // interpreting → check compile-only

    // Compiling — check IMMEDIATE flag (flag==1 or flag==2)
    LDR X9, [X19]
    CMP X9, #1
    B.EQ .Lil_found_execute         // IMMEDIATE → execute
    CMP X9, #2
    B.EQ .Lil_found_execute         // IMMEDIATE+COMPILE_ONLY → execute

    // Normal word in compile mode — compile a BL to it
    ADD X19, X19, #CELL             // drop flag
    LDR X0, [X19], #CELL            // pop xt into X0
    BL compile_call                 // emit BL xt at HERE
    B .Lil_loop

.Lil_found_interpret:
    // Interpreting — reject compile-only words (flag == -2 or flag == 2)
    LDR X9, [X19]
    CMN X9, #2                      // compare with -2
    B.EQ .Lil_compile_only
    CMP X9, #2
    B.EQ .Lil_compile_only
    // Fall through to execute

.Lil_found_execute:
    ADD X19, X19, #CELL             // drop flag
    BL forth_execute                // pops xt and jumps
    B .Lil_loop

.Lil_try_number:
    // Not in dictionary — drop 0 flag, try NUMBER
    ADD X19, X19, #CELL             // drop 0 flag ( c-addr u )

    // NUMBER ( c-addr u -- n true | c-addr u false )
    BL forth_number

    LDR X9, [X19]                   // top = true/false flag
    CBZ X9, .Lil_not_found

    // Parsed — drop true flag, number is on stack
    ADD X19, X19, #CELL             // drop true flag

    // If compiling, compile the number as a literal
    ADR X9, state
    LDR X9, [X9]
    CBZ X9, .Lil_loop               // interpreting → leave n on stack

    // Compiling — compile literal
    LDR X0, [X19], #CELL            // pop number into X0
    BL compile_literal              // emit BL LIT + value at HERE
    B .Lil_loop

.Lil_not_found:
    // Neither word nor number — error
    ADD X19, X19, #CELL             // drop false flag ( c-addr u )

    // Save offending token info for caller to report
    LDR X9, [X19]                   // u (top)
    ADR X10, err_token_len
    STR X9, [X10]
    LDR X9, [X19, #CELL]            // c-addr (second)
    ADR X10, err_token_addr
    STR X9, [X10]
    ADD X19, X19, #2*CELL           // clean up c-addr and u

    // If we were compiling, abort the definition
    ADR X9, state
    LDR X10, [X9]
    CBZ X10, .Lil_err_return
    STR XZR, [X9]                   // reset to interpret mode
    ADR X9, colon_dsp
    LDR X19, [X9]                   // restore DSP (drop compile-time stack)
    ADR X9, saved_latest
    LDR X22, [X9]                   // restore LATEST
    ADR X9, saved_here
    LDR X21, [X9]                   // restore HERE
    ADR X9, do_depth
    STR XZR, [X9]                   // reset DO nesting
    ADR X9, leave_count
    STR XZR, [X9]                   // reset leave chain

.Lil_err_return:
    MOV X0, #1                      // return 1 = error
    LDP X10, X9, [SP], #16          // pop saved il_sp (+ discard padding)
    ADR X9, il_sp
    STR X10, [X9]                   // restore previous il_sp
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lil_done:
    // End of line — drop 0 0 from PARSE-WORD
    ADD X19, X19, #2*CELL
    MOV X0, XZR                     // return 0 = success
    LDP X10, X9, [SP], #16          // pop saved il_sp (+ discard padding)
    ADR X9, il_sp
    STR X10, [X9]                   // restore previous il_sp
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lil_compile_only:
    // Compile-only word used in interpret mode — non-fatal, continue parsing
    ADD X19, X19, #2*CELL           // drop xt, flag
    ADR X0, msg_compile_only
    MOV X1, #msg_compile_only_len
    BL platform_write
    B .Lil_loop

// ---------- PAREN (comment word, IMMEDIATE) ----------
// ( "ccc)" -- )
// Skip input until closing ')' or end of line.
.global forth_paren
forth_paren:
    ADR X9, source_addr
    LDR X10, [X9]                   // X10 = buffer base
    ADR X9, source_len
    LDR X11, [X9]                   // X11 = total length
    ADR X9, to_in
    LDR X12, [X9]                   // X12 = current offset

.Lparen_scan:
    CMP X12, X11
    B.GE .Lparen_done               // end of input
    LDRB W13, [X10, X12]
    CMP W13, #')'
    B.EQ .Lparen_found
    ADD X12, X12, #1
    B .Lparen_scan

.Lparen_found:
    ADD X12, X12, #1                // skip past ')'
.Lparen_done:
    ADR X9, to_in
    STR X12, [X9]
    RET

// ---------- BACKSLASH (line comment, IMMEDIATE) ----------
// ( -- )
// Skip rest of current input line.
.global forth_backslash
forth_backslash:
    ADR X9, source_len
    LDR X10, [X9]
    ADR X9, to_in
    STR X10, [X9]
    RET

// ---------- EVALUATE ----------
// ( c-addr u -- )
// Interpret a string as Forth source. Saves and restores source context
// so nested EVALUATE and INCLUDED work correctly.
// Returns: X0 = 0 on success, 1 on error.
.global forth_evaluate
forth_evaluate:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Pop c-addr and u from data stack
    LDR X9, [X19]                   // X9 = u (top)
    LDR X10, [X19, #CELL]           // X10 = c-addr (second)
    ADD X19, X19, #2*CELL

    // Save current source context in callee-saved regs
    ADR X11, source_addr
    LDR X23, [X11]                  // save old source_addr
    ADR X12, source_len
    LDR X24, [X12]                  // save old source_len
    ADR X13, to_in
    LDR X25, [X13]                  // save old to_in

    // Set new source context
    STR X10, [X11]                  // source_addr = c-addr
    STR X9, [X12]                   // source_len = u
    STR XZR, [X13]                  // to_in = 0

    // Interpret the string
    BL forth_interpret_line
    MOV X26, X0                     // save result

    // Restore source context
    ADR X9, source_addr
    STR X23, [X9]
    ADR X9, source_len
    STR X24, [X9]
    ADR X9, to_in
    STR X25, [X9]

    MOV X0, X26                     // restore result
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- INCLUDED ----------
// ( c-addr u -- )
// Load and interpret a Forth source file. Opens the file, mmaps it,
// processes line-by-line, then munmaps. Aborts on first error with
// filename:line: ? token  error format.
// Returns: X0 = 0 on success, 1 on error.
// Special: returns 0 silently if file not found (ENOENT = -2).
.global forth_included
forth_included:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    STP X27, X28, [SP, #-16]!

    // Pop c-addr and u from data stack
    LDR X1, [X19]                   // X1 = u (filename length)
    LDR X0, [X19, #CELL]            // X0 = c-addr (filename)
    ADD X19, X19, #2*CELL

    // Save filename for error reporting
    ADR X9, file_name_addr
    STR X0, [X9]
    ADR X9, file_name_len
    STR X1, [X9]

    // Open file (X0=path, X1=len)
    BL platform_open_file           // -> X0=fd
    CMP X0, #0
    B.LT .Lincl_open_err

    MOV X23, X0                     // X23 = fd

    // Get file size
    MOV X0, X23
    BL platform_fstat               // -> X0=size
    MOV X24, X0                     // X24 = file size

    // mmap the file
    MOV X0, X23                     // fd
    MOV X1, X24                     // size
    BL platform_mmap_file           // -> X0=addr
    CMN X0, #1                      // check for MAP_FAILED (-1)
    B.EQ .Lincl_mmap_err

    MOV X25, X0                     // X25 = mmap base address

    // Close fd (no longer needed)
    MOV X0, X23
    BL platform_close_file

    // Process file line by line
    // X25 = mmap base, X24 = file size, X26 = line_start offset
    MOV X26, #0                     // line_start = 0
    MOV X9, #1
    ADR X10, file_line_num
    STR X9, [X10]                   // line counter = 1

.Lincl_line_loop:
    CMP X26, X24
    B.GE .Lincl_done                // past end of file

    // Scan for newline starting at X25 + X26
    MOV X27, X26                    // scan position
.Lincl_scan_nl:
    CMP X27, X24
    B.GE .Lincl_eol                 // end of file = end of line
    LDRB W9, [X25, X27]
    CMP W9, #'\n'
    B.EQ .Lincl_eol
    ADD X27, X27, #1
    B .Lincl_scan_nl

.Lincl_eol:
    // Line goes from X25+X26 to X25+X27 (exclusive)
    // X28 = next line start
    ADD X28, X27, #1               // next line start
    SUB X9, X27, X26               // X9 = line length

    // Skip empty lines
    CBZ X9, .Lincl_next_line

    // Set source vars for this line
    ADD X10, X25, X26
    ADR X11, source_addr
    STR X10, [X11]
    ADR X11, source_len
    STR X9, [X11]
    ADR X11, to_in
    STR XZR, [X11]

    BL forth_interpret_line

    CBNZ X0, .Lincl_error

.Lincl_next_line:
    MOV X26, X28                    // advance to next line
    ADR X9, file_line_num
    LDR X10, [X9]
    ADD X10, X10, #1
    STR X10, [X9]
    B .Lincl_line_loop

.Lincl_done:
    // Unmap file
    MOV X0, X25
    MOV X1, X24
    BL platform_munmap

    MOV X0, #0                      // return 0 = success
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lincl_error:
    // Print "filename:line: ? token\n"
    // Print filename
    ADR X9, file_name_addr
    LDR X0, [X9]
    ADR X9, file_name_len
    LDR X1, [X9]
    BL platform_write
    // Print ":"
    MOV X0, #':'
    BL platform_emit
    // Print line number
    ADR X9, file_line_num
    LDR X0, [X9]
    BL .Lprint_signed
    // Print ": ? "
    ADR X0, incl_err_sep
    MOV X1, #incl_err_sep_len
    BL platform_write
    // Print offending token
    ADR X9, err_token_addr
    LDR X0, [X9]
    ADR X9, err_token_len
    LDR X1, [X9]
    BL platform_write
    // Print newline
    MOV X0, #'\n'
    BL platform_emit

    // Unmap file
    MOV X0, X25
    MOV X1, X24
    BL platform_munmap

    MOV X0, #1                      // return 1 = error
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lincl_open_err:
    // Check for ENOENT (-2) — silent skip
    CMN X0, #2
    B.EQ .Lincl_open_skip

    // Other open error — print message
    ADR X0, incl_err_open
    MOV X1, #incl_err_open_len
    BL platform_write
    ADR X9, file_name_addr
    LDR X0, [X9]
    ADR X9, file_name_len
    LDR X1, [X9]
    BL platform_write
    MOV X0, #'\n'
    BL platform_emit

.Lincl_open_skip:
    MOV X0, #0                      // return 0 (not an error for ENOENT)
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lincl_mmap_err:
    // mmap failed — close fd and print error
    MOV X0, X23
    BL platform_close_file
    ADR X0, incl_err_open
    MOV X1, #incl_err_open_len
    BL platform_write
    ADR X9, file_name_addr
    LDR X0, [X9]
    ADR X9, file_name_len
    LDR X1, [X9]
    BL platform_write
    MOV X0, #'\n'
    BL platform_emit
    MOV X0, #1
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.section .rodata
incl_err_sep:    .ascii ": ? "
.equ incl_err_sep_len, . - incl_err_sep
incl_err_open:   .ascii "Error: cannot open "
.equ incl_err_open_len, . - incl_err_open
.text

// ---------- Control Flow Tag Constants ----------
.equ CF_ORIG, 1                     // forward reference (IF, ELSE, WHILE)
.equ CF_DEST, 2                     // backward target (BEGIN)
.equ CF_LEAVE, 3                    // saved leave count (DO)
.equ MAX_LEAVES, 8                  // max LEAVE per nesting

// cf_check_tag — verify top of stack matches expected tag.
// Input: X0 = expected tag.  On mismatch, aborts compilation and
// jumps directly to repl_loop (does not return to caller).
cf_check_tag:
    LDR X9, [X19]
    CMP X9, X0
    B.NE .Lcf_mismatch
    RET
.Lcf_mismatch:
    // Set error token for control-flow mismatch
    ADR X9, err_token_addr
    ADR X10, cf_mismatch_name
    STR X10, [X9]
    ADR X9, err_token_len
    MOV X10, #cf_mismatch_name_len
    STR X10, [X9]
    // Fall through to abort
.Lcf_abort:
    // Abort compilation — restore state and longjmp.
    // Caller must set err_token_addr/len before jumping here.
    ADR X9, colon_dsp
    LDR X19, [X9]                   // restore DSP
    ADR X9, saved_latest
    LDR X22, [X9]                   // restore LATEST
    ADR X9, saved_here
    LDR X21, [X9]                   // restore HERE
    ADR X9, state
    STR XZR, [X9]                   // interpret mode
    ADR X9, do_depth
    STR XZR, [X9]                   // reset DO nesting
    ADR X9, leave_count
    STR XZR, [X9]                   // reset leave chain
    // Longjmp back to forth_interpret_line's error return
    ADR X9, il_sp
    LDR X10, [X9]
    MOV SP, X10                     // unwind to interpret_line's frame
    MOV X0, #1                      // return error
    LDP X10, X11, [SP], #16         // pop saved il_sp (+ discard padding)
    STR X10, [X9]                   // restore previous il_sp (nesting)
    LDP X27, X28, [SP], #16         // restore all callee-saved registers
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET                             // return from interpret_line

// ---------- IF / ELSE / THEN ----------

// IF ( C: -- orig )  IMMEDIATE, COMPILE_ONLY
.global forth_if
forth_if:
    STP X29, X30, [SP, #-16]!
    BL compile_0branch              // X0 = patch addr
    STR X0, [X19, #-CELL]!         // push patch address
    MOV X9, #CF_ORIG
    STR X9, [X19, #-CELL]!         // push tag
    LDP X29, X30, [SP], #16
    RET

// THEN ( C: orig -- )  IMMEDIATE, COMPILE_ONLY
.global forth_then
forth_then:
    STP X29, X30, [SP, #-16]!
    MOV X0, #CF_ORIG
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X0, [X19], #CELL           // pop patch address
    BL patch_forward
    LDP X29, X30, [SP], #16
    RET

// ELSE ( C: orig1 -- orig2 )  IMMEDIATE, COMPILE_ONLY
.global forth_else
forth_else:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    MOV X0, #CF_ORIG
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X23, [X19], #CELL          // pop if-patch
    BL compile_branch               // X0 = else-patch
    STR X0, [X19, #-CELL]!         // push else-patch
    MOV X9, #CF_ORIG
    STR X9, [X19, #-CELL]!         // push tag
    MOV X0, X23
    BL patch_forward                // patch IF's CBZ to HERE
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- BEGIN / UNTIL / AGAIN / WHILE / REPEAT ----------

// BEGIN ( C: -- dest )  IMMEDIATE, COMPILE_ONLY
.global forth_begin
forth_begin:
    STR X21, [X19, #-CELL]!        // push HERE
    MOV X9, #CF_DEST
    STR X9, [X19, #-CELL]!         // push tag
    RET

// UNTIL ( C: dest -- )  IMMEDIATE, COMPILE_ONLY
.global forth_until
forth_until:
    STP X29, X30, [SP, #-16]!
    MOV X0, #CF_DEST
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X0, [X19], #CELL           // pop begin-addr
    BL compile_0branch_back
    LDP X29, X30, [SP], #16
    RET

// AGAIN ( C: dest -- )  IMMEDIATE, COMPILE_ONLY
.global forth_again
forth_again:
    STP X29, X30, [SP, #-16]!
    MOV X0, #CF_DEST
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X0, [X19], #CELL           // pop begin-addr
    BL compile_branch_back
    LDP X29, X30, [SP], #16
    RET

// WHILE ( C: dest -- dest orig )  IMMEDIATE, COMPILE_ONLY
.global forth_while
forth_while:
    STP X29, X30, [SP, #-16]!
    // Verify BEGIN's tag is below (peek, don't consume)
    LDR X9, [X19]
    CMP X9, #CF_DEST
    B.NE .Lcf_mismatch
    BL compile_0branch              // X0 = while-patch
    STR X0, [X19, #-CELL]!         // push while-patch
    MOV X9, #CF_ORIG
    STR X9, [X19, #-CELL]!         // push tag
    LDP X29, X30, [SP], #16
    RET

// REPEAT ( C: dest orig -- )  IMMEDIATE, COMPILE_ONLY
.global forth_repeat
forth_repeat:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    MOV X0, #CF_ORIG                // check WHILE's tag
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X23, [X19], #CELL          // pop while-patch
    MOV X0, #CF_DEST                // check BEGIN's tag
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X0, [X19], #CELL           // pop begin-addr
    BL compile_branch_back          // B back to begin
    MOV X0, X23                     // X0 = while-patch
    BL patch_forward                // patch WHILE's CBZ to HERE
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- RECURSE ----------

// RECURSE ( -- )  IMMEDIATE, COMPILE_ONLY
.global forth_recurse
forth_recurse:
    STP X29, X30, [SP, #-16]!
    ADR X9, colon_code_len_addr
    LDR X9, [X9]                    // X9 = address of code_len field
    LDR X0, [X9, #-8]              // X0 = code entry point (CodePtr field)
    BL compile_call
    LDP X29, X30, [SP], #16
    RET

// ---------- HERE, ALLOT, COMMA, C-COMMA ----------

// HERE ( -- addr )
.global forth_here
forth_here:
    STR X21, [X19, #-CELL]!        // push HERE (X21)
    RET

// ALLOT ( n -- )
.global forth_allot
forth_allot:
    LDR X9, [X19], #CELL           // pop n
    // Bounds check: dict_space <= HERE + n <= dict_space + SIZE
    ADD X10, X21, X9
    ADR X11, dict_space
    CMP X10, X11
    B.LO dict_full                  // below dict_space start
    ADR X11, dict_space_end
    CMP X10, X11
    B.HI dict_full                  // above dict_space end
    ADD X21, X21, X9                // HERE += n
    RET

// , ( x -- )
.global forth_comma
forth_comma:
    CHECK_DICT 8
    LDR X9, [X19], #CELL           // pop x
    STR X9, [X21]                   // store at HERE
    ADD X21, X21, #CELL             // advance HERE
    RET

// C, ( c -- )
.global forth_c_comma
forth_c_comma:
    CHECK_DICT 1
    LDR X9, [X19], #CELL           // pop c
    STRB W9, [X21]                  // store byte at HERE
    ADD X21, X21, #1                // advance HERE
    RET

// ---------- CREATE ----------

// CREATE ( "name" -- )
// Parse name, build dictionary header, compile code that pushes the
// data field address. Does not enter compile mode.
.global forth_create
forth_create:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    BL build_header
    CBNZ X0, .Lcreate_done         // error → bail

    // Compile code with placeholder data address (0), then patch after aligning
    MOV X0, #0                      // placeholder
    BL compile_prolog               // STP X29, X30 (4 bytes)
    BL compile_literal              // BL forth_lit + 0 (12 bytes)
    SUB X23, X21, #CELL             // X23 = address of inline value (to patch)
    BL compile_ret                  // LDP + RET (8 bytes)

    // Save code end before alignment
    MOV X24, X21                    // X24 = HERE before alignment

    // Align HERE to CELL for data field
    ADD X21, X21, #7
    AND X21, X21, #~7

    // Patch the literal with the actual aligned data field address
    STR X21, [X23]                  // write real data_addr into the literal

    // Fill code_len
    ADR X9, colon_code_len_addr
    LDR X9, [X9]                   // X9 = code_len field address
    ADD X10, X9, #4                // code start
    SUB X11, X24, X10              // code length (up to code end, before padding)
    STR W11, [X9]

    // Flush I-cache for compiled code
    ADD X0, X9, #4                 // start = code start
    MOV X1, X24                    // end = code end
    BL platform_flush_icache

    // Clear HIDDEN flag
    LDRB W9, [X22, #8]
    AND W9, W9, #~F_HIDDEN
    STRB W9, [X22, #8]

.Lcreate_done:
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- CONSTANT ----------

// CONSTANT ( x "name" -- )
// Parse name, build dictionary header, compile code that pushes x.
.global forth_constant
forth_constant:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Pop value from data stack, save on return stack (build_header clobbers X23-X26)
    LDR X9, [X19], #CELL
    STP X9, XZR, [SP, #-16]!       // save value (+ padding for alignment)

    BL build_header
    CBNZ X0, .Lconst_err           // error → bail

    // Compile code that pushes the constant value
    LDP X0, X9, [SP], #16          // restore value
    BL compile_prolog
    BL compile_literal
    BL compile_ret

    // Fill code_len
    ADR X9, colon_code_len_addr
    LDR X9, [X9]
    ADD X10, X9, #4
    SUB X11, X21, X10
    STR W11, [X9]

    // Flush I-cache
    ADD X0, X9, #4
    MOV X1, X21
    BL platform_flush_icache

    // Clear HIDDEN flag
    LDRB W9, [X22, #8]
    AND W9, W9, #~F_HIDDEN
    STRB W9, [X22, #8]

    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lconst_err:
    LDP X9, X10, [SP], #16         // restore saved value
    STR X9, [X19, #-CELL]!         // push it back onto data stack
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- DOES> ----------

// (DOES>) runtime helper — called during defining word execution.
// Patches the most recently CREATE'd word (via colon_code_len_addr)
// to B (branch) to the does-body instead of RETurning.
// does_body = X30 + 8 (skip LDP + RET compiled after BL to us).
.global forth_does_runtime
forth_does_runtime:
    ADD X9, X30, #8                 // X9 = does_body (skip LDP 4 + RET 4)
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    MOV X23, X9                     // X23 = does_body (callee-saved)
    // Get CREATE'd word's code start from colon_code_len_addr
    ADR X9, colon_code_len_addr
    LDR X9, [X9]                    // X9 = code_len field address
    ADD X24, X9, #4                 // X24 = code_start
    // Patch: replace RET at offset 20 with B does_body
    ADD X10, X24, #20              // X10 = address of RET instruction
    SUB X11, X23, X10              // byte offset = does_body - patch_addr
    ASR X11, X11, #2               // word offset (B uses word offset)
    AND W11, W11, #0x3FFFFFF       // mask to 26 bits
    MOV W12, #0x0000
    MOVK W12, #0x1400, LSL #16    // B opcode base (0x14000000)
    ORR W12, W12, W11             // B does_body
    STR W12, [X10]                 // write patched instruction
    // Flush I-cache for the patched instruction
    MOV X0, X10
    ADD X1, X10, #4
    BL platform_flush_icache
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// DOES> ( -- )  IMMEDIATE, COMPILE_ONLY
// Compile-time: emit BL (does>) + epilog, then compile prolog for
// the does-body. ; will close the does-body with its own epilog+RET.
.global forth_does
forth_does:
    STP X29, X30, [SP, #-16]!
    // Compile BL forth_does_runtime
    ADR X0, forth_does_runtime
    BL compile_call
    // Compile epilog+RET (ends defining word's normal path)
    BL compile_ret
    // Compile prolog for does-body (needs its own frame for BL calls)
    BL compile_prolog
    // Does-body starts here. Subsequent words compile into it.
    // ; will close it with epilog+RET.
    LDP X29, X30, [SP], #16
    RET

// ---------- BASE / PAD ----------

// BASE ( -- a-addr )  Push address of BASE variable.
.global forth_base
forth_base:
    ADR X9, base
    STR X9, [X19, #-CELL]!
    RET

// PAD ( -- c-addr )  Push address of PAD scratch buffer.
.global forth_pad
forth_pad:
    ADR X9, pad
    STR X9, [X19, #-CELL]!
    RET

// HLD ( -- a-addr )  Push address of HLD variable (for pictured output).
.global forth_hld
forth_hld:
    ADR X9, hld
    STR X9, [X19, #-CELL]!
    RET

// ---------- TYPE ----------

// TYPE ( c-addr u -- ) — write string to stdout
.global forth_type
forth_type:
    STP X29, X30, [SP, #-16]!
    LDR X1, [X19]               // u (length)
    LDR X0, [X19, #CELL]        // c-addr
    ADD X19, X19, #2*CELL       // pop both
    BL platform_write
    LDP X29, X30, [SP], #16
    RET

// ---------- PICK ----------

// PICK ( xu ... x1 x0 u -- xu ... x1 x0 xu )
// Copy the u-th item (0-indexed: 0 pick = dup).
.global forth_pick
forth_pick:
    LDR X9, [X19]               // u
    ADD X9, X9, #1              // u+1
    LDR X9, [X19, X9, LSL #3]  // DSP[(u+1)*CELL]
    STR X9, [X19]               // overwrite u with result
    RET

// ---------- S" and ." ----------

// forth_s_quote_runtime — runtime helper for inline strings.
// Called via BL. Reads 8-byte length + string after return address (X30).
// Pushes ( c-addr u ) to data stack. Returns past the string.
// Must align return address to 4 bytes for ARM64 instruction alignment.
.global forth_s_quote_runtime
forth_s_quote_runtime:
    LDR X9, [X30]               // length (8 bytes at return addr)
    ADD X10, X30, #8            // c-addr = retaddr + 8
    ADD X30, X30, #8            // skip length
    ADD X30, X30, X9            // skip string bytes
    ADD X30, X30, #3            // align up to 4-byte boundary
    AND X30, X30, #~3
    SUB X19, X19, #2*CELL
    STR X10, [X19, #CELL]       // push c-addr (second)
    STR X9, [X19]               // push u (top)
    RET                          // returns to adjusted address

// compile_s_quote — shared helper for S" and ."
// Parses input for closing ", compiles BL s_quote_runtime + length + string.
// Pads string to 4-byte alignment. Returns with HERE past the string.
compile_s_quote:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    // Load input state
    ADR X9, source_addr
    LDR X23, [X9]               // X23 = source_addr
    ADR X9, to_in
    LDR X24, [X9]               // X24 = to_in (current position)
    ADR X9, source_len
    LDR X25, [X9]               // X25 = source_len
    // Skip one leading space if present
    CMP X24, X25
    B.GE .Lsq_empty
    LDRB W9, [X23, X24]
    CMP W9, #32
    B.NE .Lsq_scan
    ADD X24, X24, #1
.Lsq_scan:
    // Find closing " — X26 = string start
    MOV X26, X24
.Lsq_scan_loop:
    CMP X24, X25
    B.GE .Lsq_no_close
    LDRB W9, [X23, X24]
    CMP W9, #'"'
    B.EQ .Lsq_found
    ADD X24, X24, #1
    B .Lsq_scan_loop
.Lsq_found:
    // X26 = string start, X24 = position of closing "
    SUB X25, X24, X26           // X25 = string length
    ADD X24, X24, #1            // advance past closing "
    ADR X9, to_in
    STR X24, [X9]               // update to_in
    // Bounds check: need BL(4) + CELL(8) + string bytes + 3 (alignment)
    ADD X9, X21, #4+CELL+3      // HERE + BL + CELL + alignment
    ADD X9, X9, X25             // + string length
    ADR X10, dict_space_end
    CMP X9, X10
    B.HI dict_full
    // Compile BL forth_s_quote_runtime
    ADR X0, forth_s_quote_runtime
    BL compile_call
    // Compile .quad length
    STR X25, [X21]
    ADD X21, X21, #CELL
    // Copy string bytes to HERE
    ADD X9, X23, X26            // source = source_addr + start
    MOV X10, X21                // dest = HERE
    MOV X11, X25                // count = length
    CBZ X11, .Lsq_copy_done
.Lsq_copy_loop:
    LDRB W12, [X9], #1
    STRB W12, [X10], #1
    SUBS X11, X11, #1
    B.NE .Lsq_copy_loop
.Lsq_copy_done:
    ADD X21, X21, X25           // advance HERE past string
    // Align HERE to 4-byte boundary (ARM64 instruction alignment)
    ADD X21, X21, #3
    AND X21, X21, #~3
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET
.Lsq_empty:
.Lsq_no_close:
    // No closing quote — abort compilation
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    ADR X9, err_token_addr
    ADR X10, sq_unterminated_name
    STR X10, [X9]
    ADR X9, err_token_len
    MOV X10, #sq_unterminated_name_len
    STR X10, [X9]
    B .Lcf_abort

// S" ( -- c-addr u )  IMMEDIATE, COMPILE_ONLY
.global forth_s_quote
forth_s_quote:
    STP X29, X30, [SP, #-16]!
    BL compile_s_quote
    LDP X29, X30, [SP], #16
    RET

// ." ( -- )  IMMEDIATE, COMPILE_ONLY
// Like S" but also compiles BL forth_type after the string.
.global forth_dot_quote
forth_dot_quote:
    STP X29, X30, [SP, #-16]!
    BL compile_s_quote
    ADR X0, forth_type
    BL compile_call
    LDP X29, X30, [SP], #16
    RET

// ---------- DO / LOOP / +LOOP / I / J / UNLOOP ----------
// All IMMEDIATE + COMPILE_ONLY. Compile inline machine code that
// manipulates the return stack for counted loops.
// Return stack layout during loop: [SP]=index, [SP+8]=limit (STP pair)

// Instruction constants for DO/LOOP inline code
.equ INSN_LDR_X9_X19,         0xF9400269   // LDR X9, [X19]
.equ INSN_LDR_X10_X19_8,      0xF940066A   // LDR X10, [X19, #8]
.equ INSN_ADD_X19_X19_16,     0x91004273   // ADD X19, X19, #16
.equ INSN_CMP_X9_X10,         0xEB0A013F   // CMP X9, X10
.equ INSN_BEQ_0,              0x54000000   // B.EQ +0 (placeholder)
.equ INSN_STP_X9_X10_SP_PRE,  0xA9BF2BE9   // STP X9, X10, [SP, #-16]!
.equ INSN_LDP_X9_X10_SP_POST, 0xA8C12BE9   // LDP X9, X10, [SP], #16
.equ INSN_ADD_X9_1,           0x91000529   // ADD X9, X9, #1
.equ INSN_ADD_X9_X11,         0x8B0B0129   // ADD X9, X9, X11
.equ INSN_LDR_X11_X19_POST8,  0xF840866B   // LDR X11, [X19], #8
// Loop params are on top of SP (DO pushes above prolog frame).
// I reads [SP] for index. J reads [SP+16] to skip inner pair.
.equ INSN_LDR_X9_SP,          0xF94003E9   // LDR X9, [SP]
.equ INSN_LDR_X9_SP_16,       0xF9400BE9   // LDR X9, [SP, #16]
.equ INSN_STR_X9_X19_PRE,     0xF81F8E69   // STR X9, [X19, #-8]!
.equ INSN_ADD_SP_16,           0x910043FF   // ADD SP, SP, #16

// compile_do_inline — emit DO's inline code (24 bytes, 6 instructions).
// Returns: X0 = address of B.EQ instruction (for LOOP to patch).
compile_do_inline:
    CHECK_DICT 24
    MOV W9, #(INSN_LDR_X9_X19 & 0xFFFF)
    MOVK W9, #(INSN_LDR_X9_X19 >> 16), LSL #16
    STR W9, [X21], #4
    MOV W9, #(INSN_LDR_X10_X19_8 & 0xFFFF)
    MOVK W9, #(INSN_LDR_X10_X19_8 >> 16), LSL #16
    STR W9, [X21], #4
    MOV W9, #(INSN_ADD_X19_X19_16 & 0xFFFF)
    MOVK W9, #(INSN_ADD_X19_X19_16 >> 16), LSL #16
    STR W9, [X21], #4
    MOV W9, #(INSN_CMP_X9_X10 & 0xFFFF)
    MOVK W9, #(INSN_CMP_X9_X10 >> 16), LSL #16
    STR W9, [X21], #4
    // B.EQ placeholder
    MOV W9, #(INSN_BEQ_0 & 0xFFFF)
    MOVK W9, #(INSN_BEQ_0 >> 16), LSL #16
    MOV X0, X21                     // X0 = address of B.EQ (for patching)
    STR W9, [X21], #4
    // STP X9, X10, [SP, #-16]!
    MOV W9, #(INSN_STP_X9_X10_SP_PRE & 0xFFFF)
    MOVK W9, #(INSN_STP_X9_X10_SP_PRE >> 16), LSL #16
    STR W9, [X21], #4
    RET

// compile_loop_inline — emit LOOP's inline code (24 bytes, 6 instructions).
// Input: X0 = loop body address (backward target).
// Loop params are on top of SP (pushed by DO above the prolog frame).
// LDP pops them. If loop continues, STP pushes them back.
// When done (B.EQ taken), the LDP has already removed them.
compile_loop_inline:
    CHECK_DICT 24
    STP X29, X30, [SP, #-16]!
    MOV X23, X0
    // LDP X9, X10, [SP], #16  (pop index + limit)
    MOV W9, #(INSN_LDP_X9_X10_SP_POST & 0xFFFF)
    MOVK W9, #(INSN_LDP_X9_X10_SP_POST >> 16), LSL #16
    STR W9, [X21], #4
    // ADD X9, X9, #1
    MOV W9, #(INSN_ADD_X9_1 & 0xFFFF)
    MOVK W9, #(INSN_ADD_X9_1 >> 16), LSL #16
    STR W9, [X21], #4
    // CMP X9, X10
    MOV W9, #(INSN_CMP_X9_X10 & 0xFFFF)
    MOVK W9, #(INSN_CMP_X9_X10 >> 16), LSL #16
    STR W9, [X21], #4
    // B.EQ +3 (skip STP + B = done, loop params already popped)
    MOV W9, #0x0060
    MOVK W9, #0x5400, LSL #16
    STR W9, [X21], #4
    // STP X9, X10, [SP, #-16]! (push back)
    MOV W9, #(INSN_STP_X9_X10_SP_PRE & 0xFFFF)
    MOVK W9, #(INSN_STP_X9_X10_SP_PRE >> 16), LSL #16
    STR W9, [X21], #4
    // B loop_body (backward)
    MOV X0, X23
    BL compile_branch_back
    LDP X29, X30, [SP], #16
    RET

// compile_plus_loop_inline — emit +LOOP's inline code (36 bytes, 9 instructions).
// Input: X0 = loop body address (backward target).
// Uses boundary-crossing detection: exit when (old-limit) XOR (new-limit)
// has the sign bit set (index crossed the limit in either direction).
// Uses X16, X17 as scratch (intra-procedure-call registers, caller-saved).
.equ INSN_SUB_X16_X9_X10,  0xCB0A0130   // SUB X16, X9, X10
.equ INSN_SUB_X17_X9_X10,  0xCB0A0131   // SUB X17, X9, X10
.equ INSN_EOR_X16_X16_X17, 0xCA110210   // EOR X16, X16, X17
.equ INSN_TBNZ_X16_63_3,   0xB7F80070   // TBNZ X16, #63, +3 (skip STP+B)
compile_plus_loop_inline:
    CHECK_DICT 36
    STP X29, X30, [SP, #-16]!
    MOV X23, X0
    // LDP X9, X10, [SP], #16  (pop old index + limit)
    MOV W9, #(INSN_LDP_X9_X10_SP_POST & 0xFFFF)
    MOVK W9, #(INSN_LDP_X9_X10_SP_POST >> 16), LSL #16
    STR W9, [X21], #4
    // LDR X11, [X19], #8  (pop increment from data stack)
    MOV W9, #(INSN_LDR_X11_X19_POST8 & 0xFFFF)
    MOVK W9, #(INSN_LDR_X11_X19_POST8 >> 16), LSL #16
    STR W9, [X21], #4
    // SUB X16, X9, X10  (old - limit, before adding increment)
    MOV W9, #(INSN_SUB_X16_X9_X10 & 0xFFFF)
    MOVK W9, #(INSN_SUB_X16_X9_X10 >> 16), LSL #16
    STR W9, [X21], #4
    // ADD X9, X9, X11  (new index = old + increment)
    MOV W9, #(INSN_ADD_X9_X11 & 0xFFFF)
    MOVK W9, #(INSN_ADD_X9_X11 >> 16), LSL #16
    STR W9, [X21], #4
    // SUB X17, X9, X10  (new - limit)
    MOV W9, #(INSN_SUB_X17_X9_X10 & 0xFFFF)
    MOVK W9, #(INSN_SUB_X17_X9_X10 >> 16), LSL #16
    STR W9, [X21], #4
    // EOR X16, X16, X17  (boundary cross check)
    MOV W9, #(INSN_EOR_X16_X16_X17 & 0xFFFF)
    MOVK W9, #(INSN_EOR_X16_X16_X17 >> 16), LSL #16
    STR W9, [X21], #4
    // TBNZ X16, #63, +3  (sign bit set → crossed → skip STP+B)
    MOV W9, #(INSN_TBNZ_X16_63_3 & 0xFFFF)
    MOVK W9, #(INSN_TBNZ_X16_63_3 >> 16), LSL #16
    STR W9, [X21], #4
    // STP X9, X10, [SP, #-16]! (push back new index + limit)
    MOV W9, #(INSN_STP_X9_X10_SP_PRE & 0xFFFF)
    MOVK W9, #(INSN_STP_X9_X10_SP_PRE >> 16), LSL #16
    STR W9, [X21], #4
    // B loop_body
    MOV X0, X23
    BL compile_branch_back
    LDP X29, X30, [SP], #16
    RET

// DO ( limit index -- ) (R: -- limit index)  IMMEDIATE, COMPILE_ONLY
.global forth_do
forth_do:
    STP X29, X30, [SP, #-16]!
    BL compile_do_inline            // X0 = B.EQ patch address
    // Track nesting for LEAVE validation
    ADR X9, do_depth
    LDR X10, [X9]
    ADD X10, X10, #1
    STR X10, [X9]
    // Push (skip-patch CF_ORIG) (saved-leave CF_LEAVE) (body-addr CF_DEST)
    SUB X19, X19, #6*CELL
    STR X0, [X19, #5*CELL]         // skip-patch address
    MOV X9, #CF_ORIG
    STR X9, [X19, #4*CELL]         // tag
    ADR X9, leave_count
    LDR X10, [X9]                   // save current leave count
    STR X10, [X19, #3*CELL]
    MOV X9, #CF_LEAVE
    STR X9, [X19, #2*CELL]         // tag
    STR X21, [X19, #CELL]          // body address = HERE
    MOV X9, #CF_DEST
    STR X9, [X19]                   // tag
    LDP X29, X30, [SP], #16
    RET

// LOOP ( -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
.global forth_loop
forth_loop:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    MOV X0, #CF_DEST
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X23, [X19], #CELL          // body address
    MOV X0, #CF_LEAVE
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X25, [X19], #CELL          // saved leave count
    MOV X0, #CF_ORIG
    BL cf_check_tag
    ADD X19, X19, #CELL             // drop tag
    LDR X24, [X19], #CELL          // skip-patch address
    MOV X0, X23                     // body address
    BL compile_loop_inline
    MOV X0, X24                     // skip-patch address
    BL patch_forward
    // Patch all LEAVEs for this loop
    ADR X26, leave_count
    LDR X23, [X26]                  // current count
    CMP X25, X23
    B.EQ .Lloop_leave_done
    ADR X24, leave_stack
.Lloop_leave_patch:
    SUB X23, X23, #1
    LDR X0, [X24, X23, LSL #3]     // leave_stack[i]
    BL patch_forward
    CMP X25, X23
    B.NE .Lloop_leave_patch
.Lloop_leave_done:
    STR X25, [X26]                  // restore leave_count
    ADR X9, do_depth
    LDR X10, [X9]
    SUB X10, X10, #1
    STR X10, [X9]
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// +LOOP ( n -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
.global forth_plus_loop
forth_plus_loop:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!
    MOV X0, #CF_DEST
    BL cf_check_tag
    ADD X19, X19, #CELL
    LDR X23, [X19], #CELL          // body address
    MOV X0, #CF_LEAVE
    BL cf_check_tag
    ADD X19, X19, #CELL
    LDR X25, [X19], #CELL          // saved leave count
    MOV X0, #CF_ORIG
    BL cf_check_tag
    ADD X19, X19, #CELL
    LDR X24, [X19], #CELL          // skip-patch address
    MOV X0, X23
    BL compile_plus_loop_inline
    MOV X0, X24
    BL patch_forward
    // Patch all LEAVEs for this loop
    ADR X26, leave_count
    LDR X23, [X26]                  // current count
    CMP X25, X23
    B.EQ .Lploop_leave_done
    ADR X24, leave_stack
.Lploop_leave_patch:
    SUB X23, X23, #1
    LDR X0, [X24, X23, LSL #3]
    BL patch_forward
    CMP X25, X23
    B.NE .Lploop_leave_patch
.Lploop_leave_done:
    STR X25, [X26]                  // restore leave_count
    ADR X9, do_depth
    LDR X10, [X9]
    SUB X10, X10, #1
    STR X10, [X9]
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// I ( -- index )  IMMEDIATE, COMPILE_ONLY
.global forth_i
forth_i:
    CHECK_DICT 8
    MOV W9, #(INSN_LDR_X9_SP & 0xFFFF)
    MOVK W9, #(INSN_LDR_X9_SP >> 16), LSL #16
    STR W9, [X21], #4
    MOV W9, #(INSN_STR_X9_X19_PRE & 0xFFFF)
    MOVK W9, #(INSN_STR_X9_X19_PRE >> 16), LSL #16
    STR W9, [X21], #4
    RET

// J ( -- index )  IMMEDIATE, COMPILE_ONLY
.global forth_j
forth_j:
    CHECK_DICT 8
    MOV W9, #(INSN_LDR_X9_SP_16 & 0xFFFF)
    MOVK W9, #(INSN_LDR_X9_SP_16 >> 16), LSL #16
    STR W9, [X21], #4
    MOV W9, #(INSN_STR_X9_X19_PRE & 0xFFFF)
    MOVK W9, #(INSN_STR_X9_X19_PRE >> 16), LSL #16
    STR W9, [X21], #4
    RET

// LEAVE ( -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
// Emit UNLOOP + forward B. Store patch address in leave_stack.
.global forth_leave
forth_leave:
    ADR X9, do_depth
    LDR X10, [X9]
    CBZ X10, .Lcf_mismatch         // not inside a DO loop
    STP X29, X30, [SP, #-16]!
    CHECK_DICT 4                    // UNLOOP = 4 bytes (compile_branch does its own)
    // Emit UNLOOP: ADD SP, SP, #16
    MOV W9, #(INSN_ADD_SP_16 & 0xFFFF)
    MOVK W9, #(INSN_ADD_SP_16 >> 16), LSL #16
    STR W9, [X21], #4
    // Emit forward B
    BL compile_branch               // X0 = patch address
    // Store in leave array
    ADR X9, leave_count
    LDR X10, [X9]                   // count
    ADR X11, leave_stack
    STR X0, [X11, X10, LSL #3]     // leave_stack[count] = addr
    ADD X10, X10, #1
    STR X10, [X9]                   // leave_count++
    LDP X29, X30, [SP], #16
    RET

// UNLOOP ( -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
// Loop params are on top of SP (above prolog frame).
// Just drop them with ADD SP, SP, #16.
.global forth_unloop
forth_unloop:
    CHECK_DICT 4
    MOV W9, #(INSN_ADD_SP_16 & 0xFFFF)
    MOVK W9, #(INSN_ADD_SP_16 >> 16), LSL #16
    STR W9, [X21], #4
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
DEFWORD dict_paren,      "(",          forth_paren,       dict_tick, F_IMMEDIATE
DEFWORD dict_backslash,  "\\",         forth_backslash,   dict_paren, F_IMMEDIATE
DEFWORD dict_evaluate,   "evaluate",   forth_evaluate,    dict_backslash
DEFWORD dict_included,   "included",   forth_included,    dict_evaluate
DEFWORD dict_if,         "if",         forth_if,          dict_included,  F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_then,       "then",       forth_then,        dict_if,        F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_else,       "else",       forth_else,        dict_then,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_begin,      "begin",      forth_begin,       dict_else,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_until,      "until",      forth_until,       dict_begin,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_again,      "again",      forth_again,       dict_until,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_while,      "while",      forth_while,       dict_again,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_repeat,     "repeat",     forth_repeat,      dict_while,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_recurse,    "recurse",    forth_recurse,     dict_repeat,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_here,       "here",       forth_here,        dict_recurse
DEFWORD dict_allot,      "allot",      forth_allot,       dict_here
DEFWORD dict_comma,      ",",          forth_comma,       dict_allot
DEFWORD dict_c_comma,    "c,",         forth_c_comma,     dict_comma
DEFWORD dict_create,     "create",     forth_create,      dict_c_comma
DEFWORD dict_constant,   "constant",   forth_constant,    dict_create
DEFWORD dict_do,         "do",         forth_do,          dict_constant,  F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_loop,       "loop",       forth_loop,        dict_do,        F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_plus_loop,  "+loop",      forth_plus_loop,   dict_loop,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_i,          "i",          forth_i,           dict_plus_loop, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_j,          "j",          forth_j,           dict_i,         F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_unloop,     "unloop",     forth_unloop,      dict_j,         F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_leave,      "leave",      forth_leave,       dict_unloop,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_does,       "does>",      forth_does,        dict_leave,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_type,       "type",       forth_type,        dict_does
DEFWORD dict_pick,       "pick",       forth_pick,        dict_type
DEFWORD dict_s_quote,    "s\"",        forth_s_quote,     dict_pick,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_dot_quote,  ".\"",        forth_dot_quote,   dict_s_quote,   F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_s_to_d,     "s>d",        forth_s_to_d,      dict_dot_quote
DEFWORD dict_um_star,    "um*",        forth_um_star,     dict_s_to_d
DEFWORD dict_m_star,     "m*",         forth_m_star,      dict_um_star
DEFWORD dict_um_divmod,  "um/mod",     forth_um_divmod,   dict_m_star
DEFWORD dict_sm_rem,     "sm/rem",     forth_sm_rem,      dict_um_divmod
DEFWORD dict_fm_mod,     "fm/mod",     forth_fm_mod,      dict_sm_rem
DEFWORD dict_base,       "base",       forth_base,        dict_fm_mod
DEFWORD dict_pad,        "pad",        forth_pad,         dict_base
DEFWORD dict_hld,        "hld",        forth_hld,         dict_pad
.global dict_hld

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
.global colon_dsp
colon_dsp:                          // DSP at start of : for control-flow balance check
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
.global il_sp
il_sp:                              // SP at interpret_line entry (for cf longjmp)
    .quad 0
.global err_token_addr
err_token_addr:                     // Address of last error token (set by interpret_line)
    .quad 0
.global err_token_len
err_token_len:                      // Length of last error token
    .quad 0
.global file_name_addr
file_name_addr:                     // Filename for INCLUDED error reporting
    .quad 0
.global file_name_len
file_name_len:
    .quad 0
.global file_line_num
file_line_num:                      // Line number for INCLUDED error reporting
    .quad 0
.global do_depth
do_depth:                           // DO nesting depth (for LEAVE validation)
    .quad 0
.global leave_count
leave_count:                        // Number of pending LEAVE patch addresses
    .quad 0
.global leave_stack
leave_stack:                        // Patch addresses for pending LEAVEs
    .space MAX_LEAVES * 8
.global hld
hld:                                // Current HOLD pointer for pictured numeric output
    .quad 0
.equ PAD_SIZE, 68                   // 64 binary digits + sign + padding
.global pad
pad:
    .space PAD_SIZE
