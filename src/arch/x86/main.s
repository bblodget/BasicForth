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
    mov %rax, arg_count(%rip)       # mutable count behind the ARGC variable
    lea 8(%rsp), %rdx               # &argv[0]
    mov %rdx, arg_base(%rip)        # mutable base behind the ARGV variable
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
    lea dict_munmap(%rip), %r12  # LATEST

    # Initialize saved state for error recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    call platform_init_guard_pages
    # Raw terminal mode is entered lazily on the first interactive input
    # (KEY / KEY? / ACCEPT), so a script that only writes never touches the tty.

    # Initialize rp0 before any startup load, so a fault/ABORT during core.fs
    # or the script recovers onto a valid return stack (repl_loop re-saves it).
    mov %rsp, rp0(%rip)

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
    # Shift the script (argv[1]) out of the arg vector FIRST, so that while the
    # script runs its own first argument is arg[1] / the first NEXT-ARG (like
    # gforth). Loading uses start_argv1, which is independent of the vector.
    call forth_shift_args
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
    # Mark that we are running the user script: any error (a line error
    # returned here, or a fault/ABORT that recovers into repl_loop) must exit
    # non-zero instead of dropping into the REPL, like a failing Unix utility.
    movq $1, script_running(%rip)
    call forth_included
    test %rax, %rax
    jnz .Lscript_error              # line error — message already printed
    movq $0, script_running(%rip)   # script completed cleanly
.Lno_cmdline_file:

    # Print the startup banner now, only when actually entering the interactive
    # REPL — a script that ends in bye/bye-code exits before reaching here — and
    # only when stdout is a terminal, so piped/redirected output stays clean.
    # This block sits before the repl_loop label, so it runs exactly once.
    mov $1, %rdi                    # STDOUT
    call platform_isatty
    test %rax, %rax
    jz .Lno_banner
    lea version_str(%rip), %rsi
    mov $version_len, %rdx
    call platform_write
.Lno_banner:

.global repl_loop
repl_loop:
    # If a startup script faulted or ABORTed, recovery lands here with
    # script_running still set (the clean-completion path clears it first) —
    # exit non-zero rather than entering the interactive REPL.
    cmpq $0, script_running(%rip)
    jne .Lscript_error

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

# A startup script aborted — either INCLUDED returned an error for a bad line,
# or a fault/ABORT/QUIT recovered into repl_loop with script_running still set.
# Exit non-zero (silently; the diagnostic was already printed) so the script
# fails like a Unix utility instead of dropping into the REPL.
.Lscript_error:
    movq $0, script_running(%rip)
    mov $1, %rdi
    jmp platform_exit

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
# Non-zero while the startup script (argv[1]) is executing; an error during that
# window exits non-zero instead of dropping into the REPL. Only main.s uses it.
script_running:
    .quad 0
# Mutable cells exposed to Forth as the ARGC and ARGV variables. arg_base is a
# char** into the OS argv vector; NEXT-ARG / SHIFT-ARGS consume from the front.
.global arg_count
arg_count:
    .quad 0
.global arg_base
arg_base:
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
