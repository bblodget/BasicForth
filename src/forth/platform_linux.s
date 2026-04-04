// PumpkinForth — Platform Layer (Linux)
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
.equ ICRNL,  0x100          // translate CR to NL

// c_lflag bits
.equ ECHO,   0x08           // echo input
.equ ICANON, 0x02           // canonical (line-buffered) mode
.equ ISIG,   0x04           // signal generation (Ctrl+C etc)

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

    // Clear ICRNL in c_iflag (don't translate CR to NL)
    LDR W1, [X0, #OFFSET_IFLAG]
    MOV W2, #ICRNL
    BIC W1, W1, W2
    STR W1, [X0, #OFFSET_IFLAG]

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
.global platform_key
platform_key:
    STR X30, [SP, #-16]!
    // Use stack padding area as read buffer (same trick as EMIT)
    MOV X0, #STDIN
    ADD X1, SP, #8             // buffer = stack padding area
    MOV X2, #1                 // count = 1
    MOV X8, #SYS_read
    SVC #0
    LDRB W0, [SP, #8]          // return the character in X0
    LDR X30, [SP], #16
    RET

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

// ---------- BYE ----------
// Restore terminal and exit.
.global platform_bye
platform_bye:
    STR X30, [SP, #-16]!
    BL platform_restore_term
    MOV X0, #0
    MOV X8, #SYS_exit
    SVC #0

// ---------- Terminal Data ----------
.bss
.align 2
orig_termios:
    .space TERMIOS_SIZE
raw_termios:
    .space TERMIOS_SIZE
