// PumpkinForth — Main / Test Harness
// Phase 2, Step 2: Terminal raw mode + KEY
//
// Tests:
//   1. Previous tests (stack primitives)
//   2. Raw mode echo loop — type characters, see them echoed, press 'q' to quit

.global _start

_start:
    // Initialize data stack pointer
    ADR X19, data_stack_top

    // --- Test 1: Stack primitives (same as before) ---

    // 3 + 4 = 7
    MOV X9, #3
    STR X9, [X19, #-8]!
    MOV X9, #4
    STR X9, [X19, #-8]!
    BL forth_add
    MOV X9, #48
    STR X9, [X19, #-8]!
    BL forth_add
    BL forth_emit
    MOV X9, #10
    STR X9, [X19, #-8]!
    BL forth_emit

    // SWAP(1,2) → top=1, second=2
    MOV X9, #1
    STR X9, [X19, #-8]!
    MOV X9, #2
    STR X9, [X19, #-8]!
    BL forth_swap
    MOV X9, #48
    STR X9, [X19, #-8]!
    BL forth_add
    BL forth_emit
    MOV X9, #48
    STR X9, [X19, #-8]!
    BL forth_add
    BL forth_emit
    MOV X9, #10
    STR X9, [X19, #-8]!
    BL forth_emit

    // --- Test 2: Raw mode echo loop ---

    // Print prompt message
    ADR X0, prompt_msg
    MOV X1, #prompt_len
    BL print_string

    // Enter raw mode
    BL platform_raw_mode

    // Echo loop: KEY, DUP, EMIT, check for 'q'
echo_loop:
    BL forth_key               // ( -- char )
    BL forth_dup               // ( char -- char char )
    BL forth_emit              // ( char char -- char )

    // Check if char == 'q'
    LDR X9, [X19]             // peek at top (the char)
    CMP X9, #'q'
    B.EQ echo_done

    // Check if char == CR (13), emit LF too
    CMP X9, #13
    B.NE echo_not_cr
    MOV X9, #10
    STR X9, [X19, #-8]!
    BL forth_emit
echo_not_cr:

    BL forth_drop              // drop the char
    B echo_loop

echo_done:
    BL forth_drop              // drop the 'q'

    // Print newline
    MOV X9, #10
    STR X9, [X19, #-8]!
    BL forth_emit

    // Print goodbye message
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
prompt_msg: .ascii "Type characters (q to quit): "
.equ prompt_len, . - prompt_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg
