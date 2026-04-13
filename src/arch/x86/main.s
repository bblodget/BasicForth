# BasicForth — Outer Interpreter (x86-64)
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Register convention (pure memory stack):
#   R15 = DSP (data stack pointer, points to top item; equals sp0 when empty)
#   R13 = HERE (next free byte in dictionary)
#   R12 = LATEST (most recent dictionary entry)
#   RSP = Return stack
#
# R14 is free (no longer used for TOS).

.include "version.inc"

.global _start

.equ CELL, 8
.equ INPUT_BUF_SIZE, 256

_start:
    # Save argc and argv[1] before stack is used for anything else
    # Linux _start stack: [RSP]=argc, [RSP+8]=argv[0], [RSP+16]=argv[1]
    # envp starts at [RSP + (argc+2)*8]
    mov (%rsp), %rax
    mov %rax, start_argc(%rip)
    cmp $2, %rax
    jl .Lno_argv1
    mov 16(%rsp), %rax
    mov %rax, start_argv1(%rip)
.Lno_argv1:

    # Walk envp to find BASICFORTH_PATH=
    mov start_argc(%rip), %rcx
    lea 16(%rsp,%rcx,8), %rdi       # RDI = &envp[0]
.Lenv_loop:
    mov (%rdi), %rsi                # RSI = envp[i]
    test %rsi, %rsi
    jz .Lenv_done                   # NULL = end of envp
    # Compare prefix "BASICFORTH_PATH="
    lea env_prefix(%rip), %rdx
    mov $env_prefix_len, %ecx
.Lenv_cmp:
    test %ecx, %ecx
    jz .Lenv_found                  # prefix matched
    movzbl (%rsi), %eax
    cmpb (%rdx), %al
    jne .Lenv_next
    inc %rsi
    inc %rdx
    dec %ecx
    jmp .Lenv_cmp
.Lenv_next:
    add $8, %rdi
    jmp .Lenv_loop
.Lenv_found:
    # RSI now points past "BASICFORTH_PATH=" — the value
    mov %rsi, basicforth_path(%rip)
    # Compute length
    mov %rsi, %rdi
    xor %ecx, %ecx
.Lenv_strlen:
    cmpb $0, (%rdi,%rcx)
    je .Lenv_strlen_done
    inc %ecx
    jmp .Lenv_strlen
.Lenv_strlen_done:
    movslq %ecx, %rax
    mov %rax, basicforth_path_len(%rip)
.Lenv_done:

    # Initialize engine registers
    lea data_stack_top(%rip), %r15  # DSP = sp0 (empty stack)
    mov %r15, sp0(%rip)             # save initial DSP for .S / guards
    lea dict_space(%rip), %r13      # HERE
    lea dict_include(%rip), %r12    # LATEST

    # Initialize saved state for error recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    call platform_init_guard_pages
    call platform_raw_mode

    # Print startup banner
    lea version_str(%rip), %rsi
    mov $version_len, %rdx
    call platform_write

    # Try to load core.fs (silent skip if not found)
    lea core_fs_name(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)                # push c-addr
    sub $CELL, %r15
    movq $core_fs_len, (%r15)       # push length
    call forth_included

    # If argv[1] was given, load it as a Forth source file
    cmpq $2, start_argc(%rip)
    jl .Lno_cmdline_file
    # Find string length (null-terminated argv)
    mov start_argv1(%rip), %rdi
    mov %rdi, %rsi                  # RSI = start of string
    xor %ecx, %ecx
.Largv_len:
    cmpb $0, (%rdi,%rcx)
    je .Largv_len_done
    inc %ecx
    jmp .Largv_len
.Largv_len_done:
    # Push ( c-addr u ) and call INCLUDED
    sub $CELL, %r15
    mov %rsi, (%r15)                # push c-addr
    sub $CELL, %r15
    movslq %ecx, %rax
    mov %rax, (%r15)                # push length
    call forth_included
.Lno_cmdline_file:

.global repl_loop
repl_loop:
    # Save return stack pointer for error recovery
    mov %rsp, rp0(%rip)

    # Save LATEST and HERE for guard page recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    # Print prompt
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
    call platform_write

    # ACCEPT ( c-addr max -- count )
    lea input_buf(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)                # push c-addr
    sub $CELL, %r15
    movq $INPUT_BUF_SIZE, (%r15)    # push max
    call forth_accept               # ( c-addr max -- count )

    # Empty line → re-prompt (count == 0)
    mov (%r15), %rax
    test %rax, %rax
    jz repl_empty

    # Set up source variables for PARSE-WORD
    mov (%r15), %rax                # count
    mov %rax, source_len(%rip)
    lea input_buf(%rip), %rax
    mov %rax, source_addr(%rip)
    movq $0, to_in(%rip)

    # Drop count
    add $CELL, %r15

    # Interpret the line
    call forth_interpret_line
    test %rax, %rax
    jnz repl_error

    # Success — print " ok\n"
    lea ok_msg(%rip), %rsi
    mov $ok_len, %rdx
    call platform_write
    jmp repl_loop

repl_error:
    # Print "? " + token + newline
    lea err_msg(%rip), %rsi
    mov $err_len, %rdx
    call platform_write

    mov err_token_len(%rip), %rdx
    mov err_token_addr(%rip), %rsi
    call platform_write

    mov $'\n', %rdi
    call platform_emit
    jmp repl_loop

repl_empty:
    add $CELL, %r15                 # drop 0 count
    jmp repl_loop

repl_bye:
    add $CELL, %r15                 # drop 0 count
    jmp forth_bye

# ---------- Error Handlers ----------
# Stack underflow/overflow are caught by guard pages (SIGSEGV handler
# in platform_linux.s). Only dict_full remains as an explicit handler.

.global dict_full
dict_full:
    lea msg_dict_full(%rip), %rsi
    mov $msg_dict_full_len, %rdx
    call platform_write

    # Reset return stack and data stack
    mov rp0(%rip), %rsp
    mov sp0(%rip), %r15

    # If we were compiling, abort the definition
    cmpq $0, state(%rip)
    je repl_loop
    movq $0, state(%rip)
    mov saved_latest(%rip), %r12
    mov saved_here(%rip), %r13

    jmp repl_loop

# ---------- Data ----------
.section .rodata
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
ok_msg:     .ascii " ok\n"
.equ ok_len, . - ok_msg
err_msg:    .ascii "? "
.equ err_len, . - err_msg
msg_dict_full:  .ascii "dictionary full\n"
.equ msg_dict_full_len, . - msg_dict_full
core_fs_name:   .ascii "core.fs"
.equ core_fs_len, . - core_fs_name
env_prefix:     .ascii "BASICFORTH_PATH="
.equ env_prefix_len, . - env_prefix

.data
.align 8
start_argc:
    .quad 0
start_argv1:
    .quad 0
.global basicforth_path
basicforth_path:
    .quad 0
.global basicforth_path_len
basicforth_path_len:
    .quad 0

.bss
.align 8
input_buf:
    .space INPUT_BUF_SIZE
