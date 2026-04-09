// BasicForth — Platform Layer (Linux/ARM64)
// Copyright (C) 2026 Brandon Blodget
// SPDX-License-Identifier: GPL-2.0-only
//
// Linux-specific I/O via syscalls. Swap this file to port to bare metal.

.equ SYS_ioctl, 29
.equ SYS_read,  63
.equ SYS_write, 64
.equ SYS_exit,  93

.equ STDIN,  0
.equ STDOUT, 1

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

    // TCGETS: read current terminal settings into orig_termios
    MOV X0, #STDIN
    MOV X1, #TCGETS
    ADR X2, orig_termios
    MOV X8, #SYS_ioctl
    SVC #0

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

    LDR X30, [SP], #16
    RET

// ---------- RESTORE TERMINAL ----------
// Restore original terminal settings (call before exit).
.global platform_restore_term
platform_restore_term:
    STR X30, [SP, #-16]!

    MOV X0, #STDIN
    MOV X1, #TCSETS
    ADR X2, orig_termios
    MOV X8, #SYS_ioctl
    SVC #0

    LDR X30, [SP], #16
    RET

// ---------- KEY ----------
// Read one character from stdin.
// Returns: X0 = character read
// On EOF (read returns 0), exits silently via platform_bye.
.global platform_key
platform_key:
    STR X30, [SP, #-16]!
    // Use stack padding area as read buffer (same trick as EMIT)
    MOV X0, #STDIN
    ADD X1, SP, #8             // buffer = stack padding area
    MOV X2, #1                 // count = 1
    MOV X8, #SYS_read
    SVC #0
    CMP X0, #0                 // EOF? (read returned 0)
    B.LE .Lkey_eof
    LDRB W0, [SP, #8]          // return the character in X0
    LDR X30, [SP], #16
    RET
.Lkey_eof:
    LDR X30, [SP], #16
    B platform_bye              // silent exit on EOF

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
// Write buffer to stdout.
// Input: X0 = buffer, X1 = length
.global platform_write
platform_write:
    MOV X2, X1                  // count
    MOV X1, X0                  // buf
    MOV X0, #STDOUT
    MOV X8, #SYS_write
    SVC #0
    RET

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
// Restore terminal and exit.
.global platform_bye
platform_bye:
    STR X30, [SP, #-16]!
    BL platform_restore_term
    MOV X0, #0
    MOV X8, #SYS_exit
    SVC #0

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

// Kernel sigaction struct (144 bytes on ARM64: handler+flags+mask, no restorer)
.align 3
sigact:
    .space 144

// File I/O scratch buffers
.align 3
path_scratch:
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

.equ AT_FDCWD,    -100
.equ O_RDONLY,    0
.equ PROT_READ_V, 1
.equ MAP_PRIVATE_V, 2

// st_size is at offset 48 in struct stat (ARM64)
.equ STAT_ST_SIZE, 48

.text

// platform_open_file ( X0=path X1=len -- X0=fd )
// Copies path to scratch buffer, null-terminates, opens with O_RDONLY.
// Returns fd (>=0) or negative errno on failure.
.global platform_open_file
platform_open_file:
    STP X29, X30, [SP, #-16]!

    // Copy path to scratch buffer and null-terminate
    ADR X2, path_scratch
    MOV X3, X1                      // X3 = len
    CMP X3, #255                    // clamp to buffer size - 1
    B.LE .Lopen_copy
    MOV X3, #255
.Lopen_copy:
    CBZ X3, .Lopen_null
    LDRB W4, [X0], #1
    STRB W4, [X2], #1
    SUB X3, X3, #1
    B .Lopen_copy
.Lopen_null:
    STRB WZR, [X2]                  // null terminate

    // openat(AT_FDCWD, path, O_RDONLY, 0)
    MOV X0, #AT_FDCWD
    ADR X1, path_scratch
    MOV X2, #O_RDONLY
    MOV X3, #0
    MOV X8, #SYS_openat
    SVC #0

    LDP X29, X30, [SP], #16
    RET

// platform_fstat ( X0=fd -- X0=size )
// Returns file size via fstat.
.global platform_fstat
platform_fstat:
    // fstat(fd, &stat_buf)
    MOV X1, X0                      // save fd... wait, X0=fd already
    ADR X1, stat_buf
    MOV X8, #SYS_fstat
    SVC #0
    // Extract st_size
    ADR X9, stat_buf
    LDR X0, [X9, #STAT_ST_SIZE]
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

// platform_munmap ( X0=addr X1=size -- )
.global platform_munmap
platform_munmap:
    MOV X8, #SYS_munmap
    SVC #0
    RET

// platform_close_file ( X0=fd -- )
.global platform_close_file
platform_close_file:
    MOV X8, #SYS_close
    SVC #0
    RET
