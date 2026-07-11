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

## Return-Value Contract

Every backend must honor these rules; code above the boundary (core.s and
the Forth layer) is written against them and nothing else.

1. **Success is zero or positive; failure is `-errno`** (a negative value
   whose magnitude is the platform's error code). This includes calls that
   return resources: an fd, a size, or an mmap address is never negative on
   success, so callers detect failure with a **sign test** — never by
   comparing against `-1` or any other specific value. (A `cmp $-1` on a raw
   mmap return shipped a segfault on `include <directory>`; the raw syscall
   returned `-19`.)

2. **Error magnitudes are opaque above the boundary.** The magnitude *is*
   the ANS `ior` (callers negate it), and `ior` is system-dependent by the
   standard — so portable code may test it for zero/non-zero and report it,
   but never compare it to a specific number. On Linux the magnitude is the
   errno; another backend may use its own numbering.

3. **One distinguished value: "file not found."** `INCLUDED` must
   distinguish not-found (try the next `BASICFORTH_PATH` segment; silent
   skip for a missing `core.fs`) from every other open failure (report it).
   The platform layer therefore exports the comparable value as a data
   symbol, **`platform_err_not_found`** (`-2` = `-ENOENT` on Linux); core.s
   compares against the symbol, never against a literal. A new backend sets
   it to whatever its `platform_open_file` returns for a missing file.

4. **Abstract input enums are translated below the boundary.** The
   file-access method `fam` (`r/o`=0, `w/o`=1, `r/w`=2) is a backend-neutral
   enum; `platform_open_file_mode` / `platform_create_file` translate it to
   native open flags (identity on Linux, but the translation is explicit).
   An out-of-range fam fails like a failed open (`-EINVAL`). Likewise
   `stdin`/`stdout`/`stderr` (0/1/2) are abstract handles the platform layer
   defines and consumes — identity with the OS fd on POSIX backends.

5. **Pipe handles share the fileid namespace with file handles.** A handle
   returned by `platform_popen` must be accepted by `platform_read_file` /
   `platform_write_fd` unchanged — that unification is what lets the Forth
   layer reuse `read-file`/`read-line`/`write-file` on pipes with zero new
   words. Free on POSIX (everything is an fd) and on Windows (`ReadFile`
   works on pipe HANDLEs); a backend that cannot unify them cannot offer
   `open-pipe` (fine — a backend without processes omits it entirely, like
   `platform_system`).

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

Read one character from stdin (blocking), with ANSI escape sequence parsing.

|              | ARM64                             | x86-64                           |
|--------------|-----------------------------------|----------------------------------|
| **Input**    | none                              | none                             |
| **Output**   | X0 = character or key code        | RDI = character or key code      |
| **Clobbers** | X0-X7 (syscall)                   | RAX, RCX, R11 (syscall)         |
| **Syscall**  | read(0, &buf, 1) — SYS_read #63  | read(0, &buf, 1) — SYS_read #0  |

Implementation: reads one byte. If the byte is ESC (27), checks FIONREAD
for additional bytes. If an ANSI escape sequence follows (`ESC [ letter`),
parses it and returns an abstract key code:

| Sequence  | Key code | Constant   |
|-----------|----------|------------|
| ESC [ A   | 129      | KEY_UP     |
| ESC [ B   | 130      | KEY_DOWN   |
| ESC [ C   | 131      | KEY_RIGHT  |
| ESC [ D   | 132      | KEY_LEFT   |
| ESC alone | 27       | KEY_ESCAPE |

Standalone ESC (no following bytes available) returns 27. Unknown sequences
return 27 (the ESC byte). Blocks until a character is available (VMIN=1,
VTIME=0).

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

**Lazy and idempotent.** It is *not* called at startup; instead the input
primitives (`KEY`, `KEY?`, `ACCEPT`) call it on every read. It acts only the
first time, and only when **stdin is a terminal** (`platform_isatty`); after
that an internal `term_is_raw` flag short-circuits it. Rationale:

- A program that never reads input — e.g. a script run as `tool.fs | less` —
  never touches the terminal, so it can't flip it to raw just long enough for a
  concurrent program (like `less`) to capture and later restore the raw state,
  which would break the user's shell.
- Keying off **stdin** (the thing we read), not stdout, means an interactive
  session still gets raw mode even when its stdout is piped or redirected
  (`basicforth | tee log`).

The `term_is_raw` flag also tells `platform_restore_term` whether there is
anything to undo. It is set **only after both ioctls succeed** (the `TCGETS`
that captures `orig_termios` and the `TCSETS` that applies raw mode); if either
fails, the flag stays clear so `restore_term` never writes back an invalid
`orig_termios`.

### platform_restore_term

Restore the original terminal settings saved by `platform_raw_mode`.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | none                               | none                                |
| **Output**   | none                               | none                                |
| **Clobbers** | X0-X7 (syscall)                    | RAX, RCX, RDI, RSI, RDX, R11      |

Uses ioctl TCSETS to write back the saved `orig_termios`. Must be called
before exit — failure to restore leaves the terminal in raw mode (no echo,
no line editing). It is a **no-op unless `platform_raw_mode` actually switched
the terminal** (the `term_is_raw` flag): a non-interactive run never saved an
`orig_termios`, so restoring one would corrupt a terminal we never touched.

### platform_isatty

Report whether a file descriptor refers to a terminal.

|              | ARM64                                 | x86-64                                |
|--------------|---------------------------------------|---------------------------------------|
| **Input**    | X0 = fd                               | RDI = fd                              |
| **Output**   | X0 = 1 if a tty, 0 otherwise          | RAX = 1 if a tty, 0 otherwise         |
| **Clobbers** | X0-X7 (syscall)                       | RAX, RCX, R11 (syscall)              |
| **Syscall**  | ioctl(fd, TCGETS, &buf) — SYS_ioctl   | ioctl(fd, TCGETS, &buf) — SYS_ioctl  |

Probes with TCGETS: it succeeds on a tty and fails (`-ENOTTY`) on a
pipe/file/redirect. Uses a private scratch termios buffer so it never disturbs
the saved `orig_termios`. Used to print the startup banner only when stdout is
an interactive terminal.

### platform_exit

Restore the terminal and exit the process with a caller-supplied status.

|              | ARM64                            | x86-64                           |
|--------------|----------------------------------|----------------------------------|
| **Input**    | X0 = exit status                 | RDI = exit status                |
| **Output**   | does not return                  | does not return                  |
| **Syscall**  | exit_group(status) — SYS_exit_group #94 | exit_group(status) — SYS_exit_group #231 |

Calls `platform_restore_term` first (preserving the status across the call),
then the exit syscall. This is the only safe way to exit — calling exit
directly would leave the terminal in raw mode. Backs the Forth word `BYE-CODE`
and the non-zero exit taken when a startup script errors.

Uses `exit_group`, not plain `exit`: `exit` ends only the calling thread, and
since the FFI brought in SDL (whose audio/video backends spawn threads), a
plain-`exit` `bye` with a device still open would leave the process alive —
main thread defunct, SDL threads running, the parent shell waiting forever.

### platform_bye

Restore the terminal and exit with status 0.

|              | ARM64                    | x86-64                   |
|--------------|--------------------------|--------------------------|
| **Input**    | none                     | none                     |
| **Output**   | does not return          | does not return          |
| **Syscall**  | exit_group(0) — SYS_exit_group #94 | exit_group(0) — SYS_exit_group #231 |

A thin wrapper: sets status 0 and jumps to `platform_exit`. Backs the Forth
word `BYE`, which prints "Goodbye!" before calling it.

### platform_write_fd

Write a buffer to an arbitrary file descriptor.

|              | ARM64                                | x86-64                               |
|--------------|--------------------------------------|--------------------------------------|
| **Input**    | X0 = fd, X1 = buffer, X2 = length    | RDI = fd, RSI = buffer, RDX = length |
| **Output**   | X0 = bytes written, or -errno        | RAX = bytes written, or -errno       |
| **Clobbers** | X0-X7 (syscall)                      | RAX, RCX, R11 (syscall)             |
| **Syscall**  | write(fd, buf, len) — SYS_write #64  | write(fd, buf, len) — SYS_write #1  |

Backs the Forth word `WRITE-FILE`, which turns the raw result into an `ior`
(0 on success, else the positive errno).

### platform_write

Write a buffer to stdout. Thin wrapper: sets fd = 1 and tail-calls
`platform_write_fd`, so existing callers are unchanged.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = buffer, X1 = length           | RSI = buffer, RDX = length         |
| **Output**   | none                               | none                               |
| **Clobbers** | X0-X7 (syscall)                    | RAX, RCX, R11 (syscall)           |
| **Syscall**  | write(1, buf, len) — SYS_write #64 | write(1, buf, len) — SYS_write #1 |

Used by DOT, DOT-S, TYPE, error messages, and other multi-character output.

### platform_init_guard_pages

Set up SIGSEGV handler and mprotect guard pages around the data stack.
Must be called before `platform_raw_mode` (early in startup).
See [Error_Handling.md](Error_Handling.md) for details.

|              | ARM64              | x86-64             |
|--------------|--------------------|---------------------|
| **Input**    | none               | none                |
| **Output**   | none (fatal on failure) | none (fatal on failure) |
| **Syscall**  | mprotect, rt_sigaction | mprotect, rt_sigaction |

### platform_open_file_mode

Open an existing file by abstract access method (`fam`: 0=read 1=write
2=read/write — see the Return-Value Contract). Translates the fam to native
open flags, copies the path to a scratch buffer, null-terminates it, and
calls openat. An out-of-range fam returns -EINVAL. Backs `OPEN-FILE`.

|              | ARM64                                      | x86-64                                     |
|--------------|--------------------------------------------|--------------------------------------------|
| **Input**    | X0 = path, X1 = len, X2 = fam              | RSI = path, RDX = len, R8 = fam            |
| **Output**   | X0 = fd (or negative errno)                | RAX = fd (or negative errno)               |
| **Syscall**  | openat(AT_FDCWD, path, flags, mode) #56    | openat(AT_FDCWD, path, flags, mode) #257   |

### platform_open_file

Open an existing file read-only. Thin wrapper: sets native flags = O_RDONLY,
mode = 0 (no fam translation needed) and jumps to the shared open path, so
`forth_included` is unchanged.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = path, X1 = length            | RSI = path, RDX = length           |
| **Output**   | X0 = fd (or negative errno)        | RAX = fd (or negative errno)       |

Returns the `platform_err_not_found` value (-2 = -ENOENT on Linux) if the
file does not exist — the one error magnitude callers may compare against.

### platform_create_file

Create or truncate a file, then open it. Translates the fam to native flags,
ORs in `O_CREAT | O_TRUNC`, sets mode 0666, and jumps to the shared open
path. An out-of-range fam returns -EINVAL. Backs `CREATE-FILE`.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = path, X1 = len, X2 = fam     | RSI = path, RDX = len, R8 = fam    |
| **Output**   | X0 = fd (or negative errno)        | RAX = fd (or negative errno)       |

### platform_fstat

Get file size via fstat.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = fd                            | RDI = fd                           |
| **Output**   | X0 = file size, or negative errno  | RAX = file size, or negative errno |
| **Syscall**  | fstat(fd, &stat_buf) #80           | fstat(fd, &stat_buf) #5           |

Extracts st_size from offset 48 in the stat structure; returns the negative
errno if the syscall fails. Used by `forth_included` and `FILE-SIZE`.

### platform_rename

Atomically rename/replace a file (`renameat` from the current directory). Copies
both paths into null-terminated scratch buffers first. Backs `RENAME-FILE`, used
by `SAVE` to swap a freshly written temp file over `session.fs`.

|              | ARM64                                        | x86-64                                       |
|--------------|----------------------------------------------|----------------------------------------------|
| **Input**    | X0=old, X1=old_len, X2=new, X3=new_len       | RDI=old, RSI=old_len, RDX=new, RCX=new_len   |
| **Output**   | X0 = 0, or negative errno                    | RAX = 0, or negative errno                   |
| **Syscall**  | renameat(AT_FDCWD, old, AT_FDCWD, new) #38   | renameat(AT_FDCWD, old, AT_FDCWD, new) #264  |

### platform_system

Run a shell command (`/bin/sh -c <cmd>`) and wait for it, returning the child's
exit status. Restores the terminal to cooked mode around the child so a
full-screen program (an editor) starts clean — the next interactive read
re-enters raw mode lazily. `environ` (captured at `_start` as `start_envp`) is
passed to `execve`, so the child inherits `$EDITOR`/`$PATH`/`$TERM`. ARM64 has no
`fork`, so `clone(SIGCHLD, stack=0, …)` gives fork semantics. Backs the Forth
`(system)` primitive and the `sh` / `edit` words. See **Shelling_Out.md**.

|              | ARM64                                          | x86-64                                       |
|--------------|------------------------------------------------|----------------------------------------------|
| **Input**    | X0 = NUL-terminated command string             | RDI = NUL-terminated command string          |
| **Output**   | X0 = exit status (0-255), or -1 on fork/exec   | RAX = exit status (0-255), or -1 on fork/exec |
| **Syscall**  | clone #220, execve #221, wait4 #260            | fork #57, execve #59, wait4 #61              |

### platform_popen

Run a shell command (`/bin/sh -c <cmd>`) with one end of a pipe replacing the
child's **stdout** (fam = R/O 0: read what it prints) or **stdin** (fam = W/O
1: write what it reads), returning the fd of our end. The fd is an ordinary
fileid (contract rule 5): `platform_read_file` / `platform_write_fd` accept it
unchanged. Any other fam → `-EINVAL` (R/W is refused — one process blocking on
both pipe directions is a deadlock trap). An fd→pid table (8 slots) lets
several pipes be open at once; all slots busy → `-EMFILE`. Terminal handling
and environment inheritance are as in `platform_system`. Backs the Forth
`(popen)` primitive under `open-pipe`. See **Shelling_Out.md**.

|              | ARM64                                          | x86-64                                       |
|--------------|------------------------------------------------|----------------------------------------------|
| **Input**    | X0 = NUL-terminated command, X1 = fam          | RDI = NUL-terminated command, RSI = fam      |
| **Output**   | X0 = fd, or -errno                             | RAX = fd, or -errno                          |
| **Syscall**  | pipe2 #59, dup3 #24, clone #220, execve #221   | pipe2 #293, dup3 #292, fork #57, execve #59  |

### platform_pclose

Close a `platform_popen` fd (a W/O child sees EOF on its stdin), reap the
child with `wait4`, and return its exit status (0-255). The fd is looked up in
the fd→pid table; an fd that did not come from `platform_popen` (or was
already pclose'd) returns `-EBADF`. `platform_close_file` on a pipe fd would
close it but leak a zombie child — which is why the Forth layer documents
`close-pipe` as the only correct way to finish a pipe. Backs the Forth
`(pclose)` primitive under `close-pipe`.

|              | ARM64                                          | x86-64                                       |
|--------------|------------------------------------------------|----------------------------------------------|
| **Input**    | X0 = fd from platform_popen                    | RDI = fd from platform_popen                 |
| **Output**   | X0 = exit status (0-255), or -errno            | RAX = exit status (0-255), or -errno         |
| **Syscall**  | close #57, wait4 #260                          | close #3, wait4 #61                          |

### platform_mmap_file

Memory-map a file with PROT_READ, MAP_PRIVATE.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = fd, X1 = size                | RDI = fd, RSI = size               |
| **Output**   | X0 = mapped address               | RAX = mapped address               |
| **Syscall**  | mmap(0, size, 1, 2, fd, 0) #222   | mmap(0, size, 1, 2, fd, 0) #9    |

Returns -1 (MAP_FAILED) on error. Used by `forth_included` to load
source files without a fixed buffer size.

### platform_mmap_anon

Map anonymous (file-less) zero-filled memory with PROT_READ|PROT_WRITE,
MAP_PRIVATE|MAP_ANONYMOUS — a data heap separate from the dictionary, with no
execute permission. Backs the ANS MEMORY wordset (`ALLOCATE`/`FREE`/`RESIZE`).

|              | ARM64                                       | x86-64                                      |
|--------------|---------------------------------------------|---------------------------------------------|
| **Input**    | X0 = size                                   | RDI = size                                  |
| **Output**   | X0 = mapped address, or negative errno      | RAX = mapped address, or negative errno     |
| **Syscall**  | mmap(0, size, 3, 0x22, -1, 0) #222          | mmap(0, size, 3, 0x22, -1, 0) #9            |

Page-granular (the kernel rounds size up to a whole page); returns a negative
errno on failure (MAP_FAILED path). Released with `platform_munmap`.

### platform_munmap

Unmap a previously mapped region (file or anonymous).

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = addr, X1 = size              | RDI = addr, RSI = size             |
| **Syscall**  | munmap(addr, size) #215            | munmap(addr, size) #11            |

### platform_close_file

Close a file descriptor.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = fd                            | RDI = fd                           |
| **Output**   | X0 = 0, or negative errno          | RAX = 0, or negative errno         |
| **Syscall**  | close(fd) #57                      | close(fd) #3                      |

### platform_read_file

Read up to `count` bytes from a file descriptor into a buffer. Backs
`READ-FILE`. A single `read()` is issued; the result is 0 at end of file.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = fd, X1 = buf, X2 = count      | RDI = fd, RSI = buf, RDX = count   |
| **Output**   | X0 = bytes read, or negative errno | RAX = bytes read, or negative errno |
| **Syscall**  | read(fd, buf, count) #63           | read(fd, buf, count) #0           |

### platform_getcwd

Get the current working directory as a NUL-terminated absolute path. Backs the
`(cwd)` primitive (`pwd`) and the startup-directory capture at boot.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = buf, X1 = size                | RDI = buf, RSI = size              |
| **Output**   | X0 = bytes incl. NUL, or negative errno | RAX = bytes incl. NUL, or negative errno |
| **Syscall**  | getcwd(buf, size) #17              | getcwd(buf, size) #79             |

### platform_chdir

Change the current working directory. Backs the `chdir` primitive (and thus
`cd` / `pushd` / `popd`). The path must be NUL-terminated.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = path (asciiz)                 | RDI = path (asciiz)                |
| **Output**   | X0 = 0, or negative errno          | RAX = 0, or negative errno         |
| **Syscall**  | chdir(path) #49                    | chdir(path) #80                   |

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

### platform_key_ready

Non-blocking check if keyboard input is available.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | none                               | none                               |
| **Output**   | X0 = byte count (>0 if ready)     | RDI = byte count (>0 if ready)     |
| **Syscall**  | ioctl(0, FIONREAD, &count) #29    | ioctl(0, FIONREAD, &count) #16    |

Returns 0 on failure or if no input available. Used by `forth_key_q` (KEY?)
which converts the count to a Forth boolean (-1 or 0).

### platform_ms

Sleep for a given number of milliseconds.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = milliseconds                  | RDI = milliseconds                 |
| **Output**   | none                               | none                               |
| **Syscall**  | nanosleep(&ts, NULL) #101          | nanosleep(&ts, NULL) #35          |

Builds a timespec struct on the stack: `tv_sec = ms / 1000`,
`tv_nsec = (ms % 1000) * 1000000`. Used by `forth_ms` (MS) for game loops
and animation delays.

### platform_page

Clear the screen and move cursor to home position.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | none                               | none                               |
| **Output**   | none                               | none                               |

Writes ANSI escape sequences `ESC[2J` (clear screen) + `ESC[H` (cursor
home) via `platform_write`. On a future bare metal platform, this would
clear VGA memory or the framebuffer directly.

### platform_at_xy

Move the cursor to a given column and row.

|              | ARM64                              | x86-64                             |
|--------------|------------------------------------|-------------------------------------|
| **Input**    | X0 = col, X1 = row (0-based)      | RDI = col, RSI = row (0-based)     |
| **Output**   | none                               | none                               |

Builds ANSI escape sequence `ESC[{row+1};{col+1}H` dynamically (converts
integers to decimal ASCII). On a future bare metal platform, this would
set VGA CRTC registers or framebuffer cursor position.

### platform_screen_width

Query terminal width in columns.

|              | ARM64                              | x86-64                              |
|--------------|------------------------------------|--------------------------------------|
| **Input**    | none                               | none                                 |
| **Output**   | X0 = columns                       | RAX = columns                        |
| **Syscall**  | ioctl(1, TIOCGWINSZ, &ws) #29     | ioctl(1, TIOCGWINSZ, &ws) #16      |

Reads `ws_col` (offset 2) from the `winsize` struct. Returns 80 if the
ioctl fails or returns 0. On a future bare metal platform, this would
return the VGA column count or framebuffer width / font width.

### platform_screen_height

Query terminal height in rows.

|              | ARM64                              | x86-64                              |
|--------------|------------------------------------|--------------------------------------|
| **Input**    | none                               | none                                 |
| **Output**   | X0 = rows                          | RAX = rows                           |
| **Syscall**  | ioctl(1, TIOCGWINSZ, &ws) #29     | ioctl(1, TIOCGWINSZ, &ws) #16      |

Reads `ws_row` (offset 0) from the `winsize` struct. Returns 25 if the
ioctl fails or returns 0.

### platform_ms_get

Return the current monotonic time in milliseconds.

|              | ARM64                                     | x86-64                                      |
|--------------|-------------------------------------------|----------------------------------------------|
| **Input**    | none                                      | none                                         |
| **Output**   | X0 = milliseconds                         | RAX = milliseconds                           |
| **Syscall**  | clock_gettime(1, &ts) — SYS_clock_gettime #113 | clock_gettime(1, &ts) — SYS_clock_gettime #228 |

Uses CLOCK_MONOTONIC (1). Computes `tv_sec * 1000 + tv_nsec / 1000000`.
Used by `forth_ms_get` (MS@) for game loop timing and RNG seeding.

### platform_cursor_off

Hide the terminal cursor.

|              | ARM64              | x86-64             |
|--------------|--------------------|---------------------|
| **Input**    | none               | none                |
| **Output**   | none               | none                |

Writes ANSI escape sequence `ESC[?25l` (6 bytes) via `platform_write`.
On a future bare metal platform, this would disable the VGA/framebuffer
cursor.

### platform_cursor_on

Show the terminal cursor.

|              | ARM64              | x86-64             |
|--------------|--------------------|---------------------|
| **Input**    | none               | none                |
| **Output**   | none               | none                |

Writes ANSI escape sequence `ESC[?25h` (6 bytes) via `platform_write`.

### platform_ioctl

Generic ioctl passthrough — the gateway for direct device control from Forth
(GPIO/I2C/evdev, any device node). Exposed to Forth as `(ioctl)`.

|              | ARM64                          | x86-64                         |
|--------------|--------------------------------|--------------------------------|
| **Input**    | X0 = fd, X1 = request, X2 = argp | RDI = fd, RSI = request, RDX = argp |
| **Output**   | X0 = result or -errno          | RAX = result or -errno         |
| **Syscall**  | ioctl — SYS_ioctl #29          | ioctl — SYS_ioctl #16          |

### platform_mmap_dev

Shared read/write mapping of a device fd at a byte offset (a mappable buffer
a driver hands out). Exposed to Forth as `(mmap-dev)`.

|              | ARM64                          | x86-64                         |
|--------------|--------------------------------|--------------------------------|
| **Input**    | X0 = fd, X1 = size, X2 = offset | RDI = fd, RSI = size, RDX = offset |
| **Output**   | X0 = addr or -errno            | RAX = addr or -errno           |
| **Syscall**  | mmap(NULL, size, RW, SHARED, fd, offset) — #222 | same — #9 |

### platform_dlopen / platform_dlsym

The FFI's library loader — the **only** platform functions that call libc
instead of the kernel (loading shared libraries needs ld.so, which only
libc's `dlopen`/`dlsym` reach). Exposed to Forth as `(dlopen)`/`(dlsym)`;
see [FFI.md](FFI.md).

|              | ARM64                          | x86-64                         |
|--------------|--------------------------------|--------------------------------|
| **Input**    | X0 = zpath (dlopen); X0 = handle, X1 = zname (dlsym) | RDI = zpath (dlopen); RDI = handle, RSI = zname (dlsym) |
| **Output**   | X0 = handle/fnptr or 0         | RAX = handle/fnptr or 0        |
| **Calls**    | libc `dlopen(path, RTLD_NOW)` / `dlsym` | same, with RSP 16-byte aligned around the call |

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

## Syscall Reference

| Syscall       | ARM64 # | x86-64 # | Signature                            |
|---------------|---------|----------|--------------------------------------|
| read          |      63 |        0 | (fd, buf, count)                     |
| write         |      64 |        1 | (fd, buf, count)                     |
| close         |      57 |        3 | (fd)                                 |
| fstat         |      80 |        5 | (fd, &stat_buf)                      |
| mmap          |     222 |        9 | (addr, len, prot, flags, fd, offset) |
| mprotect      |     226 |       10 | (addr, len, prot)                    |
| munmap        |     215 |       11 | (addr, len)                          |
| rt_sigaction  |     134 |       13 | (sig, &act, &oldact, sigsetsize)     |
| ioctl         |      29 |       16 | (fd, cmd, arg)                       |
| nanosleep     |     101 |       35 | (&timespec_req, &timespec_rem)       |
| clock_gettime |     113 |      228 | (clockid, &timespec)                 |
| openat        |      56 |      257 | (dirfd, path, flags, mode)           |
| exit_group    |      94 |      231 | (status) — all threads, see platform_exit |
| fork          |     n/a |       57 | () — x86 only; ARM64 uses clone      |
| clone         |     220 |      n/a | (flags, stack, ptid, tls, ctid)      |
| execve        |     221 |       59 | (path, argv, envp)                   |
| wait4         |     260 |       61 | (pid, &status, options, &rusage)     |

### ioctl Commands

| Constant   | Value  | Purpose                                   |
|------------|--------|-------------------------------------------|
| TCGETS     | 0x5401 | Get terminal attributes                   |
| TCSETS     | 0x5402 | Set terminal attributes                   |
| FIONREAD   | 0x541B | Get bytes available to read (for KEY?)    |
| TIOCGWINSZ | 0x5413 | Get terminal window size (for SCREEN-WIDTH/HEIGHT) |

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
| platform_lseek      | Seek within file                              |     4 |
| platform_fork_exec  | Fork and exec external process (for $EDITOR)  |     4 |
| platform_gpio_open  | Open /dev/gpiochip                            |     6 |
| platform_gpio_ioctl | GPIO read/write via ioctl                     |     6 |

The planned `platform_fb_open`/`platform_fb_mmap` pair was superseded in
v0.8.0 by the generic device gateway: `platform_ioctl` (fd, request, argp) and
`platform_mmap_dev` (fd, offset, size — shared RW mapping of a device fd),
exposed to Forth as `(ioctl)` and `(mmap-dev)`.
