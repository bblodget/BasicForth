# BasicForth — Core ASM Primitives (x86-64)
# Platform-independent x86-64 assembly. Requires platform_linux.s (or equivalent).
#
# Register allocation:
#   R15 = Data stack pointer (DSP) — points to second item on stack
#   R14 = Top of stack (TOS) — always holds the top value
#   R13 = HERE pointer (dictionary free space) — future
#   R12 = LATEST pointer (most recent dictionary entry) — future
#   RSP = Return stack
#
# TOS-in-register invariant: R14 always holds the top of the data stack.
# DSP (R15) points to the second item. Push = store R14 to memory, set R14.
# Pop = move R14 out, load next from memory into R14.
#
# R12-R15 are callee-saved in the System V AMD64 ABI,
# so C functions won't clobber them.

.equ CELL, 8                    # 64-bit cells
.equ DATA_STACK_SIZE, 4096      # 512 cells

# ---------- Primitives ----------

# DUP ( a -- a a )
.global forth_dup
forth_dup:
    sub $CELL, %r15             # make room
    mov %r14, (%r15)            # push TOS to memory
    ret                          # TOS unchanged

# DROP ( a -- )
.global forth_drop
forth_drop:
    mov (%r15), %r14            # pop next into TOS
    add $CELL, %r15
    ret

# SWAP ( a b -- b a )
# TOS=b, [DSP]=a -> TOS=a, [DSP]=b
.global forth_swap
forth_swap:
    mov (%r15), %rax            # rax = a
    mov %r14, (%r15)            # [DSP] = b
    mov %rax, %r14              # TOS = a
    ret

# OVER ( a b -- a b a )
# TOS=b, [DSP]=a -> push b, TOS=a
.global forth_over
forth_over:
    sub $CELL, %r15             # make room
    mov %r14, (%r15)            # push b to memory
    mov CELL(%r15), %r14        # TOS = a
    ret

# + ( a b -- a+b )
# TOS=b, [DSP]=a -> TOS=a+b
.global forth_add
forth_add:
    add (%r15), %r14            # TOS = a + b
    add $CELL, %r15             # pop a
    ret

# - ( a b -- a-b )
# TOS=b, [DSP]=a -> TOS=a-b
.global forth_sub
forth_sub:
    mov (%r15), %rax            # rax = a
    sub %r14, %rax              # rax = a - b
    mov %rax, %r14              # TOS = a - b
    add $CELL, %r15             # pop
    ret

# NEGATE ( a -- -a )
.global forth_negate
forth_negate:
    neg %r14                    # negate TOS
    ret

# ---------- EMIT (Forth-level) ----------
# ( char -- )
# TOS = char. Pass to platform_emit, pop new TOS.
.global forth_emit
forth_emit:
    mov %r14, %rdi              # RDI = char (from TOS)
    mov (%r15), %r14            # pop new TOS
    add $CELL, %r15
    jmp platform_emit           # tail call

# ---------- KEY (Forth-level) ----------
# ( -- char )
# Push old TOS, call platform_key, TOS = result.
.global forth_key
forth_key:
    sub $CELL, %r15
    mov %r14, (%r15)            # push old TOS to memory
    call platform_key           # RDI = character
    mov %rdi, %r14              # TOS = char
    ret

# ---------- ACCEPT (Forth-level) ----------
# ( c-addr +n1 -- +n2 )
# Read a line from stdin into buffer at c-addr, max n1 chars.
# Handles backspace editing and echo. Returns actual count.
# Calls platform_key and platform_emit directly (register level).
.global forth_accept
forth_accept:
    push %rbx
    push %rbp
    push %r12

    # Pop args from data stack: TOS = max_len, [DSP] = buf_addr
    mov %r14, %rbp              # RBP = max_len
    mov (%r15), %rbx            # RBX = buf_addr
    add $CELL, %r15
    xor %r12d, %r12d            # R12 = count = 0

.Laccept_loop:
    call platform_key           # RDI = char

    # Check for LF (Enter)
    cmp $10, %rdi
    je .Laccept_done

    # Check for BS (8) or DEL (127)
    cmp $8, %rdi
    je .Laccept_bs
    cmp $127, %rdi
    je .Laccept_bs

    # Ignore non-printable (< 32 or > 126)
    cmp $32, %rdi
    jb .Laccept_loop
    cmp $126, %rdi
    ja .Laccept_loop

    # Buffer full?
    cmp %rbp, %r12
    jge .Laccept_loop

    # Store char and echo
    movb %dil, (%rbx,%r12)     # buf[count] = char
    inc %r12                    # count++
    call platform_emit          # echo (RDI still has char)
    jmp .Laccept_loop

.Laccept_bs:
    # Ignore backspace if buffer empty
    test %r12, %r12
    jz .Laccept_loop
    dec %r12                    # count--
    # Erase on screen: \b space \b
    mov $8, %rdi
    call platform_emit
    mov $32, %rdi
    call platform_emit
    mov $8, %rdi
    call platform_emit
    jmp .Laccept_loop

.Laccept_done:
    # Echo the newline
    mov $10, %rdi
    call platform_emit

    # Push result: TOS = count
    mov %r12, %r14

    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- NUMBER (Forth-level) ----------
# ( c-addr u -- n true | c-addr u false )
# Try to parse string as a number. Supports:
#   - Decimal (default, or # prefix)
#   - Hex ($ prefix)
#   - Binary (% prefix)
#   - Negative sign before or after prefix (-$FF or $-FF)
#   - Case-insensitive hex digits (a-f, A-F)
# Uses BASE variable for default base.
.global forth_number
forth_number:
    push %rbx
    push %rbp
    push %r12
    push %r13                   # temporarily borrow R13 (future HERE)

    # Pop args: TOS = len, [DSP] = addr
    mov %r14, %rcx              # RCX = len
    mov (%r15), %rbx            # RBX = addr
    add $CELL, %r15
    # Save originals for failure case
    mov %rbx, %r12              # R12 = orig addr
    mov %rcx, %r13              # R13 = orig len

    # Empty string is not a number
    test %rcx, %rcx
    jz .Lnum_fail

    xor %eax, %eax              # RAX = result = 0
    xor %edx, %edx              # RDX = negate flag = 0
    mov base(%rip), %rbp        # RBP = base

    # Check for leading '-'
    movzbl (%rbx), %edi
    cmp $'-', %edi
    jne .Lnum_check_prefix
    inc %rbx
    dec %rcx
    mov $1, %edx                # set negate flag
    test %rcx, %rcx
    jz .Lnum_fail

.Lnum_check_prefix:
    movzbl (%rbx), %edi
    cmp $'$', %edi
    je .Lnum_hex
    cmp $'#', %edi
    je .Lnum_decimal
    cmp $'%', %edi
    je .Lnum_binary
    jmp .Lnum_check_sign_after

.Lnum_hex:
    mov $16, %rbp
    jmp .Lnum_consume_prefix
.Lnum_decimal:
    mov $10, %rbp
    jmp .Lnum_consume_prefix
.Lnum_binary:
    mov $2, %rbp
.Lnum_consume_prefix:
    inc %rbx
    dec %rcx
    test %rcx, %rcx
    jz .Lnum_fail

.Lnum_check_sign_after:
    # Check for '-' after prefix (e.g., $-FF)
    test %edx, %edx
    jnz .Lnum_save_and_parse    # already have sign
    movzbl (%rbx), %edi
    cmp $'-', %edi
    jne .Lnum_save_and_parse
    inc %rbx
    dec %rcx
    mov $1, %edx
    test %rcx, %rcx
    jz .Lnum_fail

.Lnum_save_and_parse:
    # Save negate flag on stack (RDX is clobbered by imul on some paths)
    push %rdx                   # negate flag on return stack

    # RAX = result, RBX = ptr, RCX = remaining, RBP = base
.Lnum_loop:
    test %rcx, %rcx
    jz .Lnum_done
    movzbl (%rbx), %edi         # RDI = char

    # Convert char to digit value
    cmp $'0', %edi
    jb .Lnum_fail2
    cmp $'9', %edi
    jbe .Lnum_digit_09

    cmp $'A', %edi
    jb .Lnum_fail2
    cmp $'Z', %edi
    jbe .Lnum_letter_upper

    cmp $'a', %edi
    jb .Lnum_fail2
    cmp $'z', %edi
    ja .Lnum_fail2

    # Lowercase letter
    sub $('a' - 10), %edi
    jmp .Lnum_check_digit

.Lnum_letter_upper:
    sub $('A' - 10), %edi
    jmp .Lnum_check_digit

.Lnum_digit_09:
    sub $'0', %edi

.Lnum_check_digit:
    # Check digit < base
    cmp %rbp, %rdi
    jge .Lnum_fail2

    # result = result * base + digit
    imul %rbp, %rax             # RAX = RAX * base
    add %rdi, %rax              # RAX += digit

    inc %rbx
    dec %rcx
    jmp .Lnum_loop

.Lnum_done:
    pop %rdx                    # restore negate flag
    test %edx, %edx
    jz .Lnum_success
    neg %rax

.Lnum_success:
    # Push n and true: ( -- n true )
    sub $CELL, %r15
    mov %rax, (%r15)            # push n to memory
    mov $-1, %r14               # TOS = true (-1)
    jmp .Lnum_exit

.Lnum_fail2:
    pop %rdx                    # clean up negate flag from stack
.Lnum_fail:
    # Push c-addr, u, and false: ( -- c-addr u false )
    sub $CELL, %r15
    mov %r12, (%r15)            # push orig c-addr
    sub $CELL, %r15
    mov %r13, (%r15)            # push orig u
    mov $0, %r14                # TOS = false

.Lnum_exit:
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- Data Stack Memory ----------
.bss
.align 8
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:

# ---------- Variables ----------
.data
.align 8
.global base
base:
    .quad 10
