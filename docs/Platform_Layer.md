# BasicForth — Platform Layer

The platform layer is the lowest layer of BasicForth's three-layer
architecture. It is the only code that knows about the operating system.
Everything above it — core.s primitives and core.fs Forth words — is
platform-independent.

```
┌─────────────────────────────────────────────┐
│  core.fs          (pure Forth words)        │  Portable across all platforms
├─────────────────────────────────────────────┤
│  core.s           (asm primitives)          │  Per-arch, platform-independent
├─────────────────────────────────────────────┤
│  platform_linux.s (Linux syscalls)     ◄──  │  THIS LAYER
└─────────────────────────────────────────────┘
```

## Design Philosophy

- **Isolate all OS interaction.** To port BasicForth to a new platform
  (bare metal, RTOS, different OS), only this file needs to change.
- **Thin wrappers.** Each function does one thing — translate a Forth-level
  operation into the platform's native mechanism (syscall, MMIO, etc.).
- **No Forth data stack access.** Platform functions use registers for
  arguments and return values. The Forth-level wrappers in core.s handle
  pushing and popping the data stack.

## Current API

### platform_emit

Write one character to stdout.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|------------------------------------|
| **Input**    | X0 = character                     | RDI = character                    |
| **Output**   | none                               | none                               |
| **Clobbers** | X0-X7 (syscall)                    | RAX, RCX, R11 (syscall)           |
| **Syscall**  | write(1, &char, 1) — SYS_write #64 | write(1, &char, 1) — SYS_write #1 |

Implementation: stores the character byte on the stack (in the padding area
of the saved frame), passes a pointer to that byte to the write syscall.

Called by `forth_emit` in core.s, which pops the character from the data
stack and passes it in the appropriate register.

### platform_key

Read one character from stdin (blocking).

|              | ARM64                             | x86-64                           |
|--------------|-----------------------------------|----------------------------------|
| **Input**    | none                              | none                             |
| **Output**   | X0 = character                    | RDI = character                  |
| **Clobbers** | X0-X7 (syscall)                   | RAX, RCX, R11 (syscall)         |
| **Syscall**  | read(0, &buf, 1) — SYS_read #63  | read(0, &buf, 1) — SYS_read #0  |

Implementation: allocates a 1-byte buffer on the stack, calls read, returns
the byte in the output register. Blocks until a character is available
(VMIN=1, VTIME=0).

Called by `forth_key` in core.s, which pushes the result onto the data stack.

### platform_raw_mode

Switch the terminal to raw mode for character-at-a-time input.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | none                               | none                                |
| **Output**   | none                               | none                                |
| **Clobbers** | X0-X7 (syscall)                    | RAX, RCX, RDI, RSI, RDX, R11      |

Saves the original terminal settings (for later restore), then applies
modified settings:

| Setting          | Default (cooked) | Raw mode | Why                                                   |
|------------------|------------------|----------|-------------------------------------------------------|
| ICANON (c_lflag) | ON               | **OFF**  | Deliver characters immediately, don't wait for Enter   |
| ECHO (c_lflag)   | ON               | **OFF**  | We echo manually via EMIT                              |
| IXON (c_iflag)   | ON               | **OFF**  | Free Ctrl+S and Ctrl+Q for use as input                |
| ICRNL (c_iflag)  | ON               | **ON**   | Let terminal convert CR to NL — we only deal with NL   |
| ISIG (c_lflag)   | ON               | **ON**   | Keep Ctrl+C working (sends SIGINT)                     |
| VMIN (c_cc)      | —                | **1**    | read() blocks until at least 1 character               |
| VTIME (c_cc)     | —                | **0**    | No timeout — wait forever                              |

Uses ioctl with TCGETS (0x5401) to read current settings and TCSETS (0x5402)
to apply new settings.

Should be called once during initialization, before entering the main loop.

### platform_restore_term

Restore the original terminal settings saved by `platform_raw_mode`.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | none                               | none                                |
| **Output**   | none                               | none                                |
| **Clobbers** | X0-X7 (syscall)                    | RAX, RCX, RDI, RSI, RDX, R11      |

Uses ioctl TCSETS to write back the saved `orig_termios`. Must be called
before exit — failure to restore leaves the terminal in raw mode (no echo,
no line editing).

### platform_bye

Restore the terminal and exit the process.

|              | ARM64                    | x86-64                   |
|--------------|--------------------------|--------------------------|
| **Input**    | none                     | none                     |
| **Output**   | does not return          | does not return          |
| **Syscall**  | exit(0) — SYS_exit #93   | exit(0) — SYS_exit #60  |

Calls `platform_restore_term` first, then the exit syscall. This is the
only safe way to exit — calling exit directly would leave the terminal
in raw mode.

### platform_write

Write a buffer to stdout.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = buffer, X1 = length           | RSI = buffer, RDX = length         |
| **Output**   | none                               | none                               |
| **Clobbers** | X0-X7 (syscall)                    | RAX, RCX, R11 (syscall)           |
| **Syscall**  | write(1, buf, len) — SYS_write #64 | write(1, buf, len) — SYS_write #1 |

Used by DOT, DOT-S, error messages, and other multi-character output.

### platform_init_guard_pages

Set up SIGSEGV handler and mprotect guard pages around the data stack.
Must be called before `platform_raw_mode` (early in startup).
See [Error_Handling.md](Error_Handling.md) for details.

|              | ARM64              | x86-64             |
|--------------|--------------------|---------------------|
| **Input**    | none               | none                |
| **Output**   | none (fatal on failure) | none (fatal on failure) |
| **Syscall**  | mprotect, rt_sigaction | mprotect, rt_sigaction |

### platform_flush_icache (ARM64 only)

Flush the instruction cache for a range of addresses after writing
compiled code to memory. Required because ARM64 has separate, non-coherent
instruction and data caches. See [I-Cache Coherency](#i-cache-coherency-arm64)
below.

|              | ARM64                              |
|--------------|------------------------------------|
| **Input**    | X0 = start address, X1 = end address (exclusive) |
| **Output**   | none                               |
| **Clobbers** | X2-X5                              |

Not needed on x86-64, where stores are immediately visible to instruction
fetch (coherent I-cache).

## I-Cache Coherency (ARM64)

ARM64 CPUs have **separate instruction and data caches** that are not
automatically kept in sync. When BasicForth's compiler writes machine
code to `dict_space` (a data write via `STR`), the new instructions land
in the D-cache but the I-cache may still hold stale data at those
addresses. Attempting to execute the new code can fetch stale or zeroed
instructions, causing intermittent **"Illegal instruction"** crashes.

This does **not** happen on x86-64 (which has a coherent I-cache) or
under QEMU user-mode emulation (which doesn't simulate cache incoherency).
It only manifests on real ARM64 hardware, and intermittently — depending
on what the I-cache happened to contain at those addresses from previous
activity.

### The Fix

After writing code to memory and before executing it, we must flush the
cache:

1. **`DC CVAU, addr`** — Clean D-cache line to Point of Unification.
   Ensures the written data is visible outside the D-cache.
2. **`DSB ISH`** — Data Synchronization Barrier. Wait for all D-cache
   operations to complete.
3. **`IC IVAU, addr`** — Invalidate I-cache line. Forces the I-cache
   to fetch fresh data on the next instruction fetch.
4. **`DSB ISH`** — Wait for I-cache invalidation to complete.
5. **`ISB`** — Instruction Synchronization Barrier. Flushes the
   pipeline so subsequent fetches use the updated I-cache.

Steps 1 and 3 must be repeated for each cache line in the range.

### Cache Line Size

Cache line sizes vary between ARM64 implementations (32, 64, or 128
bytes). `platform_flush_icache` reads the **CTR_EL0** register (Cache
Type Register, readable from userspace) to determine the correct stride:

- **DminLine** = CTR_EL0[19:16] → D-cache line size = `4 << DminLine`
- **IminLine** = CTR_EL0[3:0] → I-cache line size = `4 << IminLine`

On the Genio 510 (Cortex-A78), both are 64 bytes. Other cores may differ.

### Where We Flush

| Call site              | When                                          |
|------------------------|-----------------------------------------------|
| `forth_semicolon`      | After `;` finishes compiling a colon definition |
| Test harness (C)       | `__builtin___clear_cache()` after writing LIT test code |

### Further Reading

- ARM Architecture Reference Manual, section B2.2 (Caches and memory
  hierarchy)
- Linux kernel `arch/arm64/include/asm/cacheflush.h`
- BareMetalForth Lesson 37 (Memory Protection and JIT Compilation)

## termios Structure

The terminal settings are stored in a `termios` struct. The layout differs
between architectures:

| Field     | Offset | Size                        | ARM64       | x86-64              |
|-----------|--------|-----------------------------|-------------|----------------------|
| c_iflag   | 0      | 4 bytes                     | same        | same                 |
| c_oflag   | 4      | 4 bytes                     | same        | same                 |
| c_cflag   | 8      | 4 bytes                     | same        | same                 |
| c_lflag   | 12     | 4 bytes                     | same        | same                 |
| c_line    | 16     | 1 byte                      | same        | same                 |
| c_cc[]    | 17     | 19 bytes (arm64) / 32 (x86) | 19 entries  | 32 entries           |
| c_ispeed  | —      | —                           | not present | offset 52, 4 bytes   |
| c_ospeed  | —      | —                           | not present | offset 56, 4 bytes   |
| **Total** |        |                             | **36 bytes**| **60 bytes**         |

The fields we modify (c_iflag, c_lflag, c_cc[VMIN], c_cc[VTIME]) are at
the same offsets on both architectures. The size difference is in c_cc
array length and the speed fields that x86 includes.

VMIN and VTIME are at c_cc indices 6 and 5 respectively on both platforms.

## Defined Constants (for future use)

| Constant | Value  | Purpose                                                                     |
|----------|--------|-----------------------------------------------------------------------------|
| FIONREAD | 0x541B | ioctl command: get bytes available to read. For a future `KEY?` word that   |
|          |        | checks if input is available without blocking.                              |

## Syscall Reference

| Syscall | ARM64 # | x86-64 # | Signature        |
|---------|---------|----------|------------------|
| read    |      63 |        0 | (fd, buf, count) |
| write   |      64 |        1 | (fd, buf, count) |
| ioctl   |      29 |       16 | (fd, cmd, arg)   |
| exit    |      93 |       60 | (status)         |

### Syscall ABI

|                | ARM64                    | x86-64                       |
|----------------|--------------------------|------------------------------|
| **Syscall #**  | X8                       | RAX                          |
| **Arguments**  | X0, X1, X2, X3, X4, X5  | RDI, RSI, RDX, R10, R8, R9  |
| **Invoke**     | SVC #0                   | syscall                      |
| **Return**     | X0                       | RAX                          |
| **Clobbered**  | X0-X7                    | RCX, R11                     |

## Future Functions

Functions to be added as BasicForth grows:

| Function            | Purpose                                       | Phase |
|---------------------|-----------------------------------------------|-------|
| platform_key_ready  | Non-blocking input check via FIONREAD ioctl   |     2 |
| platform_mmap       | Memory allocation via mmap (anonymous)        |     3 |
| platform_open       | Open a file                                   |     4 |
| platform_read_file  | Read from file descriptor                     |     4 |
| platform_write_file | Write to file descriptor                      |     4 |
| platform_close      | Close file descriptor                         |     4 |
| platform_lseek      | Seek within file                              |     4 |
| platform_fork_exec  | Fork and exec external process (for $EDITOR)  |     4 |
| platform_fb_open    | Open framebuffer or DRM device                |     5 |
| platform_fb_mmap    | Map framebuffer memory                        |     5 |
| platform_gpio_open  | Open /dev/gpiochip                            |     6 |
| platform_gpio_ioctl | GPIO read/write via ioctl                     |     6 |
