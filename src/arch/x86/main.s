# BasicForth — Main / Test Harness (x86-64)
# Phase 2, Step 3: Line input + number parsing
#
# Register convention:
#   R15 = DSP (points to second item)
#   R14 = TOS (top of stack value)
#
# Tests:
#   1. Stack primitives (3+4=7, SWAP)
#   2. ACCEPT + NUMBER — read a line, try to parse as number

.global _start

.equ INPUT_BUF_SIZE, 80

_start:
    # Initialize engine registers
    lea data_stack_top(%rip), %r15  # DSP
    lea dict_space(%rip), %r13      # HERE
    lea dict_execute(%rip), %r12    # LATEST

    # --- Test 1: Stack primitives ---

    # 3 + 4 = 7
    sub $8, %r15
    mov %r14, (%r15)
    mov $3, %r14
    sub $8, %r15
    mov %r14, (%r15)
    mov $4, %r14
    call forth_add
    sub $8, %r15
    mov %r14, (%r15)
    mov $48, %r14
    call forth_add
    call forth_emit
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14
    call forth_emit

    # SWAP(1,2) -> top=1, second=2
    sub $8, %r15
    mov %r14, (%r15)
    mov $1, %r14
    sub $8, %r15
    mov %r14, (%r15)
    mov $2, %r14
    call forth_swap
    sub $8, %r15
    mov %r14, (%r15)
    mov $48, %r14
    call forth_add
    call forth_emit
    sub $8, %r15
    mov %r14, (%r15)
    mov $48, %r14
    call forth_add
    call forth_emit
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14
    call forth_emit

    # --- Test 2: ACCEPT + NUMBER ---

    # Enter raw mode
    call platform_raw_mode

accept_loop:
    # Print prompt
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
    call print_string

    # ACCEPT ( c-addr max_len -- count )
    sub $8, %r15
    mov %r14, (%r15)
    lea input_buf(%rip), %r14
    sub $8, %r15
    mov %r14, (%r15)
    mov $INPUT_BUF_SIZE, %r14
    call forth_accept           # TOS = count

    # Check for empty line -> exit
    test %r14, %r14
    jz accept_bye

    # Set up for NUMBER: need ( c-addr u ) on stack
    # TOS = count. Push input_buf below it as c-addr.
    sub $8, %r15
    mov %r14, (%r15)            # push count to memory
    lea input_buf(%rip), %r14   # TOS = buf_addr
    call forth_swap             # now: TOS=count, [DSP]=buf_addr = ( c-addr u )
    call forth_number           # ( c-addr u -- n true | c-addr u false )

    # Check flag (TOS)
    test %r14, %r14
    jz not_a_number

    # Success: TOS = true, [DSP] = n
    call forth_drop             # drop true flag, TOS = n

    # Print "= "
    lea eq_msg(%rip), %rsi
    mov $eq_len, %rdx
    call print_string

    # Print the number
    call print_number

    # Print newline
    sub $8, %r15
    mov %r14, (%r15)
    mov $10, %r14
    call forth_emit

    jmp accept_loop

not_a_number:
    # TOS = false (0), [DSP] = u, [DSP+8] = c-addr
    call forth_drop             # drop false
    call forth_drop             # drop u
    call forth_drop             # drop c-addr

    lea nan_msg(%rip), %rsi
    mov $nan_len, %rdx
    call print_string

    jmp accept_loop

accept_bye:
    call forth_drop             # drop the 0 count

    lea bye_msg(%rip), %rsi
    mov $bye_len, %rdx
    call print_string

    call platform_bye

# ---------- Helper: print_string ----------
# Input: RSI = string pointer, RDX = length
print_string:
    mov $1, %rax                # SYS_write
    mov $1, %rdi                # fd = stdout
    syscall
    ret

# ---------- Helper: print_number ----------
# Print signed decimal number from TOS. Consumes TOS.
# Uses a stack buffer to build digits right-to-left.
print_number:
    sub $32, %rsp               # digit buffer on stack

    mov %r14, %rax              # RAX = number
    mov (%r15), %r14            # pop TOS (consume the number)
    add $8, %r15

    # Handle negative
    xor %ecx, %ecx              # sign flag = 0
    test %rax, %rax
    jns .Lpn_positive
    neg %rax
    mov $1, %ecx
.Lpn_positive:
    push %rcx                   # save sign flag

    # Build digits right-to-left in stack buffer
    lea 31(%rsp), %rsi          # RSI past sign push = rsp+8+31-8 ... let me be explicit
    # After push %rcx, RSP decreased by 8. Buffer starts at RSP+8.
    # End of buffer = RSP + 8 + 31 = RSP + 39
    lea 39(%rsp), %rsi          # RSI = end of buffer
    mov %rsi, %rdi              # RDI = current position
    mov $10, %r8                # divisor

    # Handle zero specially
    test %rax, %rax
    jnz .Lpn_divloop
    dec %rdi
    movb $'0', (%rdi)
    jmp .Lpn_sign

.Lpn_divloop:
    test %rax, %rax
    jz .Lpn_sign
    xor %edx, %edx
    div %r8                     # RAX = quotient, RDX = remainder
    add $'0', %dl
    dec %rdi
    movb %dl, (%rdi)
    jmp .Lpn_divloop

.Lpn_sign:
    pop %rcx                    # restore sign flag
    test %ecx, %ecx
    jz .Lpn_print
    dec %rdi
    movb $'-', (%rdi)

.Lpn_print:
    # Print: RDI = start, RSI = end
    mov %rsi, %rdx
    sub %rdi, %rdx              # length = end - start
    mov %rdi, %rsi              # buf = start
    mov $1, %rax                # SYS_write
    mov $1, %rdi                # stdout
    syscall

    add $32, %rsp
    ret

# ---------- Data ----------
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
.align 8
input_buf:
    .space INPUT_BUF_SIZE
