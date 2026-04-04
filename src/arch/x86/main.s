# BasicForth — Main / Test Harness (x86-64)
# Phase 2, Step 2: Terminal raw mode + KEY
#
# Tests:
#   1. Stack primitives (3+4=7, SWAP)
#   2. Raw mode echo loop — type characters, see them echoed, 'q' to quit

.global _start

_start:
    # Initialize data stack pointer
    lea data_stack_top(%rip), %r15

    # --- Test 1: Stack primitives ---

    # 3 + 4 = 7
    sub $8, %r15
    movq $3, (%r15)
    sub $8, %r15
    movq $4, (%r15)
    call forth_add
    sub $8, %r15
    movq $48, (%r15)            # ASCII '0'
    call forth_add
    call forth_emit
    sub $8, %r15
    movq $10, (%r15)            # newline
    call forth_emit

    # SWAP(1,2) -> top=1, second=2
    sub $8, %r15
    movq $1, (%r15)
    sub $8, %r15
    movq $2, (%r15)
    call forth_swap
    sub $8, %r15
    movq $48, (%r15)
    call forth_add
    call forth_emit
    sub $8, %r15
    movq $48, (%r15)
    call forth_add
    call forth_emit
    sub $8, %r15
    movq $10, (%r15)
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

    # Check if char == 'q'
    mov (%r15), %rax            # peek at top
    cmp $'q', %rax
    je echo_done

    call forth_drop             # drop the char
    jmp echo_loop

echo_done:
    call forth_drop             # drop the 'q'

    # Print newline
    sub $8, %r15
    movq $10, (%r15)
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
