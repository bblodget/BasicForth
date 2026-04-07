// BasicForth — Outer Interpreter (ARM64)
//
// Register convention (pure memory stack):
//   X19 = DSP (data stack pointer, points to top item; equals sp0 when empty)
//   X21 = HERE (next free byte in dictionary)
//   X22 = LATEST (most recent dictionary entry)
//   SP  = Return stack
//
// X20 is free (no longer used for TOS).

.global _start

.equ CELL, 8
.equ INPUT_BUF_SIZE, 80

_start:
    // Initialize engine registers
    ADR X19, data_stack_top         // DSP = sp0 (empty stack)
    ADR X9, sp0
    STR X19, [X9]                   // save initial DSP for .S / guards
    ADR X21, dict_space             // HERE
    ADR X22, dict_tick              // LATEST

    BL platform_raw_mode

repl_loop:
    // Save return stack pointer for error recovery
    MOV X9, SP
    ADR X10, rp0
    STR X9, [X10]

    // Print prompt
    ADR X0, prompt_msg
    MOV X1, #prompt_len
    BL platform_write

    // ACCEPT ( c-addr max -- count )
    ADR X9, input_buf
    STR X9, [X19, #-CELL]!         // push c-addr
    MOV X9, #INPUT_BUF_SIZE
    STR X9, [X19, #-CELL]!         // push max
    BL forth_accept                 // ( c-addr max -- count )

    // Empty line → exit (count == 0)
    LDR X9, [X19]
    CBZ X9, repl_bye

    // Set up source variables for PARSE-WORD
    LDR X9, [X19]                   // count
    ADR X10, source_len
    STR X9, [X10]
    ADR X9, source_addr
    ADR X10, input_buf
    STR X10, [X9]
    ADR X9, to_in
    STR XZR, [X9]

    // Drop count
    ADD X19, X19, #CELL

interpret_loop:
    BL forth_parse_word             // ( -- c-addr u )

    // End of line? (u == 0)
    LDR X9, [X19]                   // u is on top
    CBZ X9, interpret_done

    // FIND ( c-addr u -- xt flag | c-addr u 0 )
    BL forth_find

    // Found? (flag != 0)
    LDR X9, [X19]                   // flag is on top
    CBZ X9, try_number

    // Found — top = flag (1=IMMEDIATE, -1=normal), second = xt
    // If interpreting (STATE==0), always execute.
    // If compiling: IMMEDIATE words execute, normal words get compiled.
    ADR X10, state
    LDR X10, [X10]
    CBZ X10, found_execute          // interpreting → execute

    // Compiling — check IMMEDIATE flag
    LDR X9, [X19]
    CMP X9, #1
    B.EQ found_execute              // IMMEDIATE → execute even in compile mode

    // Normal word in compile mode — compile a BL to it
    ADD X19, X19, #CELL             // drop flag
    LDR X0, [X19], #CELL            // pop xt into X0
    BL compile_call                 // emit BL xt at HERE
    B interpret_loop

found_execute:
    ADD X19, X19, #CELL             // drop flag
    BL forth_execute                // pops xt and jumps
    B interpret_loop

try_number:
    // Not in dictionary — drop 0 flag, try NUMBER
    ADD X19, X19, #CELL             // drop 0 flag ( c-addr u )

    // NUMBER ( c-addr u -- n true | c-addr u false )
    BL forth_number

    LDR X9, [X19]                   // top = true/false flag
    CBZ X9, not_found

    // Parsed — drop true flag, number is on stack
    ADD X19, X19, #CELL             // drop true flag

    // If compiling, compile the number as a literal
    ADR X9, state
    LDR X9, [X9]
    CBZ X9, interpret_loop          // interpreting → leave n on stack

    // Compiling — compile literal
    LDR X0, [X19], #CELL            // pop number into X0
    BL compile_literal              // emit BL LIT + value at HERE
    B interpret_loop

not_found:
    // Neither word nor number — error
    ADD X19, X19, #CELL             // drop false flag ( c-addr u )

    // Print "? " + token + newline
    ADR X0, err_msg
    MOV X1, #err_len
    BL platform_write

    LDR X1, [X19]                   // length = u (top)
    LDR X0, [X19, #CELL]            // buf = c-addr (second)
    BL platform_write

    MOV X0, #'\n'
    BL platform_emit

    // Clean up c-addr and u
    ADD X19, X19, #2*CELL

    // If we were compiling, abort the definition
    ADR X9, state
    LDR X10, [X9]
    CBZ X10, repl_loop
    STR XZR, [X9]                   // reset to interpret mode
    ADR X9, saved_latest
    LDR X22, [X9]                   // restore LATEST
    ADR X9, saved_here
    LDR X21, [X9]                   // restore HERE

    B repl_loop

interpret_done:
    // End of line — drop 0 0 from PARSE-WORD
    ADD X19, X19, #2*CELL

    // Print " ok"
    ADR X0, ok_msg
    MOV X1, #ok_len
    BL platform_write

    B repl_loop

repl_bye:
    ADD X19, X19, #CELL             // drop 0 count

    ADR X0, bye_msg
    MOV X1, #bye_len
    BL platform_write

    BL platform_bye

// ---------- Error Handlers ----------
// These are branched to (not called) from primitives in core.s.
// They print a message, reset the stack, recover from compile mode
// if needed, and return to the REPL.

.global stack_underflow
stack_underflow:
    ADR X0, msg_underflow
    MOV X1, #msg_underflow_len
    BL platform_write
    B error_reset

.global stack_overflow
stack_overflow:
    ADR X0, msg_overflow
    MOV X1, #msg_overflow_len
    BL platform_write
    B error_reset

.global dict_full
dict_full:
    ADR X0, msg_dict_full
    MOV X1, #msg_dict_full_len
    BL platform_write
    B error_reset

// Shared recovery: reset stack, abort compilation if needed, return to REPL.
error_reset:
    // Reset return stack (discard stale frames from nested calls)
    ADR X9, rp0
    LDR X9, [X9]
    MOV SP, X9

    // Reset data stack to empty
    ADR X9, sp0
    LDR X19, [X9]                   // DSP = sp0 (empty)

    // If we were compiling, abort the definition
    ADR X9, state
    LDR X10, [X9]
    CBZ X10, repl_loop
    STR XZR, [X9]                   // reset to interpret mode
    ADR X9, saved_latest
    LDR X22, [X9]                   // restore LATEST
    ADR X9, saved_here
    LDR X21, [X9]                   // restore HERE

    B repl_loop

// ---------- Data ----------
.section .rodata
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
ok_msg:     .ascii " ok\n"
.equ ok_len, . - ok_msg
err_msg:    .ascii "? "
.equ err_len, . - err_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg
msg_underflow:  .ascii "stack underflow\n"
.equ msg_underflow_len, . - msg_underflow
msg_overflow:   .ascii "stack overflow\n"
.equ msg_overflow_len, . - msg_overflow
msg_dict_full:  .ascii "dictionary full\n"
.equ msg_dict_full_len, . - msg_dict_full

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
