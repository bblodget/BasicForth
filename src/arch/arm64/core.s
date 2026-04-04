// BasicForth — Core ASM Primitives (ARM64)
// Platform-independent ARM64 assembly. Requires platform_linux.s (or equivalent).

.equ CELL, 8                    // 64-bit cells
.equ DATA_STACK_SIZE, 4096      // 512 cells

// ---------- Data Stack ----------
// X19 = data stack pointer (DSP), grows downward
// Stack lives in .bss, starts at the top (high address)
// Stack grows downward in memory, so we initialize X19 to the top of the stack area.

// Macros for data stack operations
.macro dpush reg
    STR \reg, [X19, #-CELL]!
.endm

.macro dpop reg
    LDR \reg, [X19], #CELL
.endm

// ---------- Primitives ----------

// DUP ( a -- a a )
.global forth_dup
forth_dup:
    LDR X9, [X19]              // peek top
    dpush X9                   // push copy
    RET

// DROP ( a -- )
.global forth_drop
forth_drop:
    ADD X19, X19, #CELL        // discard top
    RET

// SWAP ( a b -- b a )
.global forth_swap
forth_swap:
    LDR X9, [X19]              // X9 = b (top)
    LDR X10, [X19, #CELL]     // X10 = a (second)
    STR X9, [X19, #CELL]      // store b in second
    STR X10, [X19]             // store a on top
    RET

// OVER ( a b -- a b a )
.global forth_over
forth_over:
    LDR X9, [X19, #CELL]      // X9 = a (second)
    dpush X9                   // push copy of a
    RET

// + ( a b -- a+b )
.global forth_add
forth_add:
    dpop X9                    // X9 = b
    LDR X10, [X19]             // X10 = a
    ADD X10, X10, X9           // X10 = a + b
    STR X10, [X19]             // store result
    RET

// - ( a b -- a-b )
.global forth_sub
forth_sub:
    dpop X9                    // X9 = b
    LDR X10, [X19]             // X10 = a
    SUB X10, X10, X9           // X10 = a - b
    STR X10, [X19]             // store result
    RET

// NEGATE ( a -- -a )
.global forth_negate
forth_negate:
    LDR X9, [X19]              // X9 = a
    NEG X9, X9                 // X9 = -a
    STR X9, [X19]              // store result
    RET

// ---------- EMIT (Forth-level) ----------
// ( char -- )
// Pops char from data stack, calls platform_emit
.global forth_emit
forth_emit:
    STR X30, [SP, #-16]!       // save return address (nested call)
    dpop X0                    // X0 = char
    BL platform_emit
    LDR X30, [SP], #16         // restore return address
    RET

// ---------- KEY (Forth-level) ----------
// ( -- char )
// Reads one character from stdin, pushes to data stack
.global forth_key
forth_key:
    STR X30, [SP, #-16]!       // save return address (nested call)
    BL platform_key            // X0 = character
    dpush X0                   // push to data stack
    LDR X30, [SP], #16         // restore return address
    RET

// ---------- Data Stack Memory ----------
.bss
.align 4
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:
