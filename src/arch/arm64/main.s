// BasicForth — Outer Interpreter (ARM64)
// Copyright (C) 2026 Brandon Blodget
// SPDX-License-Identifier: GPL-2.0-only
//
// Register convention (pure memory stack):
//   X19 = DSP (data stack pointer, points to top item; equals sp0 when empty)
//   X21 = HERE (next free byte in dictionary)
//   X22 = LATEST (most recent dictionary entry)
//   SP  = Return stack
//
// X20 is free (no longer used for TOS).

.include "version.inc"

.global _start

.equ CELL, 8
.equ INPUT_BUF_SIZE, 256
.equ STARTUP_DIR_MAX, 1024          // buffer for the absolute startup directory

_start:
    // Save argc and argv[1] before stack is used for anything else
    // Linux _start stack: [SP]=argc, [SP+8]=argv[0], [SP+16]=argv[1]
    // envp starts at [SP + (argc+2)*8]
    LDR X9, [SP]
    ADR X10, start_argc
    STR X9, [X10]
    ADR X10, arg_count
    STR X9, [X10]                   // mutable count behind the ARGC variable
    ADD X11, SP, #8                 // &argv[0]
    ADR X10, arg_base
    STR X11, [X10]                  // mutable base behind the ARGV variable
    CMP X9, #2
    B.LT .Lno_argv1
    LDR X9, [SP, #16]
    ADR X10, start_argv1
    STR X9, [X10]
.Lno_argv1:

    // -v / --version: print the version string to stdout and exit 0, before any
    // startup work. An explicit request, so it is NOT gated on isatty (unlike the
    // banner) — `basicforth --version | cat` still prints.
    ADR X9, start_argc
    LDR X9, [X9]
    CMP X9, #2
    B.LT .Lno_version_flag
    ADR X9, start_argv1
    LDR X0, [X9]
    ADR X1, opt_v
    BL cstr_eq
    CBNZ X0, .Lprint_version
    ADR X9, start_argv1
    LDR X0, [X9]
    ADR X1, opt_version
    BL cstr_eq
    CBZ X0, .Lno_version_flag
.Lprint_version:
    ADR X0, version_str
    MOV X1, #version_len
    BL platform_write               // stdout
    MOV X0, #0                      // exit status 0
    B platform_exit
.Lno_version_flag:

    // Walk envp to find BASICFORTH_PATH=
    LDR X0, [SP]                    // argc
    ADD X0, X0, #2                  // skip argc + NULL terminator
    LSL X0, X0, #3                  // *8
    ADD X0, SP, X0                  // X0 = &envp[0]
.Lenv_loop:
    LDR X1, [X0]                    // X1 = envp[i]
    CBZ X1, .Lenv_done              // NULL = end
    // Compare prefix "BASICFORTH_PATH="
    ADR X2, env_prefix
    MOV X3, #env_prefix_len
.Lenv_cmp:
    CBZ X3, .Lenv_found             // prefix matched
    LDRB W4, [X1], #1
    LDRB W5, [X2], #1
    CMP W4, W5
    B.NE .Lenv_next
    SUB X3, X3, #1
    B .Lenv_cmp
.Lenv_next:
    ADD X0, X0, #8
    B .Lenv_loop
.Lenv_found:
    // X1 now points past "BASICFORTH_PATH=" — the value
    ADR X9, basicforth_path
    STR X1, [X9]
    // Compute length
    MOV X2, #0
.Lenv_strlen:
    LDRB W3, [X1, X2]
    CBZ W3, .Lenv_strlen_done
    ADD X2, X2, #1
    B .Lenv_strlen
.Lenv_strlen_done:
    ADR X9, basicforth_path_len
    STR X2, [X9]
.Lenv_done:

    // Walk envp again for BASICFORTH_SESSION= (override the default isatty gate
    // for the interactive session: =0 forces off, any other value forces on).
    ADR X9, session_env
    STR XZR, [X9]                   // 0 = unset (use default isatty gate)
    LDR X0, [SP]                    // argc
    ADD X0, X0, #2
    LSL X0, X0, #3
    ADD X0, SP, X0                  // &envp[0]
.Lsenv_loop:
    LDR X1, [X0]                    // envp[i]
    CBZ X1, .Lsenv_done             // NULL = end of envp
    ADR X2, sess_prefix
    MOV X3, #sess_prefix_len
.Lsenv_cmp:
    CBZ X3, .Lsenv_found            // prefix matched
    LDRB W4, [X1], #1
    LDRB W5, [X2], #1
    CMP W4, W5
    B.NE .Lsenv_next
    SUB X3, X3, #1
    B .Lsenv_cmp
.Lsenv_next:
    ADD X0, X0, #8
    B .Lsenv_loop
.Lsenv_found:
    LDRB W4, [X1]                   // first byte of the value
    CMP W4, #'0'
    B.EQ .Lsenv_off
    MOV X9, #1                      // non-'0' → force on
    ADR X10, session_env
    STR X9, [X10]
    B .Lsenv_done
.Lsenv_off:
    MOV X9, #2                      // '0' → force off
    ADR X10, session_env
    STR X9, [X10]
.Lsenv_done:

    // Walk envp again for BASICFORTH_EDITOR= (override the default isatty gate for
    // the line editor: =0 forces off, any other value forces on). Same pattern.
    ADR X9, editor_env
    STR XZR, [X9]                   // 0 = unset (use default isatty gate)
    LDR X0, [SP]                    // argc
    ADD X0, X0, #2
    LSL X0, X0, #3
    ADD X0, SP, X0                  // &envp[0]
.Leenv_loop:
    LDR X1, [X0]                    // envp[i]
    CBZ X1, .Leenv_done             // NULL = end of envp
    ADR X2, edit_prefix
    MOV X3, #edit_prefix_len
.Leenv_cmp:
    CBZ X3, .Leenv_found            // prefix matched
    LDRB W4, [X1], #1
    LDRB W5, [X2], #1
    CMP W4, W5
    B.NE .Leenv_next
    SUB X3, X3, #1
    B .Leenv_cmp
.Leenv_next:
    ADD X0, X0, #8
    B .Leenv_loop
.Leenv_found:
    LDRB W4, [X1]                   // first byte of the value
    CMP W4, #'0'
    B.EQ .Leenv_off
    MOV X9, #1                      // non-'0' → force on
    ADR X10, editor_env
    STR X9, [X10]
    B .Leenv_done
.Leenv_off:
    MOV X9, #2                      // '0' → force off
    ADR X10, editor_env
    STR X9, [X10]
.Leenv_done:

    // Walk envp again for BASICFORTH_DOCS= (colon-separated docs directories for
    // the help system: man / topics / apropos). Same pattern as the PATH walk.
    LDR X0, [SP]
    ADD X0, X0, #2
    LSL X0, X0, #3
    ADD X0, SP, X0                  // &envp[0]
.Ldenv_loop:
    LDR X1, [X0]
    CBZ X1, .Ldenv_done
    ADR X2, docs_prefix
    MOV X3, #docs_prefix_len
.Ldenv_cmp:
    CBZ X3, .Ldenv_found
    LDRB W4, [X1], #1
    LDRB W5, [X2], #1
    CMP W4, W5
    B.NE .Ldenv_next
    SUB X3, X3, #1
    B .Ldenv_cmp
.Ldenv_next:
    ADD X0, X0, #8
    B .Ldenv_loop
.Ldenv_found:
    ADR X9, basicforth_docs
    STR X1, [X9]                    // value (past "BASICFORTH_DOCS=")
    MOV X2, #0
.Ldenv_strlen:
    LDRB W3, [X1, X2]
    CBZ W3, .Ldenv_strlen_done
    ADD X2, X2, #1
    B .Ldenv_strlen
.Ldenv_strlen_done:
    ADR X9, basicforth_docs_len
    STR X2, [X9]
.Ldenv_done:

    // Walk envp again for HOME= (used by `cd ~`). Same pattern as the DOCS walk;
    // home_ptr points into the env string (valid for the process lifetime).
    LDR X0, [SP]
    ADD X0, X0, #2
    LSL X0, X0, #3
    ADD X0, SP, X0                  // &envp[0]
.Lhenv_loop:
    LDR X1, [X0]
    CBZ X1, .Lhenv_done
    ADR X2, home_prefix
    MOV X3, #home_prefix_len
.Lhenv_cmp:
    CBZ X3, .Lhenv_found
    LDRB W4, [X1], #1
    LDRB W5, [X2], #1
    CMP W4, W5
    B.NE .Lhenv_next
    SUB X3, X3, #1
    B .Lhenv_cmp
.Lhenv_next:
    ADD X0, X0, #8
    B .Lhenv_loop
.Lhenv_found:
    ADR X9, home_ptr
    STR X1, [X9]                    // value (past "HOME=")
    MOV X2, #0
.Lhenv_strlen:
    LDRB W3, [X1, X2]
    CBZ W3, .Lhenv_strlen_done
    ADD X2, X2, #1
    B .Lhenv_strlen
.Lhenv_strlen_done:
    ADR X9, home_len
    STR X2, [X9]
.Lhenv_done:

    // Capture the absolute startup directory, so `cd` with no argument can return
    // here and session.fs stays pinned to it no matter where a later `cd` goes.
    // Done before core.fs loads, while the CWD is still the launch directory.
    ADR X0, startup_dir
    MOV X1, #STARTUP_DIR_MAX
    BL platform_getcwd              // X0 = bytes incl NUL, or -errno
    CMP X0, #0
    B.LE .Lno_startup_dir           // getcwd failed -> leave length 0
    SUB X0, X0, #1                  // drop the trailing NUL
    ADR X9, startup_dir_len
    STR X0, [X9]
.Lno_startup_dir:

    // Initialize engine registers
    ADR X19, data_stack_top         // DSP = sp0 (empty stack)
    ADR X9, sp0
    STR X19, [X9]                   // save initial DSP for .S / guards
    ADR X21, dict_space             // HERE
    ADR X22, dict_mmap_dev          // LATEST (head of the built-in dictionary chain)

    // Initialize saved state for error recovery
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

    BL platform_init_guard_pages
    // Raw terminal mode is entered lazily on the first interactive input
    // (KEY / KEY? / ACCEPT), so a script that only writes never touches the tty.

    // Initialize rp0 before any startup load, so a fault/ABORT during core.fs
    // or the script recovers onto a valid return stack (repl_loop re-saves it).
    MOV X9, SP
    ADR X10, rp0
    STR X9, [X10]

    // Try to load core.fs (silent skip if not found)
    MOV X9, #0                    // forth_included sets incl_opened to 1 iff it opens
    ADR X10, incl_opened
    STR X9, [X10]
    ADR X9, core_fs_name
    STR X9, [X19, #-CELL]!         // push c-addr
    MOV X9, #core_fs_len
    STR X9, [X19, #-CELL]!         // push length
    BL forth_included

    // Warn (to stderr) if core.fs was not found. forth_included returns 0 for a
    // not-found file (silent skip), so the return value can't tell us — but it
    // sets incl_opened only when it actually opens a file. If it's still 0, core.fs
    // was reachable nowhere (CWD or BASICFORTH_PATH), so the user has only the
    // assembly primitives (no CR, IF, ., etc.) — surface it instead of failing
    // mysteriously. (An empty/comment-only core.fs still opens, so it won't warn.)
    ADR X9, incl_opened
    LDR X9, [X9]
    CBNZ X9, .Lcore_loaded
    MOV X0, #2                    // fd 2 = stderr
    ADR X1, warn_no_core
    MOV X2, #warn_no_core_len
    BL platform_write_fd
.Lcore_loaded:

    // If argv[1] was given, load it as a Forth source file
    ADR X9, start_argc
    LDR X9, [X9]
    CMP X9, #2
    B.LT .Lno_cmdline_file
    // Shift the script (argv[1]) out of the arg vector first, so while the
    // script runs its first argument is arg[1] / the first NEXT-ARG (gforth
    // style). Loading uses start_argv1, independent of the vector.
    BL forth_shift_args
    // Find string length (null-terminated argv)
    ADR X9, start_argv1
    LDR X0, [X9]                    // X0 = c-addr
    MOV X1, #0                      // X1 = length counter
.Largv_len:
    LDRB W9, [X0, X1]
    CBZ W9, .Largv_len_done
    ADD X1, X1, #1
    B .Largv_len
.Largv_len_done:
    // Push ( c-addr u ) and call INCLUDED
    STR X0, [X19, #-CELL]!         // push c-addr
    STR X1, [X19, #-CELL]!         // push length
    // Mark that we are running the user script: any error (a line error
    // returned here, or a fault/ABORT that recovers into repl_loop) must exit
    // non-zero instead of dropping into the REPL, like a failing Unix utility.
    MOV X9, #1
    ADR X10, script_running
    STR X9, [X10]
    BL forth_included
    CBZ X0, .Lcmdline_done         // loaded cleanly
    // Load error. Drop to the REPL only when we'll be interactive (same rule as
    // the session below: BASICFORTH_SESSION=1, or unset and stdin is a terminal),
    // so a broken module can be fixed in place. A script/pipe exits non-zero,
    // like a failing Unix utility.
    ADR X9, session_env
    LDR X9, [X9]
    CMP X9, #2
    B.EQ .Lscript_error            // BASICFORTH_SESSION=0 → exit
    CMP X9, #1
    B.EQ .Lcmdline_done            // BASICFORTH_SESSION=1 → drop to the REPL
    MOV X0, #0
    BL platform_isatty
    CBZ X0, .Lscript_error         // not a terminal → exit
.Lcmdline_done:
    ADR X10, script_running
    STR XZR, [X10]                 // done loading (clean, or interactive recovery)
.Lno_cmdline_file:

    // Print the startup banner now, only when actually entering the interactive
    // REPL — a script that ends in bye/bye-code exits before reaching here — and
    // only when stdout is a terminal, so piped/redirected output stays clean.
    // This block sits before the repl_loop label, so it runs exactly once.
    MOV X0, #1                      // STDOUT
    BL platform_isatty
    CBZ X0, .Lno_banner
    ADR X0, version_str
    MOV X1, #version_len
    BL platform_write
.Lno_banner:

    // ---- Interactive session: capture, seeded from the startup file if any ----
    // On when BASICFORTH_SESSION forces it on, or stdin is a terminal. A file
    // argument no longer disables it: we drop to the REPL with capture on and the
    // log seeded from that file (named-file model — there is no magic session.fs).
    ADR X9, session_active
    STR XZR, [X9]
    ADR X9, session_env
    LDR X9, [X9]
    CMP X9, #2
    B.EQ .Lsession_decided          // BASICFORTH_SESSION=0 → forced off
    CMP X9, #1
    B.EQ .Lsession_on               // BASICFORTH_SESSION=1 → forced on
    MOV X0, #0                      // else default: is stdin a terminal?
    BL platform_isatty
    CBZ X0, .Lsession_decided
.Lsession_on:
    MOV X9, #1
    ADR X10, session_active
    STR X9, [X10]
    // Call session-init ( c-addr u -- ) with the startup file path, or ( 0 0 ) if
    // no file argument was given.
    ADR X9, start_argc
    LDR X9, [X9]
    CMP X9, #2
    B.LT .Lsess_nofile
    ADR X9, start_argv1
    LDR X1, [X9]                    // X1 = path
    MOV X2, #0                      // X2 = strlen
.Lsess_arglen:
    LDRB W3, [X1, X2]
    CBZ W3, .Lsess_arglen_done
    ADD X2, X2, #1
    B .Lsess_arglen
.Lsess_arglen_done:
    STR X1, [X19, #-CELL]!          // push c-addr
    STR X2, [X19, #-CELL]!          // push length
    B .Lsess_init
.Lsess_nofile:
    STR XZR, [X19, #-CELL]!         // push 0  (no file)
    STR XZR, [X19, #-CELL]!         // push 0
.Lsess_init:
    ADR X9, session_hooks
    LDR X10, [X9]                   // [0] = session-init ( c-addr u -- )
    CBNZ X10, .Lsess_call
    ADD X19, X19, #(2*CELL)         // no hook registered → drop the 2 args
    B .Lsession_decided
.Lsess_call:
    BLR X10
.Lsession_decided:

    // Resolve once whether the line editor engages. BASICFORTH_EDITOR overrides
    // the default: =0 forces off, any other value forces on; unset → the editor
    // engages only when stdin is an interactive terminal (so piped/redirected
    // stdin uses forth_accept and script loading / integration tests are
    // unchanged).
    ADR X9, editor_env
    LDR X9, [X9]
    CMP X9, #2
    B.EQ .Linput_off
    CMP X9, #1
    B.EQ .Linput_on
    MOV X0, #0                      // STDIN
    BL platform_isatty
    ADR X9, input_interactive
    STR X0, [X9]
    B .Linput_done
.Linput_on:
    MOV X9, #1
    ADR X10, input_interactive
    STR X9, [X10]
    B .Linput_done
.Linput_off:
    ADR X10, input_interactive
    STR XZR, [X10]
.Linput_done:

.global repl_loop
repl_loop:
    // If a startup script faulted or ABORTed, recovery lands here with
    // script_running still set (the clean-completion path clears it first) —
    // exit non-zero rather than entering the interactive REPL.
    ADR X9, script_running
    LDR X9, [X9]
    CBNZ X9, .Lscript_error

    // Save return stack pointer for error recovery
    MOV X9, SP
    ADR X10, rp0
    STR X9, [X10]

    // Save LATEST and HERE for guard page recovery
    ADR X9, saved_latest
    STR X22, [X9]
    ADR X9, saved_here
    STR X21, [X9]

    // Session capture: discard any pending partial definition left over from a
    // prior line error or fault (the hook drops it only when STATE = interpret).
    ADR X9, session_active
    LDR X9, [X9]
    CBZ X9, .Lno_reset
    ADR X9, session_hooks
    LDR X10, [X9, #16]             // [2] = capture-reset
    CBZ X10, .Lno_reset
    STR X22, [X19, #-CELL]!        // push LATEST ( latest -- )
    BLR X10
.Lno_reset:

    // Print prompt — a continuation prompt ("... ") while a definition is open
    // (STATE compiling), otherwise the normal "> ". The line editor's scroll
    // margin tracks STATE the same way (so the two stay aligned).
    ADR X9, state
    LDR X9, [X9]
    CBZ X9, .Lprompt_normal
    ADR X0, cont_prompt_msg
    MOV X1, #cont_prompt_len
    B .Lprompt_show
.Lprompt_normal:
    ADR X0, prompt_msg
    MOV X1, #prompt_len
.Lprompt_show:
    BL platform_write

    // Read a line ( c-addr max -- count ). When stdin is interactive and the
    // line-editor hook (slot 3) is registered, use it; otherwise fall back to the
    // plain asm forth_accept (piped input, and the window before core.fs runs).
    ADR X9, input_buf
    STR X9, [X19, #-CELL]!         // push c-addr
    MOV X9, #INPUT_BUF_SIZE
    STR X9, [X19, #-CELL]!         // push max
    ADR X9, input_interactive
    LDR X9, [X9]
    CBZ X9, .Lrepl_accept
    ADR X9, session_hooks
    LDR X10, [X9, #24]            // [3] = line-editor (edit-line)
    CBZ X10, .Lrepl_accept
    BLR X10                        // ( c-addr max -- count )
    B .Lrepl_have_line
.Lrepl_accept:
    BL forth_accept                 // ( c-addr max -- count )
.Lrepl_have_line:

    // Empty line → re-prompt (count == 0)
    LDR X9, [X19]
    CBZ X9, repl_empty

    // Set up source variables for PARSE-WORD
    LDR X9, [X19]                   // count
    ADR X10, source_len
    STR X9, [X10]
    ADR X10, cap_line_len           // remember raw line length for session capture
    STR X9, [X10]
    ADR X9, source_addr
    ADR X10, input_buf
    STR X10, [X9]
    ADR X9, to_in
    STR XZR, [X9]

    // Drop count
    ADD X19, X19, #CELL

    // Interpret the line
    BL forth_interpret_line
    CBNZ X0, repl_error

    // Session capture: hand the raw line to (capture-line) ( c-addr u -- ).
    ADR X9, session_active
    LDR X9, [X9]
    CBZ X9, .Lno_cap_line
    ADR X9, session_hooks
    LDR X10, [X9, #8]             // [1] = capture-line
    CBZ X10, .Lno_cap_line
    ADR X9, input_buf
    STR X9, [X19, #-CELL]!         // push c-addr = input_buf
    ADR X9, cap_line_len
    LDR X9, [X9]
    STR X9, [X19, #-CELL]!         // push u = line length
    STR X22, [X19, #-CELL]!        // push LATEST
    BLR X10                        // (capture-line) ( c-addr u latest -- )
.Lno_cap_line:

    // Success — print " ok\n"
    ADR X0, ok_msg
    MOV X1, #ok_len
    BL platform_write
    B repl_loop

repl_error:
    // Print "? " + token + newline
    ADR X0, err_msg
    MOV X1, #err_len
    BL platform_write

    ADR X9, err_token_len
    LDR X1, [X9]
    ADR X9, err_token_addr
    LDR X0, [X9]
    BL platform_write

    MOV X0, #'\n'
    BL platform_emit
    B repl_loop

repl_empty:
    ADD X19, X19, #CELL             // drop 0 count
    B repl_loop

repl_bye:
    ADD X19, X19, #CELL             // drop 0 count
    B forth_bye

// A startup script aborted — either INCLUDED returned an error for a bad line,
// or a fault/ABORT/QUIT recovered into repl_loop with script_running still set.
// Exit non-zero (silently; the diagnostic was already printed) so the script
// fails like a Unix utility instead of dropping into the REPL.
.Lscript_error:
    ADR X10, script_running
    STR XZR, [X10]
    MOV X0, #1
    B platform_exit

// cstr_eq ( X0=a X1=b -- X0=1 if equal else 0 ) — compare null-terminated
// strings byte for byte. Used to recognize the -v / --version option.
cstr_eq:
.Lce_loop:
    LDRB W2, [X0], #1
    LDRB W3, [X1], #1
    CMP W2, W3
    B.NE .Lce_ne
    CBNZ W2, .Lce_loop              // not NUL yet → keep comparing
    MOV X0, #1                      // both hit NUL together → equal
    RET
.Lce_ne:
    MOV X0, #0
    RET

// (version-str) ( -- c-addr u ) — push the version/banner string. Backs the
// Forth `version` word; defined here so it can see version_str/version_len.
.global forth_version_str
forth_version_str:
    ADR X9, version_str
    STR X9, [X19, #-CELL]!          // push c-addr
    MOV X9, #version_len
    STR X9, [X19, #-CELL]!          // push u
    RET

// ---------- Error Handlers ----------
// Stack underflow/overflow are caught by guard pages (SIGSEGV handler
// in platform_linux.s). Only dict_full remains as an explicit handler.

.global dict_full
dict_full:
    ADR X0, msg_dict_full
    MOV X1, #msg_dict_full_len
    BL platform_write

    // Reset return stack and data stack
    ADR X9, rp0
    LDR X9, [X9]
    MOV SP, X9
    ADR X9, sp0
    LDR X19, [X9]

    // If we were compiling, abort the definition
    ADR X9, state
    LDR X10, [X9]
    CBZ X10, repl_loop
    STR XZR, [X9]
    ADR X9, saved_latest
    LDR X22, [X9]
    ADR X9, saved_here
    LDR X21, [X9]

    B repl_loop

// ---------- Data ----------
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
.align 3
start_argc:
    .quad 0
start_argv1:
    .quad 0
// Interactive-session state. session_env: 0=unset, 1=force on, 2=force off (from
// BASICFORTH_SESSION). session_active: resolved on/off. cap_line_len: length of
// the current REPL line, saved for the capture hook.
session_env:
    .quad 0
// Line-editor override: 0=unset (default isatty gate), 1=force on, 2=force off
// (from BASICFORTH_EDITOR). Lets the integration suite drive the editor over a
// pipe, where stdin is not a tty.
editor_env:
    .quad 0
session_active:
    .quad 0
cap_line_len:
    .quad 0
// Non-zero while the startup script (argv[1]) is executing; an error during
// that window exits non-zero instead of dropping into the REPL. Only main.s
// uses it.
script_running:
    .quad 0
// Non-zero when stdin is an interactive terminal (resolved once at startup). The
// REPL engages the line-editor hook (session_hooks[3]) only then; piped input
// falls back to the plain forth_accept.
input_interactive:
    .quad 0
// Mutable cells exposed to Forth as the ARGC and ARGV variables. arg_base is a
// char** into the OS argv vector; NEXT-ARG / SHIFT-ARGS consume from the front.
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
// BASICFORTH_DOCS value pointer + length (the help system's docs search path).
.global basicforth_docs
basicforth_docs:
    .quad 0
.global basicforth_docs_len
basicforth_docs_len:
    .quad 0
// Length of the captured absolute startup directory (0 if getcwd failed at boot).
.global startup_dir_len
startup_dir_len:
    .quad 0
// HOME environment value (pointer into envp) + its length, for `cd ~`. 0 = unset.
.global home_ptr
home_ptr:
    .quad 0
.global home_len
home_len:
    .quad 0

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
// Absolute startup directory, captured once at boot (NUL-terminated by getcwd).
.global startup_dir
startup_dir:
    .space STARTUP_DIR_MAX
