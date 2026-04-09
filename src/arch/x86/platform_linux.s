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

.equ SYS_ioctl, 16
.equ SYS_read,  0
.equ SYS_write, 1
.equ SYS_exit,  60

.equ STDIN,  0
.equ STDOUT, 1

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
    # TCGETS: read current terminal settings into orig_termios
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $TCGETS, %rsi
    lea orig_termios(%rip), %rdx
    syscall

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

    ret

# ---------- RESTORE TERMINAL ----------
# Restore original terminal settings (call before exit).
.global platform_restore_term
platform_restore_term:
    mov $SYS_ioctl, %rax
    mov $STDIN, %rdi
    mov $TCSETS, %rsi
    lea orig_termios(%rip), %rdx
    syscall
    ret

# ---------- KEY ----------
# Read one character from stdin.
# Returns: RDI = character read (for forth_key to push)
# On EOF (read returns 0), exits silently via platform_bye.
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
    movzbl 8(%rsp), %edi       # return char in RDI
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
# Write buffer to stdout.
# Input: RSI = buffer, RDX = length
.global platform_write
platform_write:
    mov $SYS_write, %rax
    mov $STDOUT, %rdi
    syscall
    ret

# ---------- BYE ----------
# Restore terminal and exit.
.global platform_bye
platform_bye:
    call platform_restore_term
    mov $SYS_exit, %rax
    xor %rdi, %rdi              # status = 0
    syscall

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

# Kernel sigaction struct (152 bytes)
.align 8
sigact:
    .space 152

# File I/O scratch buffers
.align 8
path_scratch:
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

.equ AT_FDCWD,    -100
.equ O_RDONLY,    0
.equ PROT_READ,   1
.equ MAP_PRIVATE, 2

# st_size is at offset 48 in struct stat (x86-64)
.equ STAT_ST_SIZE, 48

.text

# platform_open_file ( RSI=path RDX=len -- RAX=fd )
# Copies path to scratch buffer, null-terminates, opens with O_RDONLY.
# Returns fd (>=0) or negative errno on failure.
.global platform_open_file
platform_open_file:
    push %rbx

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

    # openat(AT_FDCWD, path, O_RDONLY, 0)
    mov $SYS_openat, %rax
    mov $AT_FDCWD, %rdi
    lea path_scratch(%rip), %rsi
    xor %edx, %edx              # O_RDONLY = 0
    xor %r10d, %r10d            # mode = 0
    syscall

    pop %rbx
    ret

# platform_fstat ( RDI=fd -- RAX=size )
# Returns file size via fstat.
.global platform_fstat
platform_fstat:
    mov %rdi, %rbx              # save fd (not needed but clear)
    mov $SYS_fstat, %rax
    # RDI already = fd
    lea stat_buf(%rip), %rsi
    syscall
    # Extract st_size
    mov stat_buf+STAT_ST_SIZE(%rip), %rax
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

# platform_munmap ( RDI=addr RSI=size -- )
.global platform_munmap
platform_munmap:
    mov $SYS_munmap, %rax
    syscall
    ret

# platform_close_file ( RDI=fd -- )
.global platform_close_file
platform_close_file:
    mov $SYS_close, %rax
    syscall
    ret
