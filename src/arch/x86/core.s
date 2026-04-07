# BasicForth — Core ASM Primitives (x86-64)
# Platform-independent x86-64 assembly. Requires platform_linux.s (or equivalent).
#
# Register allocation:
#   R15 = Data stack pointer (DSP) — points to second item on stack
#   R14 = Top of stack (TOS) — always holds the top value
#   R13 = HERE pointer (dictionary free space) — future
#   R12 = LATEST pointer (most recent dictionary entry) — future
#   RSP = Return stack
#
# TOS-in-register invariant: R14 always holds the top of the data stack.
# DSP (R15) points to the second item. Push = store R14 to memory, set R14.
# Pop = move R14 out, load next from memory into R14.
#
# R12-R15 are callee-saved in the System V AMD64 ABI,
# so C functions won't clobber them.

.equ CELL, 8                    # 64-bit cells
.equ DATA_STACK_SIZE, 4096      # 512 cells

# ---------- Dictionary Entry Layout ----------
# [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4]
#
# Flags byte: bit 7 = IMMEDIATE, bit 6 = HIDDEN, bits 0-5 = name length
.equ F_IMMEDIATE, 0x80
.equ F_HIDDEN,    0x40
.equ F_LENMASK,   0x3F

# ---------- Stack Guard Macros ----------
# Build with `as -DFAST` (or `make FAST=1`) to disable runtime checks.

# POP_TOS: pop new TOS from memory after consuming old TOS.
# Safe: if stack empty (DSP >= sp0), set TOS=0 instead of reading past stack.
# Fast: unconditional load.
.macro POP_TOS
.ifdef FAST
    mov (%r15), %r14
    add $CELL, %r15
.else
    cmp sp0(%rip), %r15
    jae .Lsp_\@
    mov (%r15), %r14
    add $CELL, %r15
    jmp .Lsp_done_\@
.Lsp_\@:
    xor %r14d, %r14d
.Lsp_done_\@:
.endif
.endm

# PUSH_TOS: push current TOS to memory, making room for a new TOS.
# Safe: check for stack overflow before push.
# Fast: unconditional push.
.macro PUSH_TOS
.ifdef FAST
    sub $CELL, %r15
    mov %r14, (%r15)
.else
    lea data_stack_bottom(%rip), %rax
    cmp %rax, %r15
    jbe stack_overflow
    sub $CELL, %r15
    mov %r14, (%r15)
.endif
.endm

# CHECK_DEPTH_2: verify at least 2 items (TOS + 1 memory item).
# Safe: jump to stack_underflow if DSP >= sp0.
# Fast: no-op.
.macro CHECK_DEPTH_2
.ifndef FAST
    cmp sp0(%rip), %r15
    jae stack_underflow
.endif
.endm

# CHECK_DEPTH_3: verify at least 3 items (TOS + 2 memory items).
# Safe: jump to stack_underflow if DSP > sp0 - 2*CELL.
# Fast: no-op.
.macro CHECK_DEPTH_3
.ifndef FAST
    mov sp0(%rip), %rax
    sub $2*CELL, %rax
    cmp %rax, %r15
    ja stack_underflow
.endif
.endm

# CHECK_DICT n: verify HERE + n bytes fits in dict_space.
# Safe: jump to dict_full if past end.
# Fast: no-op.
.macro CHECK_DICT n
.ifndef FAST
    lea dict_space+DICT_SPACE_SIZE(%rip), %rcx
    lea \n(%r13), %rdx
    cmp %rcx, %rdx
    ja dict_full
.endif
.endm

# DEFWORD entry, name, label, link, flags
#   entry: label for this dictionary entry
#   name:  the Forth name string (lowercase)
#   label: the assembly code address
#   link:  label of previous entry (0 for first)
#   flags: optional flags byte (default 0)
.macro DEFWORD entry, name, label, link, flags=0
.section .data
.balign 8
\entry:
    .quad \link
\entry\()_flags:
    .byte ((\entry\()_name_end - \entry\()_name_start) | \flags)
\entry\()_name_start:
    .ascii "\name"
\entry\()_name_end:
    .balign 8
\entry\()_xt:
    .quad \label
\entry\()_codelen:
    .long 0
    .balign 4
.text
.endm

# ---------- Primitives ----------

# DUP ( a -- a a )
.global forth_dup
forth_dup:
    PUSH_TOS
    ret                          # TOS unchanged

# DROP ( a -- )
.global forth_drop
forth_drop:
    POP_TOS
    ret

# SWAP ( a b -- b a )
# TOS=b, [DSP]=a -> TOS=a, [DSP]=b
.global forth_swap
forth_swap:
    CHECK_DEPTH_2
    mov (%r15), %rax            # rax = a
    mov %r14, (%r15)            # [DSP] = b
    mov %rax, %r14              # TOS = a
    ret

# OVER ( a b -- a b a )
# TOS=b, [DSP]=a -> push b, TOS=a
.global forth_over
forth_over:
    CHECK_DEPTH_2
    PUSH_TOS
    mov CELL(%r15), %r14        # TOS = a
    ret

# + ( a b -- a+b )
# TOS=b, [DSP]=a -> TOS=a+b
.global forth_add
forth_add:
    CHECK_DEPTH_2
    add (%r15), %r14            # TOS = a + b
    add $CELL, %r15             # pop a
    ret

# - ( a b -- a-b )
# TOS=b, [DSP]=a -> TOS=a-b
.global forth_sub
forth_sub:
    CHECK_DEPTH_2
    mov (%r15), %rax            # rax = a
    sub %r14, %rax              # rax = a - b
    mov %rax, %r14              # TOS = a - b
    add $CELL, %r15             # pop
    ret

# NEGATE ( a -- -a )
.global forth_negate
forth_negate:
    neg %r14                    # negate TOS
    ret

# ---------- Memory ----------

# @ (fetch) ( addr -- x )
# Read 8-byte cell from address
.global forth_fetch
forth_fetch:
    mov (%r14), %r14            # TOS = [TOS]
    ret

# ! (store) ( x addr -- )
# Write 8-byte cell to address
.global forth_store
forth_store:
    CHECK_DEPTH_3
    mov (%r15), %rax            # RAX = x
    mov %rax, (%r14)            # [addr] = x
    add $CELL, %r15             # pop x
    POP_TOS
    ret

# C@ (char fetch) ( addr -- byte )
# Read 1 byte from address, zero-extended
.global forth_cfetch
forth_cfetch:
    movzbl (%r14), %eax         # RAX = zero-extended byte
    mov %rax, %r14              # TOS = byte
    ret

# C! (char store) ( byte addr -- )
# Write 1 byte to address
.global forth_cstore
forth_cstore:
    CHECK_DEPTH_3
    mov (%r15), %rax            # RAX = byte
    movb %al, (%r14)            # [addr] = low byte
    add $CELL, %r15             # pop byte
    POP_TOS
    ret

# ---------- EMIT (Forth-level) ----------
# ( char -- )
# TOS = char. Pass to platform_emit, pop new TOS.
.global forth_emit
forth_emit:
    mov %r14, %rdi              # RDI = char (from TOS)
    POP_TOS
    jmp platform_emit           # tail call

# ---------- KEY (Forth-level) ----------
# ( -- char )
# Push old TOS, call platform_key, TOS = result.
.global forth_key
forth_key:
    PUSH_TOS
    call platform_key           # RDI = character
    mov %rdi, %r14              # TOS = char
    ret

# ---------- ACCEPT (Forth-level) ----------
# ( c-addr +n1 -- +n2 )
# Read a line from stdin into buffer at c-addr, max n1 chars.
# Handles backspace editing and echo. Returns actual count.
# Calls platform_key and platform_emit directly (register level).
.global forth_accept
forth_accept:
    CHECK_DEPTH_2
    push %rbx
    push %rbp
    push %r12

    # Pop args from data stack: TOS = max_len, [DSP] = buf_addr
    mov %r14, %rbp              # RBP = max_len
    mov (%r15), %rbx            # RBX = buf_addr
    add $CELL, %r15
    xor %r12d, %r12d            # R12 = count = 0

.Laccept_loop:
    call platform_key           # RDI = char

    # Check for LF (Enter)
    cmp $10, %rdi
    je .Laccept_done

    # Check for BS (8) or DEL (127)
    cmp $8, %rdi
    je .Laccept_bs
    cmp $127, %rdi
    je .Laccept_bs

    # Ignore non-printable (< 32 or > 126)
    cmp $32, %rdi
    jb .Laccept_loop
    cmp $126, %rdi
    ja .Laccept_loop

    # Buffer full?
    cmp %rbp, %r12
    jge .Laccept_loop

    # Store char and echo
    movb %dil, (%rbx,%r12)     # buf[count] = char
    inc %r12                    # count++
    call platform_emit          # echo (RDI still has char)
    jmp .Laccept_loop

.Laccept_bs:
    # Ignore backspace if buffer empty
    test %r12, %r12
    jz .Laccept_loop
    dec %r12                    # count--
    # Erase on screen: \b space \b
    mov $8, %rdi
    call platform_emit
    mov $32, %rdi
    call platform_emit
    mov $8, %rdi
    call platform_emit
    jmp .Laccept_loop

.Laccept_done:
    # Echo the newline
    mov $10, %rdi
    call platform_emit

    # Push result: TOS = count
    mov %r12, %r14

    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- NUMBER (Forth-level) ----------
# ( c-addr u -- n true | c-addr u false )
# Try to parse string as a number. Supports:
#   - Decimal (default, or # prefix)
#   - Hex ($ prefix)
#   - Binary (% prefix)
#   - Negative sign before or after prefix (-$FF or $-FF)
#   - Case-insensitive hex digits (a-f, A-F)
# Uses BASE variable for default base.
.global forth_number
forth_number:
    CHECK_DEPTH_2
    push %rbx
    push %rbp
    push %r12
    push %r13                   # temporarily borrow R13 (future HERE)

    # Pop args: TOS = len, [DSP] = addr
    mov %r14, %rcx              # RCX = len
    mov (%r15), %rbx            # RBX = addr
    add $CELL, %r15
    # Save originals for failure case
    mov %rbx, %r12              # R12 = orig addr
    mov %rcx, %r13              # R13 = orig len

    # Empty string is not a number
    test %rcx, %rcx
    jz .Lnum_fail

    xor %eax, %eax              # RAX = result = 0
    xor %edx, %edx              # RDX = negate flag = 0
    mov base(%rip), %rbp        # RBP = base

    # Check for leading '-'
    movzbl (%rbx), %edi
    cmp $'-', %edi
    jne .Lnum_check_prefix
    inc %rbx
    dec %rcx
    mov $1, %edx                # set negate flag
    test %rcx, %rcx
    jz .Lnum_fail

.Lnum_check_prefix:
    movzbl (%rbx), %edi
    cmp $'$', %edi
    je .Lnum_hex
    cmp $'#', %edi
    je .Lnum_decimal
    cmp $'%', %edi
    je .Lnum_binary
    jmp .Lnum_check_sign_after

.Lnum_hex:
    mov $16, %rbp
    jmp .Lnum_consume_prefix
.Lnum_decimal:
    mov $10, %rbp
    jmp .Lnum_consume_prefix
.Lnum_binary:
    mov $2, %rbp
.Lnum_consume_prefix:
    inc %rbx
    dec %rcx
    test %rcx, %rcx
    jz .Lnum_fail

.Lnum_check_sign_after:
    # Check for '-' after prefix (e.g., $-FF)
    test %edx, %edx
    jnz .Lnum_save_and_parse    # already have sign
    movzbl (%rbx), %edi
    cmp $'-', %edi
    jne .Lnum_save_and_parse
    inc %rbx
    dec %rcx
    mov $1, %edx
    test %rcx, %rcx
    jz .Lnum_fail

.Lnum_save_and_parse:
    # Save negate flag on stack (RDX is clobbered by imul on some paths)
    push %rdx                   # negate flag on return stack

    # RAX = result, RBX = ptr, RCX = remaining, RBP = base
.Lnum_loop:
    test %rcx, %rcx
    jz .Lnum_done
    movzbl (%rbx), %edi         # RDI = char

    # Convert char to digit value
    cmp $'0', %edi
    jb .Lnum_fail2
    cmp $'9', %edi
    jbe .Lnum_digit_09

    cmp $'A', %edi
    jb .Lnum_fail2
    cmp $'Z', %edi
    jbe .Lnum_letter_upper

    cmp $'a', %edi
    jb .Lnum_fail2
    cmp $'z', %edi
    ja .Lnum_fail2

    # Lowercase letter
    sub $('a' - 10), %edi
    jmp .Lnum_check_digit

.Lnum_letter_upper:
    sub $('A' - 10), %edi
    jmp .Lnum_check_digit

.Lnum_digit_09:
    sub $'0', %edi

.Lnum_check_digit:
    # Check digit < base
    cmp %rbp, %rdi
    jge .Lnum_fail2

    # result = result * base + digit
    imul %rbp, %rax             # RAX = RAX * base
    add %rdi, %rax              # RAX += digit

    inc %rbx
    dec %rcx
    jmp .Lnum_loop

.Lnum_done:
    pop %rdx                    # restore negate flag
    test %edx, %edx
    jz .Lnum_success
    neg %rax

.Lnum_success:
    # Push n and true: ( -- n true )
    sub $CELL, %r15
    mov %rax, (%r15)            # push n to memory
    mov $-1, %r14               # TOS = true (-1)
    jmp .Lnum_exit

.Lnum_fail2:
    pop %rdx                    # clean up negate flag from stack
.Lnum_fail:
    # Push c-addr, u, and false: ( -- c-addr u false )
    sub $CELL, %r15
    mov %r12, (%r15)            # push orig c-addr
    sub $CELL, %r15
    mov %r13, (%r15)            # push orig u
    mov $0, %r14                # TOS = false

.Lnum_exit:
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- FIND (Forth-level) ----------
# ( c-addr u -- xt 1 | xt -1 | c-addr u 0 )
# Search dictionary for word by name. Case-insensitive.
# Returns: xt and 1 (immediate), xt and -1 (normal), or
#          original c-addr u and 0 (not found).
.global forth_find
forth_find:
    CHECK_DEPTH_2
    push %rbx
    push %rbp
    push %r12                   # save LATEST (read-only)

    # Pop args: TOS = u (length), [DSP] = c-addr
    mov %r14, %rcx              # RCX = search length
    mov (%r15), %rsi            # RSI = search c-addr
    add $CELL, %r15

    mov %r12, %rbx              # RBX = current entry (start at LATEST)

.Lfind_loop:
    test %rbx, %rbx
    jz .Lfind_not_found

    # Check HIDDEN flag
    movzbl 8(%rbx), %eax        # flags+len byte (offset 8 past link)
    test $F_HIDDEN, %al
    jnz .Lfind_next

    # Save flags byte for later (need IMMEDIATE check on match)
    mov %eax, %ebp              # RBP = flags+len byte

    # Compare lengths
    and $F_LENMASK, %eax        # EAX = entry name length
    cmp %rcx, %rax
    jne .Lfind_next

    # Lengths match — compare names case-insensitively
    lea 9(%rbx), %rdi           # RDI = entry name start
    mov %rsi, %rdx              # RDX = search name ptr
    mov %rcx, %r8               # R8 = remaining count

.Lfind_cmp:
    test %r8, %r8
    jz .Lfind_match

    movzbl (%rdx), %eax         # search char
    cmp $'A', %al
    jb .Lfind_s_done
    cmp $'Z', %al
    ja .Lfind_s_done
    add $32, %al                # to lowercase
.Lfind_s_done:

    movzbl (%rdi), %r9d         # entry char
    cmp $'A', %r9b
    jb .Lfind_e_done
    cmp $'Z', %r9b
    ja .Lfind_e_done
    add $32, %r9b
.Lfind_e_done:

    cmp %r9b, %al
    jne .Lfind_next

    inc %rdx
    inc %rdi
    dec %r8
    jmp .Lfind_cmp

.Lfind_match:
    # CodePtr is at offset align8(9 + name_len) from entry start
    lea 9+7(%rcx), %rax         # 9 + len + 7
    and $~7, %rax               # round down to 8-byte boundary
    # Push xt, set TOS to immediate flag
    sub $CELL, %r15
    mov (%rbx,%rax), %rax       # RAX = xt
    mov %rax, (%r15)            # push xt to memory
    # Check IMMEDIATE flag
    test $F_IMMEDIATE, %ebp
    jz .Lfind_normal
    mov $1, %r14                # TOS = 1 (immediate)
    jmp .Lfind_done
.Lfind_normal:
    mov $-1, %r14               # TOS = -1 (normal)
    jmp .Lfind_done

.Lfind_next:
    mov (%rbx), %rbx            # follow link
    jmp .Lfind_loop

.Lfind_not_found:
    # Return original c-addr u 0: push c-addr and u back, TOS = 0
    sub $CELL, %r15
    mov %rsi, (%r15)            # push c-addr
    sub $CELL, %r15
    mov %rcx, (%r15)            # push u
    xor %r14d, %r14d            # TOS = 0

.Lfind_done:
    pop %r12
    pop %rbp
    pop %rbx
    ret

# ---------- PARSE-WORD (Forth-level) ----------
# ( -- c-addr u )
# Extract next space-delimited token from the input buffer.
# Reads source_addr, source_len, to_in globals.
# Returns 0 0 if no more tokens.
.global forth_parse_word
forth_parse_word:
    # Load globals
    mov source_addr(%rip), %rsi   # RSI = buffer base
    mov source_len(%rip), %rcx    # RCX = total length
    mov to_in(%rip), %rdx         # RDX = current offset

    # Skip leading spaces
.Lpw_skip:
    cmp %rcx, %rdx
    jge .Lpw_empty
    cmpb $' ', (%rsi,%rdx)
    jne .Lpw_found
    inc %rdx
    jmp .Lpw_skip

.Lpw_empty:
    mov %rdx, to_in(%rip)
    # Push 0 0
    sub $CELL, %r15
    mov %r14, (%r15)              # push old TOS
    sub $CELL, %r15
    movq $0, (%r15)               # c-addr = 0
    xor %r14d, %r14d              # TOS = u = 0
    ret

.Lpw_found:
    lea (%rsi,%rdx), %rdi         # RDI = start of word

    # Scan to end of word
.Lpw_scan:
    cmp %rcx, %rdx
    jge .Lpw_done
    cmpb $' ', (%rsi,%rdx)
    je .Lpw_done
    inc %rdx
    jmp .Lpw_scan

.Lpw_done:
    mov %rdx, to_in(%rip)         # update to_in
    # len = current position - start
    lea (%rsi,%rdx), %rax
    sub %rdi, %rax                # RAX = length
    # Push c-addr and u
    sub $CELL, %r15
    mov %r14, (%r15)              # push old TOS
    sub $CELL, %r15
    mov %rdi, (%r15)              # push c-addr
    mov %rax, %r14                # TOS = u
    ret

# ---------- EXECUTE (Forth-level) ----------
# ( xt -- )
# Call the execution token. Tail-call: word's RET returns to our caller.
.global forth_execute
forth_execute:
    mov %r14, %rax                # RAX = xt
    POP_TOS
    jmp *%rax                     # tail-call

# ---------- print_signed (internal helper) ----------
# Print signed 64-bit integer from RAX to stdout.
# Uses stack buffer. Clobbers RAX, RCX, RDX, RSI, RDI, R8.
# Caller must save any registers it needs preserved.
.Lprint_signed:
    sub $32, %rsp               # digit buffer

    # Handle negative
    xor %ecx, %ecx              # sign flag = 0
    test %rax, %rax
    jns .Lps_positive
    neg %rax
    mov $1, %ecx
.Lps_positive:
    push %rcx                   # save sign flag

    # Build digits right-to-left
    lea 39(%rsp), %rsi          # RSI = end of buffer
    mov %rsi, %rdi              # RDI = current position
    mov $10, %r8

    # Handle zero
    test %rax, %rax
    jnz .Lps_divloop
    dec %rdi
    movb $'0', (%rdi)
    jmp .Lps_sign

.Lps_divloop:
    test %rax, %rax
    jz .Lps_sign
    xor %edx, %edx
    div %r8
    add $'0', %dl
    dec %rdi
    movb %dl, (%rdi)
    jmp .Lps_divloop

.Lps_sign:
    pop %rcx
    test %ecx, %ecx
    jz .Lps_print
    dec %rdi
    movb $'-', (%rdi)

.Lps_print:
    mov %rsi, %rdx              # length = end - start
    sub %rdi, %rdx
    mov %rdi, %rsi              # buf = start
    call platform_write

    add $32, %rsp
    ret

# ---------- DOT (Forth-level) ----------
# ( n -- )
# Print TOS as signed decimal with trailing space.
.global forth_dot
forth_dot:
    push %rbx
    mov %r14, %rax              # RAX = number to print
    POP_TOS
    call .Lprint_signed
    mov $' ', %rdi
    call platform_emit
    pop %rbx
    ret

# ---------- DOT-S (Forth-level) ----------
# ( -- )
# Print stack contents non-destructively as <depth> item1 item2 ...
.global forth_dot_s
forth_dot_s:
    push %rbx
    push %rbp

    # Compute depth = (sp0 - DSP) / CELL
    mov sp0(%rip), %rbx         # RBX = sp0
    mov %rbx, %rbp              # RBP = sp0 (saved for walking)
    sub %r15, %rbx              # RBX = sp0 - DSP (byte diff)
    sar $3, %rbx                # RBX = depth (items in memory)

    # Print '<'
    mov $'<', %rdi
    call platform_emit

    # Print depth
    mov %rbx, %rax
    call .Lprint_signed

    # Print '> '
    mov $'>', %rdi
    call platform_emit
    mov $' ', %rdi
    call platform_emit

    # If depth <= 0, nothing to print
    test %rbx, %rbx
    jle .Lds_done

    # Print depth-1 memory items (bottom-to-top), then TOS
    # Bottom (oldest) = DSP + (depth-2)*CELL, top (2nd) = DSP
    cmp $1, %rbx
    je .Lds_tos                 # depth==1: just TOS, no memory items

    lea -2(%rbx), %rbp
    shl $3, %rbp                # RBP = (depth-2)*CELL
    add %r15, %rbp              # RBP = DSP + (depth-2)*CELL = bottom

.Lds_mem_loop:
    cmp %r15, %rbp              # RBP >= DSP?
    jl .Lds_tos
    mov (%rbp), %rax            # load stack item
    call .Lprint_signed
    mov $' ', %rdi
    call platform_emit
    sub $CELL, %rbp
    jmp .Lds_mem_loop

.Lds_tos:
    # Print TOS (topmost item)
    mov %r14, %rax
    call .Lprint_signed
    mov $' ', %rdi
    call platform_emit

.Lds_done:
    pop %rbp
    pop %rbx
    ret

# ---------- BYE (Forth-level) ----------
# ( -- )
# Restore terminal and exit.
.global forth_bye
forth_bye:
    jmp platform_bye

# ---------- LIT (runtime) ----------
# Pushes the inline 8-byte value that follows the CALL to forth_lit.
# At runtime, the return address on the hardware stack points to the
# inline data.  We read the value, advance past it, and continue.
#
# Compiled code layout:
#   CALL forth_lit      (5 bytes)
#   .quad <value>       (8 bytes)
#   <next instruction>
#
.global forth_lit
forth_lit:
.ifndef FAST
    lea data_stack_bottom(%rip), %rcx
    cmp %rcx, %r15
    jbe stack_overflow
.endif
    pop %rax                        # return addr = pointer to inline value
    sub $CELL, %r15
    mov %r14, (%r15)                # push old TOS
    mov (%rax), %r14                # TOS = inline value
    add $CELL, %rax                 # skip past the 8-byte value
    jmp *%rax                       # continue execution

# ---------- compile_call (internal) ----------
# Compile a CALL instruction at HERE to the address in RAX.
# Advances HERE (R13) by 5 bytes.
# Clobbers RCX.
.global compile_call
compile_call:
    CHECK_DICT 5
    movb $0xE8, (%r13)             # E8 opcode (CALL rel32)
    lea 5(%r13), %rcx              # RCX = address after the CALL
    sub %rcx, %rax                 # RAX = relative offset
    mov %eax, 1(%r13)              # write 32-bit relative offset
    add $5, %r13                   # advance HERE
    ret

# ---------- compile_ret (internal) ----------
# Compile a RET instruction at HERE.  Advances HERE by 1 byte.
.global compile_ret
compile_ret:
    CHECK_DICT 1
    movb $0xC3, (%r13)             # C3 opcode (RET)
    inc %r13                       # advance HERE
    ret

# ---------- compile_literal (internal) ----------
# Compile a CALL to forth_lit followed by an 8-byte inline value.
# Value is taken from RAX.  Advances HERE by 13 bytes.
# Clobbers RCX.
.global compile_literal
compile_literal:
    CHECK_DICT 13
    push %rax                       # save the literal value
    lea forth_lit(%rip), %rax       # target = forth_lit
    call compile_call               # emit CALL forth_lit (5 bytes)
    pop %rax
    mov %rax, (%r13)               # emit inline 8-byte value
    add $CELL, %r13                # advance HERE past value
    ret

# ---------- COLON (Forth-level) ----------
# ( -- )
# Parse the next word, create a dictionary header at HERE, and enter
# compile mode.  The new entry is marked HIDDEN until ; completes it.
#
# Dictionary entry layout built here:
#   [Link:8] [Flags+Len:1] [Name:N] [.balign 8] [CodePtr:8] [CodeLen:4] [pad to 4]
#   Then HERE points to where compiled code will go.
#
.global forth_colon
forth_colon:
    # Save LATEST and HERE for error recovery before modifying anything
    mov %r12, saved_latest(%rip)
    mov %r13, saved_here(%rip)

    push %rbx
    push %rbp

    # Parse name
    call forth_parse_word           # ( -- c-addr u )
    mov %r14, %rcx                  # RCX = name length
    mov (%r15), %rsi                # RSI = name c-addr
    add $CELL, %r15                 # drop both from stack
    mov (%r15), %r14
    add $CELL, %r15

    test %rcx, %rcx
    jz .Lcolon_err                  # empty name — bail

    # Check dictionary space (need ~128 bytes for header)
.ifndef FAST
    lea dict_space+DICT_SPACE_SIZE(%rip), %rax
    lea 128(%r13), %rdx
    cmp %rax, %rdx
    ja .Lcolon_dict_full
.endif

    # Clamp name length to F_LENMASK (63) max
    cmp $F_LENMASK, %rcx
    jbe .Lcolon_len_ok
    mov $F_LENMASK, %rcx
.Lcolon_len_ok:

    # R13 = HERE, R12 = LATEST
    # Align HERE to 8 before starting new entry
    add $7, %r13
    and $~7, %r13

    # Write link pointer (8 bytes) — points to old LATEST
    mov %r12, (%r13)
    mov %r13, %rbx                  # RBX = new entry address (for LATEST)
    add $CELL, %r13

    # Write flags+len byte (HIDDEN | length)
    mov %ecx, %eax
    or $F_HIDDEN, %al
    movb %al, (%r13)
    inc %r13

    # Write name (lowercase)
    mov %rcx, %rbp                  # RBP = name length (loop counter)
.Lcolon_name:
    test %rbp, %rbp
    jz .Lcolon_name_done
    movzbl (%rsi), %eax
    # Lowercase: if 'A'-'Z', add 0x20
    cmp $'A', %al
    jb .Lcolon_store
    cmp $'Z', %al
    ja .Lcolon_store
    add $0x20, %al
.Lcolon_store:
    movb %al, (%r13)
    inc %r13
    inc %rsi
    dec %rbp
    jmp .Lcolon_name

.Lcolon_name_done:
    # Align HERE to 8
    add $7, %r13
    and $~7, %r13

    # Write code pointer — will point just past code_len field
    lea 12(%r13), %rax              # code starts after CodePtr(8)+CodeLen(4)
    mov %rax, (%r13)
    add $CELL, %r13                 # past CodePtr

    # Write code_len placeholder (0), save its address for ;
    mov %r13, colon_code_len_addr(%rip)
    movl $0, (%r13)
    add $4, %r13                    # past CodeLen

    # Update LATEST and STATE
    mov %rbx, %r12                  # LATEST = new entry
    movq $1, state(%rip)            # STATE = compiling

    pop %rbp
    pop %rbx
    ret

.Lcolon_dict_full:
    pop %rbp
    pop %rbx
    jmp dict_full

.Lcolon_err:
    # No name given — just return without doing anything
    pop %rbp
    pop %rbx
    ret

# ---------- SEMICOLON (Forth-level, IMMEDIATE) ----------
# ( -- )
# End a colon definition: compile RET, fill code_len, clear HIDDEN,
# return to interpret mode.
#
.global forth_semicolon
forth_semicolon:
    # Guard: must be in compile mode
    cmpq $0, state(%rip)
    je .Lsemi_err

    # Compile RET
    call compile_ret

    # Calculate code length and write it
    mov colon_code_len_addr(%rip), %rax   # RAX = code_len field address
    lea 4(%rax), %rcx                     # RCX = code start (right after field)
    mov %r13, %rdx                        # RDX = HERE (right after compiled code)
    sub %rcx, %rdx                        # RDX = code length
    mov %edx, (%rax)                      # write code_len (32-bit)

    # Clear HIDDEN flag on new entry (LATEST + 8 is flags byte)
    andb $~F_HIDDEN, 8(%r12)

    # Return to interpret mode
    movq $0, state(%rip)
    ret

.Lsemi_err:
    # ; outside compile mode — silently ignore
    ret

# ---------- IMMEDIATE (Forth-level) ----------
# ( -- )
# Set the IMMEDIATE flag on the most recent dictionary entry.
.global forth_immediate
forth_immediate:
    orb $F_IMMEDIATE, 8(%r12)
    ret

# ---------- TICK (Forth-level, IMMEDIATE) ----------
# ( "<spaces>name" -- xt )
# Parse the next word and look it up in the dictionary.
# In interpret mode: pushes xt to stack.
# In compile mode: compiles xt as a literal (acts like ['] in std Forth).
.global forth_tick
forth_tick:
    call forth_parse_word           # ( -- c-addr u )
    call forth_find                 # ( c-addr u -- xt flag | c-addr u 0 )

    # Check if found (flag != 0)
    test %r14, %r14
    jz .Ltick_not_found

    # Found — drop flag, TOS = xt
    mov (%r15), %r14
    add $CELL, %r15

    # If compiling, compile xt as a literal
    cmpq $0, state(%rip)
    je .Ltick_done                  # interpreting → leave on stack

    # Compiling — compile literal
    mov %r14, %rax
    mov (%r15), %r14
    add $CELL, %r15
    call compile_literal
.Ltick_done:
    ret

.Ltick_not_found:
    # Not found — drop 0 flag, c-addr, u; push 0 as error
    call forth_drop                 # drop 0 flag
    call forth_drop                 # drop u
    call forth_drop                 # drop c-addr
    xor %r14d, %r14d               # TOS = 0 (invalid xt)
    ret

# ---------- Static Dictionary ----------

DEFWORD dict_dup,     "dup",     forth_dup,     0
DEFWORD dict_drop,    "drop",    forth_drop,    dict_dup
DEFWORD dict_swap,    "swap",    forth_swap,    dict_drop
DEFWORD dict_over,    "over",    forth_over,    dict_swap
DEFWORD dict_add,     "+",       forth_add,     dict_over
DEFWORD dict_sub,     "-",       forth_sub,     dict_add
DEFWORD dict_negate,  "negate",  forth_negate,  dict_sub
DEFWORD dict_fetch,   "@",       forth_fetch,   dict_negate
DEFWORD dict_store,   "!",       forth_store,   dict_fetch
DEFWORD dict_cfetch,  "c@",      forth_cfetch,  dict_store
DEFWORD dict_cstore,  "c!",      forth_cstore,  dict_cfetch
DEFWORD dict_emit,    "emit",    forth_emit,    dict_cstore
DEFWORD dict_key,     "key",     forth_key,     dict_emit
DEFWORD dict_accept,  "accept",  forth_accept,  dict_key
DEFWORD dict_number,  "number",  forth_number,  dict_accept
DEFWORD dict_find,       "find",       forth_find,       dict_number
DEFWORD dict_parse_word, "parse-word", forth_parse_word, dict_find
DEFWORD dict_execute,    "execute",    forth_execute,    dict_parse_word
DEFWORD dict_dot,        ".",          forth_dot,        dict_execute
DEFWORD dict_dot_s,      ".s",         forth_dot_s,      dict_dot
DEFWORD dict_bye,        "bye",        forth_bye,        dict_dot_s
DEFWORD dict_lit,        "lit",        forth_lit,        dict_bye, F_HIDDEN
DEFWORD dict_colon,      ":",          forth_colon,      dict_lit
DEFWORD dict_semicolon,  ";",          forth_semicolon,  dict_colon, F_IMMEDIATE
DEFWORD dict_immediate,  "immediate",  forth_immediate,  dict_semicolon
DEFWORD dict_tick,       "'",          forth_tick,        dict_immediate, F_IMMEDIATE
.global dict_tick

# ---------- Data Stack Memory ----------
.bss
.align 8
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:

# ---------- Dictionary Space ----------
.equ DICT_SPACE_SIZE, 65536     # 64KB
.balign 8
.global dict_space
dict_space:
    .space DICT_SPACE_SIZE

# ---------- Variables ----------
.data
.align 8
.global base
base:                               # NUMBER base (default decimal)
    .quad 10
.global source_addr
source_addr:                        # PARSE-WORD: pointer to input buffer
    .quad 0
.global source_len
source_len:                         # PARSE-WORD: total length of input
    .quad 0
.global to_in
to_in:                              # PARSE-WORD: current parse offset
    .quad 0
.global sp0
sp0:                                # Initial DSP value (for .S depth)
    .quad 0
.global state
state:                              # Compiler state (0=interpret, non-zero=compile)
    .quad 0
.global colon_code_len_addr
colon_code_len_addr:                # Saved code_len field address for ; to fill
    .quad 0
.global saved_latest
saved_latest:                       # LATEST before current : for error recovery
    .quad 0
.global saved_here
saved_here:                         # HERE before current : for error recovery
    .quad 0
.global rp0
rp0:                                # Return stack pointer at repl_loop entry
    .quad 0
