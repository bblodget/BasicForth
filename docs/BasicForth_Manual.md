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
basicforth                          # interactive REPL
basicforth file.fs                  # load file, then enter REPL
```

At startup, BasicForth:
1. Loads `core.fs` from the current directory (silent skip if not found)
2. If a filename argument was given, loads it via INCLUDED
3. Enters the interactive REPL

### Loading Files from the REPL

```
> include examples/snake.fs
 ok
> snake
```

`INCLUDE` parses the next word as a filename and loads it. Paths are
relative to the current working directory.

For the compile-only `S"` form (e.g., inside a colon definition):

```
> : load-snake s" examples/snake.fs" included ; load-snake
```

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
