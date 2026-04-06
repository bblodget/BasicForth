// BasicForth — Outer Interpreter (ARM64)
//
// Register convention:
//   X19 = DSP (data stack pointer, points to second item)
//   X20 = TOS (top of stack value)
//   X21 = HERE (next free byte in dictionary)
//   X22 = LATEST (most recent dictionary entry)
//   SP  = Return stack

.global _start

.equ INPUT_BUF_SIZE, 80

_start:
    // Initialize engine registers
    ADR X19, data_stack_top         // DSP
    ADR X9, sp0
    STR X19, [X9]                   // save initial DSP for .S
    ADR X21, dict_space             // HERE
    ADR X22, dict_bye               // LATEST
    MOV X20, #0                     // TOS = 0

    BL platform_raw_mode

repl_loop:
    // Print prompt
    ADR X0, prompt_msg
    MOV X1, #prompt_len
    BL platform_write

    // ACCEPT ( c-addr max -- count )
    STR X20, [X19, #-8]!           // push old TOS
    ADR X20, input_buf
    STR X20, [X19, #-8]!
    MOV X20, #INPUT_BUF_SIZE
    BL forth_accept                 // TOS = count

    // Empty line → exit
    CBZ X20, repl_bye

    // Set up source variables for PARSE-WORD
    ADR X9, source_len
    STR X20, [X9]
    ADR X9, source_addr
    ADR X10, input_buf
    STR X10, [X9]
    ADR X9, to_in
    STR XZR, [X9]

    // Drop count (restore user's TOS)
    BL forth_drop

interpret_loop:
    BL forth_parse_word             // ( -- c-addr u )

    // End of line? (u == 0)
    CBZ X20, interpret_done

    // FIND ( c-addr u -- xt flag | c-addr u 0 )
    BL forth_find

    // Found? (flag != 0)
    CBZ X20, try_number

    // Found — drop flag, execute word
    BL forth_drop                   // drop flag, TOS = xt
    BL forth_execute
    B interpret_loop

try_number:
    // Not in dictionary — drop 0 flag, try NUMBER
    BL forth_drop                   // ( c-addr u )

    // NUMBER ( c-addr u -- n true | c-addr u false )
    BL forth_number

    CBZ X20, not_found

    // Parsed — drop true flag, number is on stack
    BL forth_drop
    B interpret_loop

not_found:
    // Neither word nor number — error
    BL forth_drop                   // drop false, ( c-addr u )

    // Print "? " + token + newline
    ADR X0, err_msg
    MOV X1, #err_len
    BL platform_write

    MOV X1, X20                     // length = u (TOS)
    LDR X0, [X19]                   // buf = c-addr ([DSP])
    BL platform_write

    MOV X0, #'\n'
    BL platform_emit

    // Clean up c-addr and u
    BL forth_drop                   // drop u
    BL forth_drop                   // drop c-addr

    B repl_loop

interpret_done:
    // End of line — drop 0 0 from PARSE-WORD
    BL forth_drop
    BL forth_drop

    // Print " ok"
    ADR X0, ok_msg
    MOV X1, #ok_len
    BL platform_write

    B repl_loop

repl_bye:
    BL forth_drop                   // drop 0 count

    ADR X0, bye_msg
    MOV X1, #bye_len
    BL platform_write

    BL platform_bye

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

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
