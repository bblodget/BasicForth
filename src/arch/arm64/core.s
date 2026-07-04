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
// [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4] [SrcId:2] [Len:2] [Off:4]
//
// The trailing 8-byte source-metadata block records where a word's source came
// from, for SEE — see docs/See_Metadata.md. It sits *after* CodePtr, so FIND and
// xt derivation are unchanged; only the code-start cursor (CodeLen field + 4 + 8)
// moves. Field sizes: SrcId u16 (source-table id), Len u16 (a single
// definition's source span is never near 64 KB), Off u32 (byte offset into the
// source file). SrcId = PRIM_SRCID for assembly primitives, 0 for REPL/no-file
// words, or a source-table id (>=1) for file-loaded words.
//
// Flags byte: bit 7 = IMMEDIATE, bit 6 = HIDDEN, bits 0-5 = name length
.equ F_IMMEDIATE,   0x80
.equ F_HIDDEN,      0x40
.equ F_COMPILE_ONLY,0x20
.equ F_LENMASK,     0x1F

// Source-metadata: byte count of the trailing (SrcId,Len,Off) block, and the
// SrcId sentinel for assembly primitives.
.equ SRC_META_BYTES, 8
.equ PRIM_SRCID,     0xFFFF

// Source table: maps a source-id (>=1) to the absolute path of a file loaded by
// forth_included, so SEE can re-open the file even if the CWD changes later.
// Lives in .bss (out of the dict). id k -> slot k-1. id 0 = REPL/no file.
.equ SRC_TABLE_MAX,  64             // max distinct source files per run
.equ SRC_PATH_MAX,   1024           // max bytes per stored (absolutized) path
.equ ABS_PATH_MAX,   1024           // getcwd + path build buffer size


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
\entry\()_srcid:
    .hword PRIM_SRCID               // SrcId:2 — assembly primitive (no captured source)
\entry\()_len:
    .hword 0                        // Len:2
\entry\()_off:
    .long 0                         // Off:4
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

// LSHIFT ( x1 u -- x2 )
// Logical left shift
.global forth_lshift
forth_lshift:

    LDR X9, [X19], #CELL       // pop shift count
    LDR X10, [X19]              // x1
    LSL X10, X10, X9
    STR X10, [X19]
    RET

// RSHIFT ( x1 u -- x2 )
// Logical right shift
.global forth_rshift
forth_rshift:

    LDR X9, [X19], #CELL       // pop shift count
    LDR X10, [X19]              // x1
    LSR X10, X10, X9
    STR X10, [X19]
    RET

// 2/ ( x -- x/2 )
// Arithmetic right shift by 1 (floor of x/2)
.global forth_two_div
forth_two_div:

    LDR X9, [X19]
    ASR X9, X9, #1
    STR X9, [X19]
    RET

// U< ( u1 u2 -- flag )
// Unsigned less-than comparison
.global forth_u_less
forth_u_less:

    LDR X9, [X19], #CELL       // pop u2
    LDR X10, [X19]              // u1
    CMP X10, X9
    CSETM X10, LO              // -1 if u1 < u2 (unsigned), 0 otherwise
    STR X10, [X19]
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

// W@ (16-bit fetch, zero-extended) ( addr -- u )
.global forth_wfetch
forth_wfetch:
    LDR X9, [X19]
    LDRH W9, [X9]
    STR X9, [X19]
    RET

// W! (16-bit store, low 16 bits) ( x addr -- )
.global forth_wstore
forth_wstore:
    LDR X9, [X19], #CELL      // pop addr
    LDR X10, [X19], #CELL     // pop x
    STRH W10, [X9]
    RET

// L@ (32-bit fetch, zero-extended) ( addr -- u )
.global forth_lfetch
forth_lfetch:
    LDR X9, [X19]
    LDR W9, [X9]              // 32-bit load zero-extends into X9
    STR X9, [X19]
    RET

// L! (32-bit store, low 32 bits) ( x addr -- )
.global forth_lstore
forth_lstore:
    LDR X9, [X19], #CELL      // pop addr
    LDR X10, [X19], #CELL     // pop x
    STR W10, [X9]
    RET

// (ioctl) ( fd request argp -- ret )
// Generic ioctl from Forth. ret = kernel result (negative errno on failure).
.global forth_ioctl
forth_ioctl:
    LDR X2, [X19]            // argp (top)
    LDR X1, [X19, #CELL]     // request
    LDR X0, [X19, #(2*CELL)] // fd
    ADD X19, X19, #(2*CELL)  // pop argp, request; result replaces fd slot
    STP X29, X30, [SP, #-16]!
    BL platform_ioctl
    LDP X29, X30, [SP], #16
    STR X0, [X19]
    RET

// (mmap-dev) ( fd offset size -- addr )
// Shared read/write mmap of a device fd at a byte offset (DRM dumb buffer).
.global forth_mmap_dev
forth_mmap_dev:
    LDR X1, [X19]            // size (top)
    LDR X2, [X19, #CELL]     // offset
    LDR X0, [X19, #(2*CELL)] // fd
    ADD X19, X19, #(2*CELL)
    STP X29, X30, [SP, #-16]!
    BL platform_mmap_dev
    LDP X29, X30, [SP], #16
    STR X0, [X19]
    RET

// FILL32 ( value addr count -- )
// Store COUNT copies of the 32-bit VALUE starting at ADDR (4 bytes each).
// Fast block fill for 32bpp pixel buffers (clear, fill-rect rows).
.global forth_fill32
forth_fill32:
    LDR X2, [X19]            // count (top)
    LDR X1, [X19, #CELL]     // addr
    LDR X0, [X19, #(2*CELL)] // value (low 32 bits used)
    ADD X19, X19, #(3*CELL)  // pop all three
.Lfill32_loop:
    CBZ X2, .Lfill32_done
    STR W0, [X1], #4         // store value, post-increment addr by 4
    SUB X2, X2, #1
    B .Lfill32_loop
.Lfill32_done:
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
    BL platform_raw_mode       // lazily enter raw mode on first interactive input
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

    BL platform_raw_mode        // lazily enter raw mode on first interactive input

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
    // No word: return ( 0 0 ). u = 0 is the signal; the c-addr is a deliberate
    // NULL — callers must check u before fetching (CHAR/[CHAR] do), never deref.
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
msg_undef_defer: .ascii "uninitialized deferred word\n"
.equ msg_undef_defer_len, . - msg_undef_defer
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

// ---------- source-metadata helpers ----------

// meta_from_entry: X10 = entry (header) -> X10 = address of its source-metadata
// block [SrcId:2][Len:2][Off:4]. Clobbers X11. Leaf (no BL).
meta_from_entry:
    LDRB W11, [X10, #8]            // flags+len byte
    AND W11, W11, #F_LENMASK       // name length
    ADD X11, X11, #16             // + 9 + 7  (so (namelen+9+7)&~7 = align8(9+namelen))
    AND X11, X11, #~7
    ADD X10, X10, X11             // entry + align8(9+namelen) = CodePtr cell
    ADD X10, X10, #12            // + CodePtr(8) + CodeLen(4) = metadata block
    RET

// src_register: X0 = path addr, X1 = path length -> X0 = source-id (>=1), or 0
// if the table is full. Dedups by (len, bytes) so repeated loads of the same
// file (e.g. reload) reuse one id. Clobbers X0-X3, X9-X15. Preserves X19-X28.
src_register:
    MOV X9, #0                     // X9 = slot index
.Lsr_scan:
    ADR X10, src_table_count
    LDR X10, [X10]
    CMP X9, X10
    B.GE .Lsr_new                  // past end -> add a new slot
    ADR X10, src_table_lens
    LDR X11, [X10, X9, LSL #3]     // X11 = slot len
    CMP X11, X1
    B.NE .Lsr_scan_next            // length differs
    MOV X12, #SRC_PATH_MAX
    MUL X12, X9, X12
    ADR X13, src_table_paths
    ADD X13, X13, X12              // X13 = slot path addr
    MOV X14, X0                    // input path
    MOV X15, X1                    // compare count
    CBZ X15, .Lsr_hit
.Lsr_cmp:
    LDRB W2, [X14], #1
    LDRB W3, [X13], #1
    CMP W2, W3
    B.NE .Lsr_scan_next
    SUB X15, X15, #1
    CBNZ X15, .Lsr_cmp
.Lsr_hit:
    ADD X0, X9, #1                 // id = slot + 1
    RET
.Lsr_scan_next:
    ADD X9, X9, #1
    B .Lsr_scan
.Lsr_new:
    ADR X10, src_table_count
    LDR X9, [X10]                  // new slot index
    CMP X9, #SRC_TABLE_MAX
    B.GE .Lsr_full
    MOV X12, #SRC_PATH_MAX         // clamp length to slot size
    CMP X1, X12
    B.LS .Lsr_len_ok
    MOV X1, X12
.Lsr_len_ok:
    ADR X10, src_table_lens
    STR X1, [X10, X9, LSL #3]      // store length
    MOV X12, #SRC_PATH_MAX
    MUL X12, X9, X12
    ADR X13, src_table_paths
    ADD X13, X13, X12              // dest slot
    MOV X14, X0
    MOV X15, X1
    CBZ X15, .Lsr_copied
.Lsr_copy:
    LDRB W2, [X14], #1
    STRB W2, [X13], #1
    SUB X15, X15, #1
    CBNZ X15, .Lsr_copy
.Lsr_copied:
    ADD X0, X9, #1                 // id = ++count
    ADR X10, src_table_count
    STR X0, [X10]
    RET
.Lsr_full:
    MOV X0, #0                     // table full -> 0 (word treated as no-source)
    RET

// make_absolute: X0 = path addr, X1 = path len -> X0 = path, X1 = len that SEE
// can re-open regardless of a later CWD change. An already-absolute path
// (leading '/') passes through unchanged. A relative path becomes
// getcwd()+'/'+path in abs_path_buf; if getcwd fails or the result would
// overflow, the original (relative) path is kept. Clobbers X0,X1,X9-X15.
make_absolute:
    STP X29, X30, [SP, #-16]!      // calls platform_getcwd via BL
    LDRB W9, [X0]
    CMP W9, #'/'
    B.EQ .Lma_done                 // already absolute -> unchanged
    STP X0, X1, [SP, #-16]!        // save rel addr/len across platform_getcwd
    ADR X0, abs_path_buf
    MOV X1, #ABS_PATH_MAX
    BL platform_getcwd            // -> X0 = bytes incl NUL, or -errno
    LDP X12, X13, [SP], #16       // X12 = rel addr, X13 = rel len
    CMP X0, #0
    B.LE .Lma_fail                // getcwd failed -> keep relative
    SUB X0, X0, #1                // X0 = cwd string length (drop NUL)
    ADD X9, X0, X13
    ADD X9, X9, #1                // total = cwd_len + '/' + rel_len
    CMP X9, #ABS_PATH_MAX
    B.GE .Lma_fail                // would overflow -> keep relative
    ADR X10, abs_path_buf
    ADD X11, X10, X0             // X11 = end of cwd
    MOV W9, #'/'
    STRB W9, [X11], #1
    MOV X14, X12                 // rel src
    MOV X15, X13                 // count
    CBZ X15, .Lma_built
.Lma_copy:
    LDRB W9, [X14], #1
    STRB W9, [X11], #1
    SUB X15, X15, #1
    CBNZ X15, .Lma_copy
.Lma_built:
    ADD X1, X0, X13             // abs len = cwd_len + rel_len
    ADD X1, X1, #1              //   + '/'
    ADR X0, abs_path_buf        // X0 = absolute path
    LDP X29, X30, [SP], #16
    RET
.Lma_fail:
    MOV X0, X12                 // restore the relative path
    MOV X1, X13
    LDP X29, X30, [SP], #16
    RET
.Lma_done:
    LDP X29, X30, [SP], #16
    RET

// src_finalize: X0 = end offset (next-line start within the current source).
// Fill Len for definitions completed on the line(s) just interpreted (HIDDEN
// defs are skipped, finalized on their own closing line; stops at a different
// source or an already-filled Len). Clobbers X9-X15. Preserves X19-X28.
src_finalize:
    STP X29, X30, [SP, #-16]!      // meta_from_entry is reached via BL
    MOV X12, X0                    // X12 = end
    MOV X9, X22                    // X9 = walk pointer = LATEST
.Lsf_loop:
    CBZ X9, .Lsf_done
    LDRB W10, [X9, #8]            // flags
    TST W10, #F_HIDDEN
    B.NE .Lsf_skip                // in-progress def -> leave for its closing line
    MOV X10, X9
    BL meta_from_entry            // X10 = meta (clobbers X11)
    LDRH W11, [X10]              // SrcId
    ADR X13, cur_source_id
    LDR X13, [X13]
    CMP X11, X13
    B.NE .Lsf_done                // different source -> done
    LDRH W11, [X10, #2]         // Len
    CBNZ X11, .Lsf_done          // already finalized -> done
    LDR W13, [X10, #4]          // Off (u32)
    SUB W13, W12, W13           // end - Off
    STRH W13, [X10, #2]         // store Len (u16)
.Lsf_skip:
    LDR X9, [X9]                  // follow link
    B .Lsf_loop
.Lsf_done:
    LDP X29, X30, [SP], #16
    RET

// (source-path) ( id -- c-addr u )  Resolved path for a source-id, or 0 0.
.global forth_source_path
forth_source_path:
    LDR X0, [X19]                  // id
    CBZ X0, .Lsp_none
    ADR X9, src_table_count
    LDR X9, [X9]
    CMP X0, X9
    B.HI .Lsp_none                // id > count -> none
    SUB X1, X0, #1                // slot = id - 1
    MOV X9, #SRC_PATH_MAX
    MUL X9, X1, X9
    ADR X10, src_table_paths
    ADD X9, X10, X9               // X9 = path addr
    ADR X10, src_table_lens
    LDR X10, [X10, X1, LSL #3]    // X10 = len
    STR X9, [X19]                 // replace id with c-addr
    STR X10, [X19, #-CELL]!       // push len
    RET
.Lsp_none:
    STR XZR, [X19]               // c-addr = 0
    STR XZR, [X19, #-CELL]!      // u = 0
    RET

// (find-meta) ( c-addr u -- xt off len srcid flag )
// Look up name (case-insensitive, skipping hidden words) and return its source
// metadata. flag = -1 found / 0 not found (other cells 0 when not found).
.global forth_find_meta
forth_find_meta:
    STP X29, X30, [SP, #-16]!      // meta_from_entry is reached via BL
    LDR X1, [X19]                  // X1 = u (name length)
    LDR X0, [X19, #CELL]          // X0 = c-addr
    ADD X19, X19, #2*CELL
    MOV X9, X22                    // X9 = walk pointer = LATEST
.Lfm_loop:
    CBZ X9, .Lfm_notfound
    LDRB W10, [X9, #8]
    TST W10, #F_HIDDEN
    B.NE .Lfm_next                // hidden -> skip
    AND W10, W10, #F_LENMASK
    CMP X10, X1
    B.NE .Lfm_next                // length differs
    ADD X11, X9, #9               // entry name start (already lowercase)
    MOV X12, X0                    // input ptr
    MOV X13, X1                    // count
    CBZ X13, .Lfm_match
.Lfm_cmp:
    LDRB W14, [X12], #1          // input char
    CMP W14, #'A'
    B.LO .Lfm_nolc
    CMP W14, #'Z'
    B.HI .Lfm_nolc
    ADD W14, W14, #0x20         // lowercase the input char
.Lfm_nolc:
    LDRB W15, [X11], #1
    CMP W14, W15
    B.NE .Lfm_next
    SUB X13, X13, #1
    CBNZ X13, .Lfm_cmp
.Lfm_match:
    MOV X10, X9
    BL meta_from_entry            // X10 = meta (clobbers X11)
    LDUR X9, [X10, #-12]         // xt = CodePtr value (meta - 12)
    STR X9, [X19, #-CELL]!        // xt
    LDR W9, [X10, #4]           // off (u32)
    STR X9, [X19, #-CELL]!        // off
    LDRH W9, [X10, #2]          // len (u16)
    STR X9, [X19, #-CELL]!        // len
    LDRH W9, [X10]              // srcid (u16)
    STR X9, [X19, #-CELL]!        // srcid
    MOV X9, #-1
    STR X9, [X19, #-CELL]!        // flag = found
    LDP X29, X30, [SP], #16
    RET
.Lfm_next:
    LDR X9, [X9]                  // follow link
    B .Lfm_loop
.Lfm_notfound:
    STR XZR, [X19, #-CELL]!       // xt
    STR XZR, [X19, #-CELL]!       // off
    STR XZR, [X19, #-CELL]!       // len
    STR XZR, [X19, #-CELL]!       // srcid
    STR XZR, [X19, #-CELL]!       // flag = not found
    LDP X29, X30, [SP], #16
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

    // Write code pointer — points past CodePtr(8)+CodeLen(4)+SrcMeta(8)
    ADD X9, X21, #20
    STR X9, [X21]
    ADD X21, X21, #CELL

    // Write code_len placeholder (0), save its address
    ADR X9, colon_code_len_addr
    STR X21, [X9]
    STR WZR, [X21]
    ADD X21, X21, #4               // past CodeLen

    // Write source metadata: SrcId/Off from the current source context (set by
    // forth_included; 0/0 at the REPL). Len stays 0 until the definition's span
    // is finalized at end of line.
    ADR X9, cur_source_id
    LDR X9, [X9]
    STRH W9, [X21]                 // SrcId:2
    STRH WZR, [X21, #2]           // Len:2 (filled at finalize)
    ADR X9, cur_line_off
    LDR X9, [X9]
    STR W9, [X21, #4]            // Off:4
    ADD X21, X21, #SRC_META_BYTES  // HERE now at code area

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

    // Calculate code length and write it (skip for :NONAME)
    ADR X9, colon_code_len_addr
    LDR X9, [X9]                    // X9 = code_len field address
    CBZ X9, .Lsemi_noname           // :NONAME has no code_len field
    ADD X10, X9, #12                // X10 = code start (past CodeLen + 8-byte SrcMeta)
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
    B .Lsemi_done

.Lsemi_noname:
    // Flush I-cache for :NONAME compiled code
    ADR X9, saved_here
    LDR X0, [X9]                    // start = saved HERE (xt)
    MOV X1, X21                     // end = HERE
    BL platform_flush_icache

.Lsemi_done:
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
    STP X27, X28, [SP, #-16]!

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
    ADR X14, source_id
    LDR X27, [X14]                  // save old source_id

    // Set new source context
    STR X10, [X11]                  // source_addr = c-addr
    STR X9, [X12]                   // source_len = u
    STR XZR, [X13]                  // to_in = 0
    MOV X9, #-1
    STR X9, [X14]                   // source_id = -1 (EVALUATE)

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
    ADR X9, source_id
    STR X27, [X9]

    MOV X0, X26                     // restore result
    LDP X27, X28, [SP], #16
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
    // Save the source context (restored in .Lincl_pop_regs) so nested includes
    // don't clobber the parent's.
    ADR X9, cur_source_id
    LDR X10, [X9]
    ADR X9, cur_line_off
    LDR X11, [X9]
    STP X10, X11, [SP, #-16]!

    // Pop c-addr and u from data stack
    LDR X1, [X19]                   // X1 = u (filename length)
    LDR X0, [X19, #CELL]            // X0 = c-addr (filename)
    ADD X19, X19, #2*CELL

    // Save filename for error reporting
    ADR X9, file_name_addr
    STR X0, [X9]
    ADR X9, file_name_len
    STR X1, [X9]

    // Default resolved path = the as-typed name (CWD hit). The BASICFORTH_PATH
    // fallback overrides this if a prefixed path opens the file instead.
    ADR X9, incl_resolved_addr
    STR X0, [X9]
    ADR X9, incl_resolved_len
    STR X1, [X9]

    // Open file (X0=path, X1=len)
    BL platform_open_file           // -> X0=fd
    CMP X0, #0
    B.LT .Lincl_open_err

.Lincl_open_ok:
    MOV X9, #1                      // the file was found and opened
    ADR X10, incl_opened
    STR X9, [X10]
    MOV X23, X0                     // X23 = fd

    // Register the resolved path -> source-id and set the current source context
    // so build_header stamps file-loaded words with it. (src_register dedups, so
    // a reload of the same file reuses one id.)
    ADR X9, incl_resolved_addr
    LDR X0, [X9]
    ADR X9, incl_resolved_len
    LDR X1, [X9]
    BL make_absolute                // X0/X1 -> CWD-independent absolute path
    BL src_register                 // -> X0 = id (preserves X23)
    ADR X9, cur_source_id
    STR X0, [X9]
    ADR X9, cur_line_off
    STR XZR, [X9]

    // Get file size
    MOV X0, X23
    BL platform_fstat               // -> X0=size
    MOV X24, X0                     // X24 = file size
    CMP X24, #0
    B.LE .Lincl_empty               // empty (or fstat error) → nothing to map

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

    // Save the outer interpreter's source pointers. The line loop overwrites
    // source_addr/source_len/to_in; the caller must keep parsing its own line
    // after we return, and the mmap is freed on exit, so these are restored on
    // the loop-exit paths. 32 bytes keeps SP 16-aligned (3 used, 8 pad).
    SUB SP, SP, #32
    ADR X9, source_addr
    LDR X10, [X9]
    STR X10, [SP, #0]
    ADR X9, source_len
    LDR X10, [X9]
    STR X10, [SP, #8]
    ADR X9, to_in
    LDR X10, [X9]
    STR X10, [SP, #16]

    // Process file line by line
    // X25 = mmap base, X24 = file size, X26 = line_start offset
    MOV X26, #0                     // line_start = 0
    MOV X9, #1
    ADR X10, file_line_num
    STR X9, [X10]                   // line counter = 1

    // Skip a leading "#!" shebang line so a Forth file can be a Unix
    // executable script (#!/usr/bin/env basicforth). Only the first line, and
    // only on an exact "#!" so a leading '#' decimal literal is unaffected.
    CMP X24, #2
    B.LT .Lincl_line_loop           // too short to be a shebang
    LDRB W9, [X25]
    CMP W9, #'#'
    B.NE .Lincl_line_loop
    LDRB W9, [X25, #1]
    CMP W9, #'!'
    B.NE .Lincl_line_loop
.Lincl_sb_scan:
    CMP X26, X24
    B.GE .Lincl_line_loop           // no newline → whole file was shebang
    LDRB W9, [X25, X26]
    CMP W9, #'\n'
    B.EQ .Lincl_sb_eol
    ADD X26, X26, #1
    B .Lincl_sb_scan
.Lincl_sb_eol:
    ADD X26, X26, #1                // step past the newline
    MOV X9, #2
    ADR X10, file_line_num
    STR X9, [X10]                   // first real line is line 2

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

    ADR X11, cur_line_off          // this line's byte offset (for source metadata)
    STR X26, [X11]

    // Save error-reporting globals across the call: a nested INCLUDE/INCLUDED
    // would otherwise overwrite them and leave our own errors pointing at the
    // wrong file and line. X0 (the result) is preserved across the restore.
    ADR X9, file_name_addr
    LDR X9, [X9]
    ADR X10, file_name_len
    LDR X10, [X10]
    ADR X11, file_line_num
    LDR X11, [X11]
    STP X9, X10, [SP, #-16]!
    STP X11, XZR, [SP, #-16]!
    BL forth_interpret_line
    LDP X11, XZR, [SP], #16
    LDP X9, X10, [SP], #16
    ADR X12, file_name_addr
    STR X9, [X12]
    ADR X12, file_name_len
    STR X10, [X12]
    ADR X12, file_line_num
    STR X11, [X12]

    CBNZ X0, .Lincl_error

    // Finalize source spans for any definitions completed on this line.
    MOV X0, X28                     // end = next-line start offset
    BL src_finalize

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
    // Restore the outer interpreter's source pointers (saved before the loop)
    LDR X10, [SP, #0]
    ADR X9, source_addr
    STR X10, [X9]
    LDR X10, [SP, #8]
    ADR X9, source_len
    STR X10, [X9]
    LDR X10, [SP, #16]
    ADR X9, to_in
    STR X10, [X9]
    ADD SP, SP, #32
    MOV X0, #0                      // return 0 = success
    B .Lincl_pop_regs

// Shared register epilogue (no source restore — for paths that never ran the
// line loop, so never saved the source pointers).
.Lincl_pop_regs:
    LDP X10, X11, [SP], #16         // restore source context saved at entry
    ADR X9, cur_source_id
    STR X10, [X9]
    ADR X9, cur_line_off
    STR X11, [X9]
    LDP X27, X28, [SP], #16
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// Empty file (size 0): nothing was mapped, source pointers were not saved.
.Lincl_empty:
    MOV X0, X23                     // fd
    BL platform_close_file
    MOV X0, #0                      // return 0 = success
    B .Lincl_pop_regs

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
    // Restore the outer interpreter's source pointers (saved before the loop)
    LDR X10, [SP, #0]
    ADR X9, source_addr
    STR X10, [X9]
    LDR X10, [SP, #8]
    ADR X9, source_len
    STR X10, [X9]
    LDR X10, [SP, #16]
    ADR X9, to_in
    STR X10, [X9]
    ADD SP, SP, #32
    MOV X0, #1                      // return 1 = error
    B .Lincl_pop_regs

.Lincl_open_err:
    // Check for ENOENT (-2) — try BASICFORTH_PATH fallback
    CMN X0, #2
    B.NE .Lincl_open_other

    // BASICFORTH_PATH is a colon-separated list of directories. Try each in
    // order; load the first match. CWD was already tried above. Empty segments
    // are skipped (CWD is the implicit first lookup, so we don't re-search it).
    //
    // Loop registers (callee-saved → survive BL platform_open_file; they are
    // reinitialized at .Lincl_open_ok on success):
    //   X23 = cursor into basicforth_path (current segment start)
    //   X24 = bytes remaining from the cursor
    //   X25 = length of the current segment
    ADR X9, basicforth_path
    LDR X23, [X9]
    CBZ X23, .Lincl_open_skip       // not set → silent skip
    ADR X9, basicforth_path_len
    LDR X24, [X9]

.Lincl_seg_loop:
    CBZ X24, .Lincl_open_skip       // no segments left → silent skip
    // Scan for ':' to find this segment's length
    MOV X25, #0                     // seg_len = 0
.Lincl_seg_scan:
    CMP X25, X24
    B.GE .Lincl_seg_have           // X25 >= remaining → end of segment
    LDRB W9, [X23, X25]
    CMP W9, #':'
    B.EQ .Lincl_seg_have
    ADD X25, X25, #1
    B .Lincl_seg_scan
.Lincl_seg_have:
    // X25 = segment length; skip empty segments
    CBZ X25, .Lincl_seg_next
    // Clamp total (seg + '/' + filename) to 511 bytes
    ADR X9, file_name_len
    LDR X4, [X9]                    // X4 = filename len
    ADD X5, X25, X4
    ADD X5, X5, #1                  // total = seglen + 1 + namelen
    CMP X5, #511
    B.GT .Lincl_seg_next           // too long → try next segment
    // Build "segment/filename" in incl_path_buf
    ADR X2, incl_path_buf
    MOV X0, X23                     // segment start
    MOV X1, X25                     // segment length
.Lincl_copy_path:
    CBZ X1, .Lincl_copy_slash
    LDRB W6, [X0], #1
    STRB W6, [X2], #1
    SUB X1, X1, #1
    B .Lincl_copy_path
.Lincl_copy_slash:
    MOV W6, #'/'
    STRB W6, [X2], #1
    // Copy filename
    ADR X9, file_name_addr
    LDR X0, [X9]
    ADR X9, file_name_len
    LDR X1, [X9]
.Lincl_copy_name:
    CBZ X1, .Lincl_try_open2
    LDRB W6, [X0], #1
    STRB W6, [X2], #1
    SUB X1, X1, #1
    B .Lincl_copy_name
.Lincl_try_open2:
    // Try opening the prefixed path
    ADR X0, incl_path_buf
    MOV X1, X25                     // segment length
    ADR X9, file_name_len
    LDR X9, [X9]
    ADD X1, X1, X9
    ADD X1, X1, #1                  // +1 for '/'
    BL platform_open_file
    CMP X0, #0
    B.LT .Lincl_seg_next           // failed → try next segment
    // Found. Keep the original filename for error reporting — incl_path_buf is
    // scratch only, so a nested INCLUDE that reuses it can't corrupt our error
    // context. But record incl_path_buf as the *resolved* path so SEE can
    // re-open the file. Don't touch X0 — .Lincl_open_ok consumes it as the fd.
    ADR X9, incl_path_buf
    ADR X10, incl_resolved_addr
    STR X9, [X10]
    MOV X9, X25                     // segment length
    ADR X10, file_name_len
    LDR X10, [X10]
    ADD X9, X9, X10                 // + filename
    ADD X9, X9, #1                  // + '/'
    ADR X10, incl_resolved_len
    STR X9, [X10]
    B .Lincl_open_ok
.Lincl_seg_next:
    // Advance past this segment, then skip the ':' delimiter if present
    ADD X23, X23, X25
    SUB X24, X24, X25
    CBZ X24, .Lincl_open_skip      // no trailing delimiter → done
    ADD X23, X23, #1               // skip ':'
    SUB X24, X24, #1
    B .Lincl_seg_loop

.Lincl_open_other:
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
    B .Lincl_pop_regs

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
    B .Lincl_pop_regs

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

// ---------- CASE / OF / ENDOF / ENDCASE ----------
// All IMMEDIATE + COMPILE_ONLY.

// CASE ( -- 0 )  Push sentinel on compile-time stack.
.global forth_case
forth_case:
    STR XZR, [X19, #-CELL]!
    RET

// OF ( x1 x2 -- | x1 )  Compile OVER = 0BRANCH(fwd) DROP.
.global forth_of
forth_of:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    // Compile OVER
    ADR X0, forth_over
    BL compile_call
    // Compile =
    ADR X0, forth_equal
    BL compile_call
    // Compile 0branch
    BL compile_0branch             // X0 = patch address
    MOV X23, X0                    // save
    // Compile DROP
    ADR X0, forth_drop
    BL compile_call
    // Push patch address
    STR X23, [X19, #-CELL]!
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ENDOF ( -- )  Compile branch, patch OF's 0branch.
.global forth_endof
forth_endof:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    // Pop OF's patch address
    LDR X23, [X19], #CELL
    // Compile unconditional branch
    BL compile_branch              // X0 = branch patch address
    MOV X24, X0                    // save branch patch
    // Patch OF's 0branch to HERE
    MOV X0, X23
    BL patch_forward
    // Push branch's patch address for ENDCASE
    STR X24, [X19, #-CELL]!
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ENDCASE ( x -- )  Compile DROP, patch all ENDOF branches.
.global forth_endcase
forth_endcase:
    STP X29, X30, [SP, #-16]!
    // Compile DROP
    ADR X0, forth_drop
    BL compile_call
.Lendcase_loop:
    LDR X0, [X19], #CELL          // pop address
    CBZ X0, .Lendcase_done
    BL patch_forward
    B .Lendcase_loop
.Lendcase_done:
    LDP X29, X30, [SP], #16
    RET

// ---------- PARSE ----------
// PARSE ( char "ccc<char>" -- c-addr u )
// Parse input delimited by char. Does NOT skip leading delimiters.
.global forth_parse
forth_parse:
    LDR X0, [X19], #CELL           // pop delimiter char

    // Load source context
    ADR X9, source_addr
    LDR X10, [X9]                   // X10 = buffer base
    ADR X9, source_len
    LDR X11, [X9]                   // X11 = total length
    ADR X9, to_in
    LDR X12, [X9]                   // X12 = current offset (>IN)

    // Start of parsed region
    ADD X14, X10, X12               // X14 = c-addr (start)
    MOV X15, X12                    // X15 = start offset (save)

    // Scan for delimiter
.Lparse_scan:
    CMP X12, X11
    B.GE .Lparse_end
    LDRB W13, [X10, X12]
    CMP W13, W0
    B.EQ .Lparse_found
    ADD X12, X12, #1
    B .Lparse_scan

.Lparse_found:
    // Delimiter found — advance >IN past it
    ADD X13, X12, #1
    ADR X9, to_in
    STR X13, [X9]
    B .Lparse_push

.Lparse_end:
    // End of input — >IN = source_len
    ADR X9, to_in
    STR X12, [X9]

.Lparse_push:
    // Length = X12 - start offset
    SUB X12, X12, X15
    STR X14, [X19, #-CELL]!        // push c-addr
    STR X12, [X19, #-CELL]!        // push u
    RET

// ---------- SOURCE-ID ----------
// SOURCE-ID ( -- n )
.global forth_source_id
forth_source_id:
    ADR X9, source_id
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!
    RET

// ---------- VALUE ----------
// VALUE ( x "name" -- )
// Like CONSTANT but TO can modify the inline value.
.global forth_value
forth_value:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Pop value, save on return stack
    LDR X9, [X19], #CELL
    STP X9, XZR, [SP, #-16]!

    BL build_header
    CBNZ X0, .Lvalue_err

    // Compile code that pushes the value
    LDP X0, X9, [SP], #16          // restore value
    BL compile_prolog
    BL compile_literal
    BL compile_ret

    // Fill code_len
    ADR X9, colon_code_len_addr
    LDR X9, [X9]
    ADD X10, X9, #12               // code start (past CodeLen + 8-byte SrcMeta)
    SUB X11, X21, X10
    STR W11, [X9]

    // Flush I-cache
    ADD X0, X9, #12               // start = code start
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

.Lvalue_err:
    LDP X9, X10, [SP], #16
    STR X9, [X19, #-CELL]!
    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- TO ----------
// TO ( x "name" -- ) IMMEDIATE
// Value address on ARM64 = xt + 8 (past STP prolog + BL forth_lit opcode).
.global forth_to
forth_to:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    BL forth_parse_word
    BL forth_find
    LDR X23, [X19]                  // flag
    CBZ X23, .Lto_not_found

    ADD X19, X19, #CELL             // drop flag
    LDR X0, [X19], #CELL           // pop xt

    // Value address = xt + 8 (STP=4 + BL=4, then 8-byte inline value)
    ADD X23, X0, #8                 // X23 = addr of inline value

    // Check STATE
    ADR X9, state
    LDR X9, [X9]
    CBNZ X9, .Lto_compile

    // Interpret mode: pop x, store to value address
    LDR X9, [X19], #CELL
    STR X9, [X23]
    MOV X9, #1                      // signal a direct TO/IS so the session log can
    ADR X10, assign_flag            //   persist this line (read via (assign?))
    STR X9, [X10]
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lto_compile:
    // Compile mode: compile LITERAL(addr) + BL(forth_store)
    MOV X0, X23
    BL compile_literal
    ADR X0, forth_store
    BL compile_call
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lto_not_found:
    ADD X19, X19, #CELL             // drop 0 flag
    LDR X9, [X19]
    ADR X10, err_token_len
    STR X9, [X10]
    LDR X9, [X19, #CELL]
    ADR X10, err_token_addr
    STR X9, [X10]
    ADD X19, X19, #(2*CELL)
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    B .Lcf_abort

// ---------- (assign?) ----------
// (assign?) ( -- flag )  Read and clear the one-shot "a direct TO/IS happened"
// flag (set only by forth_to's interpret-mode store). Used by the session
// capture to persist an assignment line that defined no new word.
.global forth_assign_query
forth_assign_query:
    ADR X10, assign_flag
    LDR X9, [X10]
    STR XZR, [X10]
    STR X9, [X19, #-CELL]!
    RET

// ---------- DEFER ----------
// DEFER ( "name" -- )  Create a deferred (vectored) word. Executing it runs the
// xt stored in its inline cell (at xt+8: prolog 4 + BL forth_lit 4, same layout
// VALUE uses); set that xt with IS. Initialized to forth_undef_defer, which
// aborts if the word is executed before IS. Body: prolog ; BL forth_lit ; <xt> ;
// BL forth_execute ; epilog — forth_lit pushes the stored xt, forth_execute runs it.
.global forth_defer
forth_defer:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!

    BL build_header
    CBNZ X0, .Ldefer_err

    BL compile_prolog
    ADR X0, forth_undef_defer       // initial action xt
    BL compile_literal              // BL forth_lit + 8-byte action cell
    ADR X0, forth_execute
    BL compile_call                 // BL forth_execute
    BL compile_ret

    // Fill code_len (code starts past CodeLen + 8-byte SrcMeta = +12)
    ADR X9, colon_code_len_addr
    LDR X9, [X9]
    ADD X10, X9, #12
    SUB X11, X21, X10
    STR W11, [X9]

    // Flush I-cache over the compiled code
    ADD X0, X9, #12
    MOV X1, X21
    BL platform_flush_icache

    // Clear HIDDEN flag
    LDRB W9, [X22, #8]
    AND W9, W9, #~F_HIDDEN
    STRB W9, [X22, #8]

    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Ldefer_err:
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// Initial action for a freshly DEFERed word: report and abort to the REPL.
// Reached via forth_execute when an uninitialized deferred word is run.
.global forth_undef_defer
forth_undef_defer:
    ADR X0, msg_undef_defer
    MOV X1, #msg_undef_defer_len
    BL platform_write
    B forth_abort

// ---------- :NONAME ----------
// :NONAME ( -- xt )
.global forth_noname
forth_noname:
    // Save state for error recovery
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

    STP X29, X30, [SP, #-16]!

    // Save HERE as xt (before compiling prolog)
    MOV X23, X21

    // Compile prolog (STP X29, X30, [SP, #-16]!)
    BL compile_prolog

    LDP X29, X30, [SP], #16

    // Push xt to data stack
    STR X23, [X19, #-CELL]!

    // Save DSP AFTER pushing xt (so ; sees balanced stack)
    ADR X9, colon_dsp
    STR X19, [X9]

    // Enter compile mode
    ADR X9, state
    MOV X10, #-1
    STR X10, [X9]

    // No code_len field for :NONAME
    ADR X9, colon_code_len_addr
    STR XZR, [X9]

    RET

// ---------- ?DO ----------
// ?DO ( limit index -- ) (R: -- limit index)  IMMEDIATE, COMPILE_ONLY
.global forth_question_do
forth_question_do:
    STP X29, X30, [SP, #-16]!
    BL compile_question_do_inline   // X0 = B.EQ patch address
    ADR X9, do_depth
    LDR X10, [X9]
    ADD X10, X10, #1
    STR X10, [X9]
    SUB X19, X19, #6*CELL
    STR X0, [X19, #5*CELL]         // skip-patch address
    MOV X9, #CF_ORIG
    STR X9, [X19, #4*CELL]
    ADR X9, leave_count
    LDR X10, [X9]
    STR X10, [X19, #3*CELL]
    MOV X9, #CF_LEAVE
    STR X9, [X19, #2*CELL]
    STR X21, [X19, #CELL]          // body address = HERE
    MOV X9, #CF_DEST
    STR X9, [X19]
    LDP X29, X30, [SP], #16
    RET

// compile_question_do_inline — emit ?DO's inline code (24 bytes, 6 instructions).
// Same structure as compile_do_inline: compare BEFORE push to return stack.
// If equal, branch forward (skip loop body entirely, clean return stack).
// Returns: X0 = address of B.EQ instruction (for LOOP to patch).
compile_question_do_inline:
    CHECK_DICT 24
    // LDR X9, [X19]              (index = top of stack)
    MOV W9, #(INSN_LDR_X9_X19 & 0xFFFF)
    MOVK W9, #(INSN_LDR_X9_X19 >> 16), LSL #16
    STR W9, [X21], #4
    // LDR X10, [X19, #8]         (limit = second on stack)
    MOV W9, #(INSN_LDR_X10_X19_8 & 0xFFFF)
    MOVK W9, #(INSN_LDR_X10_X19_8 >> 16), LSL #16
    STR W9, [X21], #4
    // ADD X19, X19, #16           (pop both from data stack)
    MOV W9, #(INSN_ADD_X19_X19_16 & 0xFFFF)
    MOVK W9, #(INSN_ADD_X19_X19_16 >> 16), LSL #16
    STR W9, [X21], #4
    // CMP X9, X10
    MOV W9, #(INSN_CMP_X9_X10 & 0xFFFF)
    MOVK W9, #(INSN_CMP_X9_X10 >> 16), LSL #16
    STR W9, [X21], #4
    // B.EQ placeholder (skip if equal — branch BEFORE push to return stack)
    MOV W9, #(INSN_BEQ_0 & 0xFFFF)
    MOVK W9, #(INSN_BEQ_0 >> 16), LSL #16
    MOV X0, X21                     // X0 = address of B.EQ (for patching)
    STR W9, [X21], #4
    // STP X9, X10, [SP, #-16]!   (push to return stack only if not skipping)
    MOV W9, #(INSN_STP_X9_X10_SP_PRE & 0xFFFF)
    MOVK W9, #(INSN_STP_X9_X10_SP_PRE >> 16), LSL #16
    STR W9, [X21], #4
    RET

// ---------- WORDS ----------
// WORDS ( -- )
// Print all words in the dictionary.
.global forth_words
forth_words:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    MOV X23, X22                    // X23 = current entry (start at LATEST)

.Lwords_loop:
    CBZ X23, .Lwords_done           // NULL link = end of dictionary

    // Extract name length from flags byte (offset 8)
    LDRB W9, [X23, #8]
    AND W9, W9, #F_LENMASK

    // Name starts at offset 9
    ADD X0, X23, #9                 // X0 = name address
    MOV X1, X9                      // X1 = name length
    BL platform_write

    // Print space
    SUB SP, SP, #16
    MOV W9, #' '
    STRB W9, [SP]
    MOV X0, SP
    MOV X1, #1
    BL platform_write
    ADD SP, SP, #16

    // Follow link to next entry
    LDR X23, [X23]
    B .Lwords_loop

.Lwords_done:
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- KEY? ----------
// KEY? ( -- flag )
.global forth_key_q
forth_key_q:
    STP X29, X30, [SP, #-16]!
    BL platform_raw_mode            // lazily enter raw mode on first interactive input
    BL platform_key_ready           // X0 = count
    CMP X0, #0
    CSETM X9, NE                    // -1 if ready, 0 if not
    STR X9, [X19, #-CELL]!
    LDP X29, X30, [SP], #16
    RET

// ---------- MS ----------
// MS ( u -- )
.global forth_ms
forth_ms:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19], #CELL           // pop milliseconds
    BL platform_ms
    LDP X29, X30, [SP], #16
    RET

// ---------- PAGE ----------
// PAGE ( -- )
.global forth_page
forth_page:
    STP X29, X30, [SP, #-16]!
    BL platform_page
    LDP X29, X30, [SP], #16
    RET

// ---------- AT-XY ----------
// AT-XY ( u1 u2 -- ) u1=column, u2=row
.global forth_at_xy
forth_at_xy:
    STP X29, X30, [SP, #-16]!
    LDR X1, [X19], #CELL           // u2 = row (top)
    LDR X0, [X19], #CELL           // u1 = col (second)
    BL platform_at_xy
    LDP X29, X30, [SP], #16
    RET

// ---------- SCREEN-WIDTH ----------
// SCREEN-WIDTH ( -- u )
.global forth_screen_w
forth_screen_w:
    STP X29, X30, [SP, #-16]!
    BL platform_screen_width
    STR X0, [X19, #-CELL]!
    LDP X29, X30, [SP], #16
    RET

// ---------- SCREEN-HEIGHT ----------
// SCREEN-HEIGHT ( -- u )
.global forth_screen_h
forth_screen_h:
    STP X29, X30, [SP, #-16]!
    BL platform_screen_height
    STR X0, [X19, #-CELL]!
    LDP X29, X30, [SP], #16
    RET

// ---------- INCLUDE ----------
// INCLUDE ( "filename" -- )
// Parse the next word from input and load it as a Forth source file.
.global forth_include
forth_include:
    STP X29, X30, [SP, #-16]!
    BL forth_parse_word             // ( -- c-addr u )
    BL forth_included               // ( c-addr u -- )
    LDP X29, X30, [SP], #16
    RET

// ---------- Command-line arguments (Tier 3) ----------
// ARGC and ARGV are variables (mirroring gforth): they push the address of the
// mutable count/base cells, so `argc @` and `argv @` work. arg_base is a char**
// into the OS argv vector; SHIFT-ARGS / NEXT-ARG consume from the front.

// ARGC ( -- a-addr ) — address of the argument-count cell.
.global forth_argc
forth_argc:
    ADR X9, arg_count
    STR X9, [X19, #-CELL]!
    RET

// ARGV ( -- a-addr ) — address of the argv-base cell (a-addr @ -> char**).
.global forth_argv
forth_argv:
    ADR X9, arg_base
    STR X9, [X19, #-CELL]!
    RET

// ARG ( u -- c-addr u ) — the uth argument as a string; ( 0 0 ) if out of range.
.global forth_arg
forth_arg:
    LDR X1, [X19]                   // X1 = u (index)
    ADR X9, arg_count
    LDR X2, [X9]                    // X2 = count
    CMP X1, X2
    B.HS .Larg_oob                  // u >= count (unsigned)
    ADR X9, arg_base
    LDR X3, [X9]                    // X3 = char** base
    LDR X4, [X3, X1, LSL #3]        // X4 = char* = base[u]
    MOV X5, #0                      // strlen
.Larg_strlen:
    LDRB W6, [X4, X5]
    CBZ W6, .Larg_done
    ADD X5, X5, #1
    B .Larg_strlen
.Larg_done:
    STR X4, [X19]                   // replace u with c-addr
    STR X5, [X19, #-CELL]!          // push len
    RET
.Larg_oob:
    MOV X9, #0
    STR X9, [X19]                   // c-addr = 0
    STR X9, [X19, #-CELL]!          // len = 0
    RET

// SHIFT-ARGS ( -- ) — delete arg[1], shifting the rest left and decrementing
// argc. O(1): copy arg[0] forward into slot 1, then advance the base by a cell
// (keeps arg[0] = program name). No-op when there is no arg[1] (count < 2).
.global forth_shift_args
forth_shift_args:
    ADR X9, arg_count
    LDR X0, [X9]
    CMP X0, #2
    B.LO .Lshift_done               // count < 2 -> nothing to shift
    ADR X10, arg_base
    LDR X1, [X10]                   // char** base
    LDR X2, [X1]                    // base[0] (program name)
    STR X2, [X1, #CELL]             // base[1] = base[0]
    ADD X1, X1, #CELL               // base += 1
    STR X1, [X10]
    SUB X0, X0, #1
    STR X0, [X9]                    // count -= 1
.Lshift_done:
    RET

// NEXT-ARG ( -- c-addr u ) — return arg[1] and consume it via SHIFT-ARGS;
// ( 0 0 ) when no argument remains.
.global forth_next_arg
forth_next_arg:
    ADR X9, arg_count
    LDR X0, [X9]
    CMP X0, #2
    B.LO .Lnext_empty               // no arg[1]
    ADR X10, arg_base
    LDR X1, [X10]
    LDR X4, [X1, #CELL]             // char* = base[1]
    MOV X5, #0                      // strlen
.Lnext_strlen:
    LDRB W6, [X4, X5]
    CBZ W6, .Lnext_got
    ADD X5, X5, #1
    B .Lnext_strlen
.Lnext_got:
    STR X4, [X19, #-CELL]!          // push c-addr
    STR X5, [X19, #-CELL]!          // push len
    STR X30, [SP, #-16]!            // save LR across the call
    BL forth_shift_args             // consume arg[1]
    LDR X30, [SP], #16
    RET
.Lnext_empty:
    MOV X9, #0
    STR X9, [X19, #-CELL]!          // c-addr = 0
    STR X9, [X19, #-CELL]!          // len = 0
    RET

// BYE-CODE ( n -- ) — exit with status n, silent (no "Goodbye!" banner) so a
// utility's output is not corrupted.
.global forth_bye_code
forth_bye_code:
    LDR X0, [X19], #CELL            // status = TOS, pop
    B platform_exit

// ---------- WRITE-FILE ----------
// WRITE-FILE ( c-addr u fileid -- ior )
// Write u bytes at c-addr to the file descriptor fileid. Returns ior: 0 on
// success, else the positive errno. Loops over write() until ALL u bytes are
// written (a short write is not success), so a partial write can never silently
// truncate output. fileid is a raw OS fd (stdin/stdout/stderr = 0/1/2).
.global forth_write_file
forth_write_file:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!      // callee-saved: loop state across the syscall
    STR X25, [SP, #-16]!
    LDR X23, [X19]                 // fd
    LDR X25, [X19, #CELL]          // remaining = u
    LDR X24, [X19, #2*CELL]        // ptr = c-addr
    ADD X19, X19, #2*CELL          // pop fileid + u; TOS slot ← ior
.Lwf_loop:
    CBZ X25, .Lwf_ok               // all bytes written
    MOV X0, X23                    // fd
    MOV X1, X24                    // ptr
    MOV X2, X25                    // remaining
    BL platform_write_fd           // X0 = bytes written or -errno
    CMP X0, #0
    B.LT .Lwf_err                  // negative → error
    B.EQ .Lwf_zero                 // 0 bytes and no error → avoid spinning
    ADD X24, X24, X0               // ptr += n
    SUB X25, X25, X0               // remaining -= n
    B .Lwf_loop
.Lwf_ok:
    STR XZR, [X19]                 // ior = 0 (success)
    B .Lwf_ret
.Lwf_zero:
    MOV X0, #5                     // EIO (5): made no progress
    STR X0, [X19]
    B .Lwf_ret
.Lwf_err:
    NEG X0, X0                     // ior = errno (positive)
    STR X0, [X19]
.Lwf_ret:
    LDR X25, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- File access (Phase 4) ----------
// fileid is a raw OS file descriptor; ior is 0 on success, else positive errno.

// OPEN-FILE   ( c-addr u fam -- fileid ior )  open an existing file
// CREATE-FILE ( c-addr u fam -- fileid ior )  create/truncate (mode 0666)
// fam is the access method from R/O (0), W/O (1) or R/W (2).
.global forth_open_file
forth_open_file:
    STP X29, X30, [SP, #-16]!
    LDR X2, [X19]                   // flags = fam (R/O=0, W/O=1, R/W=2 = OS flags)
    MOV X3, #0                      // mode = 0
    LDR X1, [X19, #CELL]            // u (path length)
    LDR X0, [X19, #2*CELL]          // c-addr (path)
    ADD X19, X19, #CELL             // pop fam → ( c-addr u )
    BL platform_open_file_mode      // X0 = fd or -errno
    B .Lopen_result
.global forth_create_file
forth_create_file:
    STP X29, X30, [SP, #-16]!
    LDR X2, [X19]                   // fam (platform adds O_CREAT|O_TRUNC, mode 0666)
    LDR X1, [X19, #CELL]            // u (path length)
    LDR X0, [X19, #2*CELL]          // c-addr (path)
    ADD X19, X19, #CELL             // pop fam → ( c-addr u )
    BL platform_create_file         // X0 = fd or -errno
.Lopen_result:
    CMP X0, #0
    B.LT .Lopen_err
    STR X0, [X19, #CELL]            // fileid = fd (c-addr slot)
    STR XZR, [X19]                  // ior = 0 (u slot)
    LDP X29, X30, [SP], #16
    RET
.Lopen_err:
    NEG X0, X0                      // errno
    STR XZR, [X19, #CELL]           // fileid = 0
    STR X0, [X19]                   // ior = errno
    LDP X29, X30, [SP], #16
    RET

// CLOSE-FILE ( fileid -- ior )
.global forth_close_file
forth_close_file:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19]                   // fileid
    BL platform_close_file          // X0 = 0 or -errno
    CMP X0, #0
    B.LT .Lclose_err
    STR XZR, [X19]                  // ior = 0
    LDP X29, X30, [SP], #16
    RET
.Lclose_err:
    NEG X0, X0
    STR X0, [X19]                   // ior = errno
    LDP X29, X30, [SP], #16
    RET

// READ-FILE ( c-addr u1 fileid -- u2 ior )  read up to u1 bytes; u2 = actual
.global forth_read_file
forth_read_file:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19]                   // fileid
    LDR X2, [X19, #CELL]            // u1 (count)
    LDR X1, [X19, #2*CELL]          // c-addr (buffer)
    ADD X19, X19, #CELL             // pop fileid → ( c-addr u1 )
    BL platform_read_file           // X0 = bytes read or -errno
    CMP X0, #0
    B.LT .Lread_err
    STR X0, [X19, #CELL]            // u2 = bytes (c-addr slot)
    STR XZR, [X19]                  // ior = 0
    LDP X29, X30, [SP], #16
    RET
.Lread_err:
    NEG X0, X0
    STR XZR, [X19, #CELL]           // u2 = 0
    STR X0, [X19]                   // ior = errno
    LDP X29, X30, [SP], #16
    RET

// (getdents) ( fileid buf count -- n )  read directory entries into buf.
// n = bytes filled, 0 at end of directory, or a negative errno. The dirent
// records are parsed in core.fs; this is just the raw syscall.
.global forth_getdents
forth_getdents:
    STP X29, X30, [SP, #-16]!
    LDR X2, [X19]                   // count
    LDR X1, [X19, #CELL]            // buf
    LDR X0, [X19, #2*CELL]          // fileid (fd)
    ADD X19, X19, #(2*CELL)         // pop count + buf; TOS slot ← n
    BL platform_getdents            // X0 = bytes or -errno
    STR X0, [X19]
    LDP X29, X30, [SP], #16
    RET

// chdir ( c-addr u -- ior )  change the CWD to the path; ior 0 = ok, else -errno.
// The path is copied to a scratch buffer and NUL-terminated for the syscall.
.global forth_chdir
forth_chdir:
    STP X29, X30, [SP, #-16]!
    LDR X2, [X19]                   // u (length)
    LDR X1, [X19, #CELL]            // c-addr
    ADD X19, X19, #CELL             // pop u; TOS slot ← ior
    CMP X2, #ABS_PATH_MAX
    B.HS .Lchdir_toolong            // u >= ABS_PATH_MAX -> no room for path + NUL
    ADR X3, chdir_buf
    MOV X4, #0                      // copy index
.Lchdir_copy:
    CMP X4, X2
    B.HS .Lchdir_copydone
    LDRB W5, [X1, X4]
    STRB W5, [X3, X4]
    ADD X4, X4, #1
    B .Lchdir_copy
.Lchdir_copydone:
    STRB WZR, [X3, X4]              // NUL-terminate
    ADR X0, chdir_buf
    BL platform_chdir               // X0 = 0 or -errno
    STR X0, [X19]                   // ior
    LDP X29, X30, [SP], #16
    RET
.Lchdir_toolong:
    MOV X0, #-36                    // -ENAMETOOLONG
    STR X0, [X19]
    LDP X29, X30, [SP], #16
    RET

// (startup-dir) ( -- c-addr u )  absolute directory BasicForth was launched in
// (u = 0 if getcwd failed at boot). Backs bare `cd` and session.fs pinning.
.global forth_startup_dir
forth_startup_dir:
    ADR X9, startup_dir
    STR X9, [X19, #-CELL]!          // c-addr
    ADR X9, startup_dir_len
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!          // u
    RET

// (cwd) ( -- c-addr u )  the current working directory, freshly read via getcwd
// into a static buffer (u = 0 if getcwd fails). Backs `pwd`.
.global forth_cwd
forth_cwd:
    STP X29, X30, [SP, #-16]!
    ADR X0, cwd_buf
    MOV X1, #ABS_PATH_MAX
    BL platform_getcwd              // X0 = bytes incl NUL, or -errno
    CMP X0, #0
    B.GT .Lcwd_ok
    MOV X0, #0                      // failure -> length 0
    B .Lcwd_push
.Lcwd_ok:
    SUB X0, X0, #1                  // drop the trailing NUL
.Lcwd_push:
    ADR X9, cwd_buf
    STR X9, [X19, #-CELL]!          // c-addr
    STR X0, [X19, #-CELL]!          // u
    LDP X29, X30, [SP], #16
    RET

// (home-dir) ( -- c-addr u )  the HOME environment value and length (0 0 if HOME
// is unset). Backs `cd ~`.
.global forth_home_dir
forth_home_dir:
    ADR X9, home_ptr
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!          // c-addr
    ADR X9, home_len
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!          // u
    RET

// (docs-path) ( -- c-addr u )  the BASICFORTH_DOCS value and length (0 0 unset).
.global forth_docs_path
forth_docs_path:
    ADR X9, basicforth_docs
    LDR X0, [X9]
    STR X0, [X19, #-CELL]!          // c-addr
    ADR X9, basicforth_docs_len
    LDR X0, [X9]
    STR X0, [X19, #-CELL]!          // u
    RET

// FILE-SIZE ( fileid -- ud ior )  file size as a double cell, via fstat
.global forth_file_size
forth_file_size:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19]                   // fileid
    BL platform_fstat               // X0 = size or -errno
    CMP X0, #0
    B.LT .Lfsize_err
    STR X0, [X19]                   // ud-lo = size (overwrite fileid)
    STR XZR, [X19, #-CELL]!         // push ud-hi = 0
    STR XZR, [X19, #-CELL]!         // push ior = 0
    LDP X29, X30, [SP], #16
    RET
.Lfsize_err:
    NEG X0, X0                      // errno
    STR XZR, [X19]                  // ud-lo = 0
    STR XZR, [X19, #-CELL]!         // push ud-hi = 0
    STR X0, [X19, #-CELL]!          // push ior = errno
    LDP X29, X30, [SP], #16
    RET

// RENAME-FILE ( c-addr1 u1 c-addr2 u2 -- ior )  rename file1 → file2 (atomic).
.global forth_rename_file
forth_rename_file:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19, #3*CELL]          // c-addr1 (old)
    LDR X1, [X19, #2*CELL]          // u1
    LDR X2, [X19, #CELL]            // c-addr2 (new)
    LDR X3, [X19]                   // u2
    ADD X19, X19, #3*CELL           // pop 3 args; TOS slot ← ior
    BL platform_rename              // X0 = 0 or -errno
    CMP X0, #0
    B.LT .Lrename_err
    STR XZR, [X19]                  // ior = 0
    LDP X29, X30, [SP], #16
    RET
.Lrename_err:
    NEG X0, X0
    STR X0, [X19]                   // ior = errno
    LDP X29, X30, [SP], #16
    RET

// (system) ( c-addr u -- status )  run a shell command via /bin/sh -c, blocking
// until it finishes; status is the child's exit code (0-255), or -1 on a
// fork/exec failure. The string is copied to a private NUL-terminated buffer
// (clamped to SYS_CMD_MAX-1). The foundation under `edit`'s external-editor
// spawn and any future `sh`/`!` words.
.equ SYS_CMD_MAX, 4096
.global forth_system
forth_system:
    STR X30, [SP, #-16]!
    LDR X1, [X19, #CELL]            // c-addr (src)
    LDR X2, [X19]                   // u
    ADD X19, X19, #CELL             // pop u → TOS slot now = status
    MOV X3, #(SYS_CMD_MAX-1)
    CMP X2, X3
    CSEL X2, X2, X3, LS             // X2 = min(u, SYS_CMD_MAX-1)
    ADR X4, sys_cmd_buf
    MOV X5, #0
.Lsys_copy:
    CMP X5, X2
    B.GE .Lsys_copied
    LDRB W6, [X1, X5]
    STRB W6, [X4, X5]
    ADD X5, X5, #1
    B .Lsys_copy
.Lsys_copied:
    STRB WZR, [X4, X2]             // NUL-terminate
    MOV X0, X4                      // cmd ptr
    BL platform_system             // X0 = status
    LDR X30, [SP], #16
    STR X0, [X19]
    RET

// (tty?) ( -- f )  true when stdin is a terminal. Gates the dirty-guard prompt:
// an interactive session asks before discarding unsaved work; pipes and scripts
// never do.
.global forth_tty
forth_tty:
    STP X29, X30, [SP, #-16]!
    MOV X0, #0                      // fd 0 = stdin
    BL platform_isatty              // X0 = 1 tty / 0 not
    STR X0, [X19, #-CELL]!
    LDP X29, X30, [SP], #16
    RET

// ---------- Heap primitives (Phase 4) ----------
// Thin wrappers over the anonymous-mmap platform calls. The ANS MEMORY words
// ALLOCATE/FREE/RESIZE are built on these in core.fs; sign handling and the
// length-header bookkeeping live there.

// (mmap-anon) ( size -- addr )  addr is page-aligned, or a negative errno.
.global forth_mmap_anon
forth_mmap_anon:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19]                   // size
    BL platform_mmap_anon           // X0 = addr or -errno
    STR X0, [X19]
    LDP X29, X30, [SP], #16
    RET

// (munmap) ( addr size -- n )  n = 0 on success, or a negative errno.
.global forth_munmap
forth_munmap:
    STP X29, X30, [SP, #-16]!
    LDR X1, [X19], #CELL            // size, pop → TOS slot now = addr slot
    LDR X0, [X19]                   // addr
    BL platform_munmap              // X0 = 0 or -errno
    STR X0, [X19]
    LDP X29, X30, [SP], #16
    RET

// ---------- Session hook registration (Phase 4) ----------
// (hook!) ( xt id -- )  register a session hook word by id: 0=session-seed,
// 1=capture-line, 2=capture-reset, 3=line-editor. core.fs registers its hook
// words here so the asm REPL/startup can call them; main.s reads
// session_hooks[id] and calls it.
.global forth_hook_store
forth_hook_store:
    LDR X1, [X19], #CELL            // id, pop
    LDR X0, [X19], #CELL            // xt, pop
    ADR X2, session_hooks
    STR X0, [X2, X1, LSL #3]        // session_hooks[id] = xt
    RET

// ---------- Dictionary restore points (MARKER) ----------
// (latest@) ( -- a )  push the LATEST register (newest dictionary entry).
.global forth_latest_at
forth_latest_at:
    STR X22, [X19, #-CELL]!         // push LATEST (X22)
    RET

// (restore-dict) ( here latest -- )  rewind the dictionary: set HERE and LATEST.
// MARKER's runtime calls this to forget everything defined after the marker.
.global forth_restore_dict
forth_restore_dict:
    LDR X22, [X19], #CELL           // latest (TOS), pop
    LDR X21, [X19], #CELL           // here, pop
    RET

// (session-mark!) ( -- )  record the current HERE/LATEST as the session restore
// point (set once at session startup, just past core.fs).
.global forth_session_mark
forth_session_mark:
    ADR X0, session_mark_here
    STR X21, [X0]
    ADR X0, session_mark_latest
    STR X22, [X0]
    RET

// (session-restore) ( -- )  rewind HERE/LATEST to the session restore point,
// forgetting everything defined after it. No-op if no point was recorded.
.global forth_session_restore
forth_session_restore:
    ADR X0, session_mark_latest
    LDR X1, [X0]
    CBZ X1, .Lsr_done
    ADR X0, session_mark_here
    LDR X21, [X0]
    ADR X0, session_mark_latest
    LDR X22, [X0]
.Lsr_done:
    RET

// (included?) ( c-addr u -- ior )  like INCLUDED, but leaves forth_included's
// result on the stack: 0 = clean load, non-zero = a line errored. RELOAD uses it
// to detect a bad session.fs (and skip re-syncing the log to a broken file).
.global forth_included_ior
forth_included_ior:
    STP X29, X30, [SP, #-16]!
    BL forth_included              // consumes ( c-addr u ); X0 = 0 or 1
    STR X0, [X19, #-CELL]!         // push ior
    LDP X29, X30, [SP], #16
    RET

// ---------- MS@ ----------
// MS@ ( -- u )
// Return current monotonic milliseconds.
.global forth_ms_get
forth_ms_get:
    STP X29, X30, [SP, #-16]!
    BL platform_ms_get              // X0 = milliseconds
    STR X0, [X19, #-CELL]!
    LDP X29, X30, [SP], #16
    RET

// ---------- CURSOR-OFF ----------
// CURSOR-OFF ( -- )
// Hide the terminal cursor.
.global forth_cursor_off
forth_cursor_off:
    STP X29, X30, [SP, #-16]!
    BL platform_cursor_off
    LDP X29, X30, [SP], #16
    RET

// ---------- CURSOR-ON ----------
// CURSOR-ON ( -- )
// Show the terminal cursor.
.global forth_cursor_on
forth_cursor_on:
    STP X29, X30, [SP, #-16]!
    BL platform_cursor_on
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
    ADD X10, X9, #12               // code start (past CodeLen + 8-byte SrcMeta)
    SUB X11, X24, X10              // code length (up to code end, before padding)
    STR W11, [X9]

    // Flush I-cache for compiled code
    ADD X0, X9, #12                // start = code start
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
    ADD X10, X9, #12               // code start (past CodeLen + 8-byte SrcMeta)
    SUB X11, X21, X10
    STR W11, [X9]

    // Flush I-cache
    ADD X0, X9, #12               // start = code start
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
    ADD X24, X9, #12                // X24 = code_start (past CodeLen + 8-byte SrcMeta)
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

// UNUSED ( -- u )  Return number of free bytes in dictionary space.
.global forth_unused
forth_unused:
    ADR X9, dict_space_end
    SUB X9, X9, X21                // end - HERE
    STR X9, [X19, #-CELL]!
    RET

// ---------- System Words ----------

// >BODY ( xt -- a-addr )  Convert execution token to data field address.
// For CREATE'd words: STP(4) + BL forth_lit(4) + value(8) + LDP+RET(8)
// The inline value is at offset 8 from xt.
.global forth_to_body
forth_to_body:
    LDR X9, [X19]                  // xt
    LDR X9, [X9, #8]              // read inline value (data field address)
    STR X9, [X19]
    RET

// >IN ( -- a-addr )  Push address of >IN variable.
.global forth_to_in
forth_to_in:
    ADR X9, to_in
    STR X9, [X19, #-CELL]!
    RET

// SOURCE ( -- c-addr u )  Push current input source address and length.
.global forth_source
forth_source:
    ADR X9, source_addr
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!
    ADR X9, source_len
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!
    RET

// ABORT ( i*x -- ) ( R: j*x -- )  Clear stacks, reset to REPL.
.global forth_abort
forth_abort:
    ADR X9, sp0
    LDR X19, [X9]                  // reset data stack
    ADR X9, rp0
    LDR X9, [X9]
    MOV SP, X9                     // reset return stack
    ADR X9, state
    STR XZR, [X9]                  // reset compile state
    B repl_loop

// QUIT ( -- ) ( R: i*x -- )  Reset return stack, enter interpreter loop.
.global forth_quit
forth_quit:
    ADR X9, rp0
    LDR X9, [X9]
    MOV SP, X9                     // reset return stack
    ADR X9, state
    STR XZR, [X9]                  // reset compile state
    B repl_loop

// ---------- Compiler Words ----------

// STATE ( -- a-addr )  Push address of STATE variable.
.global forth_state
forth_state:
    ADR X9, state
    STR X9, [X19, #-CELL]!
    RET

// [ ( -- )  Switch to interpret mode.  IMMEDIATE.
.global forth_left_bracket
forth_left_bracket:
    ADR X9, state
    STR XZR, [X9]
    RET

// ] ( -- )  Switch to compile mode.
.global forth_right_bracket
forth_right_bracket:
    ADR X9, state
    MOV X10, #-1
    STR X10, [X9]
    RET

// LITERAL ( x -- )  Compile a literal at compile time.  IMMEDIATE+COMPILE_ONLY.
.global forth_literal
forth_literal:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19], #CELL           // pop value
    BL compile_literal
    LDP X29, X30, [SP], #16
    RET

// ['] ( "<spaces>name" -- )  Compile xt as literal.  IMMEDIATE+COMPILE_ONLY.
.global forth_bracket_tick
forth_bracket_tick:
    STP X29, X30, [SP, #-16]!
    BL forth_parse_word             // ( -- c-addr u )
    BL forth_find                   // ( c-addr u -- xt flag | c-addr u 0 )
    LDR X9, [X19]                   // flag
    CBZ X9, .Lbt_not_found
    ADD X19, X19, #CELL             // drop flag
    LDR X0, [X19], #CELL           // pop xt
    BL compile_literal
    LDP X29, X30, [SP], #16
    RET
.Lbt_not_found:
    ADD X19, X19, #(3*CELL)         // drop flag, u, c-addr
    STR XZR, [X19, #-CELL]!        // push 0 (invalid xt)
    LDP X29, X30, [SP], #16
    RET

// [CHAR] ( "<spaces>name" -- )  Compile char value as literal.  IMMEDIATE+COMPILE_ONLY.
.global forth_bracket_char
forth_bracket_char:
    STP X29, X30, [SP, #-16]!
    BL forth_parse_word             // ( -- c-addr u )
    LDR X10, [X19]                  // u (top)
    LDR X9, [X19, #CELL]           // c-addr (second item)
    ADD X19, X19, #(2*CELL)         // drop c-addr and u
    MOV W0, #0                      // default char = 0 (no word)
    CBZ X10, .Lbc_compile           // u == 0 → compile 0, do NOT deref c-addr
    LDRB W0, [X9]                   // first character
.Lbc_compile:
    BL compile_literal
    LDP X29, X30, [SP], #16
    RET

// EXIT ( -- )  Compile a return instruction.  IMMEDIATE+COMPILE_ONLY.
.global forth_exit
forth_exit:
    STP X29, X30, [SP, #-16]!
    BL compile_ret
    LDP X29, X30, [SP], #16
    RET

// COMPILE, ( xt -- )  Compile a call to xt into the current definition.
.global forth_compile_comma
forth_compile_comma:
    STP X29, X30, [SP, #-16]!
    LDR X0, [X19], #CELL           // pop xt
    BL compile_call
    LDP X29, X30, [SP], #16
    RET

// POSTPONE ( "<spaces>name" -- )  IMMEDIATE+COMPILE_ONLY.
.global forth_postpone
forth_postpone:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    BL forth_parse_word             // ( -- c-addr u )
    BL forth_find                   // ( c-addr u -- xt flag | c-addr u 0 )
    LDR X23, [X19]                  // flag
    CBZ X23, .Lpostpone_not_found

    ADD X19, X19, #CELL             // drop flag
    LDR X0, [X19], #CELL           // pop xt

    // Is it IMMEDIATE? (flag == 1 or flag == 2)
    CMP X23, #1
    B.EQ .Lpostpone_immediate
    CMP X23, #2
    B.EQ .Lpostpone_immediate

    // Non-immediate: compile LITERAL(xt) + BL(forth_compile_comma)
    BL compile_literal
    ADR X0, forth_compile_comma
    BL compile_call
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lpostpone_immediate:
    // IMMEDIATE: just compile a BL to it
    BL compile_call
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lpostpone_not_found:
    // Word not found — set error and abort
    ADD X19, X19, #CELL             // drop 0 flag
    LDR X9, [X19]                   // u
    ADR X10, err_token_len
    STR X9, [X10]
    LDR X9, [X19, #CELL]           // c-addr
    ADR X10, err_token_addr
    STR X9, [X10]
    ADD X19, X19, #(2*CELL)         // drop c-addr and u
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    B .Lcf_abort

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
DEFWORD dict_lshift,     "lshift",     forth_lshift,      dict_hld
DEFWORD dict_rshift,     "rshift",     forth_rshift,      dict_lshift
DEFWORD dict_two_div,    "2/",         forth_two_div,     dict_rshift
DEFWORD dict_u_less,     "u<",         forth_u_less,      dict_two_div
DEFWORD dict_state,      "state",      forth_state,       dict_u_less
DEFWORD dict_lbracket,   "[",          forth_left_bracket, dict_state, F_IMMEDIATE
DEFWORD dict_rbracket,   "]",          forth_right_bracket, dict_lbracket
DEFWORD dict_literal,    "literal",    forth_literal,     dict_rbracket, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_bracket_tick, "[']",      forth_bracket_tick, dict_literal, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_bracket_char, "[char]",   forth_bracket_char, dict_bracket_tick, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_exit,       "exit",       forth_exit,        dict_bracket_char, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_compile_comma, "compile,", forth_compile_comma, dict_exit
DEFWORD dict_postpone,   "postpone",   forth_postpone,    dict_compile_comma, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_to_body,    ">body",      forth_to_body,     dict_postpone
DEFWORD dict_to_in,      ">in",        forth_to_in,       dict_to_body
DEFWORD dict_source,     "source",     forth_source,      dict_to_in
DEFWORD dict_abort,      "abort",      forth_abort,       dict_source
DEFWORD dict_quit,       "quit",       forth_quit,        dict_abort
DEFWORD dict_unused,     "unused",     forth_unused,      dict_quit
DEFWORD dict_case,       "case",       forth_case,        dict_unused,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_of,         "of",         forth_of,          dict_case,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_endof,      "endof",      forth_endof,       dict_of,        F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_endcase,    "endcase",    forth_endcase,     dict_endof,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_parse,      "parse",      forth_parse,       dict_endcase
DEFWORD dict_source_id,  "source-id",  forth_source_id,   dict_parse
DEFWORD dict_value,      "value",      forth_value,       dict_source_id
DEFWORD dict_to,         "to",         forth_to,          dict_value,     F_IMMEDIATE
DEFWORD dict_noname,     ":noname",    forth_noname,      dict_to
DEFWORD dict_question_do,"?do",        forth_question_do, dict_noname,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_words,      "words",      forth_words,       dict_question_do
DEFWORD dict_key_q,      "key?",       forth_key_q,       dict_words
DEFWORD dict_ms,         "ms",         forth_ms,          dict_key_q
DEFWORD dict_page,       "page",       forth_page,        dict_ms
DEFWORD dict_at_xy,      "at-xy",      forth_at_xy,       dict_page
DEFWORD dict_screen_w,   "screen-width",  forth_screen_w, dict_at_xy
DEFWORD dict_screen_h,   "screen-height", forth_screen_h, dict_screen_w
DEFWORD dict_ms_get,     "ms@",           forth_ms_get,    dict_screen_h
DEFWORD dict_cursor_off, "cursor-off",    forth_cursor_off, dict_ms_get
DEFWORD dict_cursor_on,  "cursor-on",     forth_cursor_on, dict_cursor_off
DEFWORD dict_include,    "include",       forth_include,   dict_cursor_on
DEFWORD dict_argc,       "argc",          forth_argc,      dict_include
DEFWORD dict_argv,       "argv",          forth_argv,      dict_argc
DEFWORD dict_arg,        "arg",           forth_arg,       dict_argv
DEFWORD dict_shift_args, "shift-args",    forth_shift_args, dict_arg
DEFWORD dict_next_arg,   "next-arg",      forth_next_arg,  dict_shift_args
DEFWORD dict_bye_code,   "bye-code",      forth_bye_code,  dict_next_arg
DEFWORD dict_write_file, "write-file",    forth_write_file, dict_bye_code
DEFWORD dict_open_file,   "open-file",    forth_open_file,   dict_write_file
DEFWORD dict_create_file, "create-file",  forth_create_file, dict_open_file
DEFWORD dict_close_file,  "close-file",   forth_close_file,  dict_create_file
DEFWORD dict_read_file,   "read-file",    forth_read_file,   dict_close_file
DEFWORD dict_getdents,    "(getdents)",   forth_getdents,    dict_read_file
DEFWORD dict_docs_path,   "(docs-path)",  forth_docs_path,   dict_getdents
DEFWORD dict_file_size,   "file-size",    forth_file_size,   dict_docs_path
DEFWORD dict_rename_file, "rename-file",  forth_rename_file, dict_file_size
DEFWORD dict_mmap_anon,   "(mmap-anon)",  forth_mmap_anon,   dict_rename_file
DEFWORD dict_munmap,      "(munmap)",     forth_munmap,      dict_mmap_anon
DEFWORD dict_latest_at,   "(latest@)",    forth_latest_at,   dict_munmap
DEFWORD dict_restore_dict,"(restore-dict)",forth_restore_dict,dict_latest_at
DEFWORD dict_session_mark,"(session-mark!)",forth_session_mark,dict_restore_dict
DEFWORD dict_session_restore,"(session-restore)",forth_session_restore,dict_session_mark
DEFWORD dict_included_ior,"(included?)",  forth_included_ior, dict_session_restore
DEFWORD dict_hook_store,  "(hook!)",      forth_hook_store,  dict_included_ior
DEFWORD dict_source_path, "(source-path)", forth_source_path, dict_hook_store
DEFWORD dict_find_meta,   "(find-meta)",  forth_find_meta,   dict_source_path
DEFWORD dict_version_str, "(version-str)", forth_version_str, dict_find_meta
DEFWORD dict_defer,       "defer",        forth_defer,       dict_version_str
DEFWORD dict_is,          "is",           forth_to,          dict_defer,     F_IMMEDIATE
DEFWORD dict_assign_query,"(assign?)",    forth_assign_query, dict_is
DEFWORD dict_chdir,       "chdir",        forth_chdir,       dict_assign_query
DEFWORD dict_startup_dir, "(startup-dir)", forth_startup_dir, dict_chdir
DEFWORD dict_cwd,         "(cwd)",        forth_cwd,         dict_startup_dir
DEFWORD dict_home_dir,    "(home-dir)",   forth_home_dir,    dict_cwd
DEFWORD dict_wfetch,      "w@",           forth_wfetch,      dict_home_dir
DEFWORD dict_wstore,      "w!",           forth_wstore,      dict_wfetch
DEFWORD dict_lfetch,      "l@",           forth_lfetch,      dict_wstore
DEFWORD dict_lstore,      "l!",           forth_lstore,      dict_lfetch
DEFWORD dict_ioctl,       "(ioctl)",      forth_ioctl,       dict_lstore
DEFWORD dict_mmap_dev,    "(mmap-dev)",   forth_mmap_dev,    dict_ioctl
DEFWORD dict_tty,         "(tty?)",       forth_tty,         dict_mmap_dev
DEFWORD dict_system,      "(system)",     forth_system,      dict_tty
DEFWORD dict_fill32,      "fill32",       forth_fill32,      dict_system
.global dict_include
.global dict_hook_store
.global dict_find_meta
.global dict_version_str
.global dict_is
.global dict_assign_query
.global dict_startup_dir
.global dict_cwd
.global dict_home_dir
.global dict_lstore
.global dict_mmap_dev
.global dict_system
.global dict_fill32

// ---------- Data Stack Memory ----------
// Layout (grows downward):
//   guard_page_underflow  4096 bytes — mprotect PROT_NONE at startup
//   data_stack_top (sp0)  page-aligned
//   data_stack            4096 bytes (512 cells)
//   data_stack_bottom     page-aligned
//   guard_page_overflow   4096 bytes — mprotect PROT_NONE at startup
.bss
// Scratch buffer for BASICFORTH_PATH/filename concatenation
.align 3
incl_path_buf:
    .space 512

// NUL-terminated scratch path for chdir (the syscall needs a C string).
.align 3
chdir_buf:
    .space ABS_PATH_MAX

// Static buffer for (cwd)/pwd getcwd results.
.align 3
cwd_buf:
    .space ABS_PATH_MAX

// Source table (see SEE source-metadata). Parallel arrays indexed by slot = id-1.
.align 3
abs_path_buf:                       // scratch for getcwd()+'/'+path absolutization
    .space ABS_PATH_MAX
sys_cmd_buf:                        // NUL-terminated command for (system)
    .space SYS_CMD_MAX
.global src_table_lens
src_table_lens:                     // length of each registered path (u64)
    .space SRC_TABLE_MAX * 8
.global src_table_paths
src_table_paths:                    // registered absolute path strings (SRC_PATH_MAX each)
    .space SRC_TABLE_MAX * SRC_PATH_MAX

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
.equ DICT_SPACE_SIZE, 262144    // 256KB
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
.global incl_opened
incl_opened:                        // set to 1 by forth_included when it opens a file
    .quad 0                         //   (lets main.s warn when core.fs is truly missing)
assign_flag:                        // one-shot: a direct (interpret-mode) TO/IS ran
    .quad 0                         //   this line. Read+cleared by (assign?).
.global session_hooks
session_hooks:                      // [0]=session-seed [1]=capture-line [2]=capture-reset
    .quad 0                         //   [3]=line-editor (edit-line). xts; 0 = not
    .quad 0                         //   registered. Set by (hook!).
    .quad 0
    .quad 0
.global session_mark_here
session_mark_here:                  // session restore point (HERE) — 0 = unset
    .quad 0
.global session_mark_latest
session_mark_latest:                // session restore point (LATEST) — 0 = unset
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
.global cur_source_id
cur_source_id:                      // source-id being compiled from (0 = REPL/no file)
    .quad 0
.global cur_line_off
cur_line_off:                       // byte offset of the current line within cur source file
    .quad 0
.global incl_resolved_addr
incl_resolved_addr:                 // resolved path that actually opened the current file
    .quad 0
.global incl_resolved_len
incl_resolved_len:
    .quad 0
.global src_table_count
src_table_count:                    // number of registered source files (id = index + 1)
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
.global source_id
source_id:                          // Input source identifier (0=keyboard, -1=EVALUATE)
    .quad 0
.equ PAD_SIZE, 68                   // 64 binary digits + sign + padding
.global pad
pad:
    .space PAD_SIZE
