# BasicForth — Platform Layer (Linux/x86-64)
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Linux-specific I/O via syscalls. Swap this file to port to bare metal.
#
# x86-64 Linux syscall ABI:
#   syscall #: RAX
#   args:      RDI, RSI, RDX, R10, R8, R9
#   invoke:    syscall
#   return:    RAX (result or negative errno)
#   clobbered: RCX, R11

.equ SYS_ioctl,          16
.equ SYS_read,           0
.equ SYS_write,          1
.equ SYS_exit,           60
.equ SYS_clock_gettime,  228

.equ CLOCK_MONOTONIC, 1

.equ STDIN,  0
.equ STDOUT, 1
.equ STDERR, 2

# Terminal ioctl commands
.equ TCGETS, 0x5401
.equ TCSETS, 0x5402

# termios struct offsets (Linux x86-64)
# c_iflag:  offset 0   (4 bytes)
# c_oflag:  offset 4   (4 bytes)
# c_cflag:  offset 8   (4 bytes)
# c_lflag:  offset 12  (4 bytes)
# c_line:   offset 16  (1 byte)
# c_cc[32]: offset 17  (32 bytes)
# c_ispeed: offset 52  (4 bytes)
# c_ospeed: offset 56  (4 bytes)
# Total: 60 bytes
.equ TERMIOS_SIZE, 60
.equ OFFSET_IFLAG, 0
.equ OFFSET_LFLAG, 12
.equ OFFSET_CC,    17

# c_iflag bits
.equ IXON,   0x400              # XON/XOFF flow control (Ctrl+S/Ctrl+Q)

# c_lflag bits
.equ ECHO,   0x08               # echo input
.equ ICANON, 0x02               # canonical (line-buffered) mode

# Additional ioctl commands
.equ FIONREAD, 0x541B           # get bytes available to read (for future KEY?)

# c_cc indices
.equ VTIME, 5
.equ VMIN,  6

# ---------- RAW MODE ----------
# Switch terminal to raw mode for character-at-a-time input.
# Saves original settings for restore on exit.
.global platform_raw_mode
platform_raw_mode:
    # Lazy and idempotent: called at the start of every interactive input
    # (KEY / KEY? / ACCEPT). Switch to raw mode the first time, and only when
    # stdin is a terminal. Consequences:
    #   - A program that never reads input (e.g. `tool.fs | less`) never
    #     touches the terminal, so it can't leave it in raw mode for a
    #     downstream program to capture and later restore.
    #   - We key off stdin (the thing we read), not stdout, so an interactive
    #     session still gets raw mode even when its stdout is piped/redirected.
    cmpq $0, term_is_raw(%rip)
    jne .Lraw_skip                  # already raw — nothing to do
    mov $STDIN, %rdi
    call platform_isatty
    test %rax, %rax
    jz .Lraw_skip                   # stdin not a tty → stay cooked

    # TCGETS: read current terminal settings into orig_termios
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $TCGETS, %rsi
    lea orig_termios(%rip), %rdx
    syscall
    test %rax, %rax
    js .Lraw_skip                   # TCGETS failed → orig_termios invalid, bail

    # Copy orig_termios to raw_termios
    lea orig_termios(%rip), %rsi
    lea raw_termios(%rip), %rdi
    mov $TERMIOS_SIZE, %rcx
    cld
    rep movsb

    # Modify raw_termios for raw mode
    lea raw_termios(%rip), %rdi

    # Clear IXON in c_iflag (free Ctrl+S and Ctrl+Q for input)
    movl OFFSET_IFLAG(%rdi), %eax
    andl $~IXON, %eax
    movl %eax, OFFSET_IFLAG(%rdi)
    # Note: ICRNL left ON — terminal converts CR to NL for us

    # Clear ECHO, ICANON in c_lflag (keep ISIG for Ctrl+C)
    movl OFFSET_LFLAG(%rdi), %eax
    andl $~(ECHO | ICANON), %eax
    movl %eax, OFFSET_LFLAG(%rdi)

    # Set VMIN=1, VTIME=0 (blocking read, one char at a time)
    movb $1, (OFFSET_CC + VMIN)(%rdi)
    movb $0, (OFFSET_CC + VTIME)(%rdi)

    # TCSETS: apply raw settings
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $TCSETS, %rsi
    lea raw_termios(%rip), %rdx
    syscall
    test %rax, %rax
    js .Lraw_skip                   # apply failed → terminal unchanged, don't mark

    movq $1, term_is_raw(%rip)      # raw applied and orig_termios valid
.Lraw_skip:
    ret

# ---------- RESTORE TERMINAL ----------
# Restore original terminal settings (call before exit). No-op if we never
# entered raw mode — otherwise we'd write an uninitialized orig_termios and
# corrupt a terminal we never touched.
.global platform_restore_term
platform_restore_term:
    cmpq $0, term_is_raw(%rip)
    je .Lrestore_skip
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $TCSETS, %rsi
    lea orig_termios(%rip), %rdx
    syscall
    movq $0, term_is_raw(%rip)
.Lrestore_skip:
    ret

# ---------- ISATTY ----------
# platform_isatty ( RDI=fd -- RAX=1 if fd is a terminal, 0 otherwise )
# Probes with TCGETS: it succeeds on a tty and fails (-ENOTTY) on a
# pipe/file/redirect. Uses a private scratch buffer so it never disturbs the
# saved orig_termios used for restore.
.global platform_isatty
platform_isatty:
    mov $SYS_ioctl, %rax
    mov $TCGETS, %rsi
    lea isatty_termios(%rip), %rdx
    syscall
    test %rax, %rax
    js .Lisatty_no             # negative errno -> not a tty
    mov $1, %eax
    ret
.Lisatty_no:
    xor %eax, %eax
    ret

# ---------- KEY ----------
# Read one character from stdin.
# Returns: RDI = character read (for forth_key to push)
# On EOF (read returns 0), exits silently via platform_bye.
# Parses ANSI escape sequences for arrow keys:
#   ESC [ A → 129 (KEY_UP)    ESC [ B → 130 (KEY_DOWN)
#   ESC [ C → 131 (KEY_RIGHT) ESC [ D → 132 (KEY_LEFT)
# Standalone ESC (no following bytes) returns 27.
.global platform_key
platform_key:
    sub $16, %rsp               # allocate buffer on stack
    mov $SYS_read, %rax
    mov $STDIN, %rdi
    lea 8(%rsp), %rsi          # buffer
    mov $1, %rdx               # count = 1
    syscall
    test %rax, %rax             # EOF? (read returned 0)
    jle .Lkey_eof
    movzbl 8(%rsp), %edi       # char in RDI
    cmp $27, %edi               # ESC?
    je .Lkey_esc
    add $16, %rsp
    ret

.Lkey_esc:
    # Check if more bytes are available (FIONREAD)
    movq $0, (%rsp)
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $FIONREAD, %rsi
    lea (%rsp), %rdx
    syscall
    cmpl $0, (%rsp)
    jle .Lkey_esc_standalone    # no more bytes → standalone ESC

    # Read next byte — expect '['
    mov $SYS_read, %rax
    mov $STDIN, %rdi
    lea 8(%rsp), %rsi
    mov $1, %rdx
    syscall
    test %rax, %rax
    jle .Lkey_esc_standalone
    cmpb $'[', 8(%rsp)
    jne .Lkey_esc_standalone    # not '[' → return ESC (discard byte)

    # Read the final byte of the escape sequence
    mov $SYS_read, %rax
    mov $STDIN, %rdi
    lea 8(%rsp), %rsi
    mov $1, %rdx
    syscall
    test %rax, %rax
    jle .Lkey_esc_standalone
    movzbl 8(%rsp), %edi

    # Map A/B/C/D to abstract key codes 129-132
    cmp $'A', %edi
    je .Lkey_up
    cmp $'B', %edi
    je .Lkey_down
    cmp $'C', %edi
    je .Lkey_right
    cmp $'D', %edi
    je .Lkey_left
    # Unknown sequence — return ESC
    jmp .Lkey_esc_standalone

.Lkey_up:
    mov $129, %edi
    add $16, %rsp
    ret
.Lkey_down:
    mov $130, %edi
    add $16, %rsp
    ret
.Lkey_right:
    mov $131, %edi
    add $16, %rsp
    ret
.Lkey_left:
    mov $132, %edi
    add $16, %rsp
    ret

.Lkey_esc_standalone:
    mov $27, %edi
    add $16, %rsp
    ret

.Lkey_eof:
    add $16, %rsp
    jmp platform_bye            # silent exit on EOF

# ---------- EMIT ----------
# Write one character to stdout.
# Input: RDI = character to write
# Called by forth_emit in core.s, which handles the data stack.
.global platform_emit
platform_emit:
    sub $16, %rsp               # allocate buffer on stack
    movb %dil, 8(%rsp)         # store char byte
    mov $SYS_write, %rax
    mov $STDOUT, %rdi           # fd = 1
    lea 8(%rsp), %rsi          # buf
    mov $1, %rdx               # count = 1
    syscall
    add $16, %rsp
    ret

# ---------- WRITE ----------
# platform_write_fd ( RDI=fd, RSI=buffer, RDX=length -- RAX=bytes written or -errno )
# Generic write to any file descriptor. Returns the raw syscall result so
# callers (e.g. WRITE-FILE) can derive an ior.
.global platform_write_fd
platform_write_fd:
    mov $SYS_write, %rax
    syscall
    ret

# platform_write ( RSI=buffer, RDX=length ) — write to stdout.
# Thin wrapper so existing callers (TYPE, banner, error messages) are unchanged.
.global platform_write
platform_write:
    mov $STDOUT, %rdi
    jmp platform_write_fd

# ---------- BYE ----------
# Restore terminal and exit.
# platform_exit ( RDI=status -- ) — restore terminal and exit with status.
.global platform_exit
platform_exit:
    push %rdi                   # preserve status across the ioctl call
    call platform_restore_term
    pop %rdi
    mov $SYS_exit, %rax
    syscall

.global platform_bye
platform_bye:
    xor %rdi, %rdi             # status = 0
    jmp platform_exit

# ---------- Guard Pages ----------
# Set up SIGSEGV handler and mprotect guard pages around the data stack.
# Must be called before platform_raw_mode (early in startup).

.equ SYS_mprotect,     10
.equ SYS_rt_sigaction, 13
.equ SIGSEGV,          11
.equ PROT_NONE,        0
.equ SA_SIGINFO,       0x04
.equ SA_NODEFER,       0x40000000
.equ SA_RESTORER,      0x04000000
.equ PAGE_SIZE,        4096

# ucontext_t offsets for x86-64 (from kernel headers)
.equ UC_MCONTEXT_GREGS, 40       # offset of uc_mcontext.gregs in ucontext_t
.equ GREGS_R12,  72              # UC_MCONTEXT_GREGS + 4*8  (REG_R12=4)
.equ GREGS_R13,  80              # UC_MCONTEXT_GREGS + 5*8  (REG_R13=5)
.equ GREGS_R15,  96              # UC_MCONTEXT_GREGS + 7*8  (REG_R15=7)
.equ GREGS_RSP, 160              # UC_MCONTEXT_GREGS + 15*8 (REG_RSP=15)
.equ GREGS_RIP, 168              # UC_MCONTEXT_GREGS + 16*8 (REG_RIP=16)

# siginfo_t offset
.equ SI_ADDR, 16                 # offset of si_addr in siginfo_t

.global platform_init_guard_pages
platform_init_guard_pages:
    push %rbx

    # mprotect(guard_page_underflow, PAGE_SIZE, PROT_NONE)
    mov $SYS_mprotect, %rax
    lea guard_page_underflow(%rip), %rdi
    mov $PAGE_SIZE, %rsi
    xor %edx, %edx              # PROT_NONE = 0
    syscall
    test %rax, %rax
    jnz .Lguard_fail

    # mprotect(guard_page_overflow, PAGE_SIZE, PROT_NONE)
    mov $SYS_mprotect, %rax
    lea guard_page_overflow(%rip), %rdi
    mov $PAGE_SIZE, %rsi
    xor %edx, %edx
    syscall
    test %rax, %rax
    jnz .Lguard_fail

    # rt_sigaction(SIGSEGV, &sigact, NULL, 8)
    # Kernel sigaction struct: [handler:8][flags:8][restorer:8][mask:128]
    lea sigact(%rip), %rbx

    # Set handler
    lea sigsegv_handler(%rip), %rax
    mov %rax, (%rbx)

    # Set flags: SA_SIGINFO | SA_NODEFER | SA_RESTORER
    movq $(SA_SIGINFO | SA_NODEFER | SA_RESTORER), 8(%rbx)

    # Set restorer (required by kernel on x86-64)
    lea sa_restorer_trampoline(%rip), %rax
    mov %rax, 16(%rbx)

    # Zero the signal mask (128 bytes at offset 24)
    lea 24(%rbx), %rdi
    xor %eax, %eax
    mov $16, %rcx               # 16 qwords = 128 bytes
    cld
    rep stosq

    # rt_sigaction(SIGSEGV, &sigact, NULL, sizeof(sigset_t))
    mov $SYS_rt_sigaction, %rax
    mov $SIGSEGV, %rdi
    mov %rbx, %rsi              # &sigact
    xor %edx, %edx              # old = NULL
    mov $8, %r10                # sizeof(sigset_t) for kernel
    syscall
    test %rax, %rax
    jnz .Lguard_fail

    pop %rbx
    ret

.Lguard_fail:
    # Fatal: guard page setup failed — exit with error message
    mov $SYS_write, %rax
    mov $STDOUT, %rdi
    lea msg_guard_fail(%rip), %rsi
    mov $msg_guard_fail_len, %rdx
    syscall
    mov $SYS_exit, %rax
    mov $1, %rdi
    syscall

# sa_restorer trampoline — kernel requires this for signal return
sa_restorer_trampoline:
    mov $15, %rax               # SYS_rt_sigreturn
    syscall

# SIGSEGV signal handler
# Called with: RDI = signum, RSI = siginfo_t*, RDX = ucontext_t*
sigsegv_handler:
    push %rbx
    mov %rdx, %rbx              # RBX = ucontext (save before syscalls clobber RDX)

    # Get faulting address from siginfo_t
    mov SI_ADDR(%rsi), %rax     # RAX = faulting address

    # Check if fault is in underflow guard page
    lea guard_page_underflow(%rip), %rcx
    cmp %rcx, %rax
    jb .Lsig_check_overflow
    lea guard_page_underflow+PAGE_SIZE(%rip), %rcx
    cmp %rcx, %rax
    jb .Lsig_underflow

.Lsig_check_overflow:
    # Check if fault is in overflow guard page
    lea guard_page_overflow(%rip), %rcx
    cmp %rcx, %rax
    jb .Lsig_unknown
    lea guard_page_overflow+PAGE_SIZE(%rip), %rcx
    cmp %rcx, %rax
    jb .Lsig_overflow

.Lsig_unknown:
    # Not our guard page — re-raise default SIGSEGV
    # Reset handler to SIG_DFL (0) and re-raise
    lea sigact(%rip), %rsi
    movq $0, (%rsi)             # handler = SIG_DFL
    movq $0, 8(%rsi)            # flags = 0
    mov $SYS_rt_sigaction, %rax
    mov $SIGSEGV, %rdi
    xor %edx, %edx
    mov $8, %r10
    syscall
    # Return from handler — the faulting instruction re-executes,
    # this time with default handler → crash with core dump
    pop %rbx
    ret

.Lsig_underflow:
    # Print "stack underflow\n"
    mov $SYS_write, %rax
    mov $STDOUT, %rdi
    lea msg_underflow(%rip), %rsi
    mov $msg_underflow_len, %rdx
    syscall
    jmp .Lsig_recover

.Lsig_overflow:
    # Print "stack overflow\n"
    mov $SYS_write, %rax
    mov $STDOUT, %rdi
    lea msg_overflow(%rip), %rsi
    mov $msg_overflow_len, %rdx
    syscall

.Lsig_recover:
    # Modify ucontext registers to resume at repl_loop with clean state
    # RBX = ucontext_t* (saved at handler entry)
    lea repl_loop(%rip), %rax
    mov %rax, GREGS_RIP(%rbx)           # RIP = repl_loop

    mov rp0(%rip), %rax
    mov %rax, GREGS_RSP(%rbx)           # RSP = rp0

    mov sp0(%rip), %rax
    mov %rax, GREGS_R15(%rbx)           # R15 = sp0 (DSP = empty)

    # Always restore LATEST and HERE — a fault during forth_colon may
    # have partially modified R12/R13 before STATE was set to compiling.
    movq $0, state(%rip)
    mov saved_latest(%rip), %rax
    mov %rax, GREGS_R12(%rbx)           # R12 = saved LATEST
    mov saved_here(%rip), %rax
    mov %rax, GREGS_R13(%rbx)           # R13 = saved HERE

.Lsig_done:
    # Return from signal handler — kernel restores modified ucontext
    pop %rbx
    ret

# ---------- Signal Handler Messages ----------
.section .rodata
msg_underflow:  .ascii "stack underflow\n"
.equ msg_underflow_len, . - msg_underflow
msg_overflow:   .ascii "stack overflow\n"
.equ msg_overflow_len, . - msg_overflow
msg_guard_fail: .ascii "fatal: guard page setup failed\n"
.equ msg_guard_fail_len, . - msg_guard_fail

# ---------- Terminal Data ----------
.bss
.align 4
orig_termios:
    .space TERMIOS_SIZE
raw_termios:
    .space TERMIOS_SIZE
isatty_termios:
    .space TERMIOS_SIZE
# Non-zero once platform_raw_mode has actually switched the terminal to raw,
# so platform_restore_term knows whether it has anything to restore.
term_is_raw:
    .space 8

# Kernel sigaction struct (152 bytes)
.align 8
sigact:
    .space 152

# File I/O scratch buffers
.align 8
path_scratch:
    .space 256
path_scratch2:
    .space 256
stat_buf:
    .space 144

# ---------- File I/O ----------
# Internal platform routines for INCLUDED.

.equ SYS_close,   3
.equ SYS_fstat,   5
.equ SYS_mmap,    9
.equ SYS_munmap,  11
.equ SYS_openat,  257
.equ SYS_renameat, 264

.equ AT_FDCWD,    -100
.equ O_RDONLY,    0
.equ O_WRONLY,    1
.equ O_RDWR,      2
.equ O_CREAT,     64        # 0100 octal
.equ O_TRUNC,     512       # 01000 octal
.equ CREATE_MODE, 438       # 0666 octal
.equ PROT_READ,   1
.equ PROT_WRITE,  2
.equ MAP_PRIVATE, 2
.equ MAP_ANONYMOUS, 0x20

# st_size is at offset 48 in struct stat (x86-64)
.equ STAT_ST_SIZE, 48

.text

# platform_open_file_mode ( RSI=path RDX=len R8=flags R9=mode -- RAX=fd )
# Copies path to scratch buffer, null-terminates, opens with the given open
# flags and mode. Returns fd (>=0) or negative errno on failure. R8/R9 survive
# the path copy (rep movsb only touches RDI/RSI/RCX).
.global platform_open_file_mode
platform_open_file_mode:
    # Copy path to scratch buffer and null-terminate
    lea path_scratch(%rip), %rdi
    mov %rdx, %rcx              # count = len
    cmp $255, %rcx              # clamp to buffer size - 1
    jbe .Lopen_copy
    mov $255, %rcx
.Lopen_copy:
    cld
    rep movsb
    movb $0, (%rdi)             # null terminate

    # openat(AT_FDCWD, path, flags, mode)
    mov $SYS_openat, %rax
    mov $AT_FDCWD, %rdi
    lea path_scratch(%rip), %rsi
    mov %r8, %rdx              # flags
    mov %r9, %r10             # mode
    syscall
    ret

# platform_open_file ( RSI=path RDX=len -- RAX=fd )
# Thin wrapper: open existing file read-only (used by INCLUDED).
.global platform_open_file
platform_open_file:
    xor %r8d, %r8d             # flags = O_RDONLY (0)
    xor %r9d, %r9d             # mode = 0
    jmp platform_open_file_mode

# platform_create_file ( RSI=path RDX=len R8=fam -- RAX=fd )
# Create or truncate a file: open with fam | O_CREAT | O_TRUNC, mode 0666.
.global platform_create_file
platform_create_file:
    or $(O_CREAT | O_TRUNC), %r8
    mov $CREATE_MODE, %r9
    jmp platform_open_file_mode

# platform_rename ( RDI=old RSI=old_len RDX=new RCX=new_len -- RAX=0 or -errno )
# Copies both paths into null-terminated scratch buffers, then renameat() —
# an atomic replace, so it can't half-write the destination.
.global platform_rename
platform_rename:
    push %rdx                   # save new ptr
    push %rcx                   # save new len
    # copy old (RDI) → path_scratch, clamped to 255
    mov %rsi, %rcx              # count = old_len
    cmp $255, %rcx
    jbe .Lren_c1
    mov $255, %rcx
.Lren_c1:
    mov %rdi, %rsi             # src = old
    lea path_scratch(%rip), %rdi
    cld
    rep movsb
    movb $0, (%rdi)            # null terminate
    # copy new → path_scratch2
    pop %rcx                   # new len
    pop %rsi                   # new ptr
    cmp $255, %rcx
    jbe .Lren_c2
    mov $255, %rcx
.Lren_c2:
    lea path_scratch2(%rip), %rdi
    rep movsb
    movb $0, (%rdi)
    # renameat(AT_FDCWD, path_scratch, AT_FDCWD, path_scratch2)
    mov $SYS_renameat, %rax
    mov $AT_FDCWD, %rdi
    lea path_scratch(%rip), %rsi
    mov $AT_FDCWD, %rdx
    lea path_scratch2(%rip), %r10
    syscall
    ret

# platform_fstat ( RDI=fd -- RAX=size )
# Returns file size via fstat, or a negative errno if the fstat syscall fails.
.global platform_fstat
platform_fstat:
    mov $SYS_fstat, %rax
    # RDI already = fd
    lea stat_buf(%rip), %rsi
    syscall
    test %rax, %rax
    js .Lfstat_done            # syscall failed → return -errno (already in RAX)
    # Extract st_size
    mov stat_buf+STAT_ST_SIZE(%rip), %rax
.Lfstat_done:
    ret

# platform_mmap_file ( RDI=fd RSI=size -- RAX=addr )
# Maps file with PROT_READ, MAP_PRIVATE.
.global platform_mmap_file
platform_mmap_file:
    mov %rsi, %rbx              # save size
    mov $SYS_mmap, %rax
    mov %rdi, %r8               # arg5 = fd
    xor %edi, %edi              # arg1 = addr = NULL
    mov %rbx, %rsi              # arg2 = length = size
    mov $PROT_READ, %edx        # arg3 = prot
    mov $MAP_PRIVATE, %r10d     # arg4 = flags
    xor %r9d, %r9d              # arg6 = offset = 0
    syscall
    ret

# platform_mmap_anon ( RDI=size -- RAX=addr )
# Anonymous private read/write mapping (heap memory backed by no file). Returns
# the page-aligned base address, or a negative errno on failure (MAP_FAILED).
# Page-granular: the kernel rounds size up to a whole page.
.global platform_mmap_anon
platform_mmap_anon:
    mov %rdi, %rsi              # arg2 = length = size
    mov $SYS_mmap, %rax
    xor %edi, %edi              # arg1 = addr = NULL (let kernel choose)
    mov $(PROT_READ | PROT_WRITE), %edx          # arg3 = prot (data, no exec)
    mov $(MAP_PRIVATE | MAP_ANONYMOUS), %r10d    # arg4 = flags
    mov $-1, %r8               # arg5 = fd = -1 (required for MAP_ANONYMOUS)
    xor %r9d, %r9d            # arg6 = offset = 0
    syscall
    ret

# platform_munmap ( RDI=addr RSI=size -- )
.global platform_munmap
platform_munmap:
    mov $SYS_munmap, %rax
    syscall
    ret

# platform_close_file ( RDI=fd -- RAX=0 or -errno )
.global platform_close_file
platform_close_file:
    mov $SYS_close, %rax
    syscall
    ret

# platform_read_file ( RDI=fd RSI=buf RDX=count -- RAX=bytes read or -errno )
# Single read() of up to count bytes. RAX is 0 at end of file.
.global platform_read_file
platform_read_file:
    mov $SYS_read, %rax
    syscall
    ret

# ---------- Facility Platform Functions ----------

.equ SYS_nanosleep, 35
.equ TIOCGWINSZ,    0x5413

# platform_key_ready ( -- RDI=flag )
# Non-blocking check if a key is available on stdin.
# Uses ioctl(FIONREAD) to check bytes available.
.global platform_key_ready
platform_key_ready:
    sub $16, %rsp                   # allocate space for count
    movq $0, (%rsp)                 # zero it
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $FIONREAD, %rsi
    lea (%rsp), %rdx
    syscall
    test %rax, %rax
    js .Lkr_none                    # ioctl failed → no key
    mov (%rsp), %edi                # count of bytes available
    add $16, %rsp
    ret
.Lkr_none:
    xor %edi, %edi
    add $16, %rsp
    ret

# platform_ms ( RDI=milliseconds -- )
# Sleep for the given number of milliseconds using nanosleep.
.global platform_ms
platform_ms:
    sub $32, %rsp                   # timespec: tv_sec(8), tv_nsec(8)
    # tv_sec = ms / 1000
    mov %rdi, %rax
    xor %edx, %edx
    mov $1000, %rcx
    div %rcx                        # RAX = seconds, RDX = remainder ms
    mov %rax, (%rsp)                # tv_sec
    # tv_nsec = (ms % 1000) * 1000000
    imul $1000000, %rdx, %rdx
    mov %rdx, 8(%rsp)              # tv_nsec
    mov $SYS_nanosleep, %rax
    lea (%rsp), %rdi                # req
    xor %esi, %esi                  # rem = NULL
    syscall
    add $32, %rsp
    ret

# platform_page ( -- )
# Clear the screen and move cursor to home using ANSI escape sequences.
.global platform_page
platform_page:
    lea ansi_page(%rip), %rsi
    mov $ansi_page_len, %rdx
    call platform_write
    ret

# platform_at_xy ( RDI=col RSI=row -- )
# Move cursor to (col, row) using ANSI escape sequence ESC[row+1;col+1H.
# Builds the escape string on the stack.
.global platform_at_xy
platform_at_xy:
    push %rbx
    push %rbp
    mov %rdi, %rbx                  # RBX = col (0-based)
    mov %rsi, %rbp                  # RBP = row (0-based)
    sub $32, %rsp

    # Build ESC[row+1;col+1H in stack buffer
    mov %rsp, %rdi                  # RDI = buffer
    movb $0x1b, (%rdi)              # ESC
    movb $'[', 1(%rdi)
    lea 2(%rdi), %rdi

    # Convert row+1 to decimal
    lea 1(%rbp), %rax
    call .Latxy_itoa                # writes digits, RDI advances

    movb $';', (%rdi)
    inc %rdi

    # Convert col+1 to decimal
    lea 1(%rbx), %rax
    call .Latxy_itoa

    movb $'H', (%rdi)
    inc %rdi

    # Write the escape sequence
    mov %rdi, %rdx
    lea (%rsp), %rsi
    sub %rsi, %rdx                  # length
    call platform_write

    add $32, %rsp
    pop %rbp
    pop %rbx
    ret

# Helper: write unsigned integer in RAX as decimal ASCII to [RDI], advance RDI
.Latxy_itoa:
    # Convert to decimal digits on a mini stack
    push %rcx
    mov %rdi, %rcx                  # save start
    mov $10, %r9
    xor %r8d, %r8d                  # digit count
.Latxy_div:
    xor %edx, %edx
    div %r9                         # RAX = quot, RDX = rem
    add $'0', %dl
    push %rdx                       # save digit
    inc %r8d
    test %rax, %rax
    jnz .Latxy_div
.Latxy_emit:
    pop %rdx
    movb %dl, (%rdi)
    inc %rdi
    dec %r8d
    jnz .Latxy_emit
    pop %rcx
    ret

# platform_screen_width ( -- RAX=cols )
# Query terminal width via ioctl(TIOCGWINSZ). Default 80 on failure.
.global platform_screen_width
platform_screen_width:
    sub $16, %rsp
    mov $SYS_ioctl, %rax
    mov $STDOUT, %rdi
    mov $TIOCGWINSZ, %rsi
    lea (%rsp), %rdx
    syscall
    test %rax, %rax
    js .Lsw_default
    movzwl 2(%rsp), %eax            # ws_col at offset 2
    test %eax, %eax
    jz .Lsw_default
    add $16, %rsp
    ret
.Lsw_default:
    mov $80, %eax
    add $16, %rsp
    ret

# platform_screen_height ( -- RAX=rows )
# Query terminal height via ioctl(TIOCGWINSZ). Default 25 on failure.
.global platform_screen_height
platform_screen_height:
    sub $16, %rsp
    mov $SYS_ioctl, %rax
    mov $STDOUT, %rdi
    mov $TIOCGWINSZ, %rsi
    lea (%rsp), %rdx
    syscall
    test %rax, %rax
    js .Lsh_default
    movzwl (%rsp), %eax             # ws_row at offset 0
    test %eax, %eax
    jz .Lsh_default
    add $16, %rsp
    ret
.Lsh_default:
    mov $25, %eax
    add $16, %rsp
    ret

# ---------- MS@ (Millisecond Timestamp) ----------
# platform_ms_get ( -- RAX=milliseconds )
# Returns monotonic milliseconds via clock_gettime(CLOCK_MONOTONIC).
.global platform_ms_get
platform_ms_get:
    sub $32, %rsp                   # timespec: tv_sec(8), tv_nsec(8)
    mov $SYS_clock_gettime, %rax
    mov $CLOCK_MONOTONIC, %rdi
    lea (%rsp), %rsi
    syscall
    # ms = tv_sec * 1000 + tv_nsec / 1000000
    mov (%rsp), %rax                # tv_sec
    imul $1000, %rax                # tv_sec * 1000
    mov 8(%rsp), %rcx              # tv_nsec
    mov $1000000, %rdx
    push %rax                       # save sec*1000
    mov %rcx, %rax
    xor %edx, %edx
    mov $1000000, %rcx
    div %rcx                        # RAX = tv_nsec / 1000000
    pop %rcx                        # sec*1000
    add %rcx, %rax                  # total ms
    add $32, %rsp
    ret

# ---------- Cursor Visibility ----------
# platform_cursor_off ( -- )
# Hide cursor using ANSI escape sequence ESC[?25l.
.global platform_cursor_off
platform_cursor_off:
    lea ansi_cursor_off(%rip), %rsi
    mov $ansi_cursor_off_len, %rdx
    call platform_write
    ret

# platform_cursor_on ( -- )
# Show cursor using ANSI escape sequence ESC[?25h.
.global platform_cursor_on
platform_cursor_on:
    lea ansi_cursor_on(%rip), %rsi
    mov $ansi_cursor_on_len, %rdx
    call platform_write
    ret

# ---------- ANSI Escape Sequences ----------
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
