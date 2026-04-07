# BasicForth — Outer Interpreter (x86-64)
#
# Register convention (pure memory stack):
#   R15 = DSP (data stack pointer, points to top item; equals sp0 when empty)
#   R13 = HERE (next free byte in dictionary)
#   R12 = LATEST (most recent dictionary entry)
#   RSP = Return stack
#
# R14 is free (no longer used for TOS).

.global _start

.equ CELL, 8
.equ INPUT_BUF_SIZE, 80

_start:
    # Initialize engine registers
    lea data_stack_top(%rip), %r15  # DSP = sp0 (empty stack)
    mov %r15, sp0(%rip)             # save initial DSP for .S / guards
    lea dict_space(%rip), %r13      # HERE
    lea dict_tick(%rip), %r12       # LATEST

    # Initialize saved state for error recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    call platform_init_guard_pages
    call platform_raw_mode

.global repl_loop
repl_loop:
    # Save return stack pointer for error recovery
    mov %rsp, rp0(%rip)

    # Save LATEST and HERE for guard page recovery
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    # Print prompt
    lea prompt_msg(%rip), %rsi
    mov $prompt_len, %rdx
    call platform_write

    # ACCEPT ( c-addr max -- count )
    lea input_buf(%rip), %rax
    sub $CELL, %r15
    mov %rax, (%r15)                # push c-addr
    sub $CELL, %r15
    movq $INPUT_BUF_SIZE, (%r15)    # push max
    call forth_accept               # ( c-addr max -- count )

    # Empty line → exit (count == 0)
    mov (%r15), %rax
    test %rax, %rax
    jz repl_bye

    # Set up source variables for PARSE-WORD
    mov (%r15), %rax                # count
    mov %rax, source_len(%rip)
    lea input_buf(%rip), %rax
    mov %rax, source_addr(%rip)
    movq $0, to_in(%rip)

    # Drop count
    add $CELL, %r15

interpret_loop:
    call forth_parse_word           # ( -- c-addr u )

    # End of line? (u == 0)
    mov (%r15), %rax                # u is on top
    test %rax, %rax
    jz interpret_done

    # FIND ( c-addr u -- xt flag | c-addr u 0 )
    call forth_find

    # Found? (flag != 0)
    mov (%r15), %rax                # flag is on top
    test %rax, %rax
    jz try_number

    # Found — top = flag (1=IMMEDIATE, -1=normal), second = xt
    # If interpreting (STATE==0), always execute.
    # If compiling: IMMEDIATE words execute, normal words get compiled.
    cmpq $0, state(%rip)
    je found_interpret              # interpreting → check compile-only

    # Compiling — check IMMEDIATE flag
    cmpq $1, (%r15)                 # flag == 1?
    je found_execute                # IMMEDIATE → execute even in compile mode

    # Normal word in compile mode — compile a CALL to it
    add $CELL, %r15                 # drop flag
    mov (%r15), %rax                # RAX = xt
    add $CELL, %r15                 # drop xt
    call compile_call               # emit CALL xt at HERE
    jmp interpret_loop

found_interpret:
    # Interpreting — reject compile-only words (flag == -2)
    cmpq $-2, (%r15)
    je compile_only_error
    # Fall through to execute

found_execute:
    add $CELL, %r15                 # drop flag
    call forth_execute              # pops xt and jumps
    jmp interpret_loop

try_number:
    # Not in dictionary — drop 0 flag, try NUMBER
    add $CELL, %r15                 # drop 0 flag ( c-addr u )

    # NUMBER ( c-addr u -- n true | c-addr u false )
    call forth_number

    mov (%r15), %rax                # top = true/false flag
    test %rax, %rax
    jz not_found

    # Parsed — drop true flag, number is on stack
    add $CELL, %r15                 # drop true flag

    # If compiling, compile the number as a literal
    cmpq $0, state(%rip)
    je interpret_loop               # interpreting → leave n on stack

    # Compiling — compile literal
    mov (%r15), %rax                # RAX = number
    add $CELL, %r15                 # pop number
    call compile_literal            # emit CALL LIT + value at HERE
    jmp interpret_loop

not_found:
    # Neither word nor number — error
    add $CELL, %r15                 # drop false flag ( c-addr u )

    # Print "? " + token + newline
    lea err_msg(%rip), %rsi
    mov $err_len, %rdx
    call platform_write

    mov (%r15), %rdx                # length = u (top)
    mov CELL(%r15), %rsi            # buf = c-addr (second)
    call platform_write

    mov $'\n', %rdi
    call platform_emit

    # Clean up c-addr and u
    add $2*CELL, %r15

    # If we were compiling, abort the definition
    cmpq $0, state(%rip)
    je repl_loop
    movq $0, state(%rip)            # reset to interpret mode
    mov saved_latest(%rip), %r12    # restore LATEST
    mov saved_here(%rip), %r13      # restore HERE
    jmp repl_loop

interpret_done:
    # End of line — drop 0 0 from PARSE-WORD
    add $2*CELL, %r15

    # Print " ok"
    lea ok_msg(%rip), %rsi
    mov $ok_len, %rdx
    call platform_write

    jmp repl_loop

repl_bye:
    add $CELL, %r15                 # drop 0 count

    lea bye_msg(%rip), %rsi
    mov $bye_len, %rdx
    call platform_write

    call platform_bye

compile_only_error:
    # Compile-only word used in interpret mode
    # Stack: ( xt flag ) — drop both
    add $2*CELL, %r15
    lea msg_compile_only(%rip), %rsi
    mov $msg_compile_only_len, %rdx
    call platform_write
    jmp interpret_loop

# ---------- Error Handlers ----------
# Stack underflow/overflow are caught by guard pages (SIGSEGV handler
# in platform_linux.s). Only dict_full remains as an explicit handler.

.global dict_full
dict_full:
    lea msg_dict_full(%rip), %rsi
    mov $msg_dict_full_len, %rdx
    call platform_write

    # Reset return stack and data stack
    mov rp0(%rip), %rsp
    mov sp0(%rip), %r15

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
msg_dict_full:  .ascii "dictionary full\n"
.equ msg_dict_full_len, . - msg_dict_full
msg_compile_only: .ascii "compile only\n"
.equ msg_compile_only_len, . - msg_compile_only

.bss
.align 8
input_buf:
    .space INPUT_BUF_SIZE
