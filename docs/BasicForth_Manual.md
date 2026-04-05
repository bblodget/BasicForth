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

### x86-64 (native)

```
make x86
./src/arch/x86/basicforth
```

### ARM64 (cross-compile and run via QEMU)

```
make arm64
make test-arm64
```

### ARM64 (deploy to Pumpkin board)

```
make deploy
```

### How QEMU User-Mode Works

When you run `make test-arm64` on an x86-64 host, the Makefile invokes
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
make unit-test-x86
make unit-test-arm64
```

## The Prompt

When BasicForth starts, it runs a short self-test (stack primitives) and then
presents a prompt:

```
> 
```

Type a number and press Enter to see it parsed. Press Enter on an empty line
to exit.

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
