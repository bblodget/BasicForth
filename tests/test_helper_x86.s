# BasicForth — Test Helper (x86-64)
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
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

.global platform_open_file
platform_open_file:
    mov $-2, %rax               # return -ENOENT
    ret

.global platform_fstat
platform_fstat:
    xor %eax, %eax
    ret

.global platform_mmap_file
platform_mmap_file:
    mov $-1, %rax               # return MAP_FAILED
    ret

.global platform_munmap
platform_munmap:
    ret

.global platform_close_file
platform_close_file:
    ret

.global platform_key_ready
platform_key_ready:
    xor %edi, %edi
    ret

.global platform_ms
platform_ms:
    ret

.global platform_page
platform_page:
    ret

.global platform_at_xy
platform_at_xy:
    ret

.global platform_screen_width
platform_screen_width:
    mov $80, %eax
    ret

.global platform_screen_height
platform_screen_height:
    mov $25, %eax
    ret

# --- Return stack test wrappers ---
# These call >R / R> / R@ within a single stack frame so the return
# stack context is correct. Called via call_primitive like any other word.

# test_to_r_r_from: ( x -- x )  round-trip through return stack
.global test_to_r_r_from
test_to_r_r_from:
    call forth_to_r             # data->return
    call forth_r_from           # return->data
    ret

# test_to_r_r_fetch_r_from: ( x -- x x )  >R R@ R> leaves copy + original
.global test_to_r_r_fetch_r_from
test_to_r_r_fetch_r_from:
    call forth_to_r             # data->return
    call forth_r_fetch          # copy to data (non-destructive)
    call forth_r_from           # return->data
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

.global repl_loop
repl_loop:
    ret
