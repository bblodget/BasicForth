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
.equ STARTUP_DIR_MAX, 1024          # buffer for the absolute startup directory

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

    # -v / --version: print the version string to stdout and exit 0, before any
    # startup work. An explicit request, so it is NOT gated on isatty (unlike the
    # banner) — `basicforth --version | cat` still prints.
    cmpq $2, start_argc(%rip)
    jl .Lno_version_flag
    mov start_argv1(%rip), %rdi
    lea opt_v(%rip), %rsi
    call cstr_eq
    test %rax, %rax
    jnz .Lprint_version
    mov start_argv1(%rip), %rdi
    lea opt_version(%rip), %rsi
    call cstr_eq
    test %rax, %rax
    jz .Lno_version_flag
.Lprint_version:
    lea version_str(%rip), %rsi
    mov $version_len, %rdx
    call platform_write             # stdout
    xor %edi, %edi                  # exit status 0
    jmp platform_exit
.Lno_version_flag:

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

    # Walk envp again for BASICFORTH_SESSION= (override the default isatty gate
    # for the interactive session: =0 forces off, any other value forces on).
    movq $0, session_env(%rip)      # 0 = unset (use default isatty gate)
    mov start_argc(%rip), %rcx
    lea 16(%rsp,%rcx,8), %rdi       # &envp[0]
.Lsenv_loop:
    mov (%rdi), %rsi                # envp[i]
    test %rsi, %rsi
    jz .Lsenv_done                  # NULL = end of envp
    lea sess_prefix(%rip), %rdx
    mov $sess_prefix_len, %ecx
.Lsenv_cmp:
    test %ecx, %ecx
    jz .Lsenv_found                 # prefix matched
    movzbl (%rsi), %eax
    cmpb (%rdx), %al
    jne .Lsenv_next
    inc %rsi
    inc %rdx
    dec %ecx
    jmp .Lsenv_cmp
.Lsenv_next:
    add $8, %rdi
    jmp .Lsenv_loop
.Lsenv_found:
    movzbl (%rsi), %eax             # first byte of the value
    cmpb $'0', %al
    je .Lsenv_off
    movq $1, session_env(%rip)      # non-'0' → force on
    jmp .Lsenv_done
.Lsenv_off:
    movq $2, session_env(%rip)      # '0' → force off
.Lsenv_done:

    # Walk envp again for BASICFORTH_EDITOR= (override the default isatty gate for
    # the line editor: =0 forces off, any other value forces on). Same pattern.
    movq $0, editor_env(%rip)       # 0 = unset (use default isatty gate)
    mov start_argc(%rip), %rcx
    lea 16(%rsp,%rcx,8), %rdi       # &envp[0]
.Leenv_loop:
    mov (%rdi), %rsi                # envp[i]
    test %rsi, %rsi
    jz .Leenv_done                  # NULL = end of envp
    lea edit_prefix(%rip), %rdx
    mov $edit_prefix_len, %ecx
.Leenv_cmp:
    test %ecx, %ecx
    jz .Leenv_found                 # prefix matched
    movzbl (%rsi), %eax
    cmpb (%rdx), %al
    jne .Leenv_next
    inc %rsi
    inc %rdx
    dec %ecx
    jmp .Leenv_cmp
.Leenv_next:
    add $8, %rdi
    jmp .Leenv_loop
.Leenv_found:
    movzbl (%rsi), %eax             # first byte of the value
    cmpb $'0', %al
    je .Leenv_off
    movq $1, editor_env(%rip)       # non-'0' → force on
    jmp .Leenv_done
.Leenv_off:
    movq $2, editor_env(%rip)       # '0' → force off
.Leenv_done:

    # Walk envp again for BASICFORTH_DOCS= (colon-separated docs directories, used
    # by the help system: man / topics / apropos). Same pattern as the PATH walk.
    mov start_argc(%rip), %rcx
    lea 16(%rsp,%rcx,8), %rdi       # RDI = &envp[0]
.Ldenv_loop:
    mov (%rdi), %rsi
    test %rsi, %rsi
    jz .Ldenv_done
    lea docs_prefix(%rip), %rdx
    mov $docs_prefix_len, %ecx
.Ldenv_cmp:
    test %ecx, %ecx
    jz .Ldenv_found
    movzbl (%rsi), %eax
    cmpb (%rdx), %al
    jne .Ldenv_next
    inc %rsi
    inc %rdx
    dec %ecx
    jmp .Ldenv_cmp
.Ldenv_next:
    add $8, %rdi
    jmp .Ldenv_loop
.Ldenv_found:
    mov %rsi, basicforth_docs(%rip) # value (past "BASICFORTH_DOCS=")
    mov %rsi, %rdi
    xor %ecx, %ecx
.Ldenv_strlen:
    cmpb $0, (%rdi,%rcx)
    je .Ldenv_strlen_done
    inc %ecx
    jmp .Ldenv_strlen
.Ldenv_strlen_done:
    movslq %ecx, %rax
    mov %rax, basicforth_docs_len(%rip)
.Ldenv_done:

    # Walk envp again for HOME= (used by `cd ~`). Same pattern as the DOCS walk;
    # home_ptr points into the env string (valid for the process lifetime).
    mov start_argc(%rip), %rcx
    lea 16(%rsp,%rcx,8), %rdi       # RDI = &envp[0]
.Lhenv_loop:
    mov (%rdi), %rsi
    test %rsi, %rsi
    jz .Lhenv_done
    lea home_prefix(%rip), %rdx
    mov $home_prefix_len, %ecx
.Lhenv_cmp:
    test %ecx, %ecx
    jz .Lhenv_found
    movzbl (%rsi), %eax
    cmpb (%rdx), %al
    jne .Lhenv_next
    inc %rsi
    inc %rdx
    dec %ecx
    jmp .Lhenv_cmp
.Lhenv_next:
    add $8, %rdi
    jmp .Lhenv_loop
.Lhenv_found:
    mov %rsi, home_ptr(%rip)        # value (past "HOME=")
    mov %rsi, %rdi
    xor %ecx, %ecx
.Lhenv_strlen:
    cmpb $0, (%rdi,%rcx)
    je .Lhenv_strlen_done
    inc %ecx
    jmp .Lhenv_strlen
.Lhenv_strlen_done:
    movslq %ecx, %rax
    mov %rax, home_len(%rip)
.Lhenv_done:

    # Capture the absolute startup directory, so `cd` with no argument can return
    # here and session.fs stays pinned to it no matter where a later `cd` goes.
    # Done before core.fs loads, while the CWD is still the launch directory.
    lea startup_dir(%rip), %rdi
    mov $STARTUP_DIR_MAX, %rsi
    call platform_getcwd            # RAX = bytes incl NUL, or -errno
    test %rax, %rax
    jle .Lno_startup_dir            # getcwd failed -> leave length 0
    dec %rax                        # drop the trailing NUL
    mov %rax, startup_dir_len(%rip)
.Lno_startup_dir:

    # Initialize engine registers
    lea data_stack_top(%rip), %r15  # DSP = sp0 (empty stack)
    mov %r15, sp0(%rip)             # save initial DSP for .S / guards
    lea dict_space(%rip), %r13      # HERE
    lea dict_mmap_dev(%rip), %r12   # LATEST (head of the built-in dictionary chain)

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
    movq $0, incl_opened(%rip)      # forth_included sets this to 1 iff it opens a file
    lea core_fs_name(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)                # push c-addr
    sub $CELL, %r15
    movq $core_fs_len, (%r15)       # push length
    call forth_included

    # Warn (to stderr) if core.fs was not found. forth_included returns 0 for a
    # not-found file (silent skip), so the return value can't tell us — but it
    # sets incl_opened only when it actually opens a file. If it's still 0, core.fs
    # was reachable nowhere (CWD or BASICFORTH_PATH), so the user has only the
    # assembly primitives (no CR, IF, ., etc.) — surface it instead of failing
    # mysteriously. (An empty/comment-only core.fs still opens, so it won't warn.)
    cmpq $0, incl_opened(%rip)
    jne .Lcore_loaded
    mov $2, %rdi                    # fd 2 = stderr
    lea warn_no_core(%rip), %rsi
    mov $warn_no_core_len, %rdx
    call platform_write_fd
.Lcore_loaded:

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
    jz .Lcmdline_done               # loaded cleanly
    # Load error. Drop to the REPL only when we'll be interactive (same rule as
    # the session below: BASICFORTH_SESSION=1, or unset and stdin is a terminal),
    # so a broken module can be fixed in place. A script/pipe exits non-zero, like
    # a failing Unix utility.
    cmpq $2, session_env(%rip)
    je .Lscript_error               # BASICFORTH_SESSION=0 → exit
    cmpq $1, session_env(%rip)
    je .Lcmdline_done               # BASICFORTH_SESSION=1 → drop to the REPL
    xor %edi, %edi
    call platform_isatty
    test %rax, %rax
    jz .Lscript_error               # not a terminal → exit
.Lcmdline_done:
    movq $0, script_running(%rip)   # done loading (clean, or interactive recovery)
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

    # ---- Interactive session: capture, seeded from the startup file if any ----
    # On when BASICFORTH_SESSION forces it on, or stdin is a terminal. A file
    # argument no longer disables it: we drop to the REPL with capture on and the
    # log seeded from that file (named-file model — there is no magic session.fs).
    movq $0, session_active(%rip)
    cmpq $2, session_env(%rip)
    je .Lsession_decided            # BASICFORTH_SESSION=0 → forced off
    cmpq $1, session_env(%rip)
    je .Lsession_on                 # BASICFORTH_SESSION=1 → forced on
    xor %edi, %edi                  # else default: is stdin a terminal?
    call platform_isatty
    test %rax, %rax
    jz .Lsession_decided
.Lsession_on:
    movq $1, session_active(%rip)
    # Call session-init ( c-addr u -- ) with the startup file path, or ( 0 0 ) if
    # no file argument was given. The hook records the -session restore point,
    # sets the current file, and seeds the log from it.
    cmpq $2, start_argc(%rip)
    jl .Lsess_nofile
    mov start_argv1(%rip), %rsi     # RSI = path
    xor %ecx, %ecx                  # ECX = strlen
.Lsess_arglen:
    cmpb $0, (%rsi,%rcx)
    je .Lsess_arglen_done
    inc %ecx
    jmp .Lsess_arglen
.Lsess_arglen_done:
    sub $CELL, %r15
    mov %rsi, (%r15)                # push c-addr
    sub $CELL, %r15
    movslq %ecx, %rax
    mov %rax, (%r15)                # push length
    jmp .Lsess_init
.Lsess_nofile:
    sub $CELL, %r15
    movq $0, (%r15)                 # push 0  (no file)
    sub $CELL, %r15
    movq $0, (%r15)                 # push 0
.Lsess_init:
    mov session_hooks+0(%rip), %rax # [0] = session-init ( c-addr u -- )
    test %rax, %rax
    jnz .Lsess_call
    add $(2*CELL), %r15             # no hook registered → drop the 2 args
    jmp .Lsession_decided
.Lsess_call:
    call *%rax
.Lsession_decided:

    # Resolve once whether the line editor engages. BASICFORTH_EDITOR overrides
    # the default: =0 forces off, any other value forces on; unset → the editor
    # engages only when stdin is an interactive terminal (so piped/redirected
    # stdin uses forth_accept and script loading / integration tests are
    # unchanged).
    cmpq $2, editor_env(%rip)
    je .Linput_off
    cmpq $1, editor_env(%rip)
    je .Linput_on
    xor %edi, %edi                  # STDIN
    call platform_isatty
    mov %rax, input_interactive(%rip)
    jmp .Linput_done
.Linput_on:
    movq $1, input_interactive(%rip)
    jmp .Linput_done
.Linput_off:
    movq $0, input_interactive(%rip)
.Linput_done:

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

    # Session capture: discard any pending partial definition left over from a
    # prior line error or fault (the hook drops it only when STATE = interpret).
    cmpq $0, session_active(%rip)
    je .Lno_reset
    mov session_hooks+16(%rip), %rax   # [2] = capture-reset
    test %rax, %rax
    jz .Lno_reset
    sub $CELL, %r15
    mov %r12, (%r15)                   # push LATEST ( latest -- )
    call *%rax
.Lno_reset:

    # Print prompt — a continuation prompt ("... ") while a definition is open
    # (STATE compiling), otherwise the normal "> ". The line editor's scroll
    # margin tracks STATE the same way (so the two stay aligned).
    cmpq $0, state(%rip)
    je .Lprompt_normal
    lea cont_prompt_msg(%rip), %rsi
    mov $cont_prompt_len, %rdx
    jmp .Lprompt_show
.Lprompt_normal:
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
.Lprompt_show:
    call platform_write

    # Read a line ( c-addr max -- count ). When stdin is interactive and the
    # line-editor hook (slot 3) is registered, use it; otherwise fall back to the
    # plain asm forth_accept (piped input, and the window before core.fs runs).
    lea input_buf(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)                # push c-addr
    sub $CELL, %r15
    movq $INPUT_BUF_SIZE, (%r15)    # push max
    cmpq $0, input_interactive(%rip)
    je .Lrepl_accept
    mov session_hooks+24(%rip), %rax   # [3] = line-editor (edit-line)
    test %rax, %rax
    jz .Lrepl_accept
    call *%rax                      # ( c-addr max -- count )
    jmp .Lrepl_have_line
.Lrepl_accept:
    call forth_accept               # ( c-addr max -- count )
.Lrepl_have_line:

    # Empty line → re-prompt (count == 0)
    mov (%r15), %rax
    test %rax, %rax
    jz repl_empty

    # Set up source variables for PARSE-WORD
    mov (%r15), %rax                # count
    mov %rax, source_len(%rip)
    mov %rax, cap_line_len(%rip)    # remember raw line length for session capture
    lea input_buf(%rip), %rax
    mov %rax, source_addr(%rip)
    movq $0, to_in(%rip)

    # Drop count
    add $CELL, %r15

    # Interpret the line
    call forth_interpret_line
    test %rax, %rax
    jnz repl_error

    # Session capture: hand the raw line to (capture-line) ( c-addr u -- ).
    cmpq $0, session_active(%rip)
    je .Lno_cap_line
    mov session_hooks+8(%rip), %rax    # [1] = capture-line
    test %rax, %rax
    jz .Lno_cap_line
    lea input_buf(%rip), %rdx
    sub $CELL, %r15
    mov %rdx, (%r15)                    # push c-addr = input_buf
    mov cap_line_len(%rip), %rdx
    sub $CELL, %r15
    mov %rdx, (%r15)                    # push u = line length
    sub $CELL, %r15
    mov %r12, (%r15)                    # push LATEST
    call *%rax                          # (capture-line) ( c-addr u latest -- )
.Lno_cap_line:

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

# cstr_eq ( RDI=a RSI=b -- RAX=1 if equal else 0 ) — compare null-terminated
# strings byte for byte. Used to recognize the -v / --version option.
cstr_eq:
.Lce_loop:
    movzbl (%rdi), %eax
    movzbl (%rsi), %ecx
    cmpb %cl, %al
    jne .Lce_ne
    testb %al, %al
    jz .Lce_eq                      # both hit NUL at the same spot → equal
    inc %rdi
    inc %rsi
    jmp .Lce_loop
.Lce_eq:
    mov $1, %eax
    ret
.Lce_ne:
    xor %eax, %eax
    ret

# (version-str) ( -- c-addr u ) — push the version/banner string. Backs the
# Forth `version` word; defined here so it can see version_str/version_len.
.global forth_version_str
forth_version_str:
    lea version_str(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)                # c-addr
    sub $CELL, %r15
    movq $version_len, (%r15)       # u
    ret

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
cont_prompt_msg: .ascii "... "
.equ cont_prompt_len, . - cont_prompt_msg
ok_msg:     .ascii " ok\n"
.equ ok_len, . - ok_msg
err_msg:    .ascii "? "
.equ err_len, . - err_msg
msg_dict_full:  .ascii "dictionary full\n"
.equ msg_dict_full_len, . - msg_dict_full
core_fs_name:   .ascii "core.fs"
.equ core_fs_len, . - core_fs_name
warn_no_core:   .ascii "basicforth: core.fs not found - only built-in primitives are available.\n  Set BASICFORTH_PATH to the directory containing core.fs.\n"
.equ warn_no_core_len, . - warn_no_core
session_fs_name: .ascii "session.fs"
.equ session_fs_len, . - session_fs_name
env_prefix:     .ascii "BASICFORTH_PATH="
.equ env_prefix_len, . - env_prefix
sess_prefix:    .ascii "BASICFORTH_SESSION="
.equ sess_prefix_len, . - sess_prefix
edit_prefix:    .ascii "BASICFORTH_EDITOR="
.equ edit_prefix_len, . - edit_prefix
docs_prefix:    .ascii "BASICFORTH_DOCS="
.equ docs_prefix_len, . - docs_prefix
home_prefix:    .ascii "HOME="
.equ home_prefix_len, . - home_prefix
opt_v:          .asciz "-v"
opt_version:    .asciz "--version"

.data
.align 8
start_argc:
    .quad 0
start_argv1:
    .quad 0
# Interactive-session state. session_env: 0=unset, 1=force on, 2=force off (from
# BASICFORTH_SESSION). session_active: resolved on/off for this run. cap_line_len:
# length of the current REPL line, saved for the capture hook.
session_env:
    .quad 0
# Line-editor override: 0=unset (default isatty gate), 1=force on, 2=force off
# (from BASICFORTH_EDITOR). Lets the integration suite drive the editor over a
# pipe, where stdin is not a tty.
editor_env:
    .quad 0
session_active:
    .quad 0
cap_line_len:
    .quad 0
# Non-zero while the startup script (argv[1]) is executing; an error during that
# window exits non-zero instead of dropping into the REPL. Only main.s uses it.
script_running:
    .quad 0
# Non-zero when stdin is an interactive terminal (resolved once at startup). The
# REPL engages the line-editor hook (session_hooks[3]) only then; piped input
# falls back to the plain forth_accept.
input_interactive:
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
# BASICFORTH_DOCS value pointer + length (the help system's docs search path).
.global basicforth_docs
basicforth_docs:
    .quad 0
.global basicforth_docs_len
basicforth_docs_len:
    .quad 0
# Length of the captured absolute startup directory (0 if getcwd failed at boot).
.global startup_dir_len
startup_dir_len:
    .quad 0
# HOME environment value (pointer into envp) + its length, for `cd ~`. 0 = unset.
.global home_ptr
home_ptr:
    .quad 0
.global home_len
home_len:
    .quad 0

.bss
.align 8
input_buf:
    .space INPUT_BUF_SIZE
# Absolute startup directory, captured once at boot (NUL-terminated by getcwd).
.global startup_dir
startup_dir:
    .space STARTUP_DIR_MAX
