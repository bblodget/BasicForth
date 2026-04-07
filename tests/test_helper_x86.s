# BasicForth — Test Helper (x86-64)
# Bridge between C test harness and assembly primitives.
# Provides call_primitive(), init_engine(), and platform/error stubs.
#
# Pure memory stack model:
#   R15 = DSP (points to top item, or sp0 when empty)
#   R13 = HERE, R12 = LATEST

# call_primitive(fn, dsp_in, dsp_out_ptr)
#   RDI = function pointer to call
#   RSI = DSP value to set (R15)
#   RDX = pointer to store DSP result
.global call_primitive
call_primitive:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15

    # Save output pointer in callee-saved reg
    mov %rdx, %rbx              # RBX = dsp_out_ptr

    # Set engine registers
    mov %rsi, %r15              # DSP
    # R13 (HERE) and R12 (LATEST) preserved from init_engine

    # Call the primitive
    call *%rdi

    # Store result
    mov %r15, (%rbx)            # *dsp_out = DSP

    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret

# init_engine(here_val, latest_val)
#   RDI = HERE value (R13)
#   RSI = LATEST value (R12)
.global init_engine
init_engine:
    mov %rdi, %r13
    mov %rsi, %r12
    ret

# ---------- Platform stubs ----------
# These satisfy linker references from core.o.
# Not exercised by unit tests.

.global platform_emit
platform_emit:
    ret

.global platform_key
platform_key:
    xor %edi, %edi
    ret

.global platform_write
platform_write:
    ret

.global platform_bye
platform_bye:
    ret

# Error handler stubs for test harness.
# Guard pages don't exist in the test binary, so stack_underflow/overflow
# are stubs. dict_full is still used by CHECK_DICT.
.data
.global error_flag
error_flag:
    .quad 0                     # 0=none, 1=underflow, 2=overflow, 3=dict_full

.text
.global stack_underflow
stack_underflow:
    movq $1, error_flag(%rip)
    ret

.global stack_overflow
stack_overflow:
    movq $2, error_flag(%rip)
    ret

.global dict_full
dict_full:
    movq $3, error_flag(%rip)
    ret
