// BasicForth — Core ASM Primitives (ARM64)
// Platform-independent ARM64 assembly. Requires platform_linux.s (or equivalent).
//
// Register allocation:
//   X19 = Data stack pointer (DSP) — points to second item on stack
//   X20 = Top of stack (TOS) — always holds the top value
//   X21 = HERE pointer (dictionary free space) — future
//   X22 = LATEST pointer (most recent dictionary entry) — future
//   SP  = Return stack
//
// TOS-in-register invariant: X20 always holds the top of the data stack.
// DSP (X19) points to the second item. Push = store X20 to memory, set X20.
// Pop = move X20 out, load next from memory into X20.

.equ CELL, 8                    // 64-bit cells
.equ DATA_STACK_SIZE, 4096      // 512 cells

// ---------- Primitives ----------

// DUP ( a -- a a )
.global forth_dup
forth_dup:
    STR X20, [X19, #-CELL]!    // push TOS to memory
    RET                         // TOS unchanged

// DROP ( a -- )
.global forth_drop
forth_drop:
    LDR X20, [X19], #CELL      // pop next into TOS
    RET

// SWAP ( a b -- b a )
// TOS=b, [DSP]=a → TOS=a, [DSP]=b
.global forth_swap
forth_swap:
    LDR X9, [X19]              // X9 = a
    STR X20, [X19]             // [DSP] = b
    MOV X20, X9                // TOS = a
    RET

// OVER ( a b -- a b a )
// TOS=b, [DSP]=a → push b, TOS=a
.global forth_over
forth_over:
    STR X20, [X19, #-CELL]!   // push b to memory
    LDR X20, [X19, #CELL]     // TOS = a (one cell below new DSP)
    RET

// + ( a b -- a+b )
// TOS=b, [DSP]=a → TOS=a+b
.global forth_add
forth_add:
    LDR X9, [X19], #CELL      // X9 = a, pop
    ADD X20, X9, X20           // TOS = a + b
    RET

// - ( a b -- a-b )
// TOS=b, [DSP]=a → TOS=a-b
.global forth_sub
forth_sub:
    LDR X9, [X19], #CELL      // X9 = a, pop
    SUB X20, X9, X20           // TOS = a - b
    RET

// NEGATE ( a -- -a )
.global forth_negate
forth_negate:
    NEG X20, X20               // negate TOS
    RET

// ---------- EMIT (Forth-level) ----------
// ( char -- )
// TOS = char. Pass to platform_emit, pop new TOS.
.global forth_emit
forth_emit:
    MOV X0, X20                // X0 = char (from TOS)
    LDR X20, [X19], #CELL     // pop new TOS
    B platform_emit            // tail call (X30 untouched)

// ---------- KEY (Forth-level) ----------
// ( -- char )
// Push old TOS, call platform_key, TOS = result.
.global forth_key
forth_key:
    STR X30, [SP, #-16]!      // save return address
    STR X20, [X19, #-CELL]!   // push old TOS to memory
    BL platform_key            // X0 = character
    MOV X20, X0                // TOS = char
    LDR X30, [SP], #16        // restore return address
    RET

// ---------- ACCEPT (Forth-level) ----------
// ( c-addr +n1 -- +n2 )
// Read a line from stdin into buffer at c-addr, max n1 chars.
// Handles backspace editing and echo. Returns actual count.
// Calls platform_key and platform_emit directly (register level).
.global forth_accept
forth_accept:
    STP X29, X30, [SP, #-16]!
    STP X23, X24, [SP, #-16]!
    STP X25, X26, [SP, #-16]!

    // Pop args from data stack: TOS = max_len, [DSP] = buf_addr
    MOV X24, X20                // X24 = max_len
    LDR X23, [X19], #CELL      // X23 = buf_addr
    MOV X25, #0                 // X25 = count

.Laccept_loop:
    BL platform_key             // X0 = char

    // Check for LF (Enter)
    CMP X0, #10
    B.EQ .Laccept_done

    // Check for BS (8) or DEL (127)
    CMP X0, #8
    B.EQ .Laccept_bs
    CMP X0, #127
    B.EQ .Laccept_bs

    // Ignore non-printable (< 32 or > 126)
    CMP X0, #32
    B.LO .Laccept_loop
    CMP X0, #126
    B.HI .Laccept_loop

    // Buffer full?
    CMP X25, X24
    B.GE .Laccept_loop

    // Store char and echo
    STRB W0, [X23, X25]        // buf[count] = char
    ADD X25, X25, #1            // count++
    BL platform_emit            // echo (X0 still has char)
    B .Laccept_loop

.Laccept_bs:
    // Ignore backspace if buffer empty
    CBZ X25, .Laccept_loop
    SUB X25, X25, #1            // count--
    // Erase on screen: \b space \b
    MOV X0, #8
    BL platform_emit
    MOV X0, #32
    BL platform_emit
    MOV X0, #8
    BL platform_emit
    B .Laccept_loop

.Laccept_done:
    // Echo the newline
    MOV X0, #10
    BL platform_emit

    // Push result: TOS = count
    MOV X20, X25

    LDP X25, X26, [SP], #16
    LDP X23, X24, [SP], #16
    LDP X29, X30, [SP], #16
    RET

// ---------- Data Stack Memory ----------
.bss
.align 4
data_stack_bottom:
    .space DATA_STACK_SIZE
.global data_stack_top
data_stack_top:
