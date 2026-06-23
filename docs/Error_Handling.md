# BasicForth — Error Handling

BasicForth uses a combination of hardware-assisted guard pages and
software checks to catch errors and recover gracefully without crashing.
The goal is that a programming mistake at the REPL never kills the
program — the user always gets an error message and a clean prompt.

## Guard Pages (Stack Underflow/Overflow)

The data stack is bracketed by two **guard pages** — 4096-byte memory
regions marked `PROT_NONE` via `mprotect` at startup.  Any read or write
to a guard page triggers a hardware page fault (SIGSEGV), which our
signal handler catches and recovers from.

### Memory Layout

```
  guard_page_underflow   4096 bytes  PROT_NONE
  ──────────────────────────────────────────────
  data_stack_top (sp0)   page-aligned             ← DSP starts here (empty)
  data_stack             4096 bytes  PROT_READ|PROT_WRITE (512 cells)
  data_stack_bottom      page-aligned
  ──────────────────────────────────────────────
  guard_page_overflow    4096 bytes  PROT_NONE
```

Stack grows downward.  DSP points to the top item (or equals sp0 when
the stack is empty).

- **Underflow**: popping or reading past sp0 touches the underflow guard
  page.  Example: `.` on an empty stack reads `[DSP]` which is in the
  guard page.
- **Overflow**: pushing past the bottom of the stack touches the overflow
  guard page.  Example: a DUP loop that exceeds 512 cells.

### Zero Runtime Cost

Unlike explicit depth checks (which add 2-4 instructions per primitive),
guard pages are checked by the CPU's memory management unit (MMU) as part
of normal memory access.  There is **no overhead** in the normal case —
the check happens in hardware, at the speed of every other memory access.

### Setup (platform_linux.s)

At startup, `platform_init_guard_pages` does three things:

1. `mprotect(guard_page_underflow, 4096, PROT_NONE)` — make the underflow
   page inaccessible
2. `mprotect(guard_page_overflow, 4096, PROT_NONE)` — make the overflow
   page inaccessible
3. `rt_sigaction(SIGSEGV, handler, SA_SIGINFO | SA_NODEFER)` — register
   the signal handler

On x86-64, the kernel requires `SA_RESTORER` with an `rt_sigreturn`
trampoline.  ARM64 does not need a restorer.

`SA_NODEFER` prevents the kernel from blocking SIGSEGV after the handler
returns, so the handler can fire again on the next underflow.

### Signal Handler

When SIGSEGV fires, the kernel calls our handler with three arguments:

| Argument | x86-64 | ARM64 | Content                         |
|----------|--------|-------|---------------------------------|
| signum   | RDI    | X0    | Signal number (11 = SIGSEGV)    |
| siginfo  | RSI    | X1    | Pointer to `siginfo_t` struct   |
| ucontext | RDX    | X2    | Pointer to `ucontext_t` struct  |

The handler:

1. **Reads `si_addr`** from siginfo (offset 16) — the faulting address.

2. **Checks the address** against guard page ranges:
   - In underflow guard page → print "stack underflow"
   - In overflow guard page → print "stack overflow"
   - Neither → not our fault.  Reset handler to `SIG_DFL` and return,
     so the signal re-fires and produces a normal crash with core dump.

3. **Prints the error message** using raw `SYS_write` (async-signal-safe).

4. **Modifies the saved registers** in the `ucontext_t` structure:

   | Register | x86-64 offset | ARM64 offset | Set to           |
   |----------|---------------|--------------|------------------|
   | RIP / PC | 168           | 440          | `repl_loop`      |
   | RSP / SP | 160           | 432          | `rp0`            |
   | R15 / X19| 96            | 336          | `sp0` (DSP=empty)|
   | R12 / X22| 72            | 360          | `saved_latest`   |
   | R13 / X21| 80            | 352          | `saved_here`     |

   The handler also resets `state` to 0 (interpret mode).

5. **Returns**.  The kernel restores the modified register context, and
   execution resumes at `repl_loop` with a clean stack and prompt.

### ucontext Register Offsets

These are Linux-specific and differ between architectures.  The offsets
were determined from kernel headers (`sys/ucontext.h`, `asm/sigcontext.h`)
and verified with `offsetof()` test programs.

**x86-64**: `ucontext_t.uc_mcontext.gregs[]` starts at byte 40.  Each
`greg_t` is 8 bytes.  The register indices (REG_R12=4, REG_R13=5,
REG_R15=7, REG_RSP=15, REG_RIP=16) give the final offsets.

**ARM64**: `ucontext_t.uc_mcontext` starts at byte 176.  General
registers `regs[0..30]` start at byte 184 (after `fault_address`).
`sp` is at offset 432, `pc` at offset 440.

### Important: Saving the ucontext Pointer

The handler must save the ucontext pointer (RDX on x86-64, X2 on ARM64)
in a callee-saved register before calling `SYS_write`, because the
syscall clobbers argument registers.  We use RBX (x86-64) and X23
(ARM64) for this.

### The DROP Special Case

Most primitives that read from the stack (`.`, `+`, `@`, etc.) naturally
trigger the guard page when the stack is empty, because they load from
`[DSP]`.  But `DROP` only increments DSP without reading — it would
silently move DSP into the guard page without faulting.

Fix: DROP does a dummy load from `[DSP]` before incrementing.  This
ensures the guard page fires immediately on `DROP` of an empty stack,
rather than deferring to the next read.

## Dictionary Full (Software Check)

Dictionary space (`dict_space`, 64KB) does not have a guard page.
Instead, the `CHECK_DICT n` macro performs an explicit bounds check
before writing.  It is used by:

- `compile_call` (5 bytes on x86, 4 on ARM64)
- `compile_ret` (1 byte on x86, 8 on ARM64)
- `compile_literal` (13 bytes on x86, 12 on ARM64)
- `compile_prolog` (ARM64 only, 4 bytes)
- `forth_colon` (up to 128 bytes for header)

If the check fails, execution jumps to `dict_full` in main.s, which
prints "dictionary full", resets DSP, RSP, and compile state, and
returns to the REPL.

## Error During Compilation

When an error occurs while compiling a definition (either a guard page
fault or a "word not found" error), the system must undo the partial
definition.  This is handled by:

1. `forth_colon` saves LATEST and HERE to `saved_latest` / `saved_here`
   before modifying anything.
2. `repl_loop` also saves them at the start of each line, so they always
   reflect the most recent good state.
3. On error, the recovery code (either the signal handler or the
   not-found handler in main.s) restores LATEST and HERE from the saved
   values and resets STATE to 0.

This ensures that:
- The partial definition is fully discarded
- Earlier completed definitions on the same line are preserved
- The user returns to a clean interpret-mode prompt

## Recovery State

After any error recovery (guard page or software), the system state is:

| State       | Value                                     |
|-------------|-------------------------------------------|
| DSP         | sp0 (empty data stack)                    |
| RSP / SP    | rp0 (clean return stack)                  |
| LATEST      | Last good value (from `saved_latest`)     |
| HERE        | Last good value (from `saved_here`)       |
| STATE       | 0 (interpreting)                          |
| Execution   | Resumes at `repl_loop` (prints prompt) — but see "Startup Script Errors" below |

## Startup Script Errors (Exit Non-Zero)

The recovery above returns to the interactive REPL, which is correct when a
human is at the keyboard. But a Forth file run as a utility (`basicforth
foo.fs` or `./foo.fs`) should *fail* on an error, not silently drop the user
into a prompt. So errors that occur while the startup script is running exit
the process with a non-zero status instead.

A `script_running` flag (in `main.s`) is set around the user-script load and
cleared on clean completion. Both error channels honor it:

- **Line errors** — an undefined word or failed parse makes `INCLUDED` print
  `file:line: ? token` and return a non-zero code; `main.s` checks that return
  and exits 1 instead of falling into the REPL.
- **Faults / `ABORT` / `QUIT`** — these recover through `repl_loop` as above,
  but a guard at the top of `repl_loop` sees `script_running` still set and
  exits 1.

For the fault path to work, `rp0` is initialized *before* the startup load
(previously it was only set on the first `repl_loop` iteration, so a fault
during startup would have recovered onto an invalid return stack). Errors while
loading `core.fs` are deliberately excluded — a broken bootstrap drops to the
REPL for debugging. See also the "Exiting With a Status" section of the Manual.

## Error Messages

| Error             | Source              | Message              |
|-------------------|---------------------|----------------------|
| Stack underflow   | Guard page (SIGSEGV)| `stack underflow`    |
| Stack overflow    | Guard page (SIGSEGV)| `stack overflow`     |
| Dictionary full   | CHECK_DICT macro    | `dictionary full`    |
| Word not found    | Outer interpreter   | `? <token>`          |

## Limitations

- **Guard pages are Linux-specific**.  A bare-metal port would need a
  different mechanism (e.g., explicit checks or MPU regions).
- **QEMU user-mode** emulates signals correctly for our use case, but
  behavior may differ from real hardware in edge cases.
- **The underflow guard page is 4096 bytes** (512 cells).  A single word
  cannot underflow by more than 512 cells without going past the guard
  page.  This is not a practical concern.
- **Dictionary space** still uses software checks.  A future improvement
  could add a guard page after dict_space for consistency.

## Inspiration

This approach is used by production runtimes:

- **JVM**: guard pages for thread stack overflow detection
- **V8/SpiderMonkey**: guard pages for WebAssembly bounds checking
- **Go**: guard pages for goroutine stack overflow

See also BareMetalForth Lesson 37 (Memory Protection and JIT
Compilation) for background on ELF memory permissions, the NX bit, and
`READ_IMPLIES_EXEC`.
