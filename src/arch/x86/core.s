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

# ---------- Data Stack Memory ----------
.bss
.align 8
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:
