# BasicForth — Main / Test Harness (x86-64)
# Phase 2, Step 3: Line input (ACCEPT)
#
# Register convention:
#   R15 = DSP (points to second item)
#   R14 = TOS (top of stack value)
#
# Tests:
#   1. Stack primitives (3+4=7, SWAP)
#   2. ACCEPT — read a line, print it back

.global _start

.equ INPUT_BUF_SIZE, 80

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

    # --- Test 2: ACCEPT — read a line, print it back ---

    # Enter raw mode
    call platform_raw_mode

accept_loop:
    # Print prompt
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
    call print_string

    # Push args for ACCEPT: ( c-addr max_len -- count )
    sub $8, %r15
    mov %r14, (%r15)
    lea input_buf(%rip), %r14   # TOS = buf address
    sub $8, %r15
    mov %r14, (%r15)
    mov $INPUT_BUF_SIZE, %r14   # TOS = max length
    call forth_accept           # TOS = count

    # Check for empty line (just pressed Enter)
    test %r14, %r14
    jz accept_bye

    # Print "You typed: "
    lea echo_msg(%rip), %rsi
    mov $echo_len, %rdx
    call print_string

    # Print the buffer using write syscall
    # TOS = count, need buf address
    mov %r14, %rdx              # count
    lea input_buf(%rip), %rsi   # buf
    mov $1, %rax                # SYS_write
    mov $1, %rdi                # stdout
    syscall

    # Print newline
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14
    call forth_emit

    # Drop the count
    call forth_drop

    jmp accept_loop

accept_bye:
    call forth_drop             # drop the 0 count

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
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
echo_msg:   .ascii "You typed: "
.equ echo_len, . - echo_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg

.bss
.align 8
input_buf:
    .space INPUT_BUF_SIZE
