// BasicForth — Outer Interpreter (ARM64)
// Copyright (C) 2026 Brandon Blodget
// SPDX-License-Identifier: GPL-2.0-only
//
// Register convention (pure memory stack):
//   X19 = DSP (data stack pointer, points to top item; equals sp0 when empty)
//   X21 = HERE (next free byte in dictionary)
//   X22 = LATEST (most recent dictionary entry)
//   SP  = Return stack
//
// X20 is free (no longer used for TOS).

.include "version.inc"

.global _start

.equ CELL, 8
.equ INPUT_BUF_SIZE, 80

_start:
    // Initialize engine registers
    ADR X19, data_stack_top         // DSP = sp0 (empty stack)
    ADR X9, sp0
    STR X19, [X9]                   // save initial DSP for .S / guards
    ADR X21, dict_space             // HERE
    ADR X22, dict_constant          // LATEST

    // Initialize saved state for error recovery
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

    BL platform_init_guard_pages
    BL platform_raw_mode

    // Print startup banner
    ADR X0, version_str
    MOV X1, #version_len
    BL platform_write

    // Try to load core.fs (silent skip if not found)
    ADR X9, core_fs_name
    STR X9, [X19, #-CELL]!         // push c-addr
    MOV X9, #core_fs_len
    STR X9, [X19, #-CELL]!         // push length
    BL forth_included

.global repl_loop
repl_loop:
    // Save return stack pointer for error recovery
    MOV X9, SP
    ADR X10, rp0
    STR X9, [X10]

    // Save LATEST and HERE for guard page recovery
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

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

    // Empty line → re-prompt (count == 0)
    LDR X9, [X19]
    CBZ X9, repl_empty

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

    // Interpret the line
    BL forth_interpret_line
    CBNZ X0, repl_error

    // Success — print " ok\n"
    ADR X0, ok_msg
    MOV X1, #ok_len
    BL platform_write
    B repl_loop

repl_error:
    // Print "? " + token + newline
    ADR X0, err_msg
    MOV X1, #err_len
    BL platform_write

    ADR X9, err_token_len
    LDR X1, [X9]
    ADR X9, err_token_addr
    LDR X0, [X9]
    BL platform_write

    MOV X0, #'\n'
    BL platform_emit
    B repl_loop

repl_empty:
    ADD X19, X19, #CELL             // drop 0 count
    B repl_loop

repl_bye:
    ADD X19, X19, #CELL             // drop 0 count
    B forth_bye

// ---------- Error Handlers ----------
// Stack underflow/overflow are caught by guard pages (SIGSEGV handler
// in platform_linux.s). Only dict_full remains as an explicit handler.

.global dict_full
dict_full:
    ADR X0, msg_dict_full
    MOV X1, #msg_dict_full_len
    BL platform_write

    // Reset return stack and data stack
    ADR X9, rp0
    LDR X9, [X9]
    MOV SP, X9
    ADR X9, sp0
    LDR X19, [X9]

    // If we were compiling, abort the definition
    ADR X9, state
    LDR X10, [X9]
    CBZ X10, repl_loop
    STR XZR, [X9]
    ADR X9, saved_latest
    LDR X22, [X9]
    ADR X9, saved_here
    LDR X21, [X9]

    B repl_loop

// ---------- Data ----------
.section .rodata
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
ok_msg:     .ascii " ok\n"
.equ ok_len, . - ok_msg
err_msg:    .ascii "? "
.equ err_len, . - err_msg
msg_dict_full:  .ascii "dictionary full\n"
.equ msg_dict_full_len, . - msg_dict_full
core_fs_name:   .ascii "core.fs"
.equ core_fs_len, . - core_fs_name

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
