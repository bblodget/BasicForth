// BasicForth — Main / Test Harness (ARM64)
// Phase 2, Step 3: Line input (ACCEPT)
//
// Register convention:
//   X19 = DSP (points to second item)
//   X20 = TOS (top of stack value)
//
// Tests:
//   1. Stack primitives (3+4=7, SWAP)
//   2. ACCEPT — read a line, print it back

.global _start

.equ INPUT_BUF_SIZE, 80

_start:
    // Initialize data stack pointer (empty stack)
    ADR X19, data_stack_top

    // --- Test 1: Stack primitives ---

    // 3 + 4 = 7
    STR X20, [X19, #-8]!      // push old TOS (garbage, but harmless)
    MOV X20, #3                // TOS = 3
    STR X20, [X19, #-8]!      // push 3
    MOV X20, #4                // TOS = 4
    BL forth_add               // TOS = 7
    STR X20, [X19, #-8]!      // push 7
    MOV X20, #48               // TOS = '0'
    BL forth_add               // TOS = 55 ('7')
    BL forth_emit              // print '7'
    STR X20, [X19, #-8]!
    MOV X20, #10               // TOS = newline
    BL forth_emit

    // SWAP(1,2) → top=1, second=2
    STR X20, [X19, #-8]!
    MOV X20, #1                // TOS = 1
    STR X20, [X19, #-8]!
    MOV X20, #2                // TOS = 2
    BL forth_swap              // TOS = 1, [DSP] = 2
    STR X20, [X19, #-8]!
    MOV X20, #48
    BL forth_add               // TOS = '1'
    BL forth_emit
    STR X20, [X19, #-8]!
    MOV X20, #48
    BL forth_add               // TOS = '2'
    BL forth_emit
    STR X20, [X19, #-8]!
    MOV X20, #10
    BL forth_emit

    // --- Test 2: ACCEPT — read a line, print it back ---

    // Enter raw mode
    BL platform_raw_mode

accept_loop:
    // Print prompt
    ADR X0, prompt_msg
    MOV X1, #prompt_len
    BL print_string

    // Push args for ACCEPT: ( c-addr max_len -- count )
    STR X20, [X19, #-8]!
    ADR X20, input_buf         // TOS = buf address
    STR X20, [X19, #-8]!
    MOV X20, #INPUT_BUF_SIZE   // TOS = max length
    BL forth_accept            // TOS = count

    // Check for empty line (just pressed Enter)
    CBZ X20, accept_bye

    // Print "You typed: "
    ADR X0, echo_msg
    MOV X1, #echo_len
    BL print_string

    // Print the buffer using write syscall
    // TOS = count, need buf address
    MOV X2, X20                // count
    ADR X1, input_buf          // buf
    MOV X0, #1                 // stdout
    MOV X8, #64                // SYS_write
    SVC #0

    // Print newline
    STR X20, [X19, #-8]!
    MOV X20, #10
    BL forth_emit

    // Drop the count (consumed by write above, but still in TOS)
    // Actually TOS is still the count from forth_accept, and we used
    // it via MOV X2, X20. We need to drop it to keep stack clean.
    BL forth_drop

    B accept_loop

accept_bye:
    BL forth_drop              // drop the 0 count

    ADR X0, bye_msg
    MOV X1, #bye_len
    BL print_string

    // BYE restores terminal and exits
    BL platform_bye

// ---------- Helper: print_string ----------
// Input: X0 = string pointer, X1 = length
print_string:
    MOV X2, X1                 // count
    MOV X1, X0                 // buf
    MOV X0, #1                 // fd = stdout
    MOV X8, #64                // SYS_write
    SVC #0
    RET

// ---------- Data ----------
.section .rodata
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
echo_msg:   .ascii "You typed: "
.equ echo_len, . - echo_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
