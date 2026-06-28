// BasicForth — Platform Layer (Linux/ARM64)
// Copyright (C) 2026 Brandon Blodget
// SPDX-License-Identifier: GPL-2.0-only
//
// Linux-specific I/O via syscalls. Swap this file to port to bare metal.

.equ SYS_ioctl,          29
.equ SYS_read,           63
.equ SYS_write,          64
.equ SYS_exit,           93
.equ SYS_clock_gettime,  113
.equ SYS_getdents64,     61

.equ CLOCK_MONOTONIC, 1

.equ STDIN,  0
.equ STDOUT, 1
.equ STDERR, 2

// Terminal ioctl commands
.equ TCGETS, 0x5401
.equ TCSETS, 0x5402

// termios struct offsets (Linux aarch64)
// c_iflag:  offset 0   (4 bytes)
// c_oflag:  offset 4   (4 bytes)
// c_cflag:  offset 8   (4 bytes)
// c_lflag:  offset 12  (4 bytes)
// c_line:   offset 16  (1 byte)
// c_cc[19]: offset 17  (19 bytes)
// Total: 36 bytes
.equ TERMIOS_SIZE, 36
.equ OFFSET_IFLAG, 0
.equ OFFSET_LFLAG, 12
.equ OFFSET_CC,    17

// c_iflag bits
.equ IXON,   0x400          // XON/XOFF flow control (Ctrl+S/Ctrl+Q)

// c_lflag bits
.equ ECHO,   0x08           // echo input
.equ ICANON, 0x02           // canonical (line-buffered) mode

// Additional ioctl commands
.equ FIONREAD, 0x541B       // get bytes available to read (for future KEY?)

// c_cc indices
.equ VTIME, 5
.equ VMIN,  6

// ---------- RAW MODE ----------
// Switch terminal to raw mode for character-at-a-time input.
// Saves original settings for restore on exit.
.global platform_raw_mode
platform_raw_mode:
    STR X30, [SP, #-16]!

    // Lazy and idempotent: called at the start of every interactive input
    // (KEY / KEY? / ACCEPT). Switch to raw mode the first time, and only when
    // stdin is a terminal. A program that never reads input (e.g. a script run
    // as `tool.fs | less`) never touches the terminal; and we key off stdin
    // (the thing we read), not stdout, so an interactive session still gets
    // raw mode even when its stdout is piped/redirected.
    ADR X9, term_is_raw
    LDR X9, [X9]
    CBNZ X9, .Lraw_skip             // already raw — nothing to do
    MOV X0, #STDIN
    BL platform_isatty
    CBZ X0, .Lraw_skip              // stdin not a tty → stay cooked

    // TCGETS: read current terminal settings into orig_termios
    MOV X0, #STDIN
    MOV X1, #TCGETS
    ADR X2, orig_termios
    MOV X8, #SYS_ioctl
    SVC #0
    CMP X0, #0
    B.LT .Lraw_skip                // TCGETS failed → orig_termios invalid, bail

    // Copy orig_termios to raw_termios
    ADR X0, orig_termios
    ADR X1, raw_termios
    MOV X2, #TERMIOS_SIZE
1:  LDRB W3, [X0], #1
    STRB W3, [X1], #1
    SUBS X2, X2, #1
    B.NE 1b

    // Modify raw_termios for raw mode
    ADR X0, raw_termios

    // Clear IXON in c_iflag (free Ctrl+S and Ctrl+Q for input)
    LDR W1, [X0, #OFFSET_IFLAG]
    MOV W2, #IXON
    BIC W1, W1, W2
    STR W1, [X0, #OFFSET_IFLAG]
    // Note: ICRNL left ON — terminal converts CR to NL for us

    // Clear ECHO, ICANON in c_lflag (keep ISIG for Ctrl+C)
    LDR W1, [X0, #OFFSET_LFLAG]
    MOV W2, #(ECHO | ICANON)
    BIC W1, W1, W2
    STR W1, [X0, #OFFSET_LFLAG]

    // Set VMIN=1, VTIME=0 (blocking read, one char at a time)
    MOV W1, #1
    STRB W1, [X0, #(OFFSET_CC + VMIN)]
    MOV W1, #0
    STRB W1, [X0, #(OFFSET_CC + VTIME)]

    // TCSETS: apply raw settings
    MOV X0, #STDIN
    MOV X1, #TCSETS
    ADR X2, raw_termios
    MOV X8, #SYS_ioctl
    SVC #0
    CMP X0, #0
    B.LT .Lraw_skip                // apply failed → terminal unchanged, don't mark

    MOV X9, #1
    ADR X10, term_is_raw            // raw applied and orig_termios valid
    STR X9, [X10]
.Lraw_skip:
    LDR X30, [SP], #16
    RET

// ---------- RESTORE TERMINAL ----------
// Restore original terminal settings (call before exit). No-op if we never
// entered raw mode — otherwise we'd write an uninitialized orig_termios and
// corrupt a terminal we never touched.
.global platform_restore_term
platform_restore_term:
    STR X30, [SP, #-16]!

    ADR X9, term_is_raw
    LDR X9, [X9]
    CBZ X9, .Lrestore_skip

    MOV X0, #STDIN
    MOV X1, #TCSETS
    ADR X2, orig_termios
    MOV X8, #SYS_ioctl
    SVC #0

    ADR X9, term_is_raw
    STR XZR, [X9]
.Lrestore_skip:
    LDR X30, [SP], #16
    RET

// ---------- ISATTY ----------
// platform_isatty ( X0=fd -- X0=1 if fd is a terminal, 0 otherwise )
// Probes with TCGETS: it succeeds on a tty and fails (-ENOTTY) on a
// pipe/file/redirect. Uses a private scratch buffer so it never disturbs the
// saved orig_termios used for restore.
.global platform_isatty
platform_isatty:
    MOV X1, #TCGETS
    ADR X2, isatty_termios
    MOV X8, #SYS_ioctl
    SVC #0
    CMP X0, #0
    B.LT .Lisatty_no               // negative errno -> not a tty
    MOV X0, #1
    RET
.Lisatty_no:
    MOV X0, #0
    RET

// ---------- KEY ----------
// Read one character from stdin.
// Returns: X0 = character read
// On EOF (read returns 0), exits silently via platform_bye.
// Parses ANSI escape sequences for arrow keys:
//   ESC [ A → 129 (KEY_UP)    ESC [ B → 130 (KEY_DOWN)
//   ESC [ C → 131 (KEY_RIGHT) ESC [ D → 132 (KEY_LEFT)
// Standalone ESC (no following bytes) returns 27.
.global platform_key
platform_key:
    STP X29, X30, [SP, #-32]!      // 32 bytes: LR + scratch space
    // Read one byte
    MOV X0, #STDIN
    ADD X1, SP, #16                 // buffer in stack scratch
    MOV X2, #1
    MOV X8, #SYS_read
    SVC #0
    CMP X0, #0
    B.LE .Lkey_eof
    LDRB W0, [SP, #16]
    CMP W0, #27                     // ESC?
    B.EQ .Lkey_esc
    LDP X29, X30, [SP], #32
    RET

.Lkey_esc:
    // Check if more bytes available (FIONREAD)
    STR XZR, [SP, #16]             // zero count
    MOV X8, #SYS_ioctl
    MOV X0, #STDIN
    MOV X1, #FIONREAD
    ADD X2, SP, #16
    SVC #0
    LDR W9, [SP, #16]
    CBZ W9, .Lkey_esc_standalone

    // Read next byte — expect '['
    MOV X0, #STDIN
    ADD X1, SP, #16
    MOV X2, #1
    MOV X8, #SYS_read
    SVC #0
    CMP X0, #0
    B.LE .Lkey_esc_standalone
    LDRB W9, [SP, #16]
    CMP W9, #'['
    B.NE .Lkey_esc_standalone

    // Read final byte
    MOV X0, #STDIN
    ADD X1, SP, #16
    MOV X2, #1
    MOV X8, #SYS_read
    SVC #0
    CMP X0, #0
    B.LE .Lkey_esc_standalone
    LDRB W9, [SP, #16]

    // Map A/B/C/D → 129-132
    CMP W9, #'A'
    B.EQ .Lkey_up
    CMP W9, #'B'
    B.EQ .Lkey_down
    CMP W9, #'C'
    B.EQ .Lkey_right
    CMP W9, #'D'
    B.EQ .Lkey_left
    B .Lkey_esc_standalone

.Lkey_up:
    MOV X0, #129
    LDP X29, X30, [SP], #32
    RET
.Lkey_down:
    MOV X0, #130
    LDP X29, X30, [SP], #32
    RET
.Lkey_right:
    MOV X0, #131
    LDP X29, X30, [SP], #32
    RET
.Lkey_left:
    MOV X0, #132
    LDP X29, X30, [SP], #32
    RET

.Lkey_esc_standalone:
    MOV X0, #27
    LDP X29, X30, [SP], #32
    RET

.Lkey_eof:
    LDP X29, X30, [SP], #32
    B platform_bye

// ---------- EMIT ----------
// Write one character to stdout.
// Input: X0 = character to write
// Called by forth_emit in core.s, which handles the data stack.
.global platform_emit
platform_emit:
    STR X30, [SP, #-16]!
    STRB W0, [SP, #8]          // store char byte in stack padding area
    ADD X1, SP, #8             // X1 = pointer to the char
    MOV X2, #1                 // count = 1
    MOV X0, #STDOUT            // fd = 1
    MOV X8, #SYS_write
    SVC #0
    LDR X30, [SP], #16
    RET

// ---------- WRITE ----------
// platform_write_fd ( X0=fd, X1=buffer, X2=length -- X0=bytes written or -errno )
// Generic write to any file descriptor. Returns the raw syscall result so
// callers (e.g. WRITE-FILE) can derive an ior.
.global platform_write_fd
platform_write_fd:
    MOV X8, #SYS_write
    SVC #0
    RET

// platform_write ( X0=buffer, X1=length ) — write to stdout.
// Thin wrapper so existing callers (TYPE, banner, error messages) are unchanged.
.global platform_write
platform_write:
    MOV X2, X1                  // count
    MOV X1, X0                  // buf
    MOV X0, #STDOUT
    B platform_write_fd

// ---------- FLUSH ICACHE ----------
// Flush instruction cache for a range of addresses.
// Input: X0 = start address, X1 = end address (exclusive)
// Required after writing code to memory on ARM64 (I-cache/D-cache not coherent).
// Reads CTR_EL0 to determine cache line sizes (varies by CPU).
.global platform_flush_icache
platform_flush_icache:
    MRS X3, CTR_EL0                 // read Cache Type Register

    // D-cache line size: DminLine = CTR_EL0[19:16], size = 4 << DminLine
    UBFX X4, X3, #16, #4           // X4 = DminLine
    MOV X5, #4
    LSL X4, X5, X4                  // X4 = D-cache line size

    // Clean each cache line from D-cache to point of unification
    MOV X2, X0
1:  DC CVAU, X2
    ADD X2, X2, X4
    CMP X2, X1
    B.LO 1b
    DSB ISH

    // I-cache line size: IminLine = CTR_EL0[3:0], size = 4 << IminLine
    UBFX X4, X3, #0, #4            // X4 = IminLine
    LSL X4, X5, X4                  // X4 = I-cache line size

    // Invalidate each cache line in I-cache
    MOV X2, X0
2:  IC IVAU, X2
    ADD X2, X2, X4
    CMP X2, X1
    B.LO 2b
    DSB ISH
    ISB
    RET

// ---------- BYE ----------
// platform_exit ( X0=status ) — restore terminal and exit with status.
.global platform_exit
platform_exit:
    STP X0, X30, [SP, #-16]!        // preserve status + LR across the call
    BL platform_restore_term
    LDP X0, X30, [SP], #16
    MOV X8, #SYS_exit
    SVC #0

// Restore terminal and exit with status 0.
.global platform_bye
platform_bye:
    MOV X0, #0
    B platform_exit

// ---------- Guard Pages ----------
// Set up SIGSEGV handler and mprotect guard pages around the data stack.
// Must be called before platform_raw_mode (early in startup).

.equ SYS_mprotect,     226
.equ SYS_rt_sigaction, 134
.equ SIGSEGV,          11
.equ PROT_NONE,        0
.equ SA_SIGINFO,       0x04
.equ PAGE_SIZE,        4096

// ucontext_t offsets for ARM64 (from kernel headers)
// uc_mcontext starts at offset 176
// uc_mcontext.regs[0..30] at 176+8 = 184 (after fault_address)
// X19 = regs[19] = 184 + 19*8 = 336
// X21 = regs[21] = 184 + 21*8 = 352
// X22 = regs[22] = 184 + 22*8 = 360
// sp  = 176 + 256 = 432
// pc  = 176 + 264 = 440
.equ UC_X19, 336
.equ UC_X21, 352
.equ UC_X22, 360
.equ UC_SP,  432
.equ UC_PC,  440

// siginfo_t offset
.equ SI_ADDR, 16

.global platform_init_guard_pages
platform_init_guard_pages:
    STP X29, X30, [SP, #-16]!

    // mprotect(guard_page_underflow, PAGE_SIZE, PROT_NONE)
    ADR X0, guard_page_underflow
    MOV X1, #PAGE_SIZE
    MOV X2, #PROT_NONE
    MOV X8, #SYS_mprotect
    SVC #0
    CBNZ X0, .Lguard_fail

    // mprotect(guard_page_overflow, PAGE_SIZE, PROT_NONE)
    ADR X0, guard_page_overflow
    MOV X1, #PAGE_SIZE
    MOV X2, #PROT_NONE
    MOV X8, #SYS_mprotect
    SVC #0
    CBNZ X0, .Lguard_fail

    // rt_sigaction(SIGSEGV, &sigact, NULL, sizeof(sigset_t))
    // Kernel sigaction struct: [handler:8][flags:8][mask:128]
    // (ARM64 has no sa_restorer field)
    ADR X9, sigact

    // Set handler
    ADR X10, sigsegv_handler
    STR X10, [X9]

    // Set flags: SA_SIGINFO
    MOV X10, #SA_SIGINFO
    STR X10, [X9, #8]

    // Zero the signal mask (128 bytes at offset 16)
    ADD X10, X9, #16
    MOV X11, #16                // 16 qwords = 128 bytes
1:  STR XZR, [X10], #8
    SUBS X11, X11, #1
    B.NE 1b

    // rt_sigaction syscall
    MOV X0, #SIGSEGV
    MOV X1, X9                  // &sigact
    MOV X2, #0                  // old = NULL
    MOV X3, #8                  // sizeof(sigset_t) for kernel
    MOV X8, #SYS_rt_sigaction
    SVC #0
    CBNZ X0, .Lguard_fail

    LDP X29, X30, [SP], #16
    RET

.Lguard_fail:
    // Fatal: guard page setup failed — exit with error message
    MOV X0, #STDOUT
    ADR X1, msg_guard_fail
    MOV X2, #msg_guard_fail_len
    MOV X8, #SYS_write
    SVC #0
    MOV X0, #1
    MOV X8, #SYS_exit
    SVC #0

// SIGSEGV signal handler
// Called with: X0 = signum, X1 = siginfo_t*, X2 = ucontext_t*
sigsegv_handler:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    MOV X23, X2                 // X23 = ucontext (save before syscalls clobber X2)

    // Get faulting address from siginfo_t
    LDR X3, [X1, #SI_ADDR]     // X3 = faulting address

    // Check if fault is in underflow guard page
    ADR X4, guard_page_underflow
    CMP X3, X4
    B.LO .Lsig_check_overflow
    ADD X5, X4, #PAGE_SIZE
    CMP X3, X5
    B.LO .Lsig_underflow

.Lsig_check_overflow:
    // Check if fault is in overflow guard page
    ADR X4, guard_page_overflow
    CMP X3, X4
    B.LO .Lsig_unknown
    ADD X5, X4, #PAGE_SIZE
    CMP X3, X5
    B.LO .Lsig_overflow

.Lsig_unknown:
    // Not our guard page — re-raise default SIGSEGV
    ADR X1, sigact
    STR XZR, [X1]              // handler = SIG_DFL
    STR XZR, [X1, #8]         // flags = 0
    MOV X0, #SIGSEGV
    MOV X2, #0
    MOV X3, #8
    MOV X8, #SYS_rt_sigaction
    SVC #0
    // Return — faulting instruction re-executes with default handler → crash
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

.Lsig_underflow:
    // Print "stack underflow\n"
    MOV X0, #STDOUT
    ADR X1, msg_underflow
    MOV X2, #msg_underflow_len
    MOV X8, #SYS_write
    SVC #0
    B .Lsig_recover

.Lsig_overflow:
    // Print "stack overflow\n"
    MOV X0, #STDOUT
    ADR X1, msg_overflow
    MOV X2, #msg_overflow_len
    MOV X8, #SYS_write
    SVC #0

.Lsig_recover:
    // Modify ucontext registers to resume at repl_loop with clean state
    // X23 = ucontext_t* (saved at handler entry)
    ADR X3, repl_loop
    STR X3, [X23, #UC_PC]              // PC = repl_loop

    ADR X3, rp0
    LDR X3, [X3]
    STR X3, [X23, #UC_SP]              // SP = rp0

    ADR X3, sp0
    LDR X3, [X3]
    STR X3, [X23, #UC_X19]             // X19 = sp0 (DSP = empty)

    // Always restore LATEST and HERE — a fault during forth_colon may
    // have partially modified X21/X22 before STATE was set to compiling.
    ADR X3, state
    STR XZR, [X3]                       // state = 0
    ADR X3, saved_latest
    LDR X3, [X3]
    STR X3, [X23, #UC_X22]             // X22 = saved LATEST
    ADR X3, saved_here
    LDR X3, [X3]
    STR X3, [X23, #UC_X21]             // X21 = saved HERE

.Lsig_done:
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- Signal Handler Messages ----------
.section .rodata
msg_underflow:  .ascii "stack underflow\n"
.equ msg_underflow_len, . - msg_underflow
msg_overflow:   .ascii "stack overflow\n"
.equ msg_overflow_len, . - msg_overflow
msg_guard_fail: .ascii "fatal: guard page setup failed\n"
.equ msg_guard_fail_len, . - msg_guard_fail

// ---------- Terminal Data ----------
.bss
.align 2
orig_termios:
    .space TERMIOS_SIZE
raw_termios:
    .space TERMIOS_SIZE
isatty_termios:
    .space TERMIOS_SIZE
// Non-zero once platform_raw_mode has actually switched the terminal to raw,
// so platform_restore_term knows whether it has anything to restore.
term_is_raw:
    .space 8

// Kernel sigaction struct (144 bytes on ARM64: handler+flags+mask, no restorer)
.align 3
sigact:
    .space 144

// File I/O scratch buffers
.align 3
path_scratch:
    .space 256
path_scratch2:
    .space 256
stat_buf:
    .space 144

// ---------- File I/O ----------
// Internal platform routines for INCLUDED.

.equ SYS_close,   57
.equ SYS_openat,  56
.equ SYS_fstat,   80
.equ SYS_mmap,    222
.equ SYS_munmap,  215
.equ SYS_getcwd,  17
.equ SYS_chdir,   49
.equ SYS_renameat, 38

.equ AT_FDCWD,    -100
.equ O_RDONLY,    0
.equ O_WRONLY,    1
.equ O_RDWR,      2
.equ O_CREAT,     64        // 0100 octal
.equ O_TRUNC,     512       // 01000 octal
.equ CREATE_MODE, 438       // 0666 octal
.equ PROT_READ_V, 1
.equ PROT_WRITE_V, 2
.equ MAP_PRIVATE_V, 2
.equ MAP_ANONYMOUS_V, 0x20

// st_size is at offset 48 in struct stat (ARM64)
.equ STAT_ST_SIZE, 48

.text

// platform_open_file_mode ( X0=path X1=len X2=flags X3=mode -- X0=fd )
// Copies path to scratch buffer, null-terminates, opens with the given flags
// and mode. Returns fd (>=0) or negative errno. The copy uses X9-X11 so the
// incoming X2 (flags) and X3 (mode) survive for the openat call.
.global platform_open_file_mode
platform_open_file_mode:
    STP X29, X30, [SP, #-16]!

    // Copy path to scratch buffer and null-terminate
    ADR X9, path_scratch
    MOV X10, X1                     // X10 = len
    CMP X10, #255                   // clamp to buffer size - 1
    B.LE .Lopenm_copy
    MOV X10, #255
.Lopenm_copy:
    CBZ X10, .Lopenm_null
    LDRB W11, [X0], #1
    STRB W11, [X9], #1
    SUB X10, X10, #1
    B .Lopenm_copy
.Lopenm_null:
    STRB WZR, [X9]                  // null terminate

    // openat(AT_FDCWD, path, flags, mode)
    MOV X0, #AT_FDCWD
    ADR X1, path_scratch
    // X2 = flags, X3 = mode (preserved above)
    MOV X8, #SYS_openat
    SVC #0

    LDP X29, X30, [SP], #16
    RET

// platform_open_file ( X0=path X1=len -- X0=fd )
// Thin wrapper: open existing file read-only (used by INCLUDED).
.global platform_open_file
platform_open_file:
    MOV X2, #O_RDONLY              // flags
    MOV X3, #0                     // mode
    B platform_open_file_mode

// platform_create_file ( X0=path X1=len X2=fam -- X0=fd )
// Create or truncate a file: open with fam | O_CREAT | O_TRUNC, mode 0666.
.global platform_create_file
platform_create_file:
    MOV X9, #(O_CREAT | O_TRUNC)
    ORR X2, X2, X9                 // flags = fam | O_CREAT | O_TRUNC
    MOV X3, #CREATE_MODE           // mode
    B platform_open_file_mode

// platform_rename ( X0=old X1=old_len X2=new X3=new_len -- X0=0 or -errno )
// Copies both paths into null-terminated scratch buffers, then renameat() —
// an atomic replace, so it can't half-write the destination. Makes no calls,
// so it needs no frame; clobbers only caller-saved temporaries.
.global platform_rename
platform_rename:
    MOV X4, X2                      // save new ptr
    MOV X5, X3                      // save new len
    // copy old (X0,X1) → path_scratch, clamped to 255
    ADR X9, path_scratch
    MOV X10, X1
    CMP X10, #255
    B.LE .Lren_c1
    MOV X10, #255
.Lren_c1:
    CBZ X10, .Lren_c1e
.Lren_c1l:
    LDRB W11, [X0], #1
    STRB W11, [X9], #1
    SUB X10, X10, #1
    CBNZ X10, .Lren_c1l
.Lren_c1e:
    STRB WZR, [X9]                  // null terminate
    // copy new (X4,X5) → path_scratch2, clamped to 255
    ADR X9, path_scratch2
    MOV X10, X5
    CMP X10, #255
    B.LE .Lren_c2
    MOV X10, #255
.Lren_c2:
    CBZ X10, .Lren_c2e
.Lren_c2l:
    LDRB W11, [X4], #1
    STRB W11, [X9], #1
    SUB X10, X10, #1
    CBNZ X10, .Lren_c2l
.Lren_c2e:
    STRB WZR, [X9]
    // renameat(AT_FDCWD, path_scratch, AT_FDCWD, path_scratch2)
    MOV X0, #AT_FDCWD
    ADR X1, path_scratch
    MOV X2, #AT_FDCWD
    ADR X3, path_scratch2
    MOV X8, #SYS_renameat
    SVC #0
    RET

// platform_fstat ( X0=fd -- X0=size )
// Returns file size via fstat, or a negative errno if the fstat syscall fails.
.global platform_fstat
platform_fstat:
    // fstat(fd, &stat_buf)
    ADR X1, stat_buf
    MOV X8, #SYS_fstat
    SVC #0
    CMP X0, #0
    B.LT .Lfstat_done              // syscall failed → return -errno (in X0)
    // Extract st_size
    ADR X9, stat_buf
    LDR X0, [X9, #STAT_ST_SIZE]
.Lfstat_done:
    RET

// platform_getcwd ( X0=buf X1=size -- X0=n )
// Raw getcwd: fills buf with the absolute current working directory
// (NUL-terminated). Returns the number of bytes written including the NUL, or a
// negative errno on failure.
.global platform_getcwd
platform_getcwd:
    MOV X8, #SYS_getcwd
    SVC #0
    RET

// platform_chdir ( X0=path -- X0=0 or -errno )
// Raw chdir: path is a NUL-terminated absolute or relative directory path.
.global platform_chdir
platform_chdir:
    MOV X8, #SYS_chdir
    SVC #0
    RET

// platform_mmap_file ( X0=fd X1=size -- X0=addr )
// Maps file with PROT_READ, MAP_PRIVATE.
.global platform_mmap_file
platform_mmap_file:
    MOV X5, #0                      // offset = 0
    MOV X4, X0                      // fd
    MOV X3, #MAP_PRIVATE_V          // flags
    MOV X2, #PROT_READ_V            // prot
    // X1 already = size (length)
    MOV X0, #0                      // addr = NULL
    MOV X8, #SYS_mmap
    SVC #0
    RET

// platform_mmap_anon ( X0=size -- X0=addr )
// Anonymous private read/write mapping (heap memory backed by no file). Returns
// the page-aligned base address, or a negative errno on failure (MAP_FAILED).
// Page-granular: the kernel rounds size up to a whole page.
.global platform_mmap_anon
platform_mmap_anon:
    MOV X1, X0                      // length = size
    MOV X0, #0                      // addr = NULL (let kernel choose)
    MOV X2, #(PROT_READ_V | PROT_WRITE_V)        // prot (data, no exec)
    MOV X3, #(MAP_PRIVATE_V | MAP_ANONYMOUS_V)   // flags
    MOV X4, #-1                     // fd = -1 (required for MAP_ANONYMOUS)
    MOV X5, #0                      // offset = 0
    MOV X8, #SYS_mmap
    SVC #0
    RET

// platform_munmap ( X0=addr X1=size -- )
.global platform_munmap
platform_munmap:
    MOV X8, #SYS_munmap
    SVC #0
    RET

// platform_close_file ( X0=fd -- X0=0 or -errno )
.global platform_close_file
platform_close_file:
    MOV X8, #SYS_close
    SVC #0
    RET

// platform_read_file ( X0=fd X1=buf X2=count -- X0=bytes read or -errno )
// Single read() of up to count bytes. X0 is 0 at end of file.
.global platform_read_file
platform_read_file:
    MOV X8, #SYS_read
    SVC #0
    RET

// platform_getdents ( X0=fd X1=buf X2=count -- X0=bytes or -errno )
// getdents64: read directory entries (linux_dirent64 records) into buf. X0 is
// the bytes filled, 0 at end of the directory, or a negative errno. The fd must
// be a directory opened read-only (open-file with R/O works on Linux).
.global platform_getdents
platform_getdents:
    MOV X8, #SYS_getdents64
    SVC #0
    RET

// ---------- Facility Platform Functions ----------

.equ SYS_nanosleep, 101
.equ TIOCGWINSZ,    0x5413

// platform_key_ready ( -- X0=flag )
// Non-blocking check if a key is available on stdin.
.global platform_key_ready
platform_key_ready:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #16
    STR XZR, [SP]                   // zero the count
    MOV X8, #SYS_ioctl
    MOV X0, #STDIN
    MOV X1, #FIONREAD
    MOV X2, SP
    SVC #0
    CMP X0, #0
    B.LT .Lkr_none
    LDR W0, [SP]                    // count of bytes available
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET
.Lkr_none:
    MOV X0, #0
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET

// platform_ms ( X0=milliseconds -- )
// Sleep for the given number of milliseconds.
.global platform_ms
platform_ms:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #16                 // timespec: tv_sec(8), tv_nsec(8)
    // tv_sec = ms / 1000
    MOV X1, #1000
    UDIV X2, X0, X1                 // X2 = seconds
    MSUB X3, X2, X1, X0            // X3 = remainder ms
    STR X2, [SP]                    // tv_sec
    // tv_nsec = (ms % 1000) * 1000000
    MOV X4, #0x4240
    MOVK X4, #0xF, LSL #16          // X4 = 1000000
    MUL X3, X3, X4
    STR X3, [SP, #8]               // tv_nsec
    MOV X8, #SYS_nanosleep
    MOV X0, SP                      // req
    MOV X1, #0                      // rem = NULL
    SVC #0
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET

// platform_page ( -- )
// Clear screen using ANSI escape sequences.
.global platform_page
platform_page:
    STP X29, X30, [SP, #-16]!
    ADR X0, ansi_page
    MOV X1, #ansi_page_len
    BL platform_write
    LDP X29, X30, [SP], #16
    RET

// platform_at_xy ( X0=col X1=row -- )
// Move cursor using ANSI escape sequence ESC[row+1;col+1H.
.global platform_at_xy
platform_at_xy:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    ADD X23, X0, #1                 // col+1 (1-based)
    ADD X24, X1, #1                 // row+1 (1-based)
    SUB SP, SP, #32                 // buffer

    // Build ESC[row;colH
    MOV X0, SP
    MOV W9, #0x1b                   // ESC
    STRB W9, [X0], #1
    MOV W9, #'['
    STRB W9, [X0], #1

    // Convert row to decimal
    MOV X1, X24
    BL .Latxy_itoa_arm64

    MOV W9, #';'
    STRB W9, [X0], #1

    // Convert col to decimal
    MOV X1, X23
    BL .Latxy_itoa_arm64

    MOV W9, #'H'
    STRB W9, [X0], #1

    // Write escape sequence
    MOV X1, X0
    MOV X0, SP
    SUB X1, X1, X0                  // length
    BL platform_write

    ADD SP, SP, #32
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// Helper: write unsigned integer X1 as decimal to [X0], advance X0
.Latxy_itoa_arm64:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #32                 // temp digit buffer
    MOV X2, #0                      // digit count
    MOV X3, SP
    MOV X4, #10
.Latxy_div:
    UDIV X5, X1, X4
    MSUB X6, X5, X4, X1            // X6 = remainder
    ADD W6, W6, #'0'
    STRB W6, [X3, X2]
    ADD X2, X2, #1
    MOV X1, X5
    CBNZ X1, .Latxy_div
    // Digits are in reverse — emit backwards
    SUB X2, X2, #1
.Latxy_emit:
    LDRB W6, [X3, X2]
    STRB W6, [X0], #1
    SUBS X2, X2, #1
    B.GE .Latxy_emit
    ADD SP, SP, #32
    LDP X29, X30, [SP], #16
    RET

// platform_screen_width ( -- X0=cols )
// Query terminal width. Default 80 on failure.
.global platform_screen_width
platform_screen_width:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #16
    MOV X8, #SYS_ioctl
    MOV X0, #STDOUT
    MOV X1, #TIOCGWINSZ
    MOV X2, SP
    SVC #0
    CMP X0, #0
    B.LT .Lsw_def
    LDRH W0, [SP, #2]              // ws_col at offset 2
    CBZ W0, .Lsw_def
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET
.Lsw_def:
    MOV X0, #80
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET

// platform_screen_height ( -- X0=rows )
// Query terminal height. Default 25 on failure.
.global platform_screen_height
platform_screen_height:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #16
    MOV X8, #SYS_ioctl
    MOV X0, #STDOUT
    MOV X1, #TIOCGWINSZ
    MOV X2, SP
    SVC #0
    CMP X0, #0
    B.LT .Lsh_def
    LDRH W0, [SP]                   // ws_row at offset 0
    CBZ W0, .Lsh_def
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET
.Lsh_def:
    MOV X0, #25
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET

// ---------- MS@ (Millisecond Timestamp) ----------
// platform_ms_get ( -- X0=milliseconds )
// Returns monotonic milliseconds via clock_gettime(CLOCK_MONOTONIC).
.global platform_ms_get
platform_ms_get:
    STP X29, X30, [SP, #-16]!
    SUB SP, SP, #16                 // timespec: tv_sec(8), tv_nsec(8)
    MOV X0, #CLOCK_MONOTONIC
    MOV X1, SP
    MOV X8, #SYS_clock_gettime
    SVC #0
    // ms = tv_sec * 1000 + tv_nsec / 1000000
    LDR X0, [SP]                    // tv_sec
    MOV X1, #1000
    MUL X0, X0, X1                  // tv_sec * 1000
    LDR X2, [SP, #8]               // tv_nsec
    MOV X3, #0x4240
    MOVK X3, #0xF, LSL #16          // X3 = 1000000
    UDIV X2, X2, X3                 // tv_nsec / 1000000
    ADD X0, X0, X2                  // total ms
    ADD SP, SP, #16
    LDP X29, X30, [SP], #16
    RET

// ---------- Cursor Visibility ----------
// platform_cursor_off ( -- )
// Hide cursor using ANSI escape sequence ESC[?25l.
.global platform_cursor_off
platform_cursor_off:
    STP X29, X30, [SP, #-16]!
    ADR X0, ansi_cursor_off
    MOV X1, #ansi_cursor_off_len
    BL platform_write
    LDP X29, X30, [SP], #16
    RET

// platform_cursor_on ( -- )
// Show cursor using ANSI escape sequence ESC[?25h.
.global platform_cursor_on
platform_cursor_on:
    STP X29, X30, [SP, #-16]!
    ADR X0, ansi_cursor_on
    MOV X1, #ansi_cursor_on_len
    BL platform_write
    LDP X29, X30, [SP], #16
    RET

// ---------- ANSI Escape Sequences ----------
.section .rodata
ansi_page:
    .byte 0x1b
    .ascii "[2J"
    .byte 0x1b
    .ascii "[H"
.equ ansi_page_len, . - ansi_page

ansi_cursor_off:
    .byte 0x1b
    .ascii "[?25l"
.equ ansi_cursor_off_len, . - ansi_cursor_off

ansi_cursor_on:
    .byte 0x1b
    .ascii "[?25h"
.equ ansi_cursor_on_len, . - ansi_cursor_on
