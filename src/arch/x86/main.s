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
    lea dict_tick(%rip), %r12       # LATEST
    xor %r14d, %r14d                # TOS = 0

    call platform_raw_mode

repl_loop:
    # Save return stack pointer for error recovery
    mov %rsp, rp0(%rip)

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

    # Found — TOS = flag (1=IMMEDIATE, -1=normal), [DSP] = xt
    # If interpreting (STATE==0), always execute.
    # If compiling: IMMEDIATE words execute, normal words get compiled.
    cmpq $0, state(%rip)
    je found_execute                # interpreting → execute

    # Compiling — check IMMEDIATE flag
    cmp $1, %r14
    je found_execute                # IMMEDIATE → execute even in compile mode

    # Normal word in compile mode — compile a CALL to it
    call forth_drop                 # drop flag, TOS = xt
    mov %r14, %rax                  # RAX = xt
    mov (%r15), %r14                # pop xt from stack
    add $8, %r15
    call compile_call               # emit CALL xt at HERE
    jmp interpret_loop

found_execute:
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

    # If compiling, compile the number as a literal
    cmpq $0, state(%rip)
    je interpret_loop               # interpreting → leave on stack

    # Compiling — compile literal
    mov %r14, %rax                  # RAX = number
    mov (%r15), %r14                # pop number from stack
    add $8, %r15
    call compile_literal            # emit CALL LIT + value at HERE
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

    # If we were compiling, abort the definition
    cmpq $0, state(%rip)
    je repl_loop
    movq $0, state(%rip)            # reset to interpret mode
    mov saved_latest(%rip), %r12    # restore LATEST
    mov saved_here(%rip), %r13      # restore HERE
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

# ---------- Error Handlers ----------
# These are jumped to (not called) from primitives in core.s.
# They print a message, reset the stack, recover from compile mode
# if needed, and return to the REPL.

.global stack_underflow
stack_underflow:
    lea msg_underflow(%rip), %rsi
    mov $msg_underflow_len, %rdx
    call platform_write
    jmp error_reset

.global stack_overflow
stack_overflow:
    lea msg_overflow(%rip), %rsi
    mov $msg_overflow_len, %rdx
    call platform_write
    jmp error_reset

.global dict_full
dict_full:
    lea msg_dict_full(%rip), %rsi
    mov $msg_dict_full_len, %rdx
    call platform_write
    jmp error_reset

# Shared recovery: reset stack, abort compilation if needed, return to REPL.
error_reset:
    # Reset return stack (discard stale frames from nested calls)
    mov rp0(%rip), %rsp

    # Reset data stack to empty
    mov sp0(%rip), %r15             # DSP = sp0 (empty)
    xor %r14d, %r14d                # TOS = 0

    # If we were compiling, abort the definition
    cmpq $0, state(%rip)
    je repl_loop
    movq $0, state(%rip)
    mov saved_latest(%rip), %r12
    mov saved_here(%rip), %r13

    jmp repl_loop

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
msg_underflow:  .ascii "stack underflow\n"
.equ msg_underflow_len, . - msg_underflow
msg_overflow:   .ascii "stack overflow\n"
.equ msg_overflow_len, . - msg_overflow
msg_dict_full:  .ascii "dictionary full\n"
.equ msg_dict_full_len, . - msg_dict_full

.bss
.align 8
input_buf:
    .space INPUT_BUF_SIZE
