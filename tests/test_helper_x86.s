# BasicForth — Test Helper (x86-64)
# Bridge between C test harness and assembly primitives.
# Provides call_primitive(), init_engine(), and platform stubs.

# call_primitive(fn, tos_in, dsp_in, tos_out_ptr, dsp_out_ptr)
#   RDI = function pointer to call
#   RSI = TOS value to set (R14)
#   RDX = DSP value to set (R15)
#   RCX = pointer to store TOS result
#   R8  = pointer to store DSP result
.global call_primitive
call_primitive:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15

    # Save output pointers in callee-saved regs
    mov %rcx, %rbx              # RBX = tos_out_ptr
    mov %r8, %rbp               # RBP = dsp_out_ptr

    # Set engine registers
    mov %rsi, %r14              # TOS
    mov %rdx, %r15              # DSP
    # R13 (HERE) and R12 (LATEST) preserved from init_engine

    # Call the primitive
    call *%rdi

    # Store results
    mov %r14, (%rbx)            # *tos_out = TOS
    mov %r15, (%rbp)            # *dsp_out = DSP

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
