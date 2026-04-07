// BasicForth — Test Helper (ARM64)
// Bridge between C test harness and assembly primitives.
// Provides call_primitive(), init_engine(), and platform stubs.

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
    STP X23, X24, [SP, #-16]!

    // Save output pointers in scratch callee-saved regs
    MOV X23, X3                 // X23 = tos_out_ptr
    MOV X24, X4                 // X24 = dsp_out_ptr

    // Save function pointer (X0 is caller-saved)
    MOV X9, X0

    // Set engine registers
    MOV X20, X1                 // TOS
    MOV X19, X2                 // DSP
    // X21 (HERE) and X22 (LATEST) preserved from init_engine

    // Call the primitive
    BLR X9

    // Store results
    STR X20, [X23]              // *tos_out = TOS
    STR X19, [X24]              // *dsp_out = DSP

    LDP X23, X24, [SP], #16
    LDP X21, X22, [SP], #16
    LDP X19, X20, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// init_engine(here_val, latest_val)
//   X0 = HERE value (X21)
//   X1 = LATEST value (X22)
.global init_engine
init_engine:
    MOV X21, X0
    MOV X22, X1
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

.global platform_write
platform_write:
    RET

.global platform_bye
platform_bye:
    RET

// Error handler stubs — set a flag so C tests can detect guard triggers.
.data
.global error_flag
error_flag:
    .quad 0                     // 0=none, 1=underflow, 2=overflow, 3=dict_full

.text
.global stack_underflow
stack_underflow:
    ADR X9, error_flag
    MOV X10, #1
    STR X10, [X9]
    RET

.global stack_overflow
stack_overflow:
    ADR X9, error_flag
    MOV X10, #2
    STR X10, [X9]
    RET

.global dict_full
dict_full:
    ADR X9, error_flag
    MOV X10, #3
    STR X10, [X9]
    RET
