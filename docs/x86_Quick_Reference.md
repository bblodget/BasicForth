# x86-64 Quick Reference

Quick reference for x86-64 assembly using GNU as (AT&T syntax).
BasicForth-specific notes are included where relevant.

## AT&T Syntax Rules

GNU as on x86 uses AT&T syntax, which differs from Intel/NASM:

| Aspect          | Intel (NASM)              | AT&T (GNU as)                |
|-----------------|---------------------------|------------------------------|
| Operand order   | `mov dest, src`           | `mov src, dest`              |
| Registers       | `rax`                     | `%rax`                       |
| Immediates      | `42`                      | `$42` ($ = immediate, not memory) |
| Memory          | `[r15]`                   | `(%r15)`                     |
| Displacement    | `[r15 + 8]`              | `8(%r15)`                    |
| Scaled index    | `[rsi + rcx*4]`          | `(%rsi,%rcx,4)`              |
| Size suffix     | `QWORD`, `DWORD`, `BYTE` | `q`, `l`, `w`, `b` suffix    |
| Comments        | `; comment`               | `# comment`                  |
| Hex literal     | `0x1234`                  | `$0x1234`                    |

Size suffixes on instructions:

| Suffix | Size    | Register example |
|--------|---------|------------------|
| `b`    | 1 byte  | `%al`            |
| `w`    | 2 bytes | `%ax`            |
| `l`    | 4 bytes | `%eax`           |
| `q`    | 8 bytes | `%rax`           |

Often the assembler infers the size from the register, so `mov %rax, %rbx`
doesn't need a suffix. Use suffixes when the size is ambiguous:
`movb $0, 8(%rsp)` (store a byte, not a quad).

## Registers

### Register Views (Same Physical Register)

```
64-bit    32-bit    16-bit    8-bit low
──────────────────────────────────────────
%rax      %eax      %ax       %al
%rbx      %ebx      %bx       %bl
%rcx      %ecx      %cx       %cl
%rdx      %edx      %dx       %dl
%rsi      %esi      %si       %sil
%rdi      %edi      %di       %dil
%rbp      %ebp      %bp       %bpl
%rsp      %esp      %sp       %spl
%r8       %r8d      %r8w      %r8b
%r9       %r9d      %r9w      %r9b
%r10      %r10d     %r10w     %r10b
%r11      %r11d     %r11w     %r11b
%r12      %r12d     %r12w     %r12b
%r13      %r13d     %r13w     %r13b
%r14      %r14d     %r14w     %r14b
%r15      %r15d     %r15w     %r15b
```

**Important:** Writing to a 32-bit register (e.g., `%eax`) zero-extends into
the full 64-bit register. Writing to 8-bit or 16-bit registers does NOT
zero-extend — the upper bits are preserved.

```asm
mov $0xFFFFFFFF, %rax       # RAX = 0x00000000FFFFFFFF (64-bit immediate)
mov $0xFFFFFFFF, %eax       # RAX = 0x00000000FFFFFFFF (zero-extended)
mov $0xFF, %al              # RAX = 0x00000000FFFFFF_FF (only AL changed)
movzbl %al, %eax            # RAX = 0x00000000000000FF (explicit zero-extend)
```

### BasicForth Register Allocation

```
%r15 = Data stack pointer (DSP)     — callee-saved, points to top item
%r14 = scratch (available)          — callee-saved, no longer used for TOS
%r13 = HERE pointer                 — dictionary free space
%r12 = LATEST pointer               — most recent dictionary entry
%rsp = Return stack                 — hardware stack
```

### System V AMD64 ABI Conventions

| Category                           | Registers                           |
|------------------------------------|-------------------------------------|
| **Arguments (in order)**           | %rdi, %rsi, %rdx, %rcx, %r8, %r9  |
| **Return value**                   | %rax (and %rdx for 128-bit)        |
| **Caller-saved (may be clobbered)**| %rax, %rcx, %rdx, %rsi, %rdi, %r8-%r11 |
| **Callee-saved (must preserve)**   | %rbx, %rbp, %r12-%r15              |
| **Stack pointer**                  | %rsp (must be 16-byte aligned before `call`) |

BasicForth uses callee-saved registers for engine state (DSP, HERE,
LATEST), so C library functions won't clobber them.

## Common Instructions

### Data Movement

| Instruction                | Description                              | Example                          |
|----------------------------|------------------------------------------|----------------------------------|
| `mov src, dest`            | Copy data                                | `mov %rax, %rbx`                |
| `movq $imm, dest`         | Load 64-bit immediate                    | `movq $42, (%r15)`              |
| `lea addr, dest`           | Load effective address (no memory read)  | `lea 8(%r15), %rax`             |
| `movzbl src, dest`         | Move byte, zero-extend to 32/64-bit     | `movzbl (%rsp), %eax`           |
| `movsbl src, dest`         | Move byte, sign-extend                   | `movsbl (%rsp), %eax`           |
| `xchg a, b`               | Exchange (atomic if memory operand)      | `xchg %rax, %rbx`               |

`lea` is useful for arithmetic without touching flags:
```asm
lea (%rax,%rbx), %rcx       # RCX = RAX + RBX (no flags affected)
lea 1(%rax), %rcx            # RCX = RAX + 1
lea (%rax,%rax,4), %rcx     # RCX = RAX * 5
```

### Arithmetic

| Instruction                | Description                              | Example                          |
|----------------------------|------------------------------------------|----------------------------------|
| `add src, dest`            | dest = dest + src                        | `add $8, %r15`                   |
| `sub src, dest`            | dest = dest - src                        | `sub %r14, %rax`                 |
| `neg dest`                 | dest = -dest (two's complement)          | `neg %r14`                       |
| `inc dest`                 | dest = dest + 1                          | `inc %rax`                       |
| `dec dest`                 | dest = dest - 1                          | `dec %rax`                       |
| `imul src, dest`           | dest = dest * src (signed)               | `imul %rbx, %rax`                |
| `imul $imm, src, dest`    | dest = src * imm (signed, 3-operand)     | `imul $10, %rbx, %rax`           |
| `idiv src`                 | RAX = RDX:RAX / src, RDX = remainder    | `idiv %rbx`                      |
| `cqo`                      | Sign-extend RAX into RDX:RAX            | `cqo` (use before `idiv`)        |

#### Multiplication

```asm
# Two-operand: dest *= src
imul %rbx, %rax             # RAX = RAX * RBX (signed, result in RAX only)

# Three-operand: dest = src * immediate
imul $8, %rbx, %rax         # RAX = RBX * 8

# Full-width multiply: RDX:RAX = RAX * src
imul %rbx                   # Signed 128-bit result in RDX:RAX
mul %rbx                    # Unsigned 128-bit result in RDX:RAX
```

#### Division and Remainder

```asm
# Signed divide: RDX:RAX / src -> RAX=quotient, RDX=remainder
cqo                          # Sign-extend RAX into RDX:RAX
idiv %rbx                   # RAX = RDX:RAX / RBX, RDX = remainder

# Unsigned divide: same but zero RDX first
xor %edx, %edx              # Clear RDX (zero-extend clears upper 32 bits too)
div %rbx                    # RAX = RDX:RAX / RBX, RDX = remainder
```

### Logic

| Instruction                | Description                              | Example                          |
|----------------------------|------------------------------------------|----------------------------------|
| `and src, dest`            | dest = dest AND src                      | `and $0xFF, %rax`                |
| `or src, dest`             | dest = dest OR src                       | `or $1, %rax`                    |
| `xor src, dest`            | dest = dest XOR src                      | `xor %rax, %rax` (zero idiom)   |
| `not dest`                 | dest = NOT dest (flip all bits)          | `not %rax`                       |

### Shift

| Instruction                | Description                              | Example                          |
|----------------------------|------------------------------------------|----------------------------------|
| `shl $n, dest`             | Shift left (multiply by 2^n)             | `shl $3, %rax` (RAX *= 8)       |
| `shr $n, dest`             | Shift right logical (unsigned divide)    | `shr $1, %rax` (RAX /= 2)       |
| `sar $n, dest`             | Shift right arithmetic (signed divide)   | `sar $1, %rax` (preserves sign)  |
| `shl %cl, dest`            | Shift left by variable amount            | `shl %cl, %rax`                  |

**SHR vs SAR:**
```asm
mov $-8, %rax
shr $1, %rax                # RAX = 0x7FFFFFFFFFFFFFFC (wrong for signed!)
mov $-8, %rax
sar $1, %rax                # RAX = -4 (correct signed division)
```

Common patterns:
```asm
shl $3, %rax                # Multiply by 8 (CELLS in BasicForth)
shr $3, %rax                # Divide by 8 (unsigned)
```

### Compare and Test

| Instruction                | Description                              | Example                          |
|----------------------------|------------------------------------------|----------------------------------|
| `cmp src, dest`            | Compute dest - src, set flags (no store) | `cmp $'q', %r14`                |
| `test src, dest`           | Compute dest AND src, set flags (no store)| `test %rax, %rax` (zero check) |

`cmp` computes `dest - src` internally and sets flags:

| Flag | Meaning after `cmp $b, %a`           |
|------|--------------------------------------|
| ZF   | a == b                               |
| CF   | a < b (unsigned)                     |
| SF   | result is negative                   |
| OF   | signed overflow                      |

`test` computes `dest AND src` and sets flags. Most common use:
```asm
test %rax, %rax              # Sets ZF if RAX == 0, SF if negative
jz .is_zero
```

### Conditional Jumps

After `cmp` or `test`:

| Signed          | Unsigned         | Equality           |
|-----------------|------------------|--------------------|
| `jl`  (less)    | `jb`  (below)    | `je`  (equal)      |
| `jle` (less/eq) | `jbe` (below/eq) | `jne` (not equal)  |
| `jg`  (greater) | `ja`  (above)    | `jz`  (zero)       |
| `jge` (gr/eq)   | `jae` (above/eq) | `jnz` (not zero)   |

Individual flags: `jc` (carry), `jnc`, `js` (sign), `jns`, `jo` (overflow), `jno`

### Branches and Calls

| Instruction                | Description                              | Example                          |
|----------------------------|------------------------------------------|----------------------------------|
| `jmp label`                | Unconditional jump                       | `jmp echo_loop`                  |
| `call label`               | Push return address, jump                | `call forth_add`                 |
| `ret`                      | Pop return address, jump to it           | `ret`                            |

Unlike ARM64 (which uses a link register X30), x86 `call` pushes the return
address onto the hardware stack and `ret` pops it. This means nested calls
"just work" without saving a link register.

### Memory Operations

```asm
mov (%r15), %rax             # Load 64-bit from address in R15
mov %rax, (%r15)             # Store 64-bit to address in R15
movb %al, 8(%rsp)           # Store byte at RSP+8
movzbl 8(%rsp), %eax        # Load byte from RSP+8, zero-extend to 64-bit
```

Addressing modes:

| Mode                       | AT&T syntax                | Computes                  |
|----------------------------|----------------------------|---------------------------|
| Register indirect          | `(%r15)`                   | [R15]                     |
| Displacement               | `8(%r15)`                  | [R15 + 8]                 |
| Base + index               | `(%rsi,%rcx)`              | [RSI + RCX]               |
| Base + scaled index        | `(%rsi,%rcx,4)`            | [RSI + RCX*4]             |
| Disp + base + scaled index | `16(%rsi,%rcx,8)`         | [RSI + RCX*8 + 16]        |
| RIP-relative               | `symbol(%rip)`             | [RIP + offset to symbol]  |

RIP-relative addressing is the standard way to access global data in
position-independent code:
```asm
lea data_stack_top(%rip), %r15    # Load address of data_stack_top
lea orig_termios(%rip), %rdx     # Load address of orig_termios
```

### String Operations

| Instruction | Operation                       | Registers used     |
|-------------|---------------------------------|--------------------|
| `lodsb`     | %al = [%rsi], %rsi++           | %rsi -> %al        |
| `stosb`     | [%rdi] = %al, %rdi++           | %al -> %rdi        |
| `movsb`     | [%rdi] = [%rsi], both++         | %rsi -> %rdi       |
| `cmpsb`     | Compare [%rsi] vs [%rdi]        | %rsi vs %rdi       |
| `rep`       | Repeat %rcx times               | `rep movsb`        |
| `cld`       | Clear direction flag (forward)   | `cld`              |

```asm
# Copy TERMIOS_SIZE bytes
lea orig_termios(%rip), %rsi
lea raw_termios(%rip), %rdi
mov $TERMIOS_SIZE, %rcx
cld
rep movsb
```

## Flags Register (RFLAGS)

| Flag | Name      | Set when                             |
|------|-----------|--------------------------------------|
| CF   | Carry     | Unsigned overflow/borrow             |
| ZF   | Zero      | Result is zero                       |
| SF   | Sign      | Result is negative (high bit = 1)    |
| OF   | Overflow  | Signed overflow                      |
| PF   | Parity    | Low byte has even number of 1s       |
| DF   | Direction | String ops direction (cld/std)       |

## Linux Syscall ABI (x86-64)

```
Syscall #:  %rax
Arguments:  %rdi, %rsi, %rdx, %r10, %r8, %r9
Invoke:     syscall
Return:     %rax (result or negative errno)
Clobbered:  %rcx, %r11 (always), %rax (return value)
```

Common syscalls:

| Syscall       | Number | Signature                         |
|---------------|--------|-----------------------------------|
| read          |      0 | (fd, buf, count)                  |
| write         |      1 | (fd, buf, count)                  |
| open          |      2 | (path, flags, mode)               |
| close         |      3 | (fd)                              |
| ioctl         |     16 | (fd, cmd, arg)                    |
| mmap          |      9 | (addr, len, prot, flags, fd, off) |
| exit          |     60 | (status)                          |
| clone         |     56 | (flags, stack, ptid, ctid, regs)  |
| nanosleep     |     35 | (req, rem)                        |

Example — write "hello" to stdout:
```asm
mov $1, %rax                 # SYS_write
mov $1, %rdi                 # fd = stdout
lea msg(%rip), %rsi         # buf = message
mov $5, %rdx                # count = 5
syscall                      # returns bytes written in RAX
```

**Key difference from ARM64:** x86-64 `syscall` clobbers %rcx (saved RIP)
and %r11 (saved RFLAGS). ARM64 `SVC #0` clobbers X0-X7 (much more).

## Comparison with ARM64

| Aspect                    | x86-64                   | ARM64                    |
|---------------------------|--------------------------|--------------------------|
| Instruction size          | Variable (1-15 bytes)    | Fixed (4 bytes always)   |
| Operand order (GNU as)    | src, dest                | dest, src                |
| GP registers              | 16                       | 31                       |
| Subroutine call           | `call` (pushes to stack) | `BL` (saves to X30)     |
| Return                    | `ret` (pops from stack)  | `RET` (branches to X30) |
| Nested calls              | Automatic (stack-based)  | Must save X30 manually   |
| Syscall invoke            | `syscall`                | `SVC #0`                 |
| Syscall number            | %rax                     | X8                       |
| Syscall clobbers          | %rcx, %r11              | X0-X7                    |
| Memory ops on registers   | Yes (`add (%r15), %r14`)| No (must load first)     |
| Zero register             | None                     | XZR / WZR                |
| Condition codes           | Flags register           | Flags register (similar) |
| Stack alignment           | 16-byte before `call`    | 16-byte always            |

## GNU Assembler Directives

These are mostly the same for x86 and ARM64, with one important difference:
`.align` takes a **byte count** on x86 but a **power of 2** on ARM64.
So `.align 4` means 4 bytes on x86 but 2^4 = 16 bytes on ARM64.

| Directive              | Purpose                                         |
|------------------------|-------------------------------------------------|
| `.global symbol`       | Export symbol (visible to linker)                |
| `.equ NAME, value`     | Define constant                                  |
| `.ascii "text"`        | String data (no null terminator)                 |
| `.asciz "text"`        | String data (with null terminator)               |
| `.byte val`            | Emit byte                                        |
| `.long val`            | Emit 4-byte value                                |
| `.quad val`            | Emit 8-byte value                                |
| `.space N`             | Reserve N zero bytes                             |
| `.align N`             | Align to N bytes (x86) or 2^N bytes (ARM64)      |
| `.section .rodata`     | Switch to read-only data section                 |
| `.bss`                 | Switch to uninitialized data section             |
| `.text`                | Switch to code section                           |
