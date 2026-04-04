# BasicForth — Core ASM Primitives (x86-64)
# Platform-independent x86-64 assembly. Requires platform_linux.s (or equivalent).
#
# Register allocation:
#   R15 = Data stack pointer (DSP), grows downward
#   R14 = HERE pointer (dictionary free space) — future
#   R13 = LATEST pointer (most recent dictionary entry) — future
#   RSP = Return stack
#
# R13-R15 are callee-saved in the System V AMD64 ABI,
# so C functions won't clobber them.

.equ CELL, 8                    # 64-bit cells
.equ DATA_STACK_SIZE, 4096      # 512 cells

# ---------- Data Stack ----------
# R15 = data stack pointer (DSP), grows downward
# Stack lives in .bss, starts at the top (high address)

# ---------- Primitives ----------

# DUP ( a -- a a )
.global forth_dup
forth_dup:
    mov (%r15), %rax            # peek top
    sub $CELL, %r15             # make room
    mov %rax, (%r15)            # push copy
    ret

# DROP ( a -- )
.global forth_drop
forth_drop:
    add $CELL, %r15             # discard top
    ret

# SWAP ( a b -- b a )
.global forth_swap
forth_swap:
    mov (%r15), %rax            # rax = b (top)
    mov CELL(%r15), %rdx        # rdx = a (second)
    mov %rax, CELL(%r15)        # store b in second
    mov %rdx, (%r15)            # store a on top
    ret

# OVER ( a b -- a b a )
.global forth_over
forth_over:
    mov CELL(%r15), %rax        # rax = a (second)
    sub $CELL, %r15             # make room
    mov %rax, (%r15)            # push copy of a
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
    negq (%r15)                 # negate in place
    ret

# ---------- EMIT (Forth-level) ----------
# ( char -- )
# Pops char from data stack, calls platform_emit
.global forth_emit
forth_emit:
    mov (%r15), %rdi            # RDI = char
    add $CELL, %r15             # pop
    jmp platform_emit           # tail call

# ---------- KEY (Forth-level) ----------
# ( -- char )
# Reads one character from stdin, pushes to data stack
.global forth_key
forth_key:
    call platform_key           # RDI = character
    sub $CELL, %r15             # make room
    mov %rdi, (%r15)            # push to data stack
    ret

# ---------- Data Stack Memory ----------
.bss
.align 8
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:
