// BasicForth — Main / Test Harness (ARM64)
// Phase 2, Step 2: Terminal raw mode + KEY
//
// Register convention:
//   X19 = DSP (points to second item)
//   X20 = TOS (top of stack value)
//
// Tests:
//   1. Stack primitives (3+4=7, SWAP)
//   2. Raw mode echo loop — type characters, see them echoed, 'q' to quit

.global _start

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

    // Check if char == 'q' (TOS in X20)
    CMP X20, #'q'
    B.EQ echo_done

    BL forth_drop              // drop the char
    B echo_loop

echo_done:
    BL forth_drop              // drop the 'q'

    // Print newline
    STR X20, [X19, #-8]!
    MOV X20, #10
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
