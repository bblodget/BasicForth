// PumpkinForth — ARM64 Linux Forth
// Lesson 1: Hello World

.global _start

// Linux ARM64 syscall numbers
.equ SYS_write, 64
.equ SYS_exit,  93

// File descriptors
.equ STDOUT, 1

.text

_start:
    // write(STDOUT, msg, msg_len)
    mov     x0, #STDOUT
    adr     x1, msg
    mov     x2, #msg_len
    mov     x8, #SYS_write
    svc     #0

    // exit(0)
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

.section .rodata
msg:    .ascii "Hello World\n"
.equ msg_len, . - msg
