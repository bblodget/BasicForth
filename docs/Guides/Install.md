# Installing BasicForth

From `git clone` to a working prompt. The commands here were run on Raspberry
Pi OS 64-bit (a Debian 13 base) and on Pop!_OS 22.04 (an Ubuntu 22.04 base) —
which between them cover both cases, because 22.04 is old enough to predate
the SDL3 package and needs `help sdl3-source` instead. Other distributions
differ in package names, not in shape.

Building needs `binutils`, `gcc` and `make`. Running needs libc. Everything
else — graphics, sound, speech — is `dlopen`ed on demand, so a missing library
costs exactly one feature and never the build.

The whole thing, on a current Debian or Ubuntu:

    sudo apt install git binutils gcc make
    git clone https://github.com/bblodget/BasicForth.git
    cd BasicForth
    make
    . ./setup.sh
    sudo apt install libsdl3-dev libflite1    # graphics, sound, gamepads, say
    basicforth

The last `apt` line is the optional half: skip it and everything still builds
and runs, without a window or a sound. If `apt` has no `libsdl3-dev`, see
`help sdl3-source`; for rendering speech to WAV files, `help engines`.

At a glance — each of these is `help <topic>`:

    quickstart      the commands above, with what each one is for
    requirements    what is genuinely needed, to build and to run
    clone           getting the source
    build           x86-64, ARM64 cross-compile, or both
    verify          the four test suites
    installing      make install, for a permanent copy
    packages        installing and using add-on packages
    path            setup.sh, and what it exports
    first-run       your first prompt
    libraries       SDL3, flite, piper — the optional half
    flite           `say`, speaking immediately
    engines         `voice-render`, text to a WAV file
    sdl3-source     building SDL3 yourself, if apt has no package
    layout          where things live in the tree
    next-steps      where to go once it runs

For one library's own page rather than its install: `help sdl3`, `help sound`,
`help speech`, `help voice`.

## quickstart

    sudo apt install git binutils gcc make      # git fetches, the rest builds
    git clone https://github.com/bblodget/BasicForth.git
    cd BasicForth
    make
    . ./setup.sh
    basicforth

That runs BasicForth out of the checkout, which is the whole of it for trying
the language or working on it. To put a copy somewhere permanent that needs no
`setup.sh`, add `sudo make install` — `help installing`.

That is a complete installation, and a silent one. For graphics, sound,
gamepads and `say`, one more command:

    sudo apt install libsdl3-dev libflite1

Those two are the whole of it on a current distribution. If `apt` reports no
`libsdl3-dev`, yours predates SDL3 and builds it instead — `help sdl3-source`.
Rendering speech to a WAV file needs a separate engine, which is a longer
story: `help engines`.

Nothing in that second command is needed to build BasicForth or to run it.
Each library buys exactly one capability and costs exactly that capability
when it is missing — `help libraries` is the table.

## requirements

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
    sdl3.fs: needs the library libSDL3.so.0 -- see help install
    > 2 3 + .
    5  ok

The session carries on. What it does *not* do is define the words that file
would have defined — loading stops where the library was needed, so a later
`snd-open` reports `? snd-open`. If a word you expected is missing, look back
for that line rather than at the word.

A library states its requirement at the top of its file with `needs-lib`,
which is why the message names both the file that wanted it and what to do
about it (`help needs-lib`).

This is why the install is in two halves: get BasicForth running first, add
capabilities when you want them.

## clone

    sudo apt install git
    git clone https://github.com/bblodget/BasicForth.git
    cd BasicForth

`git` is not a build dependency — it is just how you fetch the source, and a
release tarball from GitHub works as well. It is worth having anyway: the
SDL3 install below clones too.

## build

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
That is enough to run from the checkout — see `help path`. To put it somewhere
permanent instead, `help installing`.

## verify

    make run-test           # unit tests (C harness, native arch)
    make run-integration    # integration suite — expect 0 failures

Two further suites need `python3`:

    make run-pty            # terminal/line-editor behaviour
    make run-lessons        # replays every docs/Tutorial lesson

The suites set their own environment, so they pass in a bare shell without
`setup.sh` having been sourced. Lessons and integration checks that need a
library you have not installed report `SKIP` with a reason rather than
failing.

## installing

Everything above runs BasicForth out of the checkout. To install it properly:

    sudo make install                 # to /usr/local
    make install PREFIX=~/.local      # or somewhere that needs no root
    basicforth

**An installed BasicForth needs no `setup.sh` and no environment at all.** It
works out where its own files are from the path of the running binary, so
`help`, `tutorial`, `include` and `require` all resolve on a bare shell:

    $ env -i /usr/local/bin/basicforth
    > help dup
    ## dup        ( x -- x x )

That also means the installed tree is **relocatable** — move or rename it and
it keeps working, with no rebuild and nothing to edit.

What lands where, under `PREFIX`:

    bin/basicforth                    the binary
    share/basicforth/forth/           core.fs and the libraries
    share/basicforth/examples/        runnable programs
    share/basicforth/docs/            the pages help and tutorial read

`make uninstall` removes exactly those (use the same `PREFIX`). `DESTDIR` is
honoured for package builds.

**If `basicforth` is not found afterwards**, the install's `bin` directory is
not on your `PATH` — likely with `PREFIX=~/.local`, where `~/.local/bin` often
is not. `make install` says so when it happens, and prints the line to add.

**Ten characters is a lot at a prompt you use constantly.** If you want it
shorter, that is a shell alias rather than a second installed name:

    echo "alias bforth=basicforth" >> ~/.bashrc

`bforth` follows the convention the other Forths use — `gforth`, `pforth`,
`yforth`. **`make install` never creates that name**, so nothing BasicForth
ships can collide with it. Whether it is free on *your* machine is a question
only your machine can answer:

    command -v bforth        # prints nothing if the name is unused here

Worth running first: an alias silently shadows an existing command of the same
name, and gives no sign it has done so. Any name works — pick one that is free.

An alias only applies at an interactive prompt. A script's `#!` line, or
anything invoking BasicForth from another program, needs the real name.

**The environment still wins.** Setting `BASICFORTH_PATH` or `BASICFORTH_DOCS`
overrides what the binary works out for itself, so a checkout with `setup.sh`
sourced keeps using the checkout even with a copy installed system-wide. That
is what lets you develop against one and have the other installed.

Nothing about installing changes the optional libraries: SDL3, flite and a
speech engine are found the same way — see `help libraries`.

## packages

Files you drop in your own package directory are found from **any** working
directory, without editing an environment variable:

    ~/.basicforth/
      lib/                a .fs file here is `require`-able anywhere
      docs/Packages/      a .md page here answers `help`
      docs/Tutorial/      a lesson here is listed by `tutorials`

Nothing creates this for you — `make install` deliberately does not, since it
may run as root and this directory is yours. Make it when you want it:

    mkdir -p ~/.basicforth/lib ~/.basicforth/docs/Packages ~/.basicforth/docs/Tutorial

Then a file `~/.basicforth/lib/greet.fs` loads with `require greet.fs` from
wherever you happen to be, and a `greet.md` beside it in `docs/Packages/`
answers `help greet`.

Three things worth knowing:

- **These are searched last.** The current directory comes first, then
  `BASICFORTH_PATH`, then your package directory. So a file you install can
  never shadow one that ships with BasicForth, and a copy in the directory
  you are working in still wins over both.
- **Your pages get their own `help` section**, listed as `Packages`, so you can
  see at a glance which topics came from something you installed.
- **`BASICFORTH_PACKAGES` moves the whole thing** if `~/.basicforth` is not where
  you want it. It names the directory itself, not its parent, so
  `BASICFORTH_PACKAGES=/opt/bf` means `/opt/bf/lib`. Set it to a directory that does
  not exist and the mechanism sits out entirely, which is what the test suites
  do. Every variable BasicForth reads is listed in `help environment`.

**Name your files for the package, not the topic.** These directories are flat
and shared — every package's pages sit in one `docs/Packages/`, every package's
lessons in one `docs/Tutorial/`, and subdirectories are not searched. So a
`Sound.md` of yours sits beside the bundled `Sound` lesson: `tutorials` lists
both, and `tutorial Sound` opens the bundled one, leaving yours advertised and
unreachable. Prefix instead — `dark-star.md`, `dark-star-levels.md` — and
nothing collides.

## path

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
  (see `help engines`); cleared if it is not
- `XMODIFIERS=@im=none` — skips the X input-method handshake, which can hang
  `SDL_Init` on a desktop with a wedged ibus (see [Graphics.md](../Graphics.md))

For a permanent setup, source it from your shell profile, using the path to
your own checkout:

    echo ". $PWD/setup.sh" >> ~/.bashrc      # run from the checkout

Without it, a binary run **from the checkout** still starts, but `include`,
`require` and `help` will not find anything, so pass the paths yourself:

    BASICFORTH_PATH=src/forth src/arch/x86/basicforth

An **installed** binary needs none of this: it locates its own files from where
it is, and `setup.sh` is only for working in a checkout. See `help installing`.

## first-run

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

## libraries

Each of these adds one capability. Skipping one costs exactly that
capability, and never the build.

| Library    | Install                      | Without it you lose        |
|------------|------------------------------|----------------------------|
| **SDL3**       | `sudo apt install libsdl3-dev` | graphics, audio, gamepads  |
| **flite**      | `sudo apt install libflite1`   | `say` — speaking immediately |
| **TTS engine** | `help engines`                 | `voice-render` — text to WAV |

On a distribution that packages SDL3, the whole optional half is one command:

    sudo apt install libsdl3-dev libflite1

**If `apt` cannot find `libsdl3-dev`, your distribution is older than SDL3.**
Ubuntu 22.04 and Debian bookworm both are. Check with

    apt-cache policy libsdl3-dev

and if it reports no candidate, build SDL3 yourself: `help sdl3-source`.

`objdump`, which the `dis` disassembler shells out to, comes with `binutils`
and is therefore already present from the build step.

SDL3 is the big one: it is the window, the audio device, and the gamepad
layer, so `sdl3.fs`, `sound.fs`, `wav.fs`, `pad.fs` and `speech.fs` all need
it. (The drawing words in `graphics.fs` are pure Forth and work without it —
you can draw into a surface, you just cannot show it on screen.)

**Your distribution's package is fine — it does not have to match the version
BasicForth is developed against.** Debian 13 (trixie) and Raspberry Pi OS
64-bit ship 3.2.10, and it was checked against the 3.4.12 the laptop builds
from source: every SDL function BasicForth binds is present, and every
constant and struct offset the Forth side hard-codes is identical between the
two. Any SDL 3.x should work for the same reason — 3.x is one stable ABI.

## flite

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

## engines

`voice.fs` renders text to a WAV file by running an external text-to-speech
program, which it takes as a command template — so it is tied to no particular
engine. Piper is a good default: neural, offline, and small.

**If you intend to ship what you render, look at the licensing before you
build a vocabulary on a voice.** Three things carry their own terms — the
engine, the voice model, and its training data — and how they bear on
generated audio is not something this page is in a position to tell you. What
it can give you is where to look:

- `piper-tts` declares **GPL-3.0-or-later** in its package metadata
  (`pip show piper-tts`).
- each **voice model** has a card at
  `huggingface.co/rhasspy/piper-voices`, naming the training dataset, that
  dataset's licence, and what the model was trained *from*. Read both of the
  last two: many piper voices are fine-tuned from a research-only model, which
  a permissive dataset line on its own will not reveal. `download_voices`
  fetches the model without its card.
- `en_US-libritts-high`, the default above, is *"Trained from scratch on
  train-clean-360"* with dataset LibriTTS under CC BY 4.0 — chosen because
  neither its data nor its lineage carries a use restriction, so the question
  need not arise for most projects.

`voice.fs` runs the engine as a separate program and never links against it.

    sudo apt install pipx                 # or your distribution's package
    pipx ensurepath                       # once: puts ~/.local/bin on PATH
    pipx install piper-tts
    command -v piper                      # check before going further

    mkdir -p ~/.local/share/piper-voices
    "$(dirname "$(readlink -f "$(command -v piper)")")/python" \
        -m piper.download_voices \
        --data-dir ~/.local/share/piper-voices en_US-libritts-high

Then re-source `setup.sh`: it builds `VOICE_ENGINE_CMD` from whatever `piper`
is on your `PATH`, so nothing has an install path written down.

**`pipx ensurepath` needs a fresh shell**, because it edits a shell profile.
Carry on in the same shell and every command above still *succeeds* while
`piper` is not on `PATH` — which is what the `command -v` check is for. An
unreachable piper leaves `VOICE_ENGINE_CMD` unset, and the only sign is the
suite reporting `SKIP … VOICE_ENGINE_CMD not set`. The voice is about 130 MB.

**If a render fails with `Unable to find voice`**, the engine was found but
`VOICE_ENGINE_CMD` was not set, so `voice.fs` fell back to its built-in
template — which names `piper` with no `--data-dir` and therefore looks
somewhere the voice is not. Re-source `setup.sh`, which knows where the voices
on this machine actually are. Piper's own message cannot tell you this, since
it never learns which template invoked it. The usual cause is installing piper
*after* sourcing `setup.sh`, and a `setup.sh` of your own that sources this one
by a hard-coded path is another: a failed `.` does not stop a shell script, so
it leaves the variable unset and still reports success.

**The `onnxruntime` warnings naming `/sys/class/drm/card0` are harmless.** It
probes for a GPU at startup, finds no vendor file to read on a machine that
does not expose one — a Raspberry Pi, for instance — and runs on the CPU, which
is what you wanted anyway. `ORT_LOGGING_LEVEL` does not suppress them. Resist
redirecting the engine's `stderr` to hide them: that is also where the reason
appears when a render genuinely fails, as above.

[Speech.md](../Speech.md) in the repository explains why the voice download
needs the environment's own interpreter, and what to do with another engine.

This is the path a game wants: render the phrases once, ship the WAVs, and
play them with `wav.fs` at run time. It needs neither SDL3 nor flite to
render — only to play the result back.

## sdl3-source

Only if `apt` has no `libsdl3-dev` — see `help libraries` first, because most
current distributions do package it and this whole page is then unnecessary.

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

To check a version BasicForth has not been tried against, `tools/sdl3off.c`
prints every constant and struct offset the Forth side hard-codes, straight
from that build's headers — build it against the two SDLs and diff the
output. That is how 3.2.10 was cleared.

## layout

    src/arch/x86/       the x86-64 binary and its build
    src/arch/arm64/     the ARM64 binary and its build
    src/forth/          core.fs and the libraries `require` loads
    examples/           runnable programs
    docs/               design documentation
    docs/Guides/        task pages (this one) that `help` reads
    docs/Tutorial/      the lessons `tutorial` reads
    docs/Language-Reference/   the pages `help` reads

Your own package directory sits outside the checkout — see `help packages`:

    ~/.basicforth/lib/          .fs files, searched after BASICFORTH_PATH
    ~/.basicforth/docs/Packages/    .md pages, listed under "Packages"
    ~/.basicforth/docs/Tutorial/    lessons, listed by `tutorials`

## next-steps

- `tutorial` at the prompt, and the [Manual](../BasicForth_Manual.md)
- [Graphics.md](../Graphics.md) for the surface model, [Sound.md](../Sound.md) for
  audio, [Speech.md](../Speech.md) for both halves of speech
- [Planning.md](../Planning.md) for the project's direction
