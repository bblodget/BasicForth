# BasicForth — Core ASM Primitives (x86-64)
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Platform-independent x86-64 assembly. Requires platform_linux.s (or equivalent).
#
# Register allocation:
#   R15 = Data stack pointer (DSP) — points to top item on stack
#         (equals sp0 when stack is empty)
#   R14 = scratch (available — no longer used for TOS)
#   R13 = HERE pointer (dictionary free space)
#   R12 = LATEST pointer (most recent dictionary entry)
#   RSP = Return stack
#
# Pure memory stack: all data stack items live in memory.
# DSP (R15) points to the topmost item. Push = decrement R15, store.
# Pop = load from R15, increment R15. Depth = (sp0 - DSP) / CELL.
#
# R12-R15 are callee-saved in the System V AMD64 ABI,
# so C functions won't clobber them.

.equ CELL, 8                    # 64-bit cells
.equ DATA_STACK_SIZE, 4096      # 512 cells

# ---------- Dictionary Entry Layout ----------
# [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4]
#
# Flags byte: bit 7 = IMMEDIATE, bit 6 = HIDDEN, bits 0-5 = name length
.equ F_IMMEDIATE,   0x80
.equ F_HIDDEN,      0x40
.equ F_COMPILE_ONLY,0x20
.equ F_LENMASK,     0x1F


# CHECK_DICT n: verify HERE + n bytes fits in dict_space.
# Always active — dictionary has no guard page.
.macro CHECK_DICT n
    lea dict_space+DICT_SPACE_SIZE(%rip), %rcx
    lea \n(%r13), %rdx
    cmp %rcx, %rdx
    ja dict_full
.endm

# DEFWORD entry, name, label, link, flags
#   entry: label for this dictionary entry
#   name:  the Forth name string (lowercase)
#   label: the assembly code address
#   link:  label of previous entry (0 for first)
#   flags: optional flags byte (default 0)
.macro DEFWORD entry, name, label, link, flags=0
.section .data
.balign 8
\entry:
    .quad \link
\entry\()_flags:
    .byte ((\entry\()_name_end - \entry\()_name_start) | \flags)
\entry\()_name_start:
    .ascii "\name"
\entry\()_name_end:
    .balign 8
\entry\()_xt:
    .quad \label
\entry\()_codelen:
    .long 0
    .balign 4
.text
.endm

# ---------- Primitives ----------

# DUP ( a -- a a )
.global forth_dup
forth_dup:


    mov (%r15), %rax
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# DROP ( a -- )
.global forth_drop
forth_drop:
    mov (%r15), %rax            # touch top item (triggers guard page if empty)
    add $CELL, %r15
    ret

# SWAP ( a b -- b a )
.global forth_swap
forth_swap:

    mov (%r15), %rax            # rax = b (top)
    mov CELL(%r15), %rcx        # rcx = a (second)
    mov %rcx, (%r15)            # top = a
    mov %rax, CELL(%r15)        # second = b
    ret

# OVER ( a b -- a b a )
.global forth_over
forth_over:


    mov CELL(%r15), %rax        # rax = a (second item)
    sub $CELL, %r15
    mov %rax, (%r15)            # push a on top
    ret

# ROT ( a b c -- b c a )
.global forth_rot
forth_rot:

    mov (%r15), %rax            # rax = c
    mov CELL(%r15), %rcx        # rcx = b
    mov 2*CELL(%r15), %rdx      # rdx = a
    mov %rcx, 2*CELL(%r15)      # bottom = b
    mov %rax, CELL(%r15)        # middle = c
    mov %rdx, (%r15)            # top = a
    ret

# NIP ( a b -- b )
.global forth_nip
forth_nip:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop
    mov %rax, (%r15)            # top = b
    ret

# TUCK ( a b -- b a b )
.global forth_tuck
forth_tuck:

    mov (%r15), %rax            # rax = b
    mov CELL(%r15), %rcx        # rcx = a
    sub $CELL, %r15             # make room
    mov %rax, (%r15)            # top = b
    mov %rcx, CELL(%r15)        # middle = a
    mov %rax, 2*CELL(%r15)      # bottom = b
    ret

# 2DUP ( a b -- a b a b )
.global forth_two_dup
forth_two_dup:

    mov (%r15), %rax            # rax = b
    mov CELL(%r15), %rcx        # rcx = a
    sub $2*CELL, %r15           # make room for 2
    mov %rax, (%r15)            # top = b
    mov %rcx, CELL(%r15)        # second = a
    ret

# 2DROP ( a b -- )
.global forth_two_drop
forth_two_drop:

    mov (%r15), %rax            # touch top (guard page trigger)
    mov CELL(%r15), %rax        # touch second (guard page trigger)
    add $2*CELL, %r15
    ret

# DEPTH ( -- n )
.global forth_depth
forth_depth:

    mov sp0(%rip), %rax
    sub %r15, %rax              # rax = sp0 - DSP (bytes)
    sar $3, %rax                # rax = depth (cells = bytes / 8)
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ?DUP ( x -- x x | 0 )
.global forth_question_dup
forth_question_dup:

    mov (%r15), %rax
    test %rax, %rax
    jz 1f
    sub $CELL, %r15
    mov %rax, (%r15)
1:  ret

# >R ( x -- ) ( R: -- x )
# Move top of data stack to return stack.
# Must juggle around the return address left by CALL.
# Marked F_COMPILE_ONLY — outer interpreter rejects in interpret mode.
.global forth_to_r
forth_to_r:

    pop %rax                    # rax = return address
    mov (%r15), %rcx            # rcx = x
    add $CELL, %r15             # pop data stack
    push %rcx                   # push x to return stack
    push %rax                   # restore return address
    ret

# R> ( -- x ) ( R: x -- )
# Move top of return stack to data stack.
.global forth_r_from
forth_r_from:

    pop %rax                    # rax = return address
    pop %rcx                    # rcx = x from return stack
    push %rax                   # restore return address
    sub $CELL, %r15
    mov %rcx, (%r15)            # push x to data stack
    ret

# R@ ( -- x ) ( R: x -- x )
# Copy top of return stack to data stack (non-destructive).
.global forth_r_fetch
forth_r_fetch:

    mov 8(%rsp), %rax           # x is just below the return address
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# + ( a b -- a+b )
.global forth_add
forth_add:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    add %rax, (%r15)            # top = a + b
    ret

# - ( a b -- a-b )
.global forth_sub
forth_sub:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    sub %rax, (%r15)            # top = a - b
    ret

# NEGATE ( a -- -a )
.global forth_negate
forth_negate:

    negq (%r15)
    ret

# * ( a b -- a*b )
.global forth_mul
forth_mul:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    imulq (%r15)                # rdx:rax = rax * [r15]
    mov %rax, (%r15)            # top = low 64 bits
    ret

# /MOD ( a b -- rem quot )
# Division by zero returns 0 0.
# INT64_MIN / -1 returns 0 INT64_MIN (matches ARM64 SDIV behavior).
.global forth_divmod
forth_divmod:

    mov (%r15), %rcx            # rcx = b (divisor)
    test %rcx, %rcx
    jz .Ldivmod_zero
    mov CELL(%r15), %rax        # rax = a (dividend)
    # Check for INT64_MIN / -1 overflow (idiv would raise SIGFPE)
    cmp $-1, %rcx
    jne .Ldivmod_ok
    movabs $0x8000000000000000, %rdx
    cmp %rdx, %rax
    je .Ldivmod_overflow
.Ldivmod_ok:
    cqo                         # sign-extend rax into rdx:rax
    idiv %rcx                   # rax = quot, rdx = rem
    mov %rdx, CELL(%r15)        # second = rem
    mov %rax, (%r15)            # top = quot
    ret
.Ldivmod_zero:
    movq $0, CELL(%r15)         # rem = 0
    movq $0, (%r15)             # quot = 0
    ret
.Ldivmod_overflow:
    movq $0, CELL(%r15)         # rem = 0
    # quot = INT64_MIN (already in rax)
    mov %rax, (%r15)
    ret

# ---------- Double-Cell Arithmetic ----------

# S>D ( n -- d )  Sign-extend single to double.
# Double-cell: high word on top, low word below.
.global forth_s_to_d
forth_s_to_d:
    mov (%r15), %rax
    cqo                         # RDX = sign extension of RAX
    sub $CELL, %r15
    mov %rax, CELL(%r15)        # low word (second)
    mov %rdx, (%r15)            # high word on top
    ret

# UM* ( u1 u2 -- ud )  Unsigned multiply, 128-bit result.
# Double-cell result: high word on top, low word below.
.global forth_um_star
forth_um_star:
    mov (%r15), %rax            # u2
    mulq CELL(%r15)             # RDX:RAX = RAX * u1 (unsigned)
    mov %rax, CELL(%r15)        # low word (second)
    mov %rdx, (%r15)            # high word (top)
    ret

# M* ( n1 n2 -- d )  Signed multiply, 128-bit result.
# Double-cell result: high word on top, low word below.
.global forth_m_star
forth_m_star:
    mov (%r15), %rax            # n2
    imulq CELL(%r15)            # RDX:RAX = RAX * n1 (signed)
    mov %rax, CELL(%r15)        # low word (second)
    mov %rdx, (%r15)            # high word (top)
    ret

# UM/MOD ( ud u1 -- u2 u3 )  Unsigned double / single → remainder quotient.
# u2 = remainder, u3 = quotient.
# Division by zero returns 0 0.
.global forth_um_divmod
forth_um_divmod:
    mov (%r15), %rcx            # divisor
    test %rcx, %rcx
    jz .Lum_divmod_zero
    mov 2*CELL(%r15), %rax      # ud-low (deepest)
    mov CELL(%r15), %rdx        # ud-high (second)
    div %rcx                    # RAX = quotient, RDX = remainder
    add $CELL, %r15             # drop one (3 in, 2 out)
    mov %rdx, CELL(%r15)        # remainder (second)
    mov %rax, (%r15)            # quotient (top)
    ret
.Lum_divmod_zero:
    add $CELL, %r15
    movq $0, CELL(%r15)
    movq $0, (%r15)
    ret

# SM/REM ( d n1 -- n2 n3 )  Symmetric (truncating) signed divide.
# n2 = remainder, n3 = quotient.
# Division by zero returns 0 0.
.global forth_sm_rem
forth_sm_rem:
    mov (%r15), %rcx            # divisor
    test %rcx, %rcx
    jz .Lsm_rem_zero
    mov 2*CELL(%r15), %rax      # d-low (deepest)
    mov CELL(%r15), %rdx        # d-high (second)
    # Check for overflow: INT64_MIN / -1
    cmp $-1, %rcx
    jne .Lsm_rem_ok
    test %rdx, %rdx
    jnz .Lsm_rem_ok
    movabs $0x8000000000000000, %rsi
    cmp %rsi, %rax
    je .Lsm_rem_overflow
.Lsm_rem_ok:
    idiv %rcx                   # RAX = quotient, RDX = remainder (truncating)
    add $CELL, %r15
    mov %rdx, CELL(%r15)        # remainder
    mov %rax, (%r15)            # quotient
    ret
.Lsm_rem_zero:
    add $CELL, %r15
    movq $0, CELL(%r15)
    movq $0, (%r15)
    ret
.Lsm_rem_overflow:
    add $CELL, %r15
    movq $0, CELL(%r15)         # remainder = 0
    mov %rsi, (%r15)            # quotient = INT64_MIN
    ret

# FM/MOD ( d n1 -- n2 n3 )  Floored signed divide.
# Like SM/REM but adjusts when remainder and divisor have different signs.
# Division by zero returns 0 0.
.global forth_fm_mod
forth_fm_mod:
    mov (%r15), %rcx            # divisor
    test %rcx, %rcx
    jz .Lfm_mod_zero
    mov 2*CELL(%r15), %rax      # d-low (deepest)
    mov CELL(%r15), %rdx        # d-high (second)
    # Check for overflow: INT64_MIN / -1
    cmp $-1, %rcx
    jne .Lfm_mod_ok
    test %rdx, %rdx
    jnz .Lfm_mod_ok
    movabs $0x8000000000000000, %rsi
    cmp %rsi, %rax
    je .Lfm_mod_overflow
.Lfm_mod_ok:
    idiv %rcx                   # RAX = quotient, RDX = remainder (truncating)
    # Floor adjustment: if remainder != 0 and signs of remainder and divisor differ
    test %rdx, %rdx
    jz .Lfm_mod_done            # remainder == 0 → no adjustment
    mov %rdx, %rsi
    xor %rcx, %rsi              # sign bits differ?
    jns .Lfm_mod_done           # same sign → no adjustment
    add %rcx, %rdx              # remainder += divisor
    dec %rax                    # quotient -= 1
.Lfm_mod_done:
    add $CELL, %r15
    mov %rdx, CELL(%r15)        # remainder
    mov %rax, (%r15)            # quotient
    ret
.Lfm_mod_zero:
    add $CELL, %r15
    movq $0, CELL(%r15)
    movq $0, (%r15)
    ret
.Lfm_mod_overflow:
    add $CELL, %r15
    movq $0, CELL(%r15)
    mov %rsi, (%r15)
    ret

# 1+ ( a -- a+1 )
.global forth_one_plus
forth_one_plus:

    addq $1, (%r15)
    ret

# 1- ( a -- a-1 )
.global forth_one_minus
forth_one_minus:

    subq $1, (%r15)
    ret

# ABS ( n -- |n| )
.global forth_abs
forth_abs:

    mov (%r15), %rax
    cqo                         # rdx = sign extension (-1 or 0)
    xor %rdx, %rax              # if negative: bitwise NOT
    sub %rdx, %rax              # if negative: +1 (two's complement abs)
    mov %rax, (%r15)
    ret

# MIN ( a b -- min )
.global forth_min
forth_min:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    cmp %rax, (%r15)            # compare a with b
    jle 1f
    mov %rax, (%r15)            # a > b, so store b
1:  ret

# MAX ( a b -- max )
.global forth_max
forth_max:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    cmp %rax, (%r15)            # compare a with b
    jge 1f
    mov %rax, (%r15)            # a < b, so store b
1:  ret

# = ( a b -- flag )
.global forth_equal
forth_equal:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    xor %ecx, %ecx              # rcx = 0 (false)
    cmp %rax, (%r15)            # compare a with b
    jne 1f
    dec %rcx                    # rcx = -1 (true)
1:  mov %rcx, (%r15)
    ret

# < ( a b -- flag )
.global forth_less
forth_less:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    xor %ecx, %ecx              # rcx = 0 (false)
    cmp %rax, (%r15)            # compare a with b
    jge 1f
    dec %rcx                    # rcx = -1 (true)
1:  mov %rcx, (%r15)
    ret

# > ( a b -- flag )
.global forth_greater
forth_greater:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    xor %ecx, %ecx              # rcx = 0 (false)
    cmp %rax, (%r15)            # compare a with b
    jle 1f
    dec %rcx                    # rcx = -1 (true)
1:  mov %rcx, (%r15)
    ret

# 0= ( a -- flag )
.global forth_zero_equal
forth_zero_equal:

    xor %ecx, %ecx              # rcx = 0 (false)
    cmpq $0, (%r15)
    jne 1f
    dec %rcx                    # rcx = -1 (true)
1:  mov %rcx, (%r15)
    ret

# 0< ( a -- flag )
.global forth_zero_less
forth_zero_less:

    mov (%r15), %rax
    sar $63, %rax               # -1 if negative, 0 if non-negative
    mov %rax, (%r15)
    ret

# AND ( a b -- a&b )
.global forth_and
forth_and:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    and %rax, (%r15)            # top = a & b
    ret

# OR ( a b -- a|b )
.global forth_or
forth_or:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    or %rax, (%r15)             # top = a | b
    ret

# XOR ( a b -- a^b )
.global forth_xor
forth_xor:

    mov (%r15), %rax            # rax = b
    add $CELL, %r15             # pop b
    xor %rax, (%r15)            # top = a ^ b
    ret

# INVERT ( a -- ~a )
.global forth_invert
forth_invert:

    notq (%r15)
    ret

# LSHIFT ( x1 u -- x2 )
# Logical left shift
.global forth_lshift
forth_lshift:

    mov (%r15), %rcx            # rcx = shift count
    add $CELL, %r15             # pop count
    shlq %cl, (%r15)            # top = x1 << u
    ret

# RSHIFT ( x1 u -- x2 )
# Logical right shift
.global forth_rshift
forth_rshift:

    mov (%r15), %rcx            # rcx = shift count
    add $CELL, %r15             # pop count
    shrq %cl, (%r15)            # top = x1 >> u (logical)
    ret

# 2/ ( x -- x/2 )
# Arithmetic right shift by 1 (floor of x/2)
.global forth_two_div
forth_two_div:

    sarq $1, (%r15)
    ret

# U< ( u1 u2 -- flag )
# Unsigned less-than comparison
.global forth_u_less
forth_u_less:

    mov (%r15), %rax            # rax = u2
    add $CELL, %r15             # pop u2
    cmp %rax, (%r15)            # compare u1 - u2 (unsigned)
    mov $0, %rax
    jnb .Lu_less_done
    mov $-1, %rax
.Lu_less_done:
    mov %rax, (%r15)
    ret

# ---------- Memory ----------

# @ (fetch) ( addr -- x )
# Read 8-byte cell from address
.global forth_fetch
forth_fetch:

    mov (%r15), %rax            # rax = addr
    mov (%rax), %rax            # rax = [addr]
    mov %rax, (%r15)            # replace top
    ret

# ! (store) ( x addr -- )
# Write 8-byte cell to address
.global forth_store
forth_store:

    mov (%r15), %rax            # rax = addr
    mov CELL(%r15), %rcx        # rcx = x
    mov %rcx, (%rax)            # [addr] = x
    add $2*CELL, %r15           # pop both
    ret

# C@ (char fetch) ( addr -- byte )
# Read 1 byte from address, zero-extended
.global forth_cfetch
forth_cfetch:

    mov (%r15), %rax
    movzbl (%rax), %eax
    mov %rax, (%r15)
    ret

# C! (char store) ( byte addr -- )
# Write 1 byte to address
.global forth_cstore
forth_cstore:

    mov (%r15), %rax            # addr
    mov CELL(%r15), %rcx        # byte
    movb %cl, (%rax)
    add $2*CELL, %r15
    ret

# ---------- EMIT (Forth-level) ----------
# ( char -- )
.global forth_emit
forth_emit:

    mov (%r15), %rdi            # char
    add $CELL, %r15             # pop
    jmp platform_emit           # tail call

# ---------- KEY (Forth-level) ----------
# ( -- char )
.global forth_key
forth_key:

    call platform_raw_mode      # lazily enter raw mode on first interactive input
    call platform_key           # RDI = character
    sub $CELL, %r15
    mov %rdi, (%r15)
    ret

# ---------- ACCEPT (Forth-level) ----------
# ( c-addr +n1 -- +n2 )
# Read a line from stdin into buffer at c-addr, max n1 chars.
# Handles backspace editing and echo. Returns actual count.
# Calls platform_key and platform_emit directly (register level).
.global forth_accept
forth_accept:

    call platform_raw_mode      # lazily enter raw mode on first interactive input
    push %rbx
    push %rbp
    push %r12

    # Pop args from data stack
    mov (%r15), %rbp            # RBP = max_len (top)
    mov CELL(%r15), %rbx        # RBX = buf_addr (second)
    add $2*CELL, %r15
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

    # Push result: count
    sub $CELL, %r15
    mov %r12, (%r15)

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
    push %r13                   # temporarily borrow R13

    # Pop args: top = len, second = addr
    mov (%r15), %rcx            # RCX = len
    mov CELL(%r15), %rbx        # RBX = addr
    add $2*CELL, %r15
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
    mov %rax, (%r15)            # push n
    sub $CELL, %r15
    movq $-1, (%r15)            # push true (-1)
    jmp .Lnum_exit

.Lnum_fail2:
    pop %rdx                    # clean up negate flag from stack
.Lnum_fail:
    # Push c-addr, u, and false: ( -- c-addr u false )
    sub $CELL, %r15
    mov %r12, (%r15)            # push orig c-addr
    sub $CELL, %r15
    mov %r13, (%r15)            # push orig u
    sub $CELL, %r15
    movq $0, (%r15)             # push false

.Lnum_exit:
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- FIND (Forth-level) ----------
# ( c-addr u -- xt 1 | xt -1 | c-addr u 0 )
# Search dictionary for word by name. Case-insensitive.
# Returns: xt and 1 (immediate), xt and -1 (normal), or
#          original c-addr u and 0 (not found).
.global forth_find
forth_find:


    push %rbx
    push %rbp
    push %r12                   # save LATEST (read-only)

    # Pop args: top = u (length), second = c-addr
    mov (%r15), %rcx            # RCX = search length
    mov CELL(%r15), %rsi        # RSI = search c-addr
    add $2*CELL, %r15

    mov %r12, %rbx              # RBX = current entry (start at LATEST)

.Lfind_loop:
    test %rbx, %rbx
    jz .Lfind_not_found

    # Check HIDDEN flag
    movzbl 8(%rbx), %eax        # flags+len byte (offset 8 past link)
    test $F_HIDDEN, %al
    jnz .Lfind_next

    # Save flags byte for later (need IMMEDIATE check on match)
    mov %eax, %ebp              # RBP = flags+len byte

    # Compare lengths
    and $F_LENMASK, %eax        # EAX = entry name length
    cmp %rcx, %rax
    jne .Lfind_next

    # Lengths match — compare names case-insensitively
    lea 9(%rbx), %rdi           # RDI = entry name start
    mov %rsi, %rdx              # RDX = search name ptr
    mov %rcx, %r8               # R8 = remaining count

.Lfind_cmp:
    test %r8, %r8
    jz .Lfind_match

    movzbl (%rdx), %eax         # search char
    cmp $'A', %al
    jb .Lfind_s_done
    cmp $'Z', %al
    ja .Lfind_s_done
    add $32, %al                # to lowercase
.Lfind_s_done:

    movzbl (%rdi), %r9d         # entry char
    cmp $'A', %r9b
    jb .Lfind_e_done
    cmp $'Z', %r9b
    ja .Lfind_e_done
    add $32, %r9b
.Lfind_e_done:

    cmp %r9b, %al
    jne .Lfind_next

    inc %rdx
    inc %rdi
    dec %r8
    jmp .Lfind_cmp

.Lfind_match:
    # CodePtr is at offset align8(9 + name_len) from entry start
    lea 9+7(%rcx), %rax         # 9 + len + 7
    and $~7, %rax               # round down to 8-byte boundary
    # Push xt and flag
    mov (%rbx,%rax), %rax       # RAX = xt
    sub $CELL, %r15
    mov %rax, (%r15)            # push xt
    # Check flags: IMMEDIATE, COMPILE_ONLY, or normal
    # Flag encoding:  1 = IMMEDIATE
    #                -1 = normal
    #                -2 = COMPILE_ONLY (non-immediate)
    #                 2 = IMMEDIATE + COMPILE_ONLY
    mov %ebp, %edx
    and $(F_IMMEDIATE | F_COMPILE_ONLY), %edx
    cmp $(F_IMMEDIATE | F_COMPILE_ONLY), %edx
    je .Lfind_imm_co
    test $F_IMMEDIATE, %ebp
    jnz .Lfind_imm
    test $F_COMPILE_ONLY, %ebp
    jnz .Lfind_co
    # Normal word
    sub $CELL, %r15
    movq $-1, (%r15)            # push -1 (normal)
    jmp .Lfind_done
.Lfind_imm:
    sub $CELL, %r15
    movq $1, (%r15)             # push 1 (immediate)
    jmp .Lfind_done
.Lfind_co:
    sub $CELL, %r15
    movq $-2, (%r15)            # push -2 (compile-only)
    jmp .Lfind_done
.Lfind_imm_co:
    sub $CELL, %r15
    movq $2, (%r15)             # push 2 (immediate + compile-only)
    jmp .Lfind_done

.Lfind_next:
    mov (%rbx), %rbx            # follow link
    jmp .Lfind_loop

.Lfind_not_found:
    # Return original c-addr u 0
    sub $CELL, %r15
    mov %rsi, (%r15)            # push c-addr
    sub $CELL, %r15
    mov %rcx, (%r15)            # push u
    sub $CELL, %r15
    movq $0, (%r15)             # push 0

.Lfind_done:
    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- PARSE-WORD (Forth-level) ----------
# ( -- c-addr u )
# Extract next space-delimited token from the input buffer.
# Reads source_addr, source_len, to_in globals.
# Returns 0 0 if no more tokens.
.global forth_parse_word
forth_parse_word:

    # Load globals
    mov source_addr(%rip), %rsi   # RSI = buffer base
    mov source_len(%rip), %rcx    # RCX = total length
    mov to_in(%rip), %rdx         # RDX = current offset

    # Skip leading spaces
.Lpw_skip:
    cmp %rcx, %rdx
    jge .Lpw_empty
    cmpb $' ', (%rsi,%rdx)
    jne .Lpw_found
    inc %rdx
    jmp .Lpw_skip

.Lpw_empty:
    mov %rdx, to_in(%rip)
    # Push 0 0
    sub $CELL, %r15
    movq $0, (%r15)               # c-addr = 0
    sub $CELL, %r15
    movq $0, (%r15)               # u = 0
    ret

.Lpw_found:
    lea (%rsi,%rdx), %rdi         # RDI = start of word

    # Scan to end of word
.Lpw_scan:
    cmp %rcx, %rdx
    jge .Lpw_done
    cmpb $' ', (%rsi,%rdx)
    je .Lpw_done
    inc %rdx
    jmp .Lpw_scan

.Lpw_done:
    mov %rdx, to_in(%rip)         # update to_in
    # len = current position - start
    lea (%rsi,%rdx), %rax
    sub %rdi, %rax                # RAX = length
    # Push c-addr and u (c-addr second, u on top)
    sub $CELL, %r15
    mov %rdi, (%r15)              # push c-addr
    sub $CELL, %r15
    mov %rax, (%r15)              # push u (on top)
    ret

# ---------- EXECUTE (Forth-level) ----------
# ( xt -- )
# Call the execution token. Tail-call: word's RET returns to our caller.
.global forth_execute
forth_execute:

    mov (%r15), %rax
    add $CELL, %r15
    jmp *%rax                     # tail-call

# ---------- print_signed (internal helper) ----------
# Print signed 64-bit integer from RAX to stdout.
# Uses stack buffer. Clobbers RAX, RCX, RDX, RSI, RDI, R8.
# Caller must save any registers it needs preserved.
.Lprint_signed:
    sub $32, %rsp               # digit buffer

    # Handle negative
    xor %ecx, %ecx              # sign flag = 0
    test %rax, %rax
    jns .Lps_positive
    neg %rax
    mov $1, %ecx
.Lps_positive:
    push %rcx                   # save sign flag

    # Build digits right-to-left
    lea 39(%rsp), %rsi          # RSI = end of buffer
    mov %rsi, %rdi              # RDI = current position
    mov $10, %r8

    # Handle zero
    test %rax, %rax
    jnz .Lps_divloop
    dec %rdi
    movb $'0', (%rdi)
    jmp .Lps_sign

.Lps_divloop:
    test %rax, %rax
    jz .Lps_sign
    xor %edx, %edx
    div %r8
    add $'0', %dl
    dec %rdi
    movb %dl, (%rdi)
    jmp .Lps_divloop

.Lps_sign:
    pop %rcx
    test %ecx, %ecx
    jz .Lps_print
    dec %rdi
    movb $'-', (%rdi)

.Lps_print:
    mov %rsi, %rdx              # length = end - start
    sub %rdi, %rdx
    mov %rdi, %rsi              # buf = start
    call platform_write

    add $32, %rsp
    ret

# ---------- DOT (Forth-level) ----------
# ( n -- )
# Print top of stack as signed decimal with trailing space.
.global forth_dot
forth_dot:

    push %rbx
    mov (%r15), %rax            # RAX = number to print
    add $CELL, %r15             # pop
    call .Lprint_signed
    mov $' ', %rdi
    call platform_emit
    pop %rbx
    ret

# ---------- DOT-S (Forth-level) ----------
# ( -- )
# Print stack contents non-destructively as <depth> item1 item2 ...
.global forth_dot_s
forth_dot_s:
    push %rbx
    push %rbp

    # Compute depth = (sp0 - DSP) / CELL
    mov sp0(%rip), %rbx
    sub %r15, %rbx
    sar $3, %rbx                # rbx = depth

    # Print '<'
    mov $'<', %rdi
    call platform_emit

    # Print depth
    mov %rbx, %rax
    call .Lprint_signed

    # Print '> '
    mov $'>', %rdi
    call platform_emit
    mov $' ', %rdi
    call platform_emit

    # If depth <= 0, done
    test %rbx, %rbx
    jle .Lds_done

    # Walk from bottom (DSP + (depth-1)*CELL) to top (DSP)
    lea -1(%rbx), %rbp
    shl $3, %rbp
    add %r15, %rbp              # rbp = bottom item address

.Lds_loop:
    cmp %r15, %rbp
    jl .Lds_done
    mov (%rbp), %rax
    call .Lprint_signed
    mov $' ', %rdi
    call platform_emit
    sub $CELL, %rbp
    jmp .Lds_loop

.Lds_done:
    pop %rbp
    pop %rbx
    ret

# ---------- BYE (Forth-level) ----------
# ( -- )
# Restore terminal and exit.
.global forth_bye
forth_bye:
    lea bye_msg(%rip), %rsi
    mov $bye_len, %rdx
    call platform_write
    jmp platform_bye

.section .rodata
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg
msg_compile_only: .ascii "compile only\n"
.equ msg_compile_only_len, . - msg_compile_only
msg_unbalanced: .ascii "unresolved control flow\n"
.equ msg_unbalanced_len, . - msg_unbalanced
msg_cf_mismatch: .ascii "mismatched control flow\n"
.equ msg_cf_mismatch_len, . - msg_cf_mismatch
cf_mismatch_name: .ascii "mismatched-control-flow"
.equ cf_mismatch_name_len, . - cf_mismatch_name
sq_unterminated_name: .ascii "unterminated string"
.equ sq_unterminated_name_len, . - sq_unterminated_name
.text

# ---------- LIT (runtime) ----------
# Pushes the inline 8-byte value that follows the CALL to forth_lit.
# At runtime, the return address on the hardware stack points to the
# inline data.  We read the value, advance past it, and continue.
#
# Compiled code layout:
#   CALL forth_lit      (5 bytes)
#   .quad <value>       (8 bytes)
#   <next instruction>
#
.global forth_lit
forth_lit:

    pop %rax                        # return addr = pointer to inline value
    mov (%rax), %rcx                # rcx = inline value
    sub $CELL, %r15
    mov %rcx, (%r15)                # push value to stack
    add $CELL, %rax                 # skip past inline value
    jmp *%rax                       # continue

# ---------- compile_call (internal) ----------
# Compile a CALL instruction at HERE to the address in RAX.
# Advances HERE (R13) by 5 bytes.
# Clobbers RCX.
.global compile_call
compile_call:
    CHECK_DICT 5
    movb $0xE8, (%r13)             # E8 opcode (CALL rel32)
    lea 5(%r13), %rcx              # RCX = address after the CALL
    sub %rcx, %rax                 # RAX = relative offset
    mov %eax, 1(%r13)              # write 32-bit relative offset
    add $5, %r13                   # advance HERE
    ret

# ---------- compile_ret (internal) ----------
# Compile a RET instruction at HERE.  Advances HERE by 1 byte.
.global compile_ret
compile_ret:
    CHECK_DICT 1
    movb $0xC3, (%r13)             # C3 opcode (RET)
    inc %r13                       # advance HERE
    ret

# ---------- compile_literal (internal) ----------
# Compile a CALL to forth_lit followed by an 8-byte inline value.
# Value is taken from RAX.  Advances HERE by 13 bytes.
# Clobbers RCX.
.global compile_literal
compile_literal:
    CHECK_DICT 13
    push %rax                       # save the literal value
    lea forth_lit(%rip), %rax       # target = forth_lit
    call compile_call               # emit CALL forth_lit (5 bytes)
    pop %rax
    mov %rax, (%r13)               # emit inline 8-byte value
    add $CELL, %r13                # advance HERE past value
    ret

# ---------- Branch Compile Helpers ----------
# Internal routines for control flow words. Not exposed as Forth words.
#
# 0branch emits 16 bytes:
#   49 8B 07           mov (%r15), %rax     (3)
#   49 83 C7 08        add $8, %r15         (4)
#   48 85 C0           test %rax, %rax      (3)
#   0F 84 [offset32]   jz rel32             (6)
#
# branch emits 5 bytes:
#   E9 [offset32]      jmp rel32            (5)
#
# Offset formula for both: target - (offset_field_addr + 4)

# compile_0branch — emit forward conditional branch with placeholder offset.
# Returns: RAX = address of the 4-byte offset field (for patching).
compile_0branch:
    CHECK_DICT 16
    movb $0x49, (%r13)             # mov (%r15), %rax
    movb $0x8B, 1(%r13)
    movb $0x07, 2(%r13)
    movb $0x49, 3(%r13)            # add $8, %r15
    movb $0x83, 4(%r13)
    movb $0xC7, 5(%r13)
    movb $0x08, 6(%r13)
    movb $0x48, 7(%r13)            # test %rax, %rax
    movb $0x85, 8(%r13)
    movb $0xC0, 9(%r13)
    movb $0x0F, 10(%r13)           # jz rel32
    movb $0x84, 11(%r13)
    movl $0, 12(%r13)              # placeholder offset
    lea 12(%r13), %rax             # RAX = address of offset field
    add $16, %r13                  # advance HERE
    ret

# compile_branch — emit forward unconditional branch with placeholder offset.
# Returns: RAX = address of the 4-byte offset field (for patching).
compile_branch:
    CHECK_DICT 5
    movb $0xE9, (%r13)             # jmp rel32
    movl $0, 1(%r13)               # placeholder offset
    lea 1(%r13), %rax              # RAX = address of offset field
    add $5, %r13                   # advance HERE
    ret

# patch_forward — patch a forward branch to jump to current HERE.
# Input: RAX = address of the 4-byte offset field.
patch_forward:
    mov %r13, %rcx                 # RCX = HERE (target)
    sub %rax, %rcx                 # RCX = HERE - offset_addr
    sub $4, %rcx                   # RCX = HERE - (offset_addr + 4)
    mov %ecx, (%rax)               # write 32-bit offset
    ret

# compile_0branch_back — emit conditional backward branch to known target.
# Input: RAX = target address.
compile_0branch_back:
    CHECK_DICT 16
    push %rax                      # save target
    movb $0x49, (%r13)             # mov (%r15), %rax
    movb $0x8B, 1(%r13)
    movb $0x07, 2(%r13)
    movb $0x49, 3(%r13)            # add $8, %r15
    movb $0x83, 4(%r13)
    movb $0xC7, 5(%r13)
    movb $0x08, 6(%r13)
    movb $0x48, 7(%r13)            # test %rax, %rax
    movb $0x85, 8(%r13)
    movb $0xC0, 9(%r13)
    movb $0x0F, 10(%r13)           # jz rel32
    movb $0x84, 11(%r13)
    pop %rax                       # RAX = target
    lea 16(%r13), %rcx             # RCX = HERE after emission
    sub %rcx, %rax                 # RAX = target - (HERE + 16)
    mov %eax, 12(%r13)             # write offset
    add $16, %r13                  # advance HERE
    ret

# compile_branch_back — emit unconditional backward branch to known target.
# Input: RAX = target address.
compile_branch_back:
    CHECK_DICT 5
    movb $0xE9, (%r13)             # jmp rel32
    lea 5(%r13), %rcx              # RCX = address after instruction
    sub %rcx, %rax                 # RAX = target - (HERE + 5)
    mov %eax, 1(%r13)              # write offset
    add $5, %r13                   # advance HERE
    ret

# ---------- build_header (internal helper) ----------
# Parse the next word and create a dictionary header at HERE.
# Saves LATEST/HERE for error recovery, updates LATEST to new entry.
# Entry is marked HIDDEN — caller must clear it when done.
# On return: HERE points to code area, R12 = new entry (LATEST).
# Uses RBX, RBP internally (caller must save if needed).
# Returns: CF=0 on success, CF=1 on error (empty name or dict full).
#
# Dictionary entry layout:
#   [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4]
#   Then HERE points to where compiled code will go.
build_header:
    # Save LATEST and HERE for error recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    # Parse name
    call forth_parse_word           # ( -- c-addr u )
    mov (%r15), %rcx                # RCX = u (name length, on top)
    mov CELL(%r15), %rsi            # RSI = c-addr (second)
    add $2*CELL, %r15

    test %rcx, %rcx
    jz .Lbh_err                     # empty name — bail

    # Check dictionary space (need ~128 bytes for header)
    lea dict_space+DICT_SPACE_SIZE(%rip), %rax
    lea 128(%r13), %rdx
    cmp %rax, %rdx
    ja .Lbh_dict_full

    # Clamp name length to F_LENMASK (31) max
    cmp $F_LENMASK, %rcx
    jbe .Lbh_len_ok
    mov $F_LENMASK, %rcx
.Lbh_len_ok:

    # Align HERE to 8 before starting new entry
    add $7, %r13
    and $~7, %r13

    # Write link pointer (8 bytes) — points to old LATEST
    mov %r12, (%r13)
    mov %r13, %rbx                  # RBX = new entry address
    add $CELL, %r13

    # Write flags+len byte (HIDDEN | length)
    mov %ecx, %eax
    or $F_HIDDEN, %al
    movb %al, (%r13)
    inc %r13

    # Write name (lowercase)
    mov %rcx, %rbp
.Lbh_name:
    test %rbp, %rbp
    jz .Lbh_name_done
    movzbl (%rsi), %eax
    cmp $'A', %al
    jb .Lbh_store
    cmp $'Z', %al
    ja .Lbh_store
    add $0x20, %al
.Lbh_store:
    movb %al, (%r13)
    inc %r13
    inc %rsi
    dec %rbp
    jmp .Lbh_name

.Lbh_name_done:
    # Align HERE to 8
    add $7, %r13
    and $~7, %r13

    # Write code pointer — will point just past code_len field
    lea 12(%r13), %rax              # code starts after CodePtr(8)+CodeLen(4)
    mov %rax, (%r13)
    add $CELL, %r13                 # past CodePtr

    # Write code_len placeholder (0), save its address
    mov %r13, colon_code_len_addr(%rip)
    movl $0, (%r13)
    add $4, %r13                    # past CodeLen — HERE now at code area

    # Update LATEST
    mov %rbx, %r12                  # LATEST = new entry (still HIDDEN)

    clc                             # success
    ret

.Lbh_dict_full:
    jmp dict_full

.Lbh_err:
    stc                             # error
    ret

# ---------- COLON (Forth-level) ----------
# ( -- )
# Parse the next word, create a dictionary header at HERE, and enter
# compile mode.  The new entry is marked HIDDEN until ; completes it.
.global forth_colon
forth_colon:
    push %rbx
    push %rbp

    call build_header
    jc .Lcolon_done                 # error → bail

    # Save data stack depth for control-flow balance check in ;
    mov %r15, colon_dsp(%rip)

    # Enter compile mode
    movq $1, state(%rip)

.Lcolon_done:
    pop %rbp
    pop %rbx
    ret

# ---------- SEMICOLON (Forth-level, IMMEDIATE) ----------
# ( -- )
# End a colon definition: compile RET, fill code_len, clear HIDDEN,
# return to interpret mode.
#
.global forth_semicolon
forth_semicolon:
    # Guard: must be in compile mode
    cmpq $0, state(%rip)
    je .Lsemi_err

    # Check control-flow stack balance: DSP must match what : saved
    mov colon_dsp(%rip), %rax
    cmp %rax, %r15
    jne .Lsemi_unbalanced

    # Compile RET
    call compile_ret

    # Calculate code length and write it (skip for :NONAME)
    mov colon_code_len_addr(%rip), %rax   # RAX = code_len field address
    test %rax, %rax
    jz .Lsemi_noname                      # :NONAME has no code_len field
    lea 4(%rax), %rcx                     # RCX = code start (right after field)
    mov %r13, %rdx                        # RDX = HERE (right after compiled code)
    sub %rcx, %rdx                        # RDX = code length
    mov %edx, (%rax)                      # write code_len (32-bit)

    # Clear HIDDEN flag on new entry (LATEST + 8 is flags byte)
    andb $~F_HIDDEN, 8(%r12)

.Lsemi_noname:
    # Return to interpret mode
    movq $0, state(%rip)
    ret

.Lsemi_unbalanced:
    # Unresolved control flow — roll back the definition
    lea msg_unbalanced(%rip), %rsi
    mov $msg_unbalanced_len, %rdx
    call platform_write

    # Restore stack, LATEST, HERE, STATE
    mov colon_dsp(%rip), %r15
    mov saved_latest(%rip), %r12
    mov saved_here(%rip), %r13
    movq $0, state(%rip)
    movq $0, do_depth(%rip)
    movq $0, leave_count(%rip)
    ret

.Lsemi_err:
    # ; outside compile mode — silently ignore
    ret

# ---------- IMMEDIATE (Forth-level) ----------
# ( -- )
# Set the IMMEDIATE flag on the most recent dictionary entry.
.global forth_immediate
forth_immediate:
    orb $F_IMMEDIATE, 8(%r12)
    ret

# ---------- TICK (Forth-level, IMMEDIATE) ----------
# ( "<spaces>name" -- xt )
# Parse the next word and look it up in the dictionary.
# In interpret mode: pushes xt to stack.
# In compile mode: compiles xt as a literal (acts like ['] in std Forth).
.global forth_tick
forth_tick:
    call forth_parse_word           # ( -- c-addr u )
    call forth_find                 # ( c-addr u -- xt flag | c-addr u 0 )

    # Check if found (flag != 0)
    mov (%r15), %rax                # rax = flag (top)
    test %rax, %rax
    jz .Ltick_not_found

    # Found — drop flag, leave xt on top
    add $CELL, %r15                 # drop flag, xt is now on top

    # If compiling, compile xt as a literal
    cmpq $0, state(%rip)
    je .Ltick_done                  # interpreting -> leave on stack

    # Compiling — pop xt and compile as literal
    mov (%r15), %rax
    add $CELL, %r15
    call compile_literal
.Ltick_done:
    ret

.Ltick_not_found:
    # Not found — drop flag, u, c-addr; push 0 as error
    add $3*CELL, %r15               # drop flag, u, c-addr
    sub $CELL, %r15
    movq $0, (%r15)                 # push 0 (invalid xt)
    ret

# ---------- INTERPRET-LINE ----------
# ( -- ) Returns status in RAX: 0=success, 1=error
# Caller must set source_addr, source_len, to_in before calling.
# On error: saves offending token in err_token_addr/err_token_len,
#           resets STATE and restores LATEST/HERE if compiling.
# On success: cleans up stack, returns 0.
.global forth_interpret_line
forth_interpret_line:
    push %rbx                       # preserve callee-saved registers
    push %rbp
    push %r14
    pushq il_rsp(%rip)              # save previous il_rsp (for nesting)
    sub $8, %rsp                    # 16-byte alignment (5 pushes + ret addr = 48)
    mov %rsp, il_rsp(%rip)          # save RSP for cf_check_tag recovery

.Lil_loop:
    call forth_parse_word           # ( -- c-addr u )

    # End of line? (u == 0)
    mov (%r15), %rax                # u is on top
    test %rax, %rax
    jz .Lil_done

    # FIND ( c-addr u -- xt flag | c-addr u 0 )
    call forth_find

    # Found? (flag != 0)
    mov (%r15), %rax                # flag is on top
    test %rax, %rax
    jz .Lil_try_number

    # Found — top = flag, second = xt
    # Flags: 1=IMMEDIATE, -1=normal, -2=COMPILE_ONLY, 2=IMMEDIATE+COMPILE_ONLY
    # If interpreting (STATE==0): execute, but reject compile-only (flag==-2 or 2)
    # If compiling: IMMEDIATE (flag==1 or 2) → execute, else compile
    cmpq $0, state(%rip)
    je .Lil_found_interpret         # interpreting → check compile-only

    # Compiling — check IMMEDIATE flag (flag==1 or flag==2)
    cmpq $1, (%r15)
    je .Lil_found_execute           # IMMEDIATE → execute
    cmpq $2, (%r15)
    je .Lil_found_execute           # IMMEDIATE+COMPILE_ONLY → execute

    # Normal word in compile mode — compile a CALL to it
    add $CELL, %r15                 # drop flag
    mov (%r15), %rax                # RAX = xt
    add $CELL, %r15                 # drop xt
    call compile_call               # emit CALL xt at HERE
    jmp .Lil_loop

.Lil_found_interpret:
    # Interpreting — reject compile-only words (flag == -2 or flag == 2)
    cmpq $-2, (%r15)
    je .Lil_compile_only
    cmpq $2, (%r15)
    je .Lil_compile_only
    # Fall through to execute

.Lil_found_execute:
    add $CELL, %r15                 # drop flag
    call forth_execute              # pops xt and jumps
    jmp .Lil_loop

.Lil_try_number:
    # Not in dictionary — drop 0 flag, try NUMBER
    add $CELL, %r15                 # drop 0 flag ( c-addr u )

    # NUMBER ( c-addr u -- n true | c-addr u false )
    call forth_number

    mov (%r15), %rax                # top = true/false flag
    test %rax, %rax
    jz .Lil_not_found

    # Parsed — drop true flag, number is on stack
    add $CELL, %r15                 # drop true flag

    # If compiling, compile the number as a literal
    cmpq $0, state(%rip)
    je .Lil_loop                    # interpreting → leave n on stack

    # Compiling — compile literal
    mov (%r15), %rax                # RAX = number
    add $CELL, %r15                 # pop number
    call compile_literal            # emit CALL LIT + value at HERE
    jmp .Lil_loop

.Lil_not_found:
    # Neither word nor number — error
    add $CELL, %r15                 # drop false flag ( c-addr u )

    # Save offending token info for caller to report
    mov (%r15), %rax                # u (top)
    mov %rax, err_token_len(%rip)
    mov CELL(%r15), %rax            # c-addr (second)
    mov %rax, err_token_addr(%rip)
    add $2*CELL, %r15               # clean up c-addr and u

    # If we were compiling, abort the definition
    cmpq $0, state(%rip)
    je .Lil_err_return
    movq $0, state(%rip)            # reset to interpret mode
    mov colon_dsp(%rip), %r15       # restore DSP (drop compile-time stack)
    mov saved_latest(%rip), %r12    # restore LATEST
    mov saved_here(%rip), %r13      # restore HERE
    movq $0, do_depth(%rip)         # reset DO nesting
    movq $0, leave_count(%rip)      # reset leave chain

.Lil_err_return:
    mov $1, %eax                    # return 1 = error
    add $8, %rsp                    # drop alignment padding
    popq il_rsp(%rip)               # restore previous il_rsp
    pop %r14
    pop %rbp
    pop %rbx
    ret

.Lil_done:
    # End of line — drop 0 0 from PARSE-WORD
    add $2*CELL, %r15
    xor %eax, %eax                  # return 0 = success
    add $8, %rsp                    # drop alignment padding
    popq il_rsp(%rip)               # restore previous il_rsp
    pop %r14
    pop %rbp
    pop %rbx
    ret

.Lil_compile_only:
    # Compile-only word used in interpret mode — non-fatal, continue parsing
    add $2*CELL, %r15               # drop xt, flag
    lea msg_compile_only(%rip), %rsi
    mov $msg_compile_only_len, %rdx
    call platform_write
    jmp .Lil_loop

# ---------- PAREN (comment word, IMMEDIATE) ----------
# ( "ccc)" -- )
# Skip input until closing ')' or end of line.
.global forth_paren
forth_paren:
    mov source_addr(%rip), %rsi     # RSI = buffer base
    mov source_len(%rip), %rcx      # RCX = total length
    mov to_in(%rip), %rdx           # RDX = current offset

.Lparen_scan:
    cmp %rcx, %rdx
    jge .Lparen_done                # end of input
    cmpb $')', (%rsi,%rdx)
    je .Lparen_found
    inc %rdx
    jmp .Lparen_scan

.Lparen_found:
    inc %rdx                        # skip past ')'
.Lparen_done:
    mov %rdx, to_in(%rip)
    ret

# ---------- BACKSLASH (line comment, IMMEDIATE) ----------
# ( -- )
# Skip rest of current input line.
.global forth_backslash
forth_backslash:
    mov source_len(%rip), %rax
    mov %rax, to_in(%rip)
    ret

# ---------- EVALUATE ----------
# ( c-addr u -- )
# Interpret a string as Forth source. Saves and restores source context
# so nested EVALUATE and INCLUDED work correctly.
# Returns: RAX = 0 on success, 1 on error.
.global forth_evaluate
forth_evaluate:
    push %rbx
    push %rbp
    push %r14
    push %r8

    # Pop c-addr and u from data stack
    mov (%r15), %rcx                # RCX = u (top)
    mov CELL(%r15), %rsi            # RSI = c-addr (second)
    add $2*CELL, %r15

    # Save current source context in callee-saved regs
    mov source_addr(%rip), %rbx     # save old source_addr
    mov source_len(%rip), %rbp      # save old source_len
    mov to_in(%rip), %r14           # save old to_in
    mov source_id(%rip), %r8        # save old source_id

    # Set new source context
    mov %rsi, source_addr(%rip)
    mov %rcx, source_len(%rip)
    movq $0, to_in(%rip)
    movq $-1, source_id(%rip)       # EVALUATE = -1

    # Interpret the string
    call forth_interpret_line
    push %rax                       # save result

    # Restore source context
    mov %rbx, source_addr(%rip)
    mov %rbp, source_len(%rip)
    mov %r14, to_in(%rip)
    mov %r8, source_id(%rip)

    pop %rax                        # restore result
    pop %r8
    pop %r14
    pop %rbp
    pop %rbx
    ret

# ---------- INCLUDED ----------
# ( c-addr u -- )
# Load and interpret a Forth source file. Opens the file, mmaps it,
# processes line-by-line, then munmaps. Aborts on first error with
# filename:line: ? token  error format.
# Returns: RAX = 0 on success, 1 on error.
# Special: returns 0 silently if file not found (ENOENT = -2).
.global forth_included
forth_included:
    push %rbx
    push %rbp
    push %r14
    push %r8                        # for line_start scratch

    # Pop c-addr and u from data stack
    mov (%r15), %rdx                # RDX = u (filename length)
    mov CELL(%r15), %rsi            # RSI = c-addr (filename)
    add $2*CELL, %r15

    # Save filename for error reporting
    mov %rsi, file_name_addr(%rip)
    mov %rdx, file_name_len(%rip)

    # Open file
    call platform_open_file         # RSI=path, RDX=len → RAX=fd
    test %rax, %rax
    js .Lincl_open_err

.Lincl_open_ok:
    mov %rax, %rbx                  # RBX = fd

    # Get file size
    mov %rbx, %rdi
    call platform_fstat             # RDI=fd → RAX=size
    mov %rax, %rbp                  # RBP = file size
    test %rbp, %rbp
    jle .Lincl_empty                # empty (or fstat error) → nothing to map

    # mmap the file
    mov %rbx, %rdi                  # fd
    mov %rbp, %rsi                  # size
    call platform_mmap_file         # → RAX=addr
    cmp $-1, %rax
    je .Lincl_mmap_err

    push %rax                       # save mmap addr

    # Close fd (no longer needed)
    mov %rbx, %rdi
    call platform_close_file

    pop %rbx                        # RBX = mmap base address

    # Process file line by line
    # RBX = mmap base, RBP = file size, R14 = line_start offset
    xor %r14d, %r14d                # line_start = 0
    movq $1, file_line_num(%rip)    # line counter = 1

    # Skip a leading "#!" shebang line so a Forth file can be a Unix
    # executable script (#!/usr/bin/env basicforth). Only the first line, and
    # only on an exact "#!" so a leading '#' decimal literal is unaffected.
    cmp $2, %rbp
    jl .Lincl_line_loop             # too short to be a shebang
    cmpb $'#', (%rbx)
    jne .Lincl_line_loop
    cmpb $'!', 1(%rbx)
    jne .Lincl_line_loop
.Lincl_sb_scan:
    cmp %rbp, %r14
    jge .Lincl_line_loop            # no newline → whole file was shebang
    cmpb $'\n', (%rbx,%r14)
    je .Lincl_sb_eol
    inc %r14
    jmp .Lincl_sb_scan
.Lincl_sb_eol:
    inc %r14                        # step past the newline
    movq $2, file_line_num(%rip)    # first real line is line 2

.Lincl_line_loop:
    cmp %rbp, %r14
    jge .Lincl_done                 # past end of file

    # Scan for newline starting at RBX + R14
    mov %r14, %rax                  # scan position
.Lincl_scan_nl:
    cmp %rbp, %rax
    jge .Lincl_eol                  # end of file = end of line
    cmpb $'\n', (%rbx,%rax)
    je .Lincl_eol
    inc %rax
    jmp .Lincl_scan_nl

.Lincl_eol:
    # Line goes from RBX+R14 to RBX+RAX (exclusive)
    # Save next line start (RAX+1 or end of file)
    lea 1(%rax), %r8                # next line start
    mov %rax, %rcx
    sub %r14, %rcx                  # RCX = line length

    # Skip empty lines
    test %rcx, %rcx
    jz .Lincl_next_line

    # Set source vars for this line
    lea (%rbx,%r14), %rax
    mov %rax, source_addr(%rip)
    mov %rcx, source_len(%rip)
    movq $0, to_in(%rip)

    # Save registers across call (RBX, RBP already callee-saved). Also save the
    # error-reporting globals: a nested INCLUDE/INCLUDED inside this line would
    # otherwise overwrite them and leave our own errors pointing at the wrong
    # file and line. The four 8-byte saves keep RSP at its body alignment
    # (RSP%16==8), so an extra 8-byte pad is needed to 16-align the call per
    # the SysV ABI. (push/pop count must stay balanced.)
    push %r8                        # save next_line_start
    pushq file_name_addr(%rip)
    pushq file_name_len(%rip)
    pushq file_line_num(%rip)
    sub $8, %rsp                    # pad: 16-align RSP before the call
    call forth_interpret_line
    add $8, %rsp                    # drop pad
    popq file_line_num(%rip)
    popq file_name_len(%rip)
    popq file_name_addr(%rip)
    pop %r8                         # restore next_line_start

    test %rax, %rax
    jnz .Lincl_error

.Lincl_next_line:
    mov %r8, %r14                   # advance to next line
    incq file_line_num(%rip)
    jmp .Lincl_line_loop

.Lincl_done:
    # Unmap file
    mov %rbx, %rdi
    mov %rbp, %rsi
    call platform_munmap

.Lincl_empty_join:
    xor %eax, %eax                  # return 0 = success
    pop %r8
    pop %r14
    pop %rbp
    pop %rbx
    ret

# Empty file (size 0): nothing was mapped — just close the fd and succeed.
.Lincl_empty:
    mov %rbx, %rdi                  # fd
    call platform_close_file
    jmp .Lincl_empty_join

.Lincl_error:
    # Print "filename:line: ? token\n"
    # Print filename
    mov file_name_addr(%rip), %rsi
    mov file_name_len(%rip), %rdx
    call platform_write
    # Print ":"
    mov $':', %rdi
    call platform_emit
    # Print line number
    mov file_line_num(%rip), %rax
    call .Lprint_signed
    # Print ": ? "
    lea incl_err_sep(%rip), %rsi
    mov $incl_err_sep_len, %rdx
    call platform_write
    # Print offending token
    mov err_token_addr(%rip), %rsi
    mov err_token_len(%rip), %rdx
    call platform_write
    # Print newline
    mov $'\n', %rdi
    call platform_emit

    # Unmap file
    mov %rbx, %rdi
    mov %rbp, %rsi
    call platform_munmap

    mov $1, %eax                    # return 1 = error
    pop %r8
    pop %r14
    pop %rbp
    pop %rbx
    ret

.Lincl_open_err:
    # Check for ENOENT (-2) — try BASICFORTH_PATH fallback
    cmp $-2, %rax
    jne .Lincl_open_other

    # BASICFORTH_PATH is a colon-separated list of directories. Try each in
    # order; load the first match. CWD was already tried above. Empty segments
    # are skipped (CWD is the implicit first lookup, so we don't re-search it).
    #
    # Loop registers (all callee-saved → survive platform_open_file):
    #   RBP = cursor into basicforth_path (current segment start)
    #   R14 = bytes remaining from the cursor
    #   RBX = length of the current segment
    mov basicforth_path(%rip), %rbp
    test %rbp, %rbp
    jz .Lincl_open_skip             # not set → silent skip
    mov basicforth_path_len(%rip), %r14

.Lincl_seg_loop:
    test %r14, %r14
    jz .Lincl_open_skip             # no segments left → silent skip
    # Scan for ':' to find this segment's length
    xor %rbx, %rbx                  # seg_len = 0
.Lincl_seg_scan:
    cmp %r14, %rbx
    jge .Lincl_seg_have            # rbx >= remaining → end of segment
    cmpb $':', (%rbp,%rbx)
    je .Lincl_seg_have
    inc %rbx
    jmp .Lincl_seg_scan
.Lincl_seg_have:
    # RBX = segment length; skip empty segments
    test %rbx, %rbx
    jz .Lincl_seg_next
    # Clamp total (seg + '/' + filename) to 511 bytes
    mov file_name_len(%rip), %rdx
    lea 1(%rbx,%rdx), %rax          # total = seglen + 1 + namelen
    cmp $511, %rax
    jg .Lincl_seg_next             # too long → try next segment
    # Build "segment/filename" in incl_path_buf
    cld
    lea incl_path_buf(%rip), %rdi
    mov %rbp, %rsi                  # segment start
    mov %rbx, %rcx                  # segment length
    rep movsb
    movb $'/', (%rdi)
    inc %rdi
    mov file_name_addr(%rip), %rsi
    mov file_name_len(%rip), %rcx
    rep movsb
    # Try opening the prefixed path
    lea incl_path_buf(%rip), %rsi
    mov %rbx, %rdx
    add file_name_len(%rip), %rdx
    inc %rdx                         # +1 for '/'
    call platform_open_file
    test %rax, %rax
    js .Lincl_seg_next             # failed → try next segment
    # Found. Keep the original filename for error reporting — incl_path_buf is
    # scratch only, so a nested INCLUDE that reuses it can't corrupt our error
    # context.
    jmp .Lincl_open_ok
.Lincl_seg_next:
    # Advance past this segment, then skip the ':' delimiter if present
    add %rbx, %rbp
    sub %rbx, %r14
    test %r14, %r14
    jz .Lincl_open_skip            # no trailing delimiter → done
    inc %rbp                        # skip ':'
    dec %r14
    jmp .Lincl_seg_loop

.Lincl_open_other:
    # Other open error — print message
    lea incl_err_open(%rip), %rsi
    mov $incl_err_open_len, %rdx
    call platform_write
    mov file_name_addr(%rip), %rsi
    mov file_name_len(%rip), %rdx
    call platform_write
    mov $'\n', %rdi
    call platform_emit

.Lincl_open_skip:
    xor %eax, %eax                  # return 0 (not an error for ENOENT)
    pop %r8
    pop %r14
    pop %rbp
    pop %rbx
    ret

.Lincl_mmap_err:
    # mmap failed — close fd and print error
    mov %rbx, %rdi
    call platform_close_file
    lea incl_err_open(%rip), %rsi
    mov $incl_err_open_len, %rdx
    call platform_write
    mov file_name_addr(%rip), %rsi
    mov file_name_len(%rip), %rdx
    call platform_write
    mov $'\n', %rdi
    call platform_emit
    mov $1, %eax
    pop %r8
    pop %r14
    pop %rbp
    pop %rbx
    ret

.section .rodata
incl_err_sep:    .ascii ": ? "
.equ incl_err_sep_len, . - incl_err_sep
incl_err_open:   .ascii "Error: cannot open "
.equ incl_err_open_len, . - incl_err_open
.text

# ---------- Control Flow Tag Constants ----------
# Pushed alongside addresses on the compile-time stack to detect
# mis-paired control structures (e.g. BEGIN ... THEN).
.equ CF_ORIG, 1                     # forward reference (IF, ELSE, WHILE)
.equ CF_DEST, 2                     # backward target (BEGIN)
.equ CF_LEAVE, 3                    # saved leave count (DO)
.equ MAX_LEAVES, 8                  # max LEAVE per nesting

# cf_check_tag — verify top of stack matches expected tag.
# Input: RAX = expected tag.  On mismatch, aborts compilation and
# jumps directly to repl_loop (does not return to caller).
cf_check_tag:
    cmp (%r15), %rax
    jne .Lcf_mismatch
    ret
.Lcf_mismatch:
    # Set error token for control-flow mismatch
    lea cf_mismatch_name(%rip), %rax
    mov %rax, err_token_addr(%rip)
    movq $cf_mismatch_name_len, err_token_len(%rip)
    # Fall through to abort
.Lcf_abort:
    # Abort compilation — restore state and longjmp.
    # Caller must set err_token_addr/len before jumping here.
    mov colon_dsp(%rip), %r15       # restore DSP
    mov saved_latest(%rip), %r12    # restore LATEST
    mov saved_here(%rip), %r13      # restore HERE
    movq $0, state(%rip)            # interpret mode
    movq $0, do_depth(%rip)         # reset DO nesting
    movq $0, leave_count(%rip)      # reset leave chain
    # Longjmp back to forth_interpret_line's error return
    mov il_rsp(%rip), %rsp          # unwind to interpret_line's frame
    mov $1, %eax                    # return error
    add $8, %rsp                    # drop alignment padding
    popq il_rsp(%rip)               # restore previous il_rsp (nesting)
    pop %r14                        # restore callee-saved registers
    pop %rbp
    pop %rbx
    ret                             # return from interpret_line

# ---------- IF / ELSE / THEN ----------

# IF ( C: -- orig )  IMMEDIATE, COMPILE_ONLY
# Compile conditional forward branch. Push (patch-addr CF_ORIG).
.global forth_if
forth_if:
    call compile_0branch            # RAX = patch addr
    sub $2*CELL, %r15
    mov %rax, CELL(%r15)            # push patch address
    movq $CF_ORIG, (%r15)           # push tag
    ret

# THEN ( C: orig -- )  IMMEDIATE, COMPILE_ONLY
# Patch a forward branch (from IF or ELSE) to land here.
.global forth_then
forth_then:
    mov $CF_ORIG, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rax                # pop patch address
    add $CELL, %r15
    call patch_forward
    ret

# ELSE ( C: orig1 -- orig2 )  IMMEDIATE, COMPILE_ONLY
# Compile unconditional forward branch (for skip-over), patch IF's branch.
.global forth_else
forth_else:
    mov $CF_ORIG, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rbx                # pop if-patch
    add $CELL, %r15
    push %rbx                       # save if-patch
    call compile_branch             # RAX = else-patch
    pop %rbx                        # restore if-patch
    sub $2*CELL, %r15
    mov %rax, CELL(%r15)            # push else-patch
    movq $CF_ORIG, (%r15)           # push tag
    mov %rbx, %rax
    call patch_forward              # patch IF's JZ to HERE
    ret

# ---------- BEGIN / UNTIL / AGAIN / WHILE / REPEAT ----------

# BEGIN ( C: -- dest )  IMMEDIATE, COMPILE_ONLY
# Mark loop start by pushing (HERE CF_DEST).
.global forth_begin
forth_begin:
    sub $2*CELL, %r15
    mov %r13, CELL(%r15)            # push HERE
    movq $CF_DEST, (%r15)           # push tag
    ret

# UNTIL ( C: dest -- )  IMMEDIATE, COMPILE_ONLY
# Compile conditional backward branch to BEGIN.
.global forth_until
forth_until:
    mov $CF_DEST, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rax                # pop begin-addr
    add $CELL, %r15
    call compile_0branch_back
    ret

# AGAIN ( C: dest -- )  IMMEDIATE, COMPILE_ONLY
# Compile unconditional backward branch to BEGIN.
.global forth_again
forth_again:
    mov $CF_DEST, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rax                # pop begin-addr
    add $CELL, %r15
    call compile_branch_back
    ret

# WHILE ( C: dest -- dest orig )  IMMEDIATE, COMPILE_ONLY
# Compile conditional forward branch (exit test). Like IF inside a loop.
.global forth_while
forth_while:
    # Verify BEGIN's tag is below (peek, don't consume)
    mov $CF_DEST, %rax
    cmp (%r15), %rax
    jne .Lcf_mismatch
    call compile_0branch            # RAX = while-patch
    sub $2*CELL, %r15
    mov %rax, CELL(%r15)            # push while-patch
    movq $CF_ORIG, (%r15)           # push tag
    ret

# REPEAT ( C: dest orig -- )  IMMEDIATE, COMPILE_ONLY
# Compile backward branch to BEGIN, patch WHILE's forward branch.
.global forth_repeat
forth_repeat:
    mov $CF_ORIG, %rax              # check WHILE's tag
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rbx                # pop while-patch
    add $CELL, %r15
    mov $CF_DEST, %rax              # check BEGIN's tag
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rax                # pop begin-addr
    add $CELL, %r15
    push %rbx                       # save while-patch
    call compile_branch_back        # JMP back to begin
    pop %rax                        # RAX = while-patch
    call patch_forward              # patch WHILE's JZ to HERE
    ret

# ---------- RECURSE ----------

# RECURSE ( -- )  IMMEDIATE, COMPILE_ONLY
# Compile a call to the current definition being compiled.
.global forth_recurse
forth_recurse:
    mov colon_code_len_addr(%rip), %rax
    mov -8(%rax), %rax              # RAX = code entry point (CodePtr field)
    call compile_call
    ret

# ---------- CASE / OF / ENDOF / ENDCASE ----------
# All IMMEDIATE + COMPILE_ONLY.

# CASE ( -- 0 )  Push sentinel on compile-time stack.
.global forth_case
forth_case:
    sub $CELL, %r15
    movq $0, (%r15)
    ret

# OF ( x1 x2 -- | x1 )  Compile OVER = 0BRANCH(fwd) DROP.
# Leaves forward reference on compile-time stack.
.global forth_of
forth_of:
    push %rbx
    # Compile OVER
    lea forth_over(%rip), %rax
    call compile_call
    # Compile =
    lea forth_equal(%rip), %rax
    call compile_call
    # Compile 0branch (conditional forward jump)
    call compile_0branch            # RAX = patch address
    mov %rax, %rbx                  # save patch address
    # Compile DROP (remove test value on match)
    lea forth_drop(%rip), %rax
    call compile_call
    # Push patch address for ENDOF
    sub $CELL, %r15
    mov %rbx, (%r15)
    pop %rbx
    ret

# ENDOF ( -- )  Compile unconditional branch, patch OF's 0branch.
.global forth_endof
forth_endof:
    push %rbx
    # Pop OF's patch address
    mov (%r15), %rbx                # save of-patch
    add $CELL, %r15
    # Compile branch (unconditional forward jump)
    call compile_branch             # RAX = branch patch address
    push %rax                       # save for pushing later
    # Patch OF's 0branch to here
    mov %rbx, %rax
    call patch_forward
    # Push branch's patch address for ENDCASE
    pop %rax
    sub $CELL, %r15
    mov %rax, (%r15)
    pop %rbx
    ret

# ENDCASE ( x -- )  Compile DROP, patch all ENDOF branches.
.global forth_endcase
forth_endcase:
    # Compile DROP (discard the selector for default path)
    push %rbx
    lea forth_drop(%rip), %rax
    call compile_call
    # Patch all ENDOF branches until 0 sentinel
.Lendcase_loop:
    mov (%r15), %rax                # pop address
    add $CELL, %r15
    test %rax, %rax
    jz .Lendcase_done
    call patch_forward
    jmp .Lendcase_loop
.Lendcase_done:
    pop %rbx
    ret

# ---------- PARSE ----------
# PARSE ( char "ccc<char>" -- c-addr u )
# Parse input delimited by char. Does NOT skip leading delimiters.
# Advances >IN past the delimiter (or to end of input).
.global forth_parse
forth_parse:
    push %rbx
    mov (%r15), %rax                # RAX = delimiter char
    add $CELL, %r15                 # pop delimiter

    # Load source context
    mov source_addr(%rip), %rsi     # RSI = buffer base
    mov source_len(%rip), %rcx      # RCX = total length
    mov to_in(%rip), %rdx           # RDX = current offset (>IN)

    # Start of parsed region
    lea (%rsi,%rdx), %rdi           # RDI = c-addr (start of string)
    mov %rdx, %rbx                  # save start offset

    # Scan for delimiter
.Lparse_scan:
    cmp %rcx, %rdx
    jge .Lparse_end                 # end of input
    cmpb %al, (%rsi,%rdx)
    je .Lparse_found
    inc %rdx
    jmp .Lparse_scan

.Lparse_found:
    # Delimiter found at rdx — advance >IN past it
    lea 1(%rdx), %rcx
    mov %rcx, to_in(%rip)
    jmp .Lparse_push

.Lparse_end:
    # End of input — >IN = source_len
    mov %rdx, to_in(%rip)

.Lparse_push:
    # Length = rdx - start
    sub %rbx, %rdx                  # RDX = string length
    sub $CELL, %r15
    mov %rdi, (%r15)                # push c-addr
    sub $CELL, %r15
    mov %rdx, (%r15)                # push u
    pop %rbx
    ret

# ---------- SOURCE-ID ----------
# SOURCE-ID ( -- n )
# Returns 0 for keyboard input, -1 for EVALUATE string.
.global forth_source_id
forth_source_id:
    sub $CELL, %r15
    mov source_id(%rip), %rax
    mov %rax, (%r15)
    ret

# ---------- VALUE ----------
# VALUE ( x "name" -- )
# Create a named value. Like CONSTANT: the value is stored inline.
# TO can modify the inline value at xt+5 (after the CALL forth_lit opcode).
.global forth_value
forth_value:
    # Identical to CONSTANT
    push %rbx
    push %rbp

    # Pop value from data stack BEFORE build_header
    mov (%r15), %rax
    add $CELL, %r15
    push %rax                       # save value

    call build_header
    jc .Lvalue_err

    # Compile code that pushes the value
    pop %rax                        # restore value
    call compile_literal            # emit CALL forth_lit + value
    call compile_ret                # emit RET

    # Fill code_len
    mov colon_code_len_addr(%rip), %rax
    lea 4(%rax), %rcx
    mov %r13, %rdx
    sub %rcx, %rdx
    mov %edx, (%rax)

    # Clear HIDDEN flag
    andb $~F_HIDDEN, 8(%r12)

    pop %rbp
    pop %rbx
    ret

.Lvalue_err:
    pop %rax                        # restore saved value
    sub $CELL, %r15
    mov %rax, (%r15)                # push it back
    pop %rbp
    pop %rbx
    ret

# ---------- TO ----------
# TO ( x "name" -- ) IMMEDIATE
# Assign a new value to a VALUE word. In interpret mode, stores immediately.
# In compile mode, compiles code to store at runtime.
# Value address is xt + 5 (skip CALL opcode + 4-byte rel32 of forth_lit).
.global forth_to
forth_to:
    push %rbx
    call forth_parse_word           # ( -- c-addr u )
    call forth_find                 # ( c-addr u -- xt flag | c-addr u 0 )
    mov (%r15), %rax                # flag
    test %rax, %rax
    jz .Lto_not_found
    add $CELL, %r15                 # drop flag
    mov (%r15), %rax                # xt
    add $CELL, %r15                 # drop xt

    # Value address = xt + 5 (past CALL forth_lit opcode)
    lea 5(%rax), %rbx               # RBX = addr of inline value

    # Check STATE
    cmpq $0, state(%rip)
    jne .Lto_compile

    # Interpret mode: pop x from stack, store to value address
    mov (%r15), %rax                # x
    add $CELL, %r15
    mov %rax, (%rbx)                # store x at value address
    pop %rbx
    ret

.Lto_compile:
    # Compile mode: compile LITERAL(addr) + CALL(forth_store)
    mov %rbx, %rax                  # addr of inline value
    call compile_literal            # compile addr as literal
    lea forth_store(%rip), %rax
    call compile_call               # compile call to !
    pop %rbx
    ret

.Lto_not_found:
    # Word not found — set error token and abort
    add $CELL, %r15                 # drop 0 flag
    mov (%r15), %rax                # u
    mov %rax, err_token_len(%rip)
    mov CELL(%r15), %rax            # c-addr
    mov %rax, err_token_addr(%rip)
    add $2*CELL, %r15
    pop %rbx
    jmp .Lcf_abort

# ---------- :NONAME ----------
# :NONAME ( -- xt )
# Begin an anonymous colon definition. Pushes the xt (HERE) to the data stack.
# ; ends it normally.
.global forth_noname
forth_noname:
    # Save state for error recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    # Save HERE as the xt — this is where the code will start
    mov %r13, %rax

    # Push xt to data stack
    sub $CELL, %r15
    mov %rax, (%r15)

    # Save DSP AFTER pushing xt (so ; sees balanced stack)
    mov %r15, colon_dsp(%rip)

    # Enter compile mode
    movq $-1, state(%rip)

    # No code_len field for :NONAME (no dictionary entry)
    # Set colon_code_len_addr to 0 so ; skips code_len fill
    movq $0, colon_code_len_addr(%rip)

    ret

# ---------- ?DO ----------
# ?DO ( limit index -- ) (R: -- limit index)  IMMEDIATE, COMPILE_ONLY
# Like DO but skips the loop body if limit == index.
# Compiles: compare-and-branch-equal-forward, then push to return stack.
# The forward branch is patched by LOOP/+LOOP (same as DO's skip-patch).
.global forth_question_do
forth_question_do:
    # Compile ?DO inline code:
    # Phase 1: Load limit and index, pop from data stack
    # Phase 2: Compare — if equal, branch forward (skip loop body entirely)
    # Phase 3: Push limit and index to return stack
    # The key difference from DO: branch BEFORE pushing to return stack,
    # so if we skip, return stack is clean.
    call compile_question_do_inline # RAX = skip-patch address
    incq do_depth(%rip)
    sub $6*CELL, %r15
    mov %rax, 5*CELL(%r15)         # skip-patch address
    movq $CF_ORIG, 4*CELL(%r15)    # tag
    mov leave_count(%rip), %rax
    mov %rax, 3*CELL(%r15)
    movq $CF_LEAVE, 2*CELL(%r15)   # tag
    mov %r13, CELL(%r15)           # body address = HERE
    movq $CF_DEST, (%r15)          # tag
    ret

# compile_question_do_inline — emit ?DO's inline code (22 bytes).
# Same as compile_do_inline but: compare and branch BEFORE pushing to
# return stack. If equal, skip the entire loop body (clean return stack).
# Returns: RAX = address of JE offset field (for LOOP to patch).
compile_question_do_inline:
    CHECK_DICT 22
    movb $0x49, 0(%r13)            # mov (%r15), %rax      (index)
    movb $0x8B, 1(%r13)
    movb $0x07, 2(%r13)
    movb $0x49, 3(%r13)            # mov 8(%r15), %rdx     (limit)
    movb $0x8B, 4(%r13)
    movb $0x57, 5(%r13)
    movb $0x08, 6(%r13)
    movb $0x49, 7(%r13)            # add $16, %r15         (pop both)
    movb $0x83, 8(%r13)
    movb $0xC7, 9(%r13)
    movb $0x10, 10(%r13)
    movb $0x48, 11(%r13)           # cmp %rax, %rdx
    movb $0x39, 12(%r13)
    movb $0xC2, 13(%r13)
    movb $0x0F, 14(%r13)           # je rel32              (skip if equal)
    movb $0x84, 15(%r13)
    movl $0, 16(%r13)              # placeholder offset
    movb $0x52, 20(%r13)           # push %rdx (limit)
    movb $0x50, 21(%r13)           # push %rax (index)
    lea 16(%r13), %rax             # RAX = JE offset field address
    add $22, %r13
    ret

# ---------- WORDS ----------
# WORDS ( -- )
# Print all words in the dictionary, walking from LATEST to end.
.global forth_words
forth_words:
    push %rbx
    push %rbp
    mov %r12, %rbx                  # RBX = current entry (start at LATEST)

.Lwords_loop:
    test %rbx, %rbx
    jz .Lwords_done                 # NULL link = end of dictionary

    # Extract name length from flags byte (offset 8 from entry)
    movzbl 8(%rbx), %eax            # flags+len byte
    and $F_LENMASK, %eax            # mask to get length
    mov %rax, %rbp                  # RBP = name length

    # Name starts at offset 9
    lea 9(%rbx), %rsi               # RSI = name address
    mov %rbp, %rdx                  # RDX = name length
    call platform_write

    # Print space
    sub $16, %rsp
    movb $' ', (%rsp)
    lea (%rsp), %rsi
    mov $1, %rdx
    call platform_write
    add $16, %rsp

    # Follow link to next entry
    mov (%rbx), %rbx
    jmp .Lwords_loop

.Lwords_done:
    pop %rbp
    pop %rbx
    ret

# ---------- KEY? ----------
# KEY? ( -- flag )
# Non-blocking check if input is available. Returns -1 if key ready, 0 if not.
.global forth_key_q
forth_key_q:
    call platform_raw_mode          # lazily enter raw mode on first interactive input
    call platform_key_ready         # RDI = count (>0 if ready)
    test %edi, %edi
    jz .Lkq_no
    mov $-1, %rax                   # TRUE
    jmp .Lkq_push
.Lkq_no:
    xor %eax, %eax                  # FALSE
.Lkq_push:
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ---------- MS ----------
# MS ( u -- )
# Pause for u milliseconds.
.global forth_ms
forth_ms:
    mov (%r15), %rdi                # pop milliseconds
    add $CELL, %r15
    call platform_ms
    ret

# ---------- PAGE ----------
# PAGE ( -- )
# Clear the screen and move cursor to home position.
.global forth_page
forth_page:
    call platform_page
    ret

# ---------- AT-XY ----------
# AT-XY ( u1 u2 -- )
# Move cursor. u1=column, u2=row (both 0-based per ANS standard).
.global forth_at_xy
forth_at_xy:
    mov (%r15), %rsi                # u2 = row (top)
    mov CELL(%r15), %rdi            # u1 = col (second)
    add $2*CELL, %r15
    call platform_at_xy
    ret

# ---------- SCREEN-WIDTH ----------
# SCREEN-WIDTH ( -- u )
.global forth_screen_w
forth_screen_w:
    call platform_screen_width      # RAX = columns
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ---------- SCREEN-HEIGHT ----------
# SCREEN-HEIGHT ( -- u )
.global forth_screen_h
forth_screen_h:
    call platform_screen_height     # RAX = rows
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ---------- INCLUDE ----------
# INCLUDE ( "filename" -- )
# Parse the next word from input and load it as a Forth source file.
# Convenience wrapper: INCLUDE foo.fs  is equivalent to  s" foo.fs" included
.global forth_include
forth_include:
    call forth_parse_word           # ( -- c-addr u )
    call forth_included             # ( c-addr u -- )
    ret

# ---------- Command-line arguments (Tier 3) ----------
# ARGC and ARGV are variables (mirroring gforth): they push the address of the
# mutable count/base cells, so `argc @` and `argv @` work. arg_base is a char**
# into the OS argv vector; SHIFT-ARGS / NEXT-ARG consume from the front.

# ARGC ( -- a-addr ) — address of the argument-count cell.
.global forth_argc
forth_argc:
    lea arg_count(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ARGV ( -- a-addr ) — address of the argv-base cell (a-addr @ -> char**).
.global forth_argv
forth_argv:
    lea arg_base(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ARG ( u -- c-addr u ) — the uth argument as a string; ( 0 0 ) if out of range.
.global forth_arg
forth_arg:
    mov (%r15), %rcx                # rcx = u (index)
    mov arg_count(%rip), %rax
    cmp %rax, %rcx
    jae .Larg_oob                   # u >= count (unsigned) -> out of range
    mov arg_base(%rip), %rdx        # char** base
    mov (%rdx,%rcx,8), %rsi         # char* = base[u]
    xor %rcx, %rcx                  # strlen
.Larg_strlen:
    cmpb $0, (%rsi,%rcx)
    je .Larg_done
    inc %rcx
    jmp .Larg_strlen
.Larg_done:
    mov %rsi, (%r15)                # replace u with c-addr
    sub $CELL, %r15
    mov %rcx, (%r15)                # push len
    ret
.Larg_oob:
    movq $0, (%r15)                 # c-addr = 0
    sub $CELL, %r15
    movq $0, (%r15)                 # len = 0
    ret

# SHIFT-ARGS ( -- ) — delete arg[1], shifting the rest left and decrementing
# argc. O(1): copy arg[0] forward into slot 1, then advance the base by a cell
# (keeps arg[0] = program name). No-op when there is no arg[1] (count < 2).
.global forth_shift_args
forth_shift_args:
    mov arg_count(%rip), %rax
    cmp $2, %rax
    jb .Lshift_done
    mov arg_base(%rip), %rdx
    mov (%rdx), %rcx                # base[0] (program name)
    mov %rcx, CELL(%rdx)            # base[1] = base[0]
    add $CELL, %rdx                 # base += 1
    mov %rdx, arg_base(%rip)
    decq arg_count(%rip)
.Lshift_done:
    ret

# NEXT-ARG ( -- c-addr u ) — return arg[1] and consume it via SHIFT-ARGS;
# ( 0 0 ) when no argument remains.
.global forth_next_arg
forth_next_arg:
    mov arg_count(%rip), %rax
    cmp $2, %rax
    jb .Lnext_empty                 # no arg[1]
    mov arg_base(%rip), %rdx
    mov CELL(%rdx), %rsi            # char* = base[1]
    xor %rcx, %rcx                  # strlen
.Lnext_strlen:
    cmpb $0, (%rsi,%rcx)
    je .Lnext_got
    inc %rcx
    jmp .Lnext_strlen
.Lnext_got:
    sub $CELL, %r15
    mov %rsi, (%r15)                # push c-addr
    sub $CELL, %r15
    mov %rcx, (%r15)                # push len
    call forth_shift_args           # consume arg[1]
    ret
.Lnext_empty:
    sub $CELL, %r15
    movq $0, (%r15)                 # c-addr = 0
    sub $CELL, %r15
    movq $0, (%r15)                 # len = 0
    ret

# BYE-CODE ( n -- ) — exit with status n, silent (no "Goodbye!" banner) so a
# utility's output is not corrupted.
.global forth_bye_code
forth_bye_code:
    mov (%r15), %rdi                # status = TOS
    add $CELL, %r15
    jmp platform_exit

# ---------- WRITE-FILE ----------
# WRITE-FILE ( c-addr u fileid -- ior )
# Write u bytes at c-addr to the file descriptor fileid. Returns ior: 0 on
# success, else the positive errno. Loops over write() until ALL u bytes are
# written (a short write is not success), so a partial write can never silently
# truncate output. fileid is a raw OS fd (stdin/stdout/stderr = 0/1/2).
.global forth_write_file
forth_write_file:
    push %rbx                       # callee-saved: loop state across the syscall
    push %rbp
    push %r14
    mov (%r15), %r14                # fd
    mov CELL(%r15), %rbp            # remaining = u
    mov 2*CELL(%r15), %rbx          # ptr = c-addr
    add $2*CELL, %r15               # pop fileid + u; TOS slot ← ior
.Lwf_loop:
    test %rbp, %rbp
    jz .Lwf_ok                      # all bytes written
    mov %r14, %rdi                  # fd
    mov %rbx, %rsi                  # ptr
    mov %rbp, %rdx                  # remaining
    call platform_write_fd          # RAX = bytes written or -errno
    test %rax, %rax
    js .Lwf_err                     # negative → error
    jz .Lwf_zero                    # 0 bytes and no error → avoid spinning
    add %rax, %rbx                  # ptr += n
    sub %rax, %rbp                  # remaining -= n
    jmp .Lwf_loop
.Lwf_ok:
    movq $0, (%r15)                 # ior = 0 (success)
    jmp .Lwf_ret
.Lwf_zero:
    movq $5, (%r15)                 # ior = EIO (5): made no progress
    jmp .Lwf_ret
.Lwf_err:
    neg %rax                        # ior = errno (positive)
    mov %rax, (%r15)
.Lwf_ret:
    pop %r14
    pop %rbp
    pop %rbx
    ret

# ---------- File access (Phase 4) ----------
# fileid is a raw OS file descriptor; ior is 0 on success, else positive errno.

# OPEN-FILE   ( c-addr u fam -- fileid ior )  open an existing file
# CREATE-FILE ( c-addr u fam -- fileid ior )  create/truncate (mode 0666)
# fam is the access method from R/O (0), W/O (1) or R/W (2).
.global forth_open_file
forth_open_file:
    mov (%r15), %r8                 # flags = fam (R/O=0, W/O=1, R/W=2 = OS flags)
    xor %r9d, %r9d                  # mode = 0
    mov CELL(%r15), %rdx            # u (path length)
    mov 2*CELL(%r15), %rsi          # c-addr (path)
    add $CELL, %r15                 # pop fam → ( c-addr u )
    call platform_open_file_mode    # RAX = fd or -errno
    jmp .Lopen_result
.global forth_create_file
forth_create_file:
    mov (%r15), %r8                 # fam (platform adds O_CREAT|O_TRUNC, mode 0666)
    mov CELL(%r15), %rdx            # u (path length)
    mov 2*CELL(%r15), %rsi          # c-addr (path)
    add $CELL, %r15                 # pop fam → ( c-addr u )
    call platform_create_file       # RAX = fd or -errno
.Lopen_result:
    test %rax, %rax
    js .Lopen_err
    mov %rax, CELL(%r15)            # fileid = fd (overwrite c-addr slot)
    movq $0, (%r15)                 # ior = 0  (overwrite u slot)
    ret
.Lopen_err:
    movq $0, CELL(%r15)             # fileid = 0
    neg %rax
    mov %rax, (%r15)                # ior = errno
    ret

# CLOSE-FILE ( fileid -- ior )
.global forth_close_file
forth_close_file:
    mov (%r15), %rdi                # fileid
    call platform_close_file        # RAX = 0 or -errno
    test %rax, %rax
    js .Lclose_err
    movq $0, (%r15)                 # ior = 0
    ret
.Lclose_err:
    neg %rax
    mov %rax, (%r15)                # ior = errno
    ret

# READ-FILE ( c-addr u1 fileid -- u2 ior )  read up to u1 bytes; u2 = actual
.global forth_read_file
forth_read_file:
    mov (%r15), %rdi                # fileid
    mov CELL(%r15), %rdx            # u1 (count)
    mov 2*CELL(%r15), %rsi          # c-addr (buffer)
    add $CELL, %r15                 # pop fileid → ( c-addr u1 )
    call platform_read_file         # RAX = bytes read or -errno
    test %rax, %rax
    js .Lread_err
    mov %rax, CELL(%r15)            # u2 = bytes (overwrite c-addr slot)
    movq $0, (%r15)                 # ior = 0
    ret
.Lread_err:
    movq $0, CELL(%r15)             # u2 = 0
    neg %rax
    mov %rax, (%r15)                # ior = errno
    ret

# FILE-SIZE ( fileid -- ud ior )  file size as a double cell, via fstat
.global forth_file_size
forth_file_size:
    mov (%r15), %rdi                # fileid
    call platform_fstat             # RAX = size or -errno
    test %rax, %rax
    js .Lfsize_err
    mov %rax, (%r15)                # ud-lo = size (overwrite fileid)
    sub $CELL, %r15
    movq $0, (%r15)                 # ud-hi = 0
    sub $CELL, %r15
    movq $0, (%r15)                 # ior = 0
    ret
.Lfsize_err:
    neg %rax                        # errno
    mov %rax, %rcx
    movq $0, (%r15)                 # ud-lo = 0
    sub $CELL, %r15
    movq $0, (%r15)                 # ud-hi = 0
    sub $CELL, %r15
    mov %rcx, (%r15)                # ior = errno
    ret

# RENAME-FILE ( c-addr1 u1 c-addr2 u2 -- ior )  rename file1 → file2 (atomic).
.global forth_rename_file
forth_rename_file:
    mov 3*CELL(%r15), %rdi          # c-addr1 (old)
    mov 2*CELL(%r15), %rsi          # u1
    mov CELL(%r15), %rdx            # c-addr2 (new)
    mov (%r15), %rcx                # u2
    add $3*CELL, %r15               # pop 3 args; TOS slot ← ior
    call platform_rename            # RAX = 0 or -errno
    test %rax, %rax
    js .Lrename_err
    movq $0, (%r15)                 # ior = 0
    ret
.Lrename_err:
    neg %rax
    mov %rax, (%r15)                # ior = errno
    ret

# ---------- Heap primitives (Phase 4) ----------
# Thin wrappers over the anonymous-mmap platform calls. The ANS MEMORY words
# ALLOCATE/FREE/RESIZE are built on these in core.fs; sign handling and the
# length-header bookkeeping live there.

# (mmap-anon) ( size -- addr )  addr is page-aligned, or a negative errno.
.global forth_mmap_anon
forth_mmap_anon:
    mov (%r15), %rdi                # size
    call platform_mmap_anon         # RAX = addr or -errno
    mov %rax, (%r15)
    ret

# (munmap) ( addr size -- n )  n = 0 on success, or a negative errno.
.global forth_munmap
forth_munmap:
    mov (%r15), %rsi                # size
    mov CELL(%r15), %rdi            # addr
    add $CELL, %r15                 # pop size → TOS slot now = addr slot
    call platform_munmap            # RAX = 0 or -errno
    mov %rax, (%r15)
    ret

# ---------- Session hook registration (Phase 4) ----------
# (hook!) ( xt id -- )  register a session hook word by id: 0=session-boot,
# 1=capture-line, 2=capture-reset. core.fs registers its hook words here so the
# asm REPL/startup can call them; main.s reads session_hooks[id] and calls it.
.global forth_hook_store
forth_hook_store:
    mov (%r15), %rax                # id
    mov CELL(%r15), %rdx            # xt
    add $2*CELL, %r15               # pop id + xt
    lea session_hooks(%rip), %rcx
    mov %rdx, (%rcx,%rax,8)         # session_hooks[id] = xt
    ret

# ---------- Dictionary restore points (MARKER) ----------
# (latest@) ( -- a )  push the LATEST register (newest dictionary entry).
.global forth_latest_at
forth_latest_at:
    sub $CELL, %r15
    mov %r12, (%r15)                # push LATEST (R12)
    ret

# (restore-dict) ( here latest -- )  rewind the dictionary: set HERE and LATEST.
# MARKER's runtime calls this to forget everything defined after the marker.
.global forth_restore_dict
forth_restore_dict:
    mov (%r15), %r12               # latest (TOS)
    mov CELL(%r15), %r13          # here
    add $2*CELL, %r15             # pop both
    ret

# ---------- MS@ ----------
# MS@ ( -- u )
# Return current monotonic milliseconds.
.global forth_ms_get
forth_ms_get:
    call platform_ms_get            # RAX = milliseconds
    sub $CELL, %r15
    mov %rax, (%r15)
    ret

# ---------- CURSOR-OFF ----------
# CURSOR-OFF ( -- )
# Hide the terminal cursor.
.global forth_cursor_off
forth_cursor_off:
    call platform_cursor_off
    ret

# ---------- CURSOR-ON ----------
# CURSOR-ON ( -- )
# Show the terminal cursor.
.global forth_cursor_on
forth_cursor_on:
    call platform_cursor_on
    ret

# ---------- HERE, ALLOT, COMMA, C-COMMA ----------

# HERE ( -- addr )
# Push the current dictionary free-space pointer.
.global forth_here
forth_here:
    sub $CELL, %r15
    mov %r13, (%r15)                # push HERE (R13)
    ret

# ALLOT ( n -- )
# Reserve n bytes in dictionary space.
.global forth_allot
forth_allot:
    mov (%r15), %rax
    add $CELL, %r15                 # pop n
    # Bounds check: dict_space <= HERE + n <= dict_space + SIZE
    lea (%r13,%rax), %rcx           # RCX = HERE + n
    lea dict_space(%rip), %rdx
    cmp %rdx, %rcx
    jb dict_full                    # below dict_space start
    lea dict_space+DICT_SPACE_SIZE(%rip), %rdx
    cmp %rdx, %rcx
    ja dict_full                    # above dict_space end
    add %rax, %r13                  # HERE += n
    ret

# , ( x -- )
# Store x at HERE and advance HERE by one cell.
.global forth_comma
forth_comma:
    CHECK_DICT 8
    mov (%r15), %rax
    add $CELL, %r15                 # pop x
    mov %rax, (%r13)                # store at HERE
    add $CELL, %r13                 # advance HERE
    ret

# C, ( c -- )
# Store byte at HERE and advance HERE by one byte.
.global forth_c_comma
forth_c_comma:
    CHECK_DICT 1
    mov (%r15), %rax
    add $CELL, %r15                 # pop c
    movb %al, (%r13)                # store byte at HERE
    inc %r13                        # advance HERE
    ret

# ---------- CREATE ----------

# CREATE ( "name" -- )
# Parse name, build dictionary header, compile code that pushes the
# data field address. Does not enter compile mode.
.global forth_create
forth_create:
    push %rbx
    push %rbp

    call build_header
    jc .Lcreate_done                # error → bail

    # Compile code with placeholder data address (0), then patch after aligning
    xor %eax, %eax                  # placeholder = 0
    call compile_literal            # emit CALL forth_lit + 0
    lea -8(%r13), %rbx              # RBX = address of inline value (to patch)
    call compile_ret                # emit RET
    # Reserve 4 NOP bytes for DOES> to overwrite (RET + 4 NOPs = 5 bytes for JMP rel32)
    movb $0x90, 0(%r13)
    movb $0x90, 1(%r13)
    movb $0x90, 2(%r13)
    movb $0x90, 3(%r13)
    add $4, %r13

    # Align HERE to CELL for data field
    add $7, %r13
    and $~7, %r13

    # Patch the literal with the actual aligned data field address
    mov %r13, (%rbx)                # write real data_addr into the literal

    # Fill code_len (code = from code_start to just before alignment padding)
    mov colon_code_len_addr(%rip), %rax
    lea 4(%rax), %rcx              # code start
    mov %rbx, %rdx                 # end of code = literal value addr
    add $8, %rdx                   # + 8 bytes for the value itself
    add $5, %rdx                   # + 5 bytes for RET + 4 NOPs
    sub %rcx, %rdx
    mov %edx, (%rax)               # write code_len

    # Clear HIDDEN flag — word is now visible
    andb $~F_HIDDEN, 8(%r12)

.Lcreate_done:
    pop %rbp
    pop %rbx
    ret

# ---------- CONSTANT ----------

# CONSTANT ( x "name" -- )
# Parse name, build dictionary header, compile code that pushes x.
.global forth_constant
forth_constant:
    push %rbx
    push %rbp

    # Pop value from data stack BEFORE build_header (which parses name)
    mov (%r15), %rax
    add $CELL, %r15
    push %rax                       # save value on return stack (build_header clobbers RBX)

    call build_header
    jc .Lconst_err                  # error → bail

    # Compile code that pushes the constant value
    pop %rax                        # restore value
    call compile_literal            # emit CALL forth_lit + value
    call compile_ret                # emit RET

    # Fill code_len
    mov colon_code_len_addr(%rip), %rax
    lea 4(%rax), %rcx
    mov %r13, %rdx
    sub %rcx, %rdx
    mov %edx, (%rax)

    # Clear HIDDEN flag
    andb $~F_HIDDEN, 8(%r12)

    pop %rbp
    pop %rbx
    ret

.Lconst_err:
    pop %rax                        # restore saved value
    sub $CELL, %r15
    mov %rax, (%r15)                # push it back onto data stack
    pop %rbp
    pop %rbx
    ret

# ---------- DOES> ----------

# (DOES>) runtime helper — called during defining word execution.
# Patches the most recently CREATE'd word (via colon_code_len_addr)
# to JMP to the does-body instead of RETurning.
# does_body = our return address + 1 (skip the RET byte after CALL us).
.global forth_does_runtime
forth_does_runtime:
    push %rbx
    # Get does_body address from our return address
    mov 8(%rsp), %rax              # return addr (8 = 1 pushed reg)
    lea 1(%rax), %rbx              # RBX = does_body (skip the 1-byte RET)
    # Get CREATE'd word's code start from colon_code_len_addr
    mov colon_code_len_addr(%rip), %rax
    lea 4(%rax), %rdi              # RDI = code_start
    # Patch offset 13 (RET + NOPs) with JMP rel32 to does_body
    movb $0xE9, 13(%rdi)          # JMP opcode
    lea 18(%rdi), %rcx            # address after JMP (offset 13 + 5 = 18)
    mov %rbx, %rax
    sub %rcx, %rax                # offset = does_body - after_jmp
    mov %eax, 14(%rdi)            # write rel32
    pop %rbx
    ret

# DOES> ( -- )  IMMEDIATE, COMPILE_ONLY
# Compile-time: emit CALL (does>) + RET, then continue compiling
# the does-body. ; will close the does-body with its own RET.
.global forth_does
forth_does:
    # Compile CALL forth_does_runtime
    lea forth_does_runtime(%rip), %rax
    call compile_call
    # Compile RET (ends defining word's normal path)
    call compile_ret
    # Does-body starts at HERE now. Subsequent words compile into it.
    # ; will close it with RET.
    ret

# ---------- BASE / PAD ----------

# BASE ( -- a-addr )  Push address of BASE variable.
.global forth_base
forth_base:
    sub $CELL, %r15
    lea base(%rip), %rax
    mov %rax, (%r15)
    ret

# PAD ( -- c-addr )  Push address of PAD scratch buffer.
.global forth_pad
forth_pad:
    sub $CELL, %r15
    lea pad(%rip), %rax
    mov %rax, (%r15)
    ret

# HLD ( -- a-addr )  Push address of HLD variable (for pictured output).
.global forth_hld
forth_hld:
    sub $CELL, %r15
    lea hld(%rip), %rax
    mov %rax, (%r15)
    ret

# UNUSED ( -- u )  Return number of free bytes in dictionary space.
.global forth_unused
forth_unused:
    sub $CELL, %r15
    lea dict_space+DICT_SPACE_SIZE(%rip), %rax
    sub %r13, %rax                  # end - HERE
    mov %rax, (%r15)
    ret

# ---------- System Words ----------

# >BODY ( xt -- a-addr )  Convert execution token to data field address.
# For CREATE'd words, the code is: CALL forth_lit(5) + value(8) + RET + NOPs
# The inline value at offset 5 IS the data field address.
.global forth_to_body
forth_to_body:
    mov (%r15), %rax                # xt
    mov 5(%rax), %rax               # read inline value (data field address)
    mov %rax, (%r15)
    ret

# >IN ( -- a-addr )  Push address of >IN variable.
.global forth_to_in
forth_to_in:
    sub $CELL, %r15
    lea to_in(%rip), %rax
    mov %rax, (%r15)
    ret

# SOURCE ( -- c-addr u )  Push current input source address and length.
.global forth_source
forth_source:
    sub $CELL, %r15
    mov source_addr(%rip), %rax
    mov %rax, (%r15)
    sub $CELL, %r15
    mov source_len(%rip), %rax
    mov %rax, (%r15)
    ret

# ABORT ( i*x -- ) ( R: j*x -- )  Clear stacks, reset to REPL.
.global forth_abort
forth_abort:
    mov sp0(%rip), %r15             # reset data stack
    mov rp0(%rip), %rsp             # reset return stack
    movq $0, state(%rip)            # reset compile state
    jmp repl_loop

# QUIT ( -- ) ( R: i*x -- )  Reset return stack, enter interpreter loop.
.global forth_quit
forth_quit:
    mov rp0(%rip), %rsp             # reset return stack
    movq $0, state(%rip)            # reset compile state
    jmp repl_loop

# ---------- Compiler Words ----------

# STATE ( -- a-addr )  Push address of STATE variable.
.global forth_state
forth_state:
    sub $CELL, %r15
    lea state(%rip), %rax
    mov %rax, (%r15)
    ret

# [ ( -- )  Switch to interpret mode.  IMMEDIATE.
.global forth_left_bracket
forth_left_bracket:
    movq $0, state(%rip)
    ret

# ] ( -- )  Switch to compile mode.
.global forth_right_bracket
forth_right_bracket:
    movq $-1, state(%rip)
    ret

# LITERAL ( x -- )  Compile a literal at compile time.  IMMEDIATE+COMPILE_ONLY.
# Takes x from data stack and compiles CALL LIT + x into the current definition.
.global forth_literal
forth_literal:
    mov (%r15), %rax
    add $CELL, %r15
    call compile_literal
    ret

# ['] ( "<spaces>name" -- )  Compile xt as literal.  IMMEDIATE+COMPILE_ONLY.
# Same as ' but always compiles (compile-only).
.global forth_bracket_tick
forth_bracket_tick:
    call forth_parse_word           # ( -- c-addr u )
    call forth_find                 # ( c-addr u -- xt flag | c-addr u 0 )
    mov (%r15), %rax                # flag
    test %rax, %rax
    jz .Lbt_not_found
    add $CELL, %r15                 # drop flag
    mov (%r15), %rax                # xt
    add $CELL, %r15                 # drop xt
    call compile_literal            # compile xt as literal
    ret
.Lbt_not_found:
    add $3*CELL, %r15               # drop flag, u, c-addr
    sub $CELL, %r15
    movq $0, (%r15)                 # push 0 (invalid xt)
    ret

# [CHAR] ( "<spaces>name" -- )  Compile char value as literal.  IMMEDIATE+COMPILE_ONLY.
.global forth_bracket_char
forth_bracket_char:
    call forth_parse_word           # ( -- c-addr u )
    mov CELL(%r15), %rax            # c-addr
    movzbl (%rax), %eax             # first character
    add $2*CELL, %r15               # drop c-addr and u
    call compile_literal            # compile char as literal
    ret

# EXIT ( -- )  Compile a return instruction.  IMMEDIATE+COMPILE_ONLY.
.global forth_exit
forth_exit:
    call compile_ret
    ret

# COMPILE, ( xt -- )  Compile a call to xt into the current definition.
.global forth_compile_comma
forth_compile_comma:
    mov (%r15), %rax
    add $CELL, %r15
    jmp compile_call                # tail call

# POSTPONE ( "<spaces>name" -- )  IMMEDIATE+COMPILE_ONLY.
# If the word is IMMEDIATE: compile a CALL to it (so it runs at runtime).
# If non-immediate: compile code that will compile a CALL at runtime.
# This is: compile LITERAL(xt) + compile CALL(compile_call)
.global forth_postpone
forth_postpone:
    push %rbx
    call forth_parse_word           # ( -- c-addr u )
    call forth_find                 # ( c-addr u -- xt flag | c-addr u 0 )
    mov (%r15), %rax                # flag
    test %rax, %rax
    jz .Lpostpone_not_found
    mov %rax, %rbx                  # save flag
    add $CELL, %r15                 # drop flag
    mov (%r15), %rax                # xt
    add $CELL, %r15                 # drop xt

    # Is it IMMEDIATE? (flag == 1 or flag == 2)
    cmpq $1, %rbx
    je .Lpostpone_immediate
    cmpq $2, %rbx
    je .Lpostpone_immediate

    # Non-immediate: compile LITERAL(xt) + CALL(forth_compile_comma)
    call compile_literal            # compile xt as literal
    lea forth_compile_comma(%rip), %rax
    call compile_call               # compile call to forth_compile_comma
    pop %rbx
    ret

.Lpostpone_immediate:
    # IMMEDIATE: just compile a CALL to it
    call compile_call
    pop %rbx
    ret

.Lpostpone_not_found:
    # Word not found — set error and abort
    add $CELL, %r15                 # drop 0 flag
    # c-addr and u are still on stack — set error token
    mov (%r15), %rax                # u
    mov %rax, err_token_len(%rip)
    mov CELL(%r15), %rax            # c-addr
    mov %rax, err_token_addr(%rip)
    add $2*CELL, %r15               # drop c-addr and u
    pop %rbx
    jmp .Lcf_abort

# ---------- TYPE ----------

# TYPE ( c-addr u -- ) — write string to stdout
.global forth_type
forth_type:
    mov (%r15), %rdx            # u (length)
    mov CELL(%r15), %rsi        # c-addr
    add $2*CELL, %r15           # pop both
    call platform_write
    ret

# ---------- PICK ----------

# PICK ( xu ... x1 x0 u -- xu ... x1 x0 xu )
# Copy the u-th item (0-indexed: 0 pick = dup).
.global forth_pick
forth_pick:
    mov (%r15), %rax            # u
    mov CELL(%r15,%rax,CELL), %rax  # DSP[(u+1)*8]
    mov %rax, (%r15)            # overwrite u with result
    ret

# ---------- S" and ." ----------

# forth_s_quote_runtime — runtime helper for inline strings.
# Called via CALL. Reads 8-byte length + string after return address.
# Pushes ( c-addr u ) to data stack. Adjusts return address to skip string.
.global forth_s_quote_runtime
forth_s_quote_runtime:
    pop %rax                    # return address
    mov (%rax), %rcx            # length (8 bytes)
    lea 8(%rax), %rdx           # c-addr = retaddr + 8
    lea 8(%rax,%rcx), %rax      # new retaddr = past string
    push %rax                   # push adjusted return address
    sub $2*CELL, %r15
    mov %rdx, CELL(%r15)        # push c-addr (second)
    mov %rcx, (%r15)            # push u (top)
    ret

# S" compile helper — shared by S" and ."
# Parses input for closing ", compiles CALL s_quote_runtime + length + string.
# Returns with HERE past the string.
compile_s_quote:
    push %rbx
    push %rbp
    # Skip leading space after S" / ."
    mov source_addr(%rip), %rsi
    mov to_in(%rip), %rbx       # current parse position
    mov source_len(%rip), %rcx
    # Skip one space if present
    cmp %rcx, %rbx
    jge .Lsq_empty              # to_in >= source_len → no input
    cmpb $32, (%rsi,%rbx)
    jne .Lsq_scan
    inc %rbx
.Lsq_scan:
    # Find closing "
    mov %rbx, %rbp              # RBP = string start in input
.Lsq_scan_loop:
    cmp %rcx, %rbx
    jge .Lsq_no_close           # to_in >= source_len → no closing "
    cmpb $'"', (%rsi,%rbx)
    je .Lsq_found
    inc %rbx
    jmp .Lsq_scan_loop
.Lsq_found:
    # RBP = start of string, RBX = position of closing "
    mov %rbx, %rax
    sub %rbp, %rax              # RAX = string length
    lea 1(%rbx), %rbx
    mov %rbx, to_in(%rip)      # advance to_in past closing "
    # Bounds check: need CALL(5) + CELL(8) + string bytes in dict_space
    lea dict_space+DICT_SPACE_SIZE(%rip), %rcx
    lea (5+CELL)(%r13,%rax), %rdx  # HERE + 5 + CELL + string_length
    cmp %rcx, %rdx
    ja dict_full
    # Compile CALL forth_s_quote_runtime
    push %rax                   # save length
    push %rbp                   # save string start offset
    lea forth_s_quote_runtime(%rip), %rax
    call compile_call
    pop %rbp                    # restore string start offset
    pop %rax                    # restore length
    # Compile .quad length
    mov %rax, (%r13)
    add $CELL, %r13
    # Copy string bytes to HERE
    push %rax                   # save length
    mov source_addr(%rip), %rsi
    add %rbp, %rsi              # RSI = source string addr
    mov %r13, %rdi              # RDI = HERE (destination)
    mov %rax, %rcx              # RCX = length
    rep movsb                   # copy
    pop %rax
    add %rax, %r13              # advance HERE past string
    pop %rbp
    pop %rbx
    ret
.Lsq_empty:
.Lsq_no_close:
    # No closing quote — abort compilation
    pop %rbp
    pop %rbx
    lea sq_unterminated_name(%rip), %rax
    mov %rax, err_token_addr(%rip)
    movq $sq_unterminated_name_len, err_token_len(%rip)
    jmp .Lcf_abort

# S" ( -- c-addr u )  IMMEDIATE, COMPILE_ONLY
.global forth_s_quote
forth_s_quote:
    call compile_s_quote
    ret

# ." ( -- )  IMMEDIATE, COMPILE_ONLY
# Like S" but also compiles CALL forth_type after the string.
.global forth_dot_quote
forth_dot_quote:
    call compile_s_quote
    lea forth_type(%rip), %rax
    call compile_call
    ret

# ---------- DO / LOOP / +LOOP / I / J / UNLOOP ----------
# All IMMEDIATE + COMPILE_ONLY. Compile inline machine code that
# manipulates the return stack for counted loops.
# Return stack layout during loop: [RSP]=index, [RSP+8]=limit

# compile_do_inline — emit DO's inline code (22 bytes).
# Returns: RAX = address of JE offset field (for LOOP to patch).
compile_do_inline:
    CHECK_DICT 22
    movb $0x49, 0(%r13)            # mov (%r15), %rax
    movb $0x8B, 1(%r13)
    movb $0x07, 2(%r13)
    movb $0x49, 3(%r13)            # mov 8(%r15), %rdx
    movb $0x8B, 4(%r13)
    movb $0x57, 5(%r13)
    movb $0x08, 6(%r13)
    movb $0x49, 7(%r13)            # add $16, %r15
    movb $0x83, 8(%r13)
    movb $0xC7, 9(%r13)
    movb $0x10, 10(%r13)
    movb $0x48, 11(%r13)           # cmp %rax, %rdx
    movb $0x39, 12(%r13)
    movb $0xC2, 13(%r13)
    movb $0x0F, 14(%r13)           # je rel32
    movb $0x84, 15(%r13)
    movl $0, 16(%r13)              # placeholder offset
    movb $0x52, 20(%r13)           # push %rdx (limit)
    movb $0x50, 21(%r13)           # push %rax (index)
    lea 16(%r13), %rax             # RAX = JE offset field address
    add $22, %r13
    ret

# compile_loop_inline — emit LOOP's inline code (17 bytes).
# Input: RAX = loop body address (backward target).
compile_loop_inline:
    CHECK_DICT 17
    movb $0x58, 0(%r13)            # pop %rax (index)
    movb $0x5A, 1(%r13)            # pop %rdx (limit)
    movb $0x48, 2(%r13)            # inc %rax
    movb $0xFF, 3(%r13)
    movb $0xC0, 4(%r13)
    movb $0x48, 5(%r13)            # cmp %rdx, %rax
    movb $0x39, 6(%r13)
    movb $0xC2, 7(%r13)
    movb $0x74, 8(%r13)            # je +7 (skip push+push+jmp)
    movb $0x07, 9(%r13)
    movb $0x52, 10(%r13)           # push %rdx (limit)
    movb $0x50, 11(%r13)           # push %rax (index)
    movb $0xE9, 12(%r13)           # jmp rel32
    lea 17(%r13), %rcx             # address after jmp
    sub %rcx, %rax                 # offset = target - after
    mov %eax, 13(%r13)
    add $17, %r13
    ret

# compile_plus_loop_inline — emit +LOOP's inline code (36 bytes).
# Input: RAX = loop body address (backward target).
# Uses boundary-crossing detection: exit when (old-limit) XOR (new-limit)
# has the sign bit set (index crossed the limit in either direction).
compile_plus_loop_inline:
    CHECK_DICT 36
    movb $0x58, 0(%r13)            # pop %rax (old index)
    movb $0x5A, 1(%r13)            # pop %rdx (limit)
    movb $0x49, 2(%r13)            # mov (%r15), %rcx  (increment)
    movb $0x8B, 3(%r13)
    movb $0x0F, 4(%r13)
    movb $0x49, 5(%r13)            # add $8, %r15  (pop increment)
    movb $0x83, 6(%r13)
    movb $0xC7, 7(%r13)
    movb $0x08, 8(%r13)
    movb $0x48, 9(%r13)            # mov %rax, %rsi  (save old index)
    movb $0x89, 10(%r13)
    movb $0xC6, 11(%r13)
    movb $0x48, 12(%r13)           # sub %rdx, %rsi  (old - limit)
    movb $0x29, 13(%r13)
    movb $0xD6, 14(%r13)
    movb $0x48, 15(%r13)           # add %rcx, %rax  (new index)
    movb $0x01, 16(%r13)
    movb $0xC8, 17(%r13)
    movb $0x48, 18(%r13)           # mov %rax, %rdi  (new index copy)
    movb $0x89, 19(%r13)
    movb $0xC7, 20(%r13)
    movb $0x48, 21(%r13)           # sub %rdx, %rdi  (new - limit)
    movb $0x29, 22(%r13)
    movb $0xD7, 23(%r13)
    movb $0x48, 24(%r13)           # xor %rdi, %rsi  (cross check)
    movb $0x31, 25(%r13)
    movb $0xFE, 26(%r13)
    movb $0x78, 27(%r13)           # js +7  (sign set → boundary crossed)
    movb $0x07, 28(%r13)
    movb $0x52, 29(%r13)           # push %rdx (limit)
    movb $0x50, 30(%r13)           # push %rax (new index)
    movb $0xE9, 31(%r13)           # jmp rel32
    lea 36(%r13), %rcx
    sub %rcx, %rax
    mov %eax, 32(%r13)
    add $36, %r13
    ret

# DO ( limit index -- ) (R: -- limit index)  IMMEDIATE, COMPILE_ONLY
.global forth_do
forth_do:
    call compile_do_inline          # RAX = skip-patch address
    incq do_depth(%rip)             # track nesting for LEAVE
    sub $6*CELL, %r15
    mov %rax, 5*CELL(%r15)         # skip-patch address
    movq $CF_ORIG, 4*CELL(%r15)    # tag
    mov leave_count(%rip), %rax    # save current leave count
    mov %rax, 3*CELL(%r15)
    movq $CF_LEAVE, 2*CELL(%r15)   # tag
    mov %r13, CELL(%r15)           # body address = HERE
    movq $CF_DEST, (%r15)          # tag
    ret

# LOOP ( -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
.global forth_loop
forth_loop:
    mov $CF_DEST, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rax                # body address
    add $CELL, %r15
    push %rax                       # save body address
    mov $CF_LEAVE, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rax                # saved leave count
    add $CELL, %r15
    push %rax                       # save it
    mov $CF_ORIG, %rax
    call cf_check_tag
    add $CELL, %r15                 # drop tag
    mov (%r15), %rbx                # skip-patch address
    add $CELL, %r15
    pop %rcx                        # saved leave count
    pop %rax                        # body address
    push %rcx                       # re-save leave count
    push %rbx                       # save skip-patch
    call compile_loop_inline
    pop %rax                        # skip-patch
    call patch_forward              # patch DO's JE to HERE
    # Patch all LEAVEs for this loop
    mov leave_count(%rip), %rbx     # current count
    pop %rcx                        # saved leave count (from DO)
    push %rcx                       # keep for restore
    cmp %rcx, %rbx
    je .Lloop_leave_done
    lea leave_stack(%rip), %rdx
.Lloop_leave_patch:
    dec %rbx
    mov (%rdx,%rbx,8), %rax
    push %rbx
    push %rcx
    push %rdx
    call patch_forward
    pop %rdx
    pop %rcx
    pop %rbx
    cmp %rcx, %rbx
    jne .Lloop_leave_patch
.Lloop_leave_done:
    pop %rax                        # restore saved leave count
    mov %rax, leave_count(%rip)
    decq do_depth(%rip)
    ret

# +LOOP ( n -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
.global forth_plus_loop
forth_plus_loop:
    mov $CF_DEST, %rax
    call cf_check_tag
    add $CELL, %r15
    mov (%r15), %rax
    add $CELL, %r15
    push %rax
    mov $CF_LEAVE, %rax
    call cf_check_tag
    add $CELL, %r15
    mov (%r15), %rax                # saved leave count
    add $CELL, %r15
    push %rax
    mov $CF_ORIG, %rax
    call cf_check_tag
    add $CELL, %r15
    mov (%r15), %rbx
    add $CELL, %r15
    pop %rcx                        # saved leave count
    pop %rax                        # body address
    push %rcx
    push %rbx                       # skip-patch
    call compile_plus_loop_inline
    pop %rax                        # skip-patch
    call patch_forward
    # Patch all LEAVEs for this loop
    mov leave_count(%rip), %rbx
    pop %rcx                        # saved leave count
    push %rcx
    cmp %rcx, %rbx
    je .Lploop_leave_done
    lea leave_stack(%rip), %rdx
.Lploop_leave_patch:
    dec %rbx
    mov (%rdx,%rbx,8), %rax
    push %rbx
    push %rcx
    push %rdx
    call patch_forward
    pop %rdx
    pop %rcx
    pop %rbx
    cmp %rcx, %rbx
    jne .Lploop_leave_patch
.Lploop_leave_done:
    pop %rax
    mov %rax, leave_count(%rip)
    decq do_depth(%rip)
    ret

# I ( -- index )  IMMEDIATE, COMPILE_ONLY
.global forth_i
forth_i:
    CHECK_DICT 11
    movb $0x48, 0(%r13)            # mov (%rsp), %rax
    movb $0x8B, 1(%r13)
    movb $0x04, 2(%r13)
    movb $0x24, 3(%r13)
    movb $0x49, 4(%r13)            # sub $8, %r15
    movb $0x83, 5(%r13)
    movb $0xEF, 6(%r13)
    movb $0x08, 7(%r13)
    movb $0x49, 8(%r13)            # mov %rax, (%r15)
    movb $0x89, 9(%r13)
    movb $0x07, 10(%r13)
    add $11, %r13
    ret

# J ( -- index )  IMMEDIATE, COMPILE_ONLY
.global forth_j
forth_j:
    CHECK_DICT 12
    movb $0x48, 0(%r13)            # mov 16(%rsp), %rax
    movb $0x8B, 1(%r13)
    movb $0x44, 2(%r13)
    movb $0x24, 3(%r13)
    movb $0x10, 4(%r13)
    movb $0x49, 5(%r13)            # sub $8, %r15
    movb $0x83, 6(%r13)
    movb $0xEF, 7(%r13)
    movb $0x08, 8(%r13)
    movb $0x49, 9(%r13)            # mov %rax, (%r15)
    movb $0x89, 10(%r13)
    movb $0x07, 11(%r13)
    add $12, %r13
    ret

# LEAVE ( -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
# Emit UNLOOP + forward JMP. Store patch address in leave_stack.
.global forth_leave
forth_leave:
    cmpq $0, do_depth(%rip)         # inside a DO loop?
    je .Lcf_mismatch                # no — trigger mismatch error
    CHECK_DICT 4                    # UNLOOP = 4 bytes (compile_branch does its own CHECK_DICT)
    movb $0x48, 0(%r13)            # add $16, %rsp  (UNLOOP inline)
    movb $0x83, 1(%r13)
    movb $0xC4, 2(%r13)
    movb $0x10, 3(%r13)
    add $4, %r13
    call compile_branch             # RAX = patch address of forward JMP
    mov leave_count(%rip), %rcx
    lea leave_stack(%rip), %rdx
    mov %rax, (%rdx,%rcx,8)        # leave_stack[count] = patch_addr
    inc %rcx
    mov %rcx, leave_count(%rip)
    ret

# UNLOOP ( -- ) (R: limit index -- )  IMMEDIATE, COMPILE_ONLY
.global forth_unloop
forth_unloop:
    CHECK_DICT 4
    movb $0x48, 0(%r13)            # add $16, %rsp
    movb $0x83, 1(%r13)
    movb $0xC4, 2(%r13)
    movb $0x10, 3(%r13)
    add $4, %r13
    ret

# ---------- Static Dictionary ----------

DEFWORD dict_dup,     "dup",     forth_dup,     0
DEFWORD dict_drop,    "drop",    forth_drop,    dict_dup
DEFWORD dict_swap,    "swap",    forth_swap,    dict_drop
DEFWORD dict_over,    "over",    forth_over,    dict_swap
DEFWORD dict_add,     "+",       forth_add,     dict_over
DEFWORD dict_sub,     "-",       forth_sub,     dict_add
DEFWORD dict_negate,  "negate",  forth_negate,  dict_sub
DEFWORD dict_fetch,   "@",       forth_fetch,   dict_negate
DEFWORD dict_store,   "!",       forth_store,   dict_fetch
DEFWORD dict_cfetch,  "c@",      forth_cfetch,  dict_store
DEFWORD dict_cstore,  "c!",      forth_cstore,  dict_cfetch
DEFWORD dict_emit,    "emit",    forth_emit,    dict_cstore
DEFWORD dict_key,     "key",     forth_key,     dict_emit
DEFWORD dict_accept,  "accept",  forth_accept,  dict_key
DEFWORD dict_number,  "number",  forth_number,  dict_accept
DEFWORD dict_find,       "find",       forth_find,       dict_number
DEFWORD dict_parse_word, "parse-word", forth_parse_word, dict_find
DEFWORD dict_execute,    "execute",    forth_execute,    dict_parse_word
DEFWORD dict_dot,        ".",          forth_dot,        dict_execute
DEFWORD dict_dot_s,      ".s",         forth_dot_s,      dict_dot
DEFWORD dict_bye,        "bye",        forth_bye,        dict_dot_s
DEFWORD dict_lit,        "lit",        forth_lit,        dict_bye, F_HIDDEN
DEFWORD dict_colon,      ":",          forth_colon,      dict_lit
DEFWORD dict_semicolon,  ";",          forth_semicolon,  dict_colon, F_IMMEDIATE
DEFWORD dict_immediate,  "immediate",  forth_immediate,  dict_semicolon
DEFWORD dict_mul,        "*",          forth_mul,         dict_immediate
DEFWORD dict_divmod,     "/mod",       forth_divmod,      dict_mul
DEFWORD dict_one_plus,   "1+",         forth_one_plus,    dict_divmod
DEFWORD dict_one_minus,  "1-",         forth_one_minus,   dict_one_plus
DEFWORD dict_abs,        "abs",        forth_abs,         dict_one_minus
DEFWORD dict_min,        "min",        forth_min,         dict_abs
DEFWORD dict_max,        "max",        forth_max,         dict_min
DEFWORD dict_equal,      "=",          forth_equal,       dict_max
DEFWORD dict_less,       "<",          forth_less,        dict_equal
DEFWORD dict_greater,    ">",          forth_greater,     dict_less
DEFWORD dict_zero_equal, "0=",         forth_zero_equal,  dict_greater
DEFWORD dict_zero_less,  "0<",         forth_zero_less,   dict_zero_equal
DEFWORD dict_and,        "and",        forth_and,         dict_zero_less
DEFWORD dict_or,         "or",         forth_or,          dict_and
DEFWORD dict_xor,        "xor",        forth_xor,         dict_or
DEFWORD dict_invert,     "invert",     forth_invert,      dict_xor
DEFWORD dict_rot,        "rot",        forth_rot,         dict_invert
DEFWORD dict_nip,        "nip",        forth_nip,         dict_rot
DEFWORD dict_tuck,       "tuck",       forth_tuck,        dict_nip
DEFWORD dict_two_dup,    "2dup",       forth_two_dup,     dict_tuck
DEFWORD dict_two_drop,   "2drop",      forth_two_drop,    dict_two_dup
DEFWORD dict_depth,      "depth",      forth_depth,       dict_two_drop
DEFWORD dict_question_dup, "?dup",     forth_question_dup, dict_depth
DEFWORD dict_to_r,       ">r",         forth_to_r,        dict_question_dup, F_COMPILE_ONLY
DEFWORD dict_r_from,     "r>",         forth_r_from,      dict_to_r, F_COMPILE_ONLY
DEFWORD dict_r_fetch,    "r@",         forth_r_fetch,     dict_r_from, F_COMPILE_ONLY
DEFWORD dict_tick,       "'",          forth_tick,        dict_r_fetch, F_IMMEDIATE
DEFWORD dict_paren,      "(",          forth_paren,       dict_tick, F_IMMEDIATE
DEFWORD dict_backslash,  "\\",         forth_backslash,   dict_paren, F_IMMEDIATE
DEFWORD dict_evaluate,   "evaluate",   forth_evaluate,    dict_backslash
DEFWORD dict_included,   "included",   forth_included,    dict_evaluate
DEFWORD dict_if,         "if",         forth_if,          dict_included,  F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_then,       "then",       forth_then,        dict_if,        F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_else,       "else",       forth_else,        dict_then,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_begin,      "begin",      forth_begin,       dict_else,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_until,      "until",      forth_until,       dict_begin,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_again,      "again",      forth_again,       dict_until,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_while,      "while",      forth_while,       dict_again,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_repeat,     "repeat",     forth_repeat,      dict_while,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_recurse,    "recurse",    forth_recurse,     dict_repeat,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_here,       "here",       forth_here,        dict_recurse
DEFWORD dict_allot,      "allot",      forth_allot,       dict_here
DEFWORD dict_comma,      ",",          forth_comma,       dict_allot
DEFWORD dict_c_comma,    "c,",         forth_c_comma,     dict_comma
DEFWORD dict_create,     "create",     forth_create,      dict_c_comma
DEFWORD dict_constant,   "constant",   forth_constant,    dict_create
DEFWORD dict_do,         "do",         forth_do,          dict_constant,  F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_loop,       "loop",       forth_loop,        dict_do,        F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_plus_loop,  "+loop",      forth_plus_loop,   dict_loop,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_i,          "i",          forth_i,           dict_plus_loop, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_j,          "j",          forth_j,           dict_i,         F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_unloop,     "unloop",     forth_unloop,      dict_j,         F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_leave,      "leave",      forth_leave,       dict_unloop,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_does,       "does>",      forth_does,        dict_leave,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_type,       "type",       forth_type,        dict_does
DEFWORD dict_pick,       "pick",       forth_pick,        dict_type
DEFWORD dict_s_quote,    "s\"",        forth_s_quote,     dict_pick,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_dot_quote,  ".\"",        forth_dot_quote,   dict_s_quote,   F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_s_to_d,     "s>d",        forth_s_to_d,      dict_dot_quote
DEFWORD dict_um_star,    "um*",        forth_um_star,     dict_s_to_d
DEFWORD dict_m_star,     "m*",         forth_m_star,      dict_um_star
DEFWORD dict_um_divmod,  "um/mod",     forth_um_divmod,   dict_m_star
DEFWORD dict_sm_rem,     "sm/rem",     forth_sm_rem,      dict_um_divmod
DEFWORD dict_fm_mod,     "fm/mod",     forth_fm_mod,      dict_sm_rem
DEFWORD dict_base,       "base",       forth_base,        dict_fm_mod
DEFWORD dict_pad,        "pad",        forth_pad,         dict_base
DEFWORD dict_hld,        "hld",        forth_hld,         dict_pad
DEFWORD dict_lshift,     "lshift",     forth_lshift,      dict_hld
DEFWORD dict_rshift,     "rshift",     forth_rshift,      dict_lshift
DEFWORD dict_two_div,    "2/",         forth_two_div,     dict_rshift
DEFWORD dict_u_less,     "u<",         forth_u_less,      dict_two_div
DEFWORD dict_state,      "state",      forth_state,       dict_u_less
DEFWORD dict_lbracket,   "[",          forth_left_bracket, dict_state, F_IMMEDIATE
DEFWORD dict_rbracket,   "]",          forth_right_bracket, dict_lbracket
DEFWORD dict_literal,    "literal",    forth_literal,     dict_rbracket, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_bracket_tick, "[']",      forth_bracket_tick, dict_literal, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_bracket_char, "[char]",   forth_bracket_char, dict_bracket_tick, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_exit,       "exit",       forth_exit,        dict_bracket_char, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_compile_comma, "compile,", forth_compile_comma, dict_exit
DEFWORD dict_postpone,   "postpone",   forth_postpone,    dict_compile_comma, F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_to_body,    ">body",      forth_to_body,     dict_postpone
DEFWORD dict_to_in,      ">in",        forth_to_in,       dict_to_body
DEFWORD dict_source,     "source",     forth_source,      dict_to_in
DEFWORD dict_abort,      "abort",      forth_abort,       dict_source
DEFWORD dict_quit,       "quit",       forth_quit,        dict_abort
DEFWORD dict_unused,     "unused",     forth_unused,      dict_quit
DEFWORD dict_case,       "case",       forth_case,        dict_unused,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_of,         "of",         forth_of,          dict_case,      F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_endof,      "endof",      forth_endof,       dict_of,        F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_endcase,    "endcase",    forth_endcase,     dict_endof,     F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_parse,      "parse",      forth_parse,       dict_endcase
DEFWORD dict_source_id,  "source-id",  forth_source_id,   dict_parse
DEFWORD dict_value,      "value",      forth_value,       dict_source_id
DEFWORD dict_to,         "to",         forth_to,          dict_value,     F_IMMEDIATE
DEFWORD dict_noname,     ":noname",    forth_noname,      dict_to
DEFWORD dict_question_do,"?do",        forth_question_do, dict_noname,    F_IMMEDIATE+F_COMPILE_ONLY
DEFWORD dict_words,      "words",      forth_words,       dict_question_do
DEFWORD dict_key_q,      "key?",       forth_key_q,       dict_words
DEFWORD dict_ms,         "ms",         forth_ms,          dict_key_q
DEFWORD dict_page,       "page",       forth_page,        dict_ms
DEFWORD dict_at_xy,      "at-xy",      forth_at_xy,       dict_page
DEFWORD dict_screen_w,   "screen-width",  forth_screen_w, dict_at_xy
DEFWORD dict_screen_h,   "screen-height", forth_screen_h, dict_screen_w
DEFWORD dict_ms_get,     "ms@",           forth_ms_get,    dict_screen_h
DEFWORD dict_cursor_off, "cursor-off",    forth_cursor_off, dict_ms_get
DEFWORD dict_cursor_on,  "cursor-on",     forth_cursor_on, dict_cursor_off
DEFWORD dict_include,    "include",       forth_include,   dict_cursor_on
DEFWORD dict_argc,       "argc",          forth_argc,      dict_include
DEFWORD dict_argv,       "argv",          forth_argv,      dict_argc
DEFWORD dict_arg,        "arg",           forth_arg,       dict_argv
DEFWORD dict_shift_args, "shift-args",    forth_shift_args, dict_arg
DEFWORD dict_next_arg,   "next-arg",      forth_next_arg,  dict_shift_args
DEFWORD dict_bye_code,   "bye-code",      forth_bye_code,  dict_next_arg
DEFWORD dict_write_file, "write-file",    forth_write_file, dict_bye_code
DEFWORD dict_open_file,   "open-file",    forth_open_file,   dict_write_file
DEFWORD dict_create_file, "create-file",  forth_create_file, dict_open_file
DEFWORD dict_close_file,  "close-file",   forth_close_file,  dict_create_file
DEFWORD dict_read_file,   "read-file",    forth_read_file,   dict_close_file
DEFWORD dict_file_size,   "file-size",    forth_file_size,   dict_read_file
DEFWORD dict_rename_file, "rename-file",  forth_rename_file, dict_file_size
DEFWORD dict_mmap_anon,   "(mmap-anon)",  forth_mmap_anon,   dict_rename_file
DEFWORD dict_munmap,      "(munmap)",     forth_munmap,      dict_mmap_anon
DEFWORD dict_latest_at,   "(latest@)",    forth_latest_at,   dict_munmap
DEFWORD dict_restore_dict,"(restore-dict)",forth_restore_dict,dict_latest_at
DEFWORD dict_hook_store,  "(hook!)",      forth_hook_store,  dict_restore_dict
.global dict_include
.global dict_hook_store

# ---------- Data Stack Memory ----------
# Layout (grows downward):
#   guard_page_underflow  4096 bytes — mprotect PROT_NONE at startup
#   data_stack_top (sp0)  page-aligned
#   data_stack            4096 bytes (512 cells)
#   data_stack_bottom     page-aligned
#   guard_page_overflow   4096 bytes — mprotect PROT_NONE at startup
#
# Reading past sp0 hits the underflow guard page → SIGSEGV → handler recovers.
# Writing past bottom hits the overflow guard page → SIGSEGV → handler recovers.
.bss
# Scratch buffer for BASICFORTH_PATH/filename concatenation
.align 8
incl_path_buf:
    .space 512

.balign 4096
.global guard_page_overflow
guard_page_overflow:
    .space 4096
.global data_stack_bottom
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:
.global guard_page_underflow
guard_page_underflow:
    .space 4096

# ---------- Dictionary Space ----------
.equ DICT_SPACE_SIZE, 65536     # 64KB
.balign 8
.global dict_space
dict_space:
    .space DICT_SPACE_SIZE

# ---------- Variables ----------
.data
.align 8
.global base
base:                               # NUMBER base (default decimal)
    .quad 10
.global source_addr
source_addr:                        # PARSE-WORD: pointer to input buffer
    .quad 0
.global source_len
source_len:                         # PARSE-WORD: total length of input
    .quad 0
.global to_in
to_in:                              # PARSE-WORD: current parse offset
    .quad 0
.global sp0
sp0:                                # Initial DSP value (for .S depth)
    .quad 0
.global state
state:                              # Compiler state (0=interpret, non-zero=compile)
    .quad 0
.global colon_code_len_addr
colon_code_len_addr:                # Saved code_len field address for ; to fill
    .quad 0
.global colon_dsp
colon_dsp:                          # DSP at start of : for control-flow balance check
    .quad 0
.global saved_latest
saved_latest:                       # LATEST before current : for error recovery
    .quad 0
.global saved_here
saved_here:                         # HERE before current : for error recovery
    .quad 0
.global session_hooks
session_hooks:                      # [0]=session-boot [1]=capture-line [2]=capture-reset
    .quad 0                         #   xts; 0 = not registered. Set by (hook!).
    .quad 0
    .quad 0
.global rp0
rp0:                                # Return stack pointer at repl_loop entry
    .quad 0
.global il_rsp
il_rsp:                             # RSP at interpret_line entry (for cf longjmp)
    .quad 0
.global err_token_addr
err_token_addr:                     # Address of last error token (set by interpret_line)
    .quad 0
.global err_token_len
err_token_len:                      # Length of last error token
    .quad 0
.global file_name_addr
file_name_addr:                     # Filename for INCLUDED error reporting
    .quad 0
.global file_name_len
file_name_len:
    .quad 0
.global file_line_num
file_line_num:                      # Line number for INCLUDED error reporting
    .quad 0
.global do_depth
do_depth:                           # DO nesting depth (for LEAVE validation)
    .quad 0
.global leave_count
leave_count:                        # Number of pending LEAVE patch addresses
    .quad 0
.global leave_stack
leave_stack:                        # Patch addresses for pending LEAVEs
    .space MAX_LEAVES * 8
.global hld
hld:                                # Current HOLD pointer for pictured numeric output
    .quad 0
.global source_id
source_id:                          # Input source identifier (0=keyboard, -1=EVALUATE)
    .quad 0
.equ PAD_SIZE, 68                   # 64 binary digits + sign + padding
.global pad
pad:
    .space PAD_SIZE
