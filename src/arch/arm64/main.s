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

// Address of a thread-local variable (local-exec model): the thread pointer
// TPIDR_EL0 plus the offset the linker assigns. See the TLS block in core.s
// for which vars are per-thread and why. Writes only \reg.
.macro TLS_ADDR reg, sym
    MRS \reg, TPIDR_EL0
    ADD \reg, \reg, #:tprel_hi12:\sym, LSL #12
    ADD \reg, \reg, #:tprel_lo12_nc:\sym
.endm

.global _start

// Tunable sizes, shared with core.s and the x86-64 build. CELL comes from
// here rather than being redefined per file -- three copies of the one value
// this file exists to keep single is exactly the drift it prevents.
.include "../../config.inc"
.equ INPUT_BUF_SIZE, 256
.equ STARTUP_DIR_MAX, 1024          // buffer for the absolute startup directory
// Install-tree derivation. PREFIX_MAX is the binding one: the platform layer
// copies every path through a 255-byte scratch, so a prefix near that would
// fail later, in a place with no way to say why. Refuse it here instead. The
// derived buffers then cannot overflow -- the longest template holds three
// prefixes and ~110 fixed bytes.
.equ EXE_BUF_MAX,     1024          // /proc/self/exe answer
.equ PREFIX_MAX,       160          // install prefix we are willing to use
.equ PROBE_BUF_MAX,    256          // "<prefix>/share/basicforth/forth/core.fs"
.equ DERIVED_BUF_MAX,  768          // built BASICFORTH_PATH / BASICFORTH_DOCS
.equ F_HIDDEN, 0x40                 // header flags2 bit; must match core.s

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

    // Save &envp[0] for platform_system (execve's third arg). envp[0] sits at
    // [SP + (argc+2)*8], just past argv and its NULL terminator.
    LDR X9, [SP]                    // argc
    ADD X9, X9, #2
    LSL X9, X9, #3
    ADD X9, SP, X9                  // &envp[0]
    ADR X10, start_envp
    STR X9, [X10]

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

    // The environment BasicForth reads for itself. platform_getenv walks
    // start_envp (saved just above) and returns a pointer INTO the environment
    // block plus its length — the strings live as long as the process, so
    // nothing here is copied or owned. Each name matches only up to a following
    // '=', so BASICFORTH_PATH cannot be answered by BASICFORTH_PATHOLOGICAL.
    // Unset gives 0/0, which is what these already hold.
    ADR X0, env_name
    MOV X1, #env_name_len
    BL platform_getenv
    ADR X9, basicforth_path
    STR X0, [X9]
    ADR X9, basicforth_path_len
    STR X1, [X9]

    // BASICFORTH_SESSION — override the isatty gate for the interactive
    // session: '0' forces off, any other value forces on, unset keeps the
    // default. A value that is EMPTY counts as "any other value", since its
    // first byte is the terminating NUL — which is what the hand-written walk
    // did, and what the tests pin.
    ADR X9, session_env
    STR XZR, [X9]                   // 0 = unset (use default isatty gate)
    ADR X0, sess_name
    MOV X1, #sess_name_len
    BL platform_getenv
    CBZ X0, .Lsenv_done
    ADR X9, session_env
    MOV X2, #1
    STR X2, [X9]                    // set → force on...
    LDRB W3, [X0]
    CMP W3, #'0'
    B.NE .Lsenv_done
    MOV X2, #2
    STR X2, [X9]                    // ...unless it starts with '0'
.Lsenv_done:

    // BASICFORTH_EDITOR — the same gate for the line editor.
    ADR X9, editor_env
    STR XZR, [X9]                   // 0 = unset (use default isatty gate)
    ADR X0, edit_name
    MOV X1, #edit_name_len
    BL platform_getenv
    CBZ X0, .Leenv_done
    ADR X9, editor_env
    MOV X2, #1
    STR X2, [X9]
    LDRB W3, [X0]
    CMP W3, #'0'
    B.NE .Leenv_done
    MOV X2, #2
    STR X2, [X9]
.Leenv_done:

    // BASICFORTH_DOCS — colon-separated docs directories for help / tutorials
    // / apropos.
    ADR X0, docs_name
    MOV X1, #docs_name_len
    BL platform_getenv
    ADR X9, basicforth_docs
    STR X0, [X9]
    ADR X9, basicforth_docs_len
    STR X1, [X9]

    // HOME — used by `cd ~`.
    ADR X0, home_name
    MOV X1, #home_name_len
    BL platform_getenv
    ADR X9, home_ptr
    STR X0, [X9]
    ADR X9, home_len
    STR X1, [X9]

    // Fall back to the install tree for anything the environment did not set.
    // Must run after all four getenv calls above and before core.fs is loaded.
    BL derive_install_paths

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
    TLS_ADDR X9, sp0
    STR X19, [X9]                   // save initial DSP for .S / guards
    TLS_ADDR X9, is_repl
    MOV X10, #1
    STR X10, [X9]                   // this is the REPL thread; workers get 0
    ADR X10, locals_stack_top       // LP = lp0 (no frames)
    TLS_ADDR X9, lp
    STR X10, [X9]
    TLS_ADDR X9, lp0
    STR X10, [X9]
    ADR X21, dict_space             // HERE
    ADR X22, dict_throw             // LATEST (head of the built-in dictionary chain)

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
    ADR X0, banner_str
    MOV X1, #banner_len
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
    // If a startup script faulted, ABORTed, or (since EVALUATE and INCLUDED
    // propagate) threw out of a nested load, recovery lands here with
    // script_running still set — the clean-completion path clears it first.
    //
    // Apply the SAME policy the command-line loader applies to a load error it
    // gets as a return value, rather than exiting unconditionally. The two used
    // to disagree, and nothing reached the disagreement until errors began
    // propagating: a broken module dropped you to a fixable REPL or exited
    // depending on which of the two routes its failure happened to take.
    ADR X9, script_running
    LDR X9, [X9]
    CBZ X9, .Lrepl_not_script
    ADR X9, session_env
    LDR X9, [X9]
    CMP X9, #2
    B.EQ .Lscript_error             // BASICFORTH_SESSION=0 → exit
    CMP X9, #1
    B.EQ .Lrepl_script_recover      // BASICFORTH_SESSION=1 → REPL
    MOV X0, #0
    BL platform_isatty
    CBZ X0, .Lscript_error          // not a terminal → exit
.Lrepl_script_recover:
    ADR X10, script_running
    STR XZR, [X10]                  // recovered; this is now a normal session
.Lrepl_not_script:

    // Save return stack pointer for error recovery
    MOV X9, SP
    ADR X10, rp0
    STR X9, [X10]
    TLS_ADDR X10, handler
    STR XZR, [X10]                  // any CATCH frames died with the last line

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
    // Enter printed no newline; one is owed. The next write to stdout pays it
    // (platform_linux.s), so output and errors still start on a fresh line
    // while a silent line keeps its ` ok` up here on the command line.
    // forth_accept sets this itself for direct ACCEPT callers; setting it here
    // covers the line-editor path too, and setting it twice is harmless.
    ADR X9, pending_nl
    MOV X10, #1
    STR X10, [X9]

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

    // Success — print " ok\n", unless a definition is still open. The "... "
    // continuation prompt already says "still compiling", so an ok after every
    // line is noise: a four-line definition printed four of them, doubling its
    // height on screen. STATE alone can't decide — `[` interprets inside an
    // open definition — so also check LATEST's hidden bit, which `:` sets and
    // `;` clears (the same pair the Ctrl-D guard uses).
    ADR X9, state
    LDR X9, [X9]
    CBNZ X9, repl_loop             // compiling → say nothing
    LDRB W9, [X22, #8]             // LATEST flags2
    TST W9, #F_HIDDEN              // definition open but interpreting?
    B.NE repl_loop
    // ` ok` is the ONE message that appends rather than flushing: drop the owed
    // newline so a silent line reads `> : foo 1 ;  ok` on one line. Its own
    // trailing \n ends the line. Anything the line printed already paid.
    ADR X9, pending_nl
    STR XZR, [X9]
    ADR X0, ok_msg
    MOV X1, #ok_len
    BL platform_write
    B repl_loop

repl_error:
    // Print the error's own wording + token + newline. The wording is chosen by
    // the site that raised it (see err_pfx_addr in core.s) so every line error
    // reads the same shape: "? nosuchword", "compile only: dup". EVALUATE prints
    // the identical shape before it throws, so the sequence lives once, in
    // core.s, rather than in two places that have to agree.
    BL print_line_error
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
// ---------- Install-tree fallback ----------
// An installed binary has no setup.sh behind it, so BASICFORTH_PATH and
// BASICFORTH_DOCS arrive unset and `include`, `help` and `tutorial` would all
// come up empty. Derive them from where the binary actually is:
//
//     <prefix>/bin/basicforth  ->  <prefix>/share/basicforth/{forth,docs,...}
//
// DERIVED, not compiled in. The tree stays relocatable, and the binary the
// suites test is byte-for-byte the one that ships -- a baked-in prefix would
// make the tested build and the installed build different objects.
//
// The environment always wins. A repo checkout (setup.sh, or the suites, which
// set the variables themselves) never reaches the probe below, so this whole
// path costs a running-from-the-repo session two loads and a branch.
//
// expand_prefix ( X0=tmpl X1=tmpl_len X2=dest X3=cap -- X0=len, 0 = would not fit )
// Copy tmpl to dest, expanding each '%' to the install prefix. One loop rather
// than open-coded concatenation, because the three templates below differ only
// in how many times the prefix appears.
expand_prefix:
    MOV X9, #0                      // out index
    MOV X10, #0                     // in index
    ADR X13, exe_buf
    ADR X14, install_prefix_len
    LDR X14, [X14]                  // prefix length
.Lxp_loop:
    CMP X10, X1
    B.HS .Lxp_done
    LDRB W11, [X0, X10]
    ADD X10, X10, #1
    CMP W11, #'%'
    B.EQ .Lxp_prefix
    CMP X9, X3
    B.HS .Lxp_overflow
    STRB W11, [X2, X9]
    ADD X9, X9, #1
    B .Lxp_loop
.Lxp_prefix:
    MOV X12, #0
.Lxp_pfx_loop:
    CMP X12, X14
    B.HS .Lxp_loop
    CMP X9, X3
    B.HS .Lxp_overflow
    LDRB W11, [X13, X12]
    STRB W11, [X2, X9]
    ADD X9, X9, #1
    ADD X12, X12, #1
    B .Lxp_pfx_loop
.Lxp_overflow:
    MOV X0, #0                      // 0 = did not fit; caller leaves things unset
    RET
.Lxp_done:
    MOV X0, X9
    RET

derive_install_paths:
    STP X29, X30, [SP, #-16]!
    STP X19, X20, [SP, #-16]!
    // Nothing to do when the environment supplied both.
    ADR X9, basicforth_path_len
    LDR X9, [X9]
    CBZ X9, .Ldip_needed
    ADR X9, basicforth_docs_len
    LDR X9, [X9]
    CBNZ X9, .Ldip_ret
.Ldip_needed:
    ADR X0, exe_buf
    MOV X1, #EXE_BUF_MAX
    BL platform_self_exe            // X0 = length, or -errno
    CMP X0, #0
    B.LE .Ldip_ret
    MOV X9, #EXE_BUF_MAX
    CMP X0, X9
    B.HS .Ldip_ret                  // filled the buffer: possibly truncated, so
    MOV X19, X0                     //   do not trust it
    // Strip two path components: ".../bin/basicforth" -> ".../bin" -> "..."
    ADR X20, exe_buf
    MOV X10, #2                     // components to strip
.Ldip_strip:
    CBZ X19, .Ldip_ret
.Ldip_scan:
    SUB X19, X19, #1
    CBZ X19, .Ldip_ret              // hit the leading '/': no prefix above it
    LDRB W11, [X20, X19]
    CMP W11, #'/'
    B.NE .Ldip_scan
    SUB X10, X10, #1
    CBNZ X10, .Ldip_strip
    // A prefix long enough to overflow the include path's own 255-byte scratch
    // would fail later in a place that could not explain itself. Refuse here.
    MOV X9, #PREFIX_MAX
    CMP X19, X9
    B.HI .Ldip_ret
    ADR X9, install_prefix_len
    STR X19, [X9]

    // Is this actually an install tree? Probe for the one file that decides it.
    // Without this check a repo build would publish two directories that do not
    // exist, and `help` would report a docs path rather than saying it has none.
    ADR X0, tmpl_probe
    MOV X1, #tmpl_probe_len
    ADR X2, probe_buf
    MOV X3, #PROBE_BUF_MAX
    BL expand_prefix
    CBZ X0, .Ldip_ret
    MOV X1, X0
    ADR X0, probe_buf
    BL platform_open_file           // X0 = fd, or negative
    CMP X0, #0
    B.LT .Ldip_ret                  // not installed here; leave everything unset
    BL platform_close_file

    ADR X9, basicforth_path_len
    LDR X9, [X9]
    CBNZ X9, .Ldip_docs
    ADR X0, tmpl_path
    MOV X1, #tmpl_path_len
    ADR X2, derived_path
    MOV X3, #DERIVED_BUF_MAX
    BL expand_prefix
    CBZ X0, .Ldip_docs
    ADR X9, basicforth_path_len
    STR X0, [X9]
    ADR X9, basicforth_path
    ADR X10, derived_path
    STR X10, [X9]
.Ldip_docs:
    ADR X9, basicforth_docs_len
    LDR X9, [X9]
    CBNZ X9, .Ldip_ret
    ADR X0, tmpl_docs
    MOV X1, #tmpl_docs_len
    ADR X2, derived_docs
    MOV X3, #DERIVED_BUF_MAX
    BL expand_prefix
    CBZ X0, .Ldip_ret
    ADR X9, basicforth_docs_len
    STR X0, [X9]
    ADR X9, basicforth_docs
    ADR X10, derived_docs
    STR X10, [X9]
.Ldip_ret:
    LDP X19, X20, [SP], #16
    LDP X29, X30, [SP], #16
    RET

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

    // Reset return stack, data stack and locals stack
    ADR X9, rp0
    LDR X9, [X9]
    MOV SP, X9
    TLS_ADDR X9, sp0
    LDR X19, [X9]
    TLS_ADDR X9, lp0
    LDR X10, [X9]
    TLS_ADDR X9, lp
    STR X10, [X9]
    // UNCONDITIONAL, above the STATE test below: we are going to repl_loop
    // either way, and neither of these is tied to being mid-definition.
    // in_load is not about compiling at all, and `[` makes STATE 0 *inside* an
    // open definition, so gating either on STATE skips exactly the cases that
    // need them.
    ADR X9, locals_count
    STR XZR, [X9]                   // the names die with the definition
    ADR X9, in_load
    STR XZR, [X9]                   // and any abandoned loader frame

    // Roll back an open definition. STATE alone cannot decide -- `[` interprets
    // INSIDE an open definition -- so also check LATEST's hidden bit, the same
    // pair the ` ok` suppression uses. Gating on STATE alone left the partial
    // header alive when the dictionary ran out inside `[ ... ]`, and the
    // definition-open guard then refused every LATER definition: the session
    // was wedged, with nothing on screen to explain it.
    ADR X9, state
    LDR X10, [X9]
    CBNZ X10, .Ldf_rollback
    LDRB W10, [X22, #8]                 // definition open but interpreting?
    TST W10, #F_HIDDEN
    B.EQ repl_loop
.Ldf_rollback:
    STR XZR, [X9]
    ADR X9, saved_latest
    LDR X22, [X9]
    ADR X9, saved_here
    LDR X21, [X9]
    // Drop the partial header the anchor may still point AT (core.s's
    // DROP_PARTIAL_HEADER macro, hand-written: it is not visible here).
    LDRB W9, [X22, #8]
    TST W9, #F_HIDDEN
    B.EQ .Ldf_done
    MOV X21, X22
    LDR X22, [X22]
.Ldf_done:

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
// Lines 2-3 of the interactive banner. Kept here rather than in the generated
// version.inc because nothing in them varies with the build; version.inc stays
// a single line so `basicforth -v` prints exactly one line for scripts.
banner_str: .ascii "Copyright (C) 2026 Brandon Blodget.  No warranty; type `license'.\nType `help' for the manual, `tutorials' to learn, `bye' to exit.\n"
.equ banner_len, . - banner_str
core_fs_name:   .ascii "core.fs"
.equ core_fs_len, . - core_fs_name
warn_no_core:   .ascii "basicforth: core.fs not found - only built-in primitives are available.\n  Set BASICFORTH_PATH to the directory containing core.fs.\n"
.equ warn_no_core_len, . - warn_no_core
session_fs_name: .ascii "session.fs"
.equ session_fs_len, . - session_fs_name
// Variable NAMES, without the '=' — platform_getenv matches the name and
// requires the '=' itself, so spelling it here would look for "NAME==".
env_name:       .ascii "BASICFORTH_PATH"
.equ env_name_len, . - env_name
sess_name:      .ascii "BASICFORTH_SESSION"
.equ sess_name_len, . - sess_name
edit_name:      .ascii "BASICFORTH_EDITOR"
.equ edit_name_len, . - edit_name
docs_name:      .ascii "BASICFORTH_DOCS"
.equ docs_name_len, . - docs_name
home_name:      .ascii "HOME"
.equ home_name_len, . - home_name
opt_v:          .asciz "-v"
opt_version:    .asciz "--version"

// Install-tree templates. '%' expands to the derived prefix (expand_prefix).
// The layout these describe is the one `make install` writes, and the two are
// checked against each other by the install test rather than by eye.
tmpl_probe:     .ascii "%/share/basicforth/forth/core.fs"
.equ tmpl_probe_len, . - tmpl_probe
tmpl_path:      .ascii "%/share/basicforth/forth:%/share/basicforth/examples"
.equ tmpl_path_len, . - tmpl_path
tmpl_docs:      .ascii "%/share/basicforth/docs/Language-Reference:%/share/basicforth/docs/Tutorials:%/share/basicforth/docs/Guides"
.equ tmpl_docs_len, . - tmpl_docs

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
// &envp[0], captured at _start, passed to execve by platform_system so a spawned
// program inherits the environment (e.g. $EDITOR/$PATH/$TERM for `edit`).
.global start_envp
start_envp:
    .quad 0

.bss
.align 4
input_buf:
    .space INPUT_BUF_SIZE
// Absolute startup directory, captured once at boot (NUL-terminated by getcwd).
.global startup_dir
startup_dir:
    .space STARTUP_DIR_MAX
// Install-tree derivation (derive_install_paths). exe_buf holds the answer from
// /proc/self/exe; install_prefix_len is how much of it is the prefix, so the
// prefix needs no copy of its own. The derived strings must OUTLIVE the
// derivation -- basicforth_path points into them for the whole session, exactly
// as it otherwise points into the environment block.
exe_buf:
    .space EXE_BUF_MAX
install_prefix_len:
    .quad 0
probe_buf:
    .space PROBE_BUF_MAX
derived_path:
    .space DERIVED_BUF_MAX
derived_docs:
    .space DERIVED_BUF_MAX
