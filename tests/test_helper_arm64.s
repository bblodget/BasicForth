// BasicForth — Test Helper (ARM64)
// Copyright (C) 2026 Brandon Blodget
// SPDX-License-Identifier: GPL-2.0-only
//
// Bridge between C test harness and assembly primitives.
// Provides call_primitive(), init_engine(), and platform/error stubs.
//
// Pure memory stack model:
//   X19 = DSP (points to top item, or sp0 when empty)
//   X21 = HERE, X22 = LATEST

// call_primitive(fn, dsp_in, dsp_out_ptr)
//   X0 = function pointer to call
//   X1 = DSP value to set (X19)
//   X2 = pointer to store DSP result
.global call_primitive
call_primitive:
    STP X29, X30, [SP, #-16]!
    STP X19, X20, [SP, #-16]!
    STP X21, X22, [SP, #-16]!
    STP X23, X24, [SP, #-16]!

    // Save output pointer in callee-saved reg
    MOV X23, X2                 // X23 = dsp_out_ptr

    // Set engine registers
    MOV X19, X1                 // DSP
    // X21 (HERE) and X22 (LATEST) preserved from init_engine

    // Call the primitive
    BLR X0

    // Store result
    STR X19, [X23]              // *dsp_out = DSP

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

.global platform_emit
platform_emit:
    RET

.global platform_key
platform_key:
    MOV X0, #0
    RET

.global platform_raw_mode
platform_raw_mode:
    RET

.global platform_write
platform_write:
    RET

.global platform_write_fd
platform_write_fd:
    RET

.global platform_bye
platform_bye:
    RET

.global platform_exit
platform_exit:
    RET

.global platform_open_file
platform_open_file:
    MOV X0, #-2                     // return -ENOENT
    RET

.global platform_open_file_mode
platform_open_file_mode:
    MOV X0, #-2                     // return -ENOENT
    RET

.global platform_create_file
platform_create_file:
    MOV X0, #-2                     // return -ENOENT
    RET

.global platform_read_file
platform_read_file:
    MOV X0, #0                      // return 0 (EOF)
    RET

.global platform_fstat
platform_fstat:
    MOV X0, #0
    RET

.global platform_mmap_file
platform_mmap_file:
    MOV X0, #-1                     // return MAP_FAILED
    RET

.global platform_mmap_anon
platform_mmap_anon:
    MOV X0, #-1                     // return MAP_FAILED
    RET

.global platform_munmap
platform_munmap:
    RET

.global platform_close_file
platform_close_file:
    RET

.global platform_key_ready
platform_key_ready:
    MOV X0, #0
    RET

.global platform_ms
platform_ms:
    RET

.global platform_page
platform_page:
    RET

.global platform_at_xy
platform_at_xy:
    RET

.global platform_screen_width
platform_screen_width:
    MOV X0, #80
    RET

.global platform_screen_height
platform_screen_height:
    MOV X0, #25
    RET

// BASICFORTH_PATH variables (defined in main.s, needed by forth_included)
.data
.align 3
.global basicforth_path
basicforth_path:
    .quad 0
.global basicforth_path_len
basicforth_path_len:
    .quad 0
.global arg_count
arg_count:
    .quad 0
.global arg_base
arg_base:
    .quad 0

.text
.global platform_ms_get
platform_ms_get:
    MOV X0, #12345
    RET

.global platform_cursor_off
platform_cursor_off:
    RET

.global platform_cursor_on
platform_cursor_on:
    RET

// I-cache flush for compiled code (same as platform_linux.s).
// Needed by compiler tests that execute code written to dict_space.
// Reads CTR_EL0 to determine cache line sizes (varies by CPU).
.global platform_flush_icache
platform_flush_icache:
    MRS X3, CTR_EL0
    UBFX X4, X3, #16, #4
    MOV X5, #4
    LSL X4, X5, X4                  // X4 = D-cache line size
    MOV X2, X0
1:  DC CVAU, X2
    ADD X2, X2, X4
    CMP X2, X1
    B.LO 1b
    DSB ISH
    UBFX X4, X3, #0, #4
    LSL X4, X5, X4                  // X4 = I-cache line size
    MOV X2, X0
2:  IC IVAU, X2
    ADD X2, X2, X4
    CMP X2, X1
    B.LO 2b
    DSB ISH
    ISB
    RET

// --- Return stack test wrappers ---
// These call >R / R> / R@ within a single stack frame so the return
// stack context is correct. Called via call_primitive like any other word.

// test_to_r_r_from: ( x -- x )  round-trip through return stack
.global test_to_r_r_from
test_to_r_r_from:
    STP X29, X30, [SP, #-16]!
    BL forth_to_r               // data->return
    BL forth_r_from             // return->data
    LDP X29, X30, [SP], #16
    RET

// test_to_r_r_fetch_r_from: ( x -- x x )  >R R@ R> leaves copy + original
.global test_to_r_r_fetch_r_from
test_to_r_r_fetch_r_from:
    STP X29, X30, [SP, #-16]!
    BL forth_to_r               // data->return
    BL forth_r_fetch            // copy to data (non-destructive)
    BL forth_r_from             // return->data
    LDP X29, X30, [SP], #16
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

.global repl_loop
repl_loop:
    RET
