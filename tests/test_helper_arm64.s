// BasicForth — Test Helper (ARM64)
// Bridge between C test harness and assembly primitives.
// Provides call_primitive() and platform stubs.

// call_primitive(fn, tos_in, dsp_in, tos_out_ptr, dsp_out_ptr)
//   X0 = function pointer to call
//   X1 = TOS value to set (X20)
//   X2 = DSP value to set (X19)
//   X3 = pointer to store TOS result
//   X4 = pointer to store DSP result
.global call_primitive
call_primitive:
    STP X29, X30, [SP, #-16]!
    STP X19, X20, [SP, #-16]!
    STP X21, X22, [SP, #-16]!

    // Save output pointers in unused callee-saved regs
    MOV X21, X3                 // X21 = tos_out_ptr
    MOV X22, X4                 // X22 = dsp_out_ptr

    // Save function pointer (X0 is caller-saved)
    MOV X9, X0

    // Set engine registers
    MOV X20, X1                 // TOS
    MOV X19, X2                 // DSP

    // Call the primitive
    BLR X9

    // Store results
    STR X20, [X21]              // *tos_out = TOS
    STR X19, [X22]              // *dsp_out = DSP

    LDP X21, X22, [SP], #16
    LDP X19, X20, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- Platform stubs ----------
// These satisfy linker references from core.o.
// Not exercised by unit tests.

.global platform_emit
platform_emit:
    RET

.global platform_key
platform_key:
    MOV X0, #0
    RET
