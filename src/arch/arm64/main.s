// BasicForth — Main / Test Harness (ARM64)
// Phase 2, Step 3: Line input + number parsing
//
// Register convention:
//   X19 = DSP (points to second item)
//   X20 = TOS (top of stack value)
//
// Tests:
//   1. Stack primitives (3+4=7, SWAP)
//   2. ACCEPT + NUMBER — read a line, try to parse as number

.global _start

.equ INPUT_BUF_SIZE, 80

_start:
    // Initialize engine registers
    ADR X19, data_stack_top         // DSP
    ADR X21, dict_space             // HERE
    MOV X22, #0                     // LATEST (0 = empty, updated in Step 3)

    // --- Test 1: Stack primitives ---

    // 3 + 4 = 7
    STR X20, [X19, #-8]!
    MOV X20, #3
    STR X20, [X19, #-8]!
    MOV X20, #4
    BL forth_add
    STR X20, [X19, #-8]!
    MOV X20, #48
    BL forth_add
    BL forth_emit
    STR X20, [X19, #-8]!
    MOV X20, #10
    BL forth_emit

    // SWAP(1,2) → top=1, second=2
    STR X20, [X19, #-8]!
    MOV X20, #1
    STR X20, [X19, #-8]!
    MOV X20, #2
    BL forth_swap
    STR X20, [X19, #-8]!
    MOV X20, #48
    BL forth_add
    BL forth_emit
    STR X20, [X19, #-8]!
    MOV X20, #48
    BL forth_add
    BL forth_emit
    STR X20, [X19, #-8]!
    MOV X20, #10
    BL forth_emit

    // --- Test 2: ACCEPT + NUMBER ---

    // Enter raw mode
    BL platform_raw_mode

accept_loop:
    // Print prompt
    ADR X0, prompt_msg
    MOV X1, #prompt_len
    BL print_string

    // ACCEPT ( c-addr max_len -- count )
    STR X20, [X19, #-8]!
    ADR X20, input_buf
    STR X20, [X19, #-8]!
    MOV X20, #INPUT_BUF_SIZE
    BL forth_accept            // TOS = count

    // Check for empty line → exit
    CBZ X20, accept_bye

    // Set up for NUMBER: need ( c-addr u ) on stack
    // TOS = count. Push input_buf below it as c-addr.
    STR X20, [X19, #-8]!      // push count to memory
    ADR X20, input_buf         // TOS = buf_addr
    BL forth_swap              // now: TOS=count, [DSP]=buf_addr = ( c-addr u )
    BL forth_number            // ( c-addr u -- n true | c-addr u false )

    // Check flag (TOS)
    CMP X20, #0
    B.EQ not_a_number

    // Success: TOS = true, [DSP] = n
    BL forth_drop              // drop the true flag, TOS = n

    // Print "= "
    ADR X0, eq_msg
    MOV X1, #eq_len
    BL print_string

    // Print the number (simple decimal print)
    // TOS = n, call print_number helper
    BL print_number

    // Print newline
    STR X20, [X19, #-8]!
    MOV X20, #10
    BL forth_emit

    B accept_loop

not_a_number:
    // TOS = false (0), [DSP] = u, [DSP+8] = c-addr
    BL forth_drop              // drop false
    BL forth_drop              // drop u
    BL forth_drop              // drop c-addr

    ADR X0, nan_msg
    MOV X1, #nan_len
    BL print_string

    B accept_loop

accept_bye:
    BL forth_drop              // drop the 0 count

    ADR X0, bye_msg
    MOV X1, #bye_len
    BL print_string

    BL platform_bye

// ---------- Helper: print_string ----------
// Input: X0 = string pointer, X1 = length
print_string:
    MOV X2, X1
    MOV X1, X0
    MOV X0, #1
    MOV X8, #64
    SVC #0
    RET

// ---------- Helper: print_number ----------
// Print signed decimal number from TOS. Consumes TOS.
// Uses a stack buffer to build digits right-to-left.
print_number:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #32            // digit buffer on stack

    MOV X9, X20                // X9 = number
    LDR X20, [X19], #8        // pop TOS (consume the number)

    // Handle negative
    MOV X11, #0                // sign flag
    CMP X9, #0
    B.GE .Lpn_positive
    NEG X9, X9
    MOV X11, #1
.Lpn_positive:

    // Build digits right-to-left in stack buffer
    ADD X12, SP, #31           // X12 = end of buffer
    MOV X13, X12               // X13 = current position
    MOV X14, #10               // divisor

    // Handle zero specially
    CBNZ X9, .Lpn_divloop
    SUB X13, X13, #1
    MOV W10, #'0'
    STRB W10, [X13]
    B .Lpn_sign

.Lpn_divloop:
    CBZ X9, .Lpn_sign
    UDIV X10, X9, X14          // X10 = quotient
    MSUB X15, X10, X14, X9     // X15 = remainder
    ADD W15, W15, #'0'         // convert to ASCII
    SUB X13, X13, #1
    STRB W15, [X13]
    MOV X9, X10                // quotient for next iteration
    B .Lpn_divloop

.Lpn_sign:
    CBZ X11, .Lpn_print
    SUB X13, X13, #1
    MOV W10, #'-'
    STRB W10, [X13]

.Lpn_print:
    // Print: X13 = start, X12 = end
    SUB X2, X12, X13           // length
    MOV X1, X13                // buf
    MOV X0, #1                 // stdout
    MOV X8, #64
    SVC #0

    ADD SP, SP, #32
    LDP X29, X30, [SP], #16
    RET

// ---------- Data ----------
.section .rodata
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
eq_msg:     .ascii "= "
.equ eq_len, . - eq_msg
nan_msg:    .ascii "  Not a number\n"
.equ nan_len, . - nan_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
