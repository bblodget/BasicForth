# BasicForth — Outer Interpreter (x86-64)
#
# Register convention:
#   R15 = DSP (data stack pointer, points to second item)
#   R14 = TOS (top of stack value)
#   R13 = HERE (next free byte in dictionary)
#   R12 = LATEST (most recent dictionary entry)
#   RSP = Return stack

.global _start

.equ INPUT_BUF_SIZE, 80

_start:
    # Initialize engine registers
    lea data_stack_top(%rip), %r15  # DSP
    mov %r15, sp0(%rip)             # save initial DSP for .S
    lea dict_space(%rip), %r13      # HERE
    lea dict_bye(%rip), %r12        # LATEST
    xor %r14d, %r14d                # TOS = 0

    call platform_raw_mode

repl_loop:
    # Print prompt
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
    call platform_write

    # ACCEPT ( c-addr max -- count )
    sub $8, %r15
    mov %r14, (%r15)                # push old TOS
    lea input_buf(%rip), %r14
    sub $8, %r15
    mov %r14, (%r15)
    mov $INPUT_BUF_SIZE, %r14
    call forth_accept               # TOS = count

    # Newline (ACCEPT doesn't echo Enter)
    mov $'\n', %rdi
    call platform_emit

    # Empty line → exit
    test %r14, %r14
    jz repl_bye

    # Set up source variables for PARSE-WORD
    mov %r14, source_len(%rip)
    lea input_buf(%rip), %rax
    mov %rax, source_addr(%rip)
    movq $0, to_in(%rip)

    # Drop count (restore user's TOS)
    call forth_drop

interpret_loop:
    call forth_parse_word           # ( -- c-addr u )

    # End of line? (u == 0)
    test %r14, %r14
    jz interpret_done

    # FIND ( c-addr u -- xt flag | c-addr u 0 )
    call forth_find

    # Found? (flag != 0)
    test %r14, %r14
    jz try_number

    # Found — drop flag, execute word
    call forth_drop                 # drop flag, TOS = xt
    call forth_execute
    jmp interpret_loop

try_number:
    # Not in dictionary — drop 0 flag, try NUMBER
    call forth_drop                 # ( c-addr u )

    # NUMBER ( c-addr u -- n true | c-addr u false )
    call forth_number

    test %r14, %r14
    jz not_found

    # Parsed — drop true flag, number is on stack
    call forth_drop
    jmp interpret_loop

not_found:
    # Neither word nor number — error
    call forth_drop                 # drop false, ( c-addr u )

    # Print "? " + token + newline
    lea err_msg(%rip), %rsi
    mov $err_len, %rdx
    call platform_write

    mov %r14, %rdx                  # length = u (TOS)
    mov (%r15), %rsi                # buf = c-addr ([DSP])
    call platform_write

    mov $'\n', %rdi
    call platform_emit

    # Clean up c-addr and u
    call forth_drop                 # drop u
    call forth_drop                 # drop c-addr

    jmp repl_loop

interpret_done:
    # End of line — drop 0 0 from PARSE-WORD
    call forth_drop
    call forth_drop

    # Print " ok"
    lea ok_msg(%rip), %rsi
    mov $ok_len, %rdx
    call platform_write

    jmp repl_loop

repl_bye:
    call forth_drop                 # drop 0 count

    lea bye_msg(%rip), %rsi
    mov $bye_len, %rdx
    call platform_write

    call platform_bye

# ---------- Data ----------
.section .rodata
prompt_msg: .ascii "> "
.equ prompt_len, . - prompt_msg
ok_msg:     .ascii " ok\n"
.equ ok_len, . - ok_msg
err_msg:    .ascii "? "
.equ err_len, . - err_msg
bye_msg:    .ascii "Goodbye!\n"
.equ bye_len, . - bye_msg

.bss
.align 8
input_buf:
    .space INPUT_BUF_SIZE
