# BasicForth Manual

A modern Forth environment for Linux, inspired by 1980s BASIC. Boot up and
start coding — games, robots, whatever you want.

## Prerequisites

### x86-64 (native build)

```
sudo apt install binutils gcc make
```

### ARM64 (cross-compile from x86-64)

```
sudo apt install binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu make qemu-user-static
```

- `binutils-aarch64-linux-gnu` — cross-assembler and linker (`as`, `ld`)
- `gcc-aarch64-linux-gnu` — cross-compiler (needed for unit tests)
- `qemu-user-static` — user-mode emulation to run ARM64 binaries on x86

### ARM64 (native build on ARM64 board)

```
sudo apt install binutils gcc make
```

## Building and Running

Run `make help` for a full list of targets.

### Native build

```
make
cd src/arch/x86        # or arm64
./basicforth
```

This auto-detects your architecture — builds x86-64 on x86 hosts, ARM64 on ARM64 hosts.

### x86-64 (explicit)

```
make x86
./src/arch/x86/basicforth
```

### ARM64 (cross-compile and run via QEMU)

```
make arm64
make run-arm64
```

### ARM64 (deploy to a remote board)

See `src/arch/arm64/deploy_template.sh` — copy it to `deploy.sh` and
customize with your board's SSH hostname.

### How QEMU User-Mode Works

When you run `make run-arm64` on an x86-64 host, the Makefile invokes
`qemu-aarch64-static` to run the ARM64 binary. This is QEMU **user-mode
emulation** — it translates ARM64 instructions to x86-64 on the fly
(dynamic binary translation), while Linux syscalls pass straight through
to the host kernel.

No virtual machine, no emulated OS — just CPU translation. That's why it's
fast and why our syscall-based programs work perfectly.

The `qemu-user-static` package also registers with the kernel via
**binfmt_misc**, which teaches Linux to recognize ARM64 ELF binaries and
run them through QEMU automatically. So `./basicforth` just works, even
though it's an ARM64 binary on an x86 machine.

**Limitation:** user-mode QEMU only emulates the CPU, not hardware. Programs
that access framebuffers, GPIO, or device-specific ioctls need real hardware.

### Unit Tests

```
make run-test-x86
make run-test-arm64
```

## Usage

```
./basicforth                        # interactive REPL
./basicforth file.fs                # load file, then enter REPL
```

Run from the build directory (`src/arch/x86/` or `src/arch/arm64/`)
where `core.fs` is located, or set `BASICFORTH_PATH` to find library
files from any directory:

```
BASICFORTH_PATH=src/forth src/arch/x86/basicforth
```

`BASICFORTH_PATH` accepts a colon-separated list of directories, like
`PATH`. For example, to find both `core.fs` and the bundled examples:

```
BASICFORTH_PATH=src/forth:examples src/arch/x86/basicforth snake.fs
```

### Environment Variables

| Variable          | Description                                              |
|-------------------|---------------------------------------------------------|
| `BASICFORTH_PATH` | Colon-separated directories searched when a file is not found in CWD |

When `INCLUDE`, `INCLUDED`, or the startup `core.fs` load fails to find
a file in the current directory, BasicForth searches each directory in
`$BASICFORTH_PATH` in order and loads the first match
(`$DIR/filename`). The current directory is always tried first; empty
segments (e.g. from a leading, trailing, or doubled `:`) are skipped.
If the variable is not set, only CWD is searched.

### Startup Sequence

At startup, BasicForth:
1. Loads `core.fs` from CWD, falling back to `$BASICFORTH_PATH/core.fs`
2. If a filename argument was given, loads it via INCLUDED
3. Enters the interactive REPL

### Loading Files from the REPL

```
> include ../../../examples/snake.fs
 ok
> snake
```

`INCLUDE` parses the next word as a filename and loads it. Paths are
relative to the current working directory (the build directory).

For the compile-only `S"` form (e.g., inside a colon definition):

```
> : load-snake s" ../../../examples/snake.fs" included ; load-snake
```

### Executable Scripts (`#!`)

A Forth file can be run directly as a Unix executable script. Give it a
`#!` first line pointing at the interpreter, make it executable, and run
it:

```
#!/usr/bin/env basicforth
.( Hello from BasicForth) cr
bye
```

```
$ chmod +x hello.fs
$ ./hello.fs
Hello from BasicForth
```

BasicForth ignores a leading `#!` line (only the first line, and only an
exact `#!` — a leading `#` decimal literal such as `#10` is unaffected).
Error line numbers still count the shebang as line 1, so they match the
file's physical lines.

Notes:
- End the script with `bye` (or `0 bye-code`); otherwise BasicForth enters
  the interactive REPL after the script runs.
- If the script hits an error (an undefined word, a failed parse, a stack
  underflow, `ABORT`, …), BasicForth prints the diagnostic and exits with a
  non-zero status instead of dropping into the REPL — so a Forth utility fails
  like any other Unix program. (Errors while loading `core.fs` still drop to
  the REPL, since a broken bootstrap is a development problem, not a script
  failure.)
- `core.fs` is still loaded from the current directory or `BASICFORTH_PATH`,
  so set `BASICFORTH_PATH` if the script is run from an arbitrary directory.
- With `#!/usr/bin/env basicforth`, `basicforth` must be on your `PATH`;
  alternatively use an absolute path to the binary.
- The startup banner is printed only when BasicForth enters the interactive
  REPL (a script ending in `bye`/`bye-code` exits first) and only when stdout
  is a terminal, so a script run as a utility produces clean output whether its
  output goes to a terminal, a pipe, or a file.

### Command-Line Arguments

Scripts can read their arguments, mirroring gforth:

| Word | Stack | Description |
|------|-------|-------------|
| `argc` | ( -- a-addr ) | variable: number of arguments (`argc @`) |
| `argv` | ( -- a-addr ) | variable: pointer to the argument vector |
| `arg` | ( u -- c-addr u ) | the uth argument as a string; `0 0` if out of range |
| `next-arg` | ( -- c-addr u ) | return the next argument and consume it; `0 0` when none remain |
| `shift-args` | ( -- ) | drop the first argument, decrementing `argc` |

The auto-loaded script itself is removed from the vector at startup, so a
script's own first argument is `arg[1]` and the first `next-arg`. `arg[0]`
is the interpreter name. Both of these pass `level1.txt` as the first
argument:

```
basicforth game.fs level1.txt        # game.fs is the script
./game.fs level1.txt                 # shebang launcher, same result
```

### Exiting With a Status

`bye-code ( n -- )` exits with status `n` (visible to the shell as `$?`)
and prints nothing, so a utility's output is not corrupted. Plain `bye`
prints `Goodbye!` and exits 0, for interactive use.

```forth
matched? if  0 bye-code  else  1 bye-code  then
```

A script that errors before reaching `bye`/`bye-code` exits with status `1`
automatically (see the Notes above), so you only need an explicit `bye-code`
to return a *specific* status on success or on a handled condition.

See `examples/echo.fs` for a small Unix utility (a Forth `echo`) that uses
`next-arg` and `bye-code`.

## The Prompt

BasicForth presents an interactive prompt:

```
> 
```

Type Forth expressions and press Enter. Type `bye` to exit.

## Numbers

BasicForth parses number literals in several bases. The default base is
decimal (10), controlled by the `BASE` variable.

### Decimal

Plain digits are parsed in the current base (decimal by default):

```
> 42
= 42
> 0
= 0
```

The `#` prefix forces decimal regardless of the current base:

```
> #99
= 99
```

### Hexadecimal

The `$` prefix selects base 16. Hex digits A–F are case-insensitive:

```
> $FF
= 255
> $ff
= 255
> $1A3
= 419
```

### Binary

The `%` prefix selects base 2:

```
> %1010
= 10
> %11111111
= 255
```

### Negative Numbers

A `-` sign can appear before or after the base prefix:

```
> -7
= -7
> -$10
= -16
> $-10
= -16
```

Both forms are equivalent.

### Invalid Input

If the input cannot be parsed as a number, BasicForth reports an error:

```
> hello
  Not a number
> $GG
  Not a number
> %2
  Not a number
```

Digits are validated against the current base — `G` is not a valid hex digit,
and `2` is not a valid binary digit.

## Stack

BasicForth uses a data stack to pass values between words. Numbers are pushed
onto the stack as they are entered. Stack manipulation words will be
documented here as they become available in the interactive environment.

### Stack Words (planned)

| Word     | Effect             | Description                   |
|----------|--------------------|-------------------------------|
| `DUP`    | `( a -- a a )`     | Duplicate top of stack        |
| `DROP`   | `( a -- )`         | Remove top of stack           |
| `SWAP`   | `( a b -- b a )`   | Exchange top two items        |
| `OVER`   | `( a b -- a b a )` | Copy second item to top       |
| `.S`     | `( -- )`           | Display the stack (non-destructive) |
