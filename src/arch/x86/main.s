# BasicForth — Main / Test Harness (x86-64)
# Phase 2, Step 2: Terminal raw mode + KEY
#
# Register convention:
#   R15 = DSP (points to second item)
#   R14 = TOS (top of stack value)
#
# Tests:
#   1. Stack primitives (3+4=7, SWAP)
#   2. Raw mode echo loop — type characters, see them echoed, 'q' to quit

.global _start

_start:
    # Initialize data stack pointer (empty stack)
    lea data_stack_top(%rip), %r15

    # --- Test 1: Stack primitives ---

    # 3 + 4 = 7
    sub $8, %r15
    mov %r14, (%r15)            # push old TOS (garbage, but harmless)
    mov $3, %r14                # TOS = 3
    sub $8, %r15
    mov %r14, (%r15)            # push 3
    mov $4, %r14                # TOS = 4
    call forth_add              # TOS = 7
    sub $8, %r15
    mov %r14, (%r15)            # push 7
    mov $48, %r14               # TOS = '0'
    call forth_add              # TOS = 55 ('7')
    call forth_emit             # print '7'
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14               # TOS = newline
    call forth_emit

    # SWAP(1,2) -> top=1, second=2
    sub $8, %r15
    mov %r14, (%r15)
    mov $1, %r14                # TOS = 1
    sub $8, %r15
    mov %r14, (%r15)
    mov $2, %r14                # TOS = 2
    call forth_swap             # TOS = 1, [DSP] = 2
    sub $8, %r15
    mov %r14, (%r15)
    mov $48, %r14
    call forth_add              # TOS = '1'
    call forth_emit
    sub $8, %r15
    mov %r14, (%r15)
    mov $48, %r14
    call forth_add              # TOS = '2'
    call forth_emit
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14
    call forth_emit

    # --- Test 2: Raw mode echo loop ---

    # Print prompt message
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
    call print_string

    # Enter raw mode
    call platform_raw_mode

    # Echo loop: KEY, DUP, EMIT, check for 'q'
echo_loop:
    call forth_key              # ( -- char )
    call forth_dup              # ( char -- char char )
    call forth_emit             # ( char char -- char )

    # Check if char == 'q' (TOS in R14)
    cmp $'q', %r14
    je echo_done

    call forth_drop             # drop the char
    jmp echo_loop

echo_done:
    call forth_drop             # drop the 'q'

    # Print newline
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14
    call forth_emit

    # Print goodbye message
    lea bye_msg(%rip), %rsi
    mov $bye_len, %rdx
    call print_string

    # BYE restores terminal and exits
    call platform_bye

# ---------- Helper: print_string ----------
# Input: RSI = string pointer, RDX = length
print_string:
    mov $1, %rax                # SYS_write
    mov $1, %rdi                # fd = stdout
    syscall
    ret

# ---------- Data ----------
.section .rodata
prompt_msg: .ascii "Type characters (q to quit): "
.equ prompt_len, . - prompt_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg
