# BasicForth — Test Helper (x86-64)
# Bridge between C test harness and assembly primitives.
# Provides call_primitive() and platform stubs.

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
    push %r14
    push %r15

    # Save output pointers in callee-saved regs
    mov %rcx, %rbx              # RBX = tos_out_ptr
    mov %r8, %rbp               # RBP = dsp_out_ptr

    # Set engine registers
    mov %rsi, %r14              # TOS
    mov %rdx, %r15              # DSP

    # Call the primitive
    call *%rdi

    # Store results
    mov %r14, (%rbx)            # *tos_out = TOS
    mov %r15, (%rbp)            # *dsp_out = DSP

    pop %r15
    pop %r14
    pop %rbp
    pop %rbx
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
