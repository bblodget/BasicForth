# BasicForth — Platform Layer (Linux/x86-64)
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
.global platform_key
platform_key:
    sub $16, %rsp               # allocate buffer on stack
    mov $SYS_read, %rax
    mov $STDIN, %rdi
    lea 8(%rsp), %rsi          # buffer
    mov $1, %rdx               # count = 1
    syscall
    movzbl 8(%rsp), %edi       # return char in RDI
    add $16, %rsp
    ret

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

# ---------- Terminal Data ----------
.bss
.align 4
orig_termios:
    .space TERMIOS_SIZE
raw_termios:
    .space TERMIOS_SIZE
