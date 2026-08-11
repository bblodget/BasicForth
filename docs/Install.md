# Installing BasicForth

From `git clone` to a working prompt. Everything on this page was run on
Pop!_OS 22.04 (an Ubuntu 22.04 base); other distributions differ in package
names, not in shape.

## The short version

    sudo apt install git binutils gcc make      # git fetches, the rest builds
    git clone https://github.com/bblodget/BasicForth.git
    cd BasicForth
    make
    . ./setup.sh
    basicforth

That is a complete installation. Graphics, sound and speech need libraries,
but nothing on this page below "Optional libraries" is needed to build
BasicForth or to run it.

## What BasicForth actually requires

**To build: an assembler, a linker, and `make`.** The source is assembly, so
there is no compiler in the usual sense — `as` assembles it and `gcc` links
it. That is the whole build dependency list.

`gcc` is doing the *link*, not a compile: the binary is dynamically linked so
that the FFI can `dlopen` C libraries at run time, and letting gcc drive the
link is what supplies the dynamic loader and libc's initializers. (It is also
what builds the unit-test harness, which is C.)

**To run: libc.** That is the entire list:

    $ ldd src/arch/x86/basicforth
        linux-vdso.so.1
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6
        /lib64/ld-linux-x86-64.so.2

**Everything else is optional, and stays optional.** BasicForth never links
against SDL3, flite, or anything else — it `dlopen`s them the moment a
library file asks for one, and not before. So a missing library cannot break
the build, cannot stop the binary starting, and cannot affect any feature but
its own:

    > require sdl3.fs
    dlopen: cannot load library
    > 2 3 + .
    5  ok

The session carries on. What it does *not* do is define the words that file
would have defined — loading stops where the library was needed, so a later
`snd-open` reports `? snd-open`. If a word you expected is missing, look back
for the `dlopen` line rather than at the word.

This is why the install is in two halves: get BasicForth running first, add
capabilities when you want them.

## Get the source

    sudo apt install git
    git clone https://github.com/bblodget/BasicForth.git
    cd BasicForth

`git` is not a build dependency — it is just how you fetch the source, and a
release tarball from GitHub works as well. It is worth having anyway: the
SDL3 install below clones too.

## Build

### x86-64 (native)

    sudo apt install binutils gcc make
    make

### ARM64 (cross-compile from x86-64)

    sudo apt install binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu make \
                     qemu-user-static
    make arm64

- `binutils-aarch64-linux-gnu` — cross-assembler and linker
- `gcc-aarch64-linux-gnu` — links the binary, and builds the unit tests
- `qemu-user-static` — user-mode emulation, so you can run and test the
  ARM64 binary on your x86 machine. Optional, but `make run-arm64` and the
  ARM64 test targets use it.

### ARM64 (native, on an ARM64 board)

    sudo apt install binutils gcc make
    make

`make` on its own builds for whatever architecture you are on: the top-level
Makefile reads `uname -m` and dispatches. `make all` builds both.

The binary lands in `src/arch/x86/basicforth` or `src/arch/arm64/basicforth`.
There is no `make install` — see "Putting basicforth on PATH" below.

## Check the build

    make run-test           # unit tests (C harness, native arch)
    make run-integration    # integration suite — expect 0 failures

Two further suites need `python3`:

    make run-pty            # terminal/line-editor behaviour
    make run-lessons        # replays every docs/Tutorial lesson

The suites set their own environment, so they pass in a bare shell without
`setup.sh` having been sourced. Lessons and integration checks that need a
library you have not installed report `SKIP` with a reason rather than
failing.

## Putting basicforth on PATH

    . ./setup.sh

**Source it, don't run it** — it exports variables into your current shell,
which a subprocess could not do. The leading `./` matters too: a bare
`. setup.sh` searches `$PATH` under POSIX rules and may not find the file
next to you.

It works out the checkout's location from its own path, so it is correct in
any worktree with no editing, and it sets:

- `PATH` — the build directory for this machine, so `basicforth` runs from
  anywhere
- `BASICFORTH_PATH` — where `include` and `require` look for `.fs` files
  (`src/forth`, then `examples`)
- `BASICFORTH_DOCS` — where `help`, `apropos` and `tutorial` find their pages
- `VOICE_ENGINE_CMD` — a piper command line, if piper is on your `PATH`
  (see "Speech engines" below); cleared if it is not
- `XMODIFIERS=@im=none` — skips the X input-method handshake, which can hang
  `SDL_Init` on a desktop with a wedged ibus (see [Graphics.md](Graphics.md))

For a permanent setup, source it from your shell profile, using the path to
your own checkout:

    echo ". $PWD/setup.sh" >> ~/.bashrc      # run from the checkout

Without it, BasicForth still runs — but `include`, `require` and `help` will
not find anything, so pass the paths yourself:

    BASICFORTH_PATH=src/forth src/arch/x86/basicforth

## First run

    $ basicforth
    *** BasicForth v0.15.1 (Linux/x86-64) ***
    > 2 3 + .
    5  ok
    > tutorial
    usage: tutorial <name> [step]   then  next / back / step  to move
    Tutorials (start one with:  tutorial <name>):
      Arrays — Your First Data Structure
      Bitmaps — Sprites You Type in Binary
      ...

`tutorial <name>` starts a lesson; `help <word>` explains a word; `apropos`
searches; `words` lists everything defined. `bye` exits.

If `help` or `tutorial` answers `(BASICFORTH_DOCS not set)`, `setup.sh` has
not been sourced in this shell — that is what points `BASICFORTH_DOCS` at the
pages.

## Optional libraries

Each of these adds one capability. Skipping one costs exactly that
capability.

| Library | Install | Without it you lose |
|---|---|---|
| **SDL3** | from source, see below | windows, graphics, all audio, gamepads |
| **flite** | `sudo apt install libflite1` | `say` — speaking immediately |
| **TTS engine** (piper) | see [Speech.md](Speech.md) | `voice-render` — text to WAV |

`objdump`, which the `dis` disassembler shells out to, comes with `binutils`
and is therefore already present from the build step.

### SDL3 — graphics, sound and gamepads

SDL3 is the big one: it is the window, the audio device, and the gamepad
layer, so `sdl3.fs`, `sound.fs`, `wav.fs`, `pad.fs` and `speech.fs` all need
it. (The drawing words in `graphics.fs` are pure Forth and work without it —
you can draw into a surface, you just cannot show it on screen.)

**Check your distribution first.** SDL3 is recent enough that many stable
releases do not package it yet:

    apt-cache policy libsdl3-0 libsdl3-dev

If that prints nothing — as it does on Ubuntu 22.04 and Debian bookworm —
build it from source:

    sudo apt install cmake
    git clone --depth 1 --branch release-3.4.12 \
        https://github.com/libsdl-org/SDL.git
    cmake -S SDL -B sdl-build -DCMAKE_BUILD_TYPE=Release
    cmake --build sdl-build -j$(nproc)
    sudo cmake --install sdl-build
    sudo ldconfig

`release-3.4.12` is the version BasicForth is developed against; any SDL 3.x
should work. The build takes a few minutes.

**Two things to watch:**

**Read the "Enabled backends" summary that `cmake -S` prints.** SDL builds
happily with no video or audio backend at all if the development headers for
them are missing, and you only find out later when `sdl-open` fails on a
machine that looks correctly set up. You want real drivers listed, not just
`dummy`:

    -- Enabled backends:
    --   Video drivers: dummy kmsdrm(dynamic) offscreen wayland(dynamic) x11(dynamic)
    --   Audio drivers: alsa(dynamic) disk dummy jack(dynamic) pulseaudio(dynamic) …

If you see only `dummy offscreen`, install your distribution's X11, Wayland
and ALSA development packages and configure again. SDL's own
`docs/README-linux.md`, in the checkout you just made, lists them per
distribution — it is the authoritative list, and longer than BasicForth
needs.

**Do not skip `sudo ldconfig`.** The install lands in `/usr/local/lib`, which
is on the loader's search path but only via a cache that `ldconfig` rebuilds.
Without it, `require sdl3.fs` reports that it cannot load the library even
though the file is sitting there.

To test a build without installing it system-wide, point the loader at it:

    LD_LIBRARY_PATH=/path/to/prefix/lib basicforth

### flite — `say`

`say` speaks text immediately, synthesizing in memory. It needs flite plus a
voice, both of which come in one package:

    sudo apt install libflite1

`speech.fs` loads `libflite.so.1` and the `cmu_us_slt` voice by default.
Other voices ship in the same package and `speech-voice!` switches between
them — see `help speech`.

**`libflite.so.1` is correct even though the file on disk is
`libflite.so.2.2`.** Debian versions the filename differently from the
library's own SONAME; `.so.1` is what the loader answers to. Do not "fix" it.

Speech plays through a sound channel, so it needs SDL3 as well.

### Speech engines — `voice-render`

`voice.fs` renders text to a WAV file by running an external text-to-speech
program, which it takes as a command template — so it is tied to no
particular engine. Piper is a good default (neural, offline, permissively
licensed); [Speech.md](Speech.md) has the install, and `setup.sh` picks piper
up automatically if it is on your `PATH`.

This is the path a game wants: render the phrases once, ship the WAVs, and
play them with `wav.fs` at run time. It needs neither SDL3 nor flite to
render — only to play the result back.

## Where things are

    src/arch/x86/       the x86-64 binary and its build
    src/arch/arm64/     the ARM64 binary and its build
    src/forth/          core.fs and the libraries `require` loads
    examples/           runnable programs
    docs/               design documentation
    docs/Tutorial/      the lessons `tutorial` reads
    docs/Language-Reference/   the pages `help` reads

## Next steps

- `tutorial` at the prompt, and the [Manual](BasicForth_Manual.md)
- [Graphics.md](Graphics.md) for the surface model, [Sound.md](Sound.md) for
  audio, [Speech.md](Speech.md) for both halves of speech
- [Planning.md](Planning.md) for the project's direction
