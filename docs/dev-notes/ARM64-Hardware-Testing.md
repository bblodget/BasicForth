# Testing on Real ARM64 Hardware

Day to day, the ARM64 build is cross-compiled on an x86-64 laptop and exercised
under `qemu-aarch64`. That catches most things, but qemu models the
*instruction set*, not the *machine*. Two gaps matter:

- **Weak memory ordering.** qemu will happily run code whose loads and stores
  are only correct under x86-64's stronger TSO model. The threading and audio
  channel code is exactly the kind that can pass every suite in emulation and
  still be wrong on hardware.
- **An incoherent instruction cache.** ARM64's I-cache is not coherent with
  the D-cache; qemu's is, in effect, because it re-translates. Any code that
  *writes* code — which for a Forth is `;`, `:noname` and every machine-code
  word — depends on a cache maintenance sequence that emulation never tests.

The second one is not hypothetical: it is what the board found on its first
run (see Status), after years of green ARM64 suites.

So the suites are also run on a real board.

## The board

A **Raspberry Pi 400** (BCM2711, Cortex-A72), reachable as `pi400` over wifi
and `pi400-eth` over a direct cable — see
[Direct-Ethernet-Link.md](Direct-Ethernet-Link.md).

**The OS matters more than the hardware.** A Pi 400 is 64-bit capable, but
Raspberry Pi OS shipped 32-bit by default for years, and an older install is
very likely `armv7l`. Check first:

    ssh <board> uname -m        # aarch64 = good, armv7l = stop here

There is no useful shortcut from a 32-bit install. `/boot/kernel8.img` exists,
so setting `arm_64bit=1` boots a 64-bit *kernel* — but the userland stays
armhf with no aarch64 glibc, and our binary is dynamically linked (the FFI
needs `dlopen`). Raspbian is an armhf-only archive, so adding arm64 as a
foreign architecture finds no packages either. Reflash with a 64-bit image;
use a spare SD card so the old install survives on its own card.

Ours runs **Raspberry Pi OS 64-bit (Debian trixie)**, kernel 6.18.

## Toolchain

The desktop image already had everything: `gcc`, `as`, `ld`, `make`, `git`,
`python3`. No `build-essential` install was needed — worth checking before
assuming otherwise:

    ssh <board> 'for t in gcc as ld make git python3; do command -v $t; done'

`src/arch/arm64/Makefile` keys off `uname -m`: on `aarch64` it drops the
`aarch64-linux-gnu-` prefix and skips qemu, so `make arm64` builds natively
with no arguments and no configuration.

The Python suites (`tests/test_lessons.py`, `tests/test_line_editor_pty.py`)
import **stdlib only** — `pty`, `select`, `termios`, `struct`, `fcntl`. No
pytest, no pexpect.

Only build **native** here. `make all` also tries the x86 target and fails on
a board with no x86 assembler; `make` alone reads `uname -m` and does the
right thing. There is no reason to want a cross-compiler on the board.

## Optional libraries

Installed 2026-08-15, and worth doing: without them the board silently tests
*less* than the laptop rather than differently.

    sudo apt install libsdl3-dev libflite1

That is the whole of it on Debian 13 (trixie) — **SDL3 is packaged**, so the
from-source build in `help sdl3-source` is not needed here. It unblocks the
SDL, audio, speech and gamepad sections of the integration suite (69 tests
that qemu skips wholesale for lack of a sysroot libSDL3) and the 8 tutorial
lessons that need a window.

**The packaged 3.2.10 was checked against the 3.4.12 the laptop builds from
source**, rather than assumed compatible, because `sdl3.fs` hard-codes
constants and struct offsets verified against the newer headers. Build
`tools/sdl3off.c` against each and diff:

    cc -o /tmp/sdl3off tools/sdl3off.c && /tmp/sdl3off

All 51 constants and offsets were identical, and all 49 SDL symbols the Forth
side binds are present in 3.2.10 (`nm -D` on the library, stripping the
`@@SDL3_0.0.0` version suffixes — without that every symbol appears missing).
Use the same two checks for any other SDL version.

A TTS engine is deliberately **not** installed on the board. Games ship
pre-rendered WAVs precisely so they do not need one, and the board is where
that claim gets tested.

## Getting the source onto the board

**Do not rsync a git worktree.** We develop in several worktrees at once
(`BasicForth-2`, `BasicForth-3`, …), and a worktree's `.git` is a
*file* pointing into the main repo's `.git/worktrees/`, not a directory. A
copy therefore lands on the board as a broken repository. That also breaks
`git describe --tags`, which is where `VERSION` comes from — the binary then
reports `unknown`, which is the stale-version trap in a new disguise.

Worktrees are also frequently on a **detached HEAD** rather than a branch,
since only one worktree may hold a given branch at a time. So don't write
`staging` into these commands and assume it resolves to what you are looking
at. Use an explicit revision, and check what you actually have:

    git -C <worktree> rev-parse --short HEAD
    git -C <worktree> status -sb | head -1        # "## HEAD (no branch)" if detached

**For anything already merged and pushed, pulling on the board is the normal
path** and the rest of this section covers what pulling cannot do. But pull
*from a branch*, explicitly:

    git checkout staging && git pull

**`git pull` needs a branch**, and the bundle workflow below leaves the board
on a detached HEAD. From there a bare pull refuses and changes nothing:

    You are not currently on a branch.
    Please specify which branch you want to merge with.

Which is the good outcome — it stops rather than guessing. Check where the
board is standing when a pull does nothing, before assuming the remote had
nothing to give:

    git -C ~/Dev/BasicForth status -sb | head -1
    # "## staging...origin/staging"  good
    # "## HEAD (no branch)"          check out the branch you meant first

For a change that is not committed at all, `scp` the changed files into the
board's tree, run, then `git checkout <path>` to restore it. That suits a
test-only edit; anything touching `.s` or `core.fs` needs a rebuild there
anyway.

The repo is public, so the board can clone anonymously and keep a usable
`origin` for later. Clone rather than bundle the bulk of it — **the clone is
also where the board gets its tags**, which `git describe --tags` needs and
therefore `VERSION` depends on:

    git clone https://github.com/bblodget/BasicForth.git

For work that is committed locally but not yet pushed, send a **delta bundle**
of just those commits. It is small, and it avoids needing an sshd on the
laptop (there isn't one).

**A bundle stores refs, not arbitrary commits.** Naming a bare SHA fails
outright:

    $ git bundle create /tmp/delta.bundle origin/main..856b333
    fatal: Refusing to create empty bundle.

So bundle a *name*, and run the command with `-C <the worktree you mean>`:

    git -C ~/Dev/BasicForth-2 bundle create /tmp/delta.bundle origin/main..HEAD
    scp /tmp/delta.bundle <board>:~/

**The ref name inside the bundle depends on what you named**, which is the
trap. A detached worktree bundled as `HEAD` stores `HEAD`; a worktree on a
branch bundled as `<branch>` stores `refs/heads/<branch>`. So a fixed refspec
on the receiving side works for one and fails on the other with
*"couldn't find remote ref HEAD"*. Don't hard-code it — read it out of the
bundle. On the board:

    cd BasicForth
    git bundle verify ~/delta.bundle || echo "missing prerequisites - git fetch origin first"
    ref=$(git bundle list-heads ~/delta.bundle | awk 'NR==1{print $2}')
    git fetch ~/delta.bundle "$ref"
    git checkout --detach FETCH_HEAD

Fetching to `FETCH_HEAD` rather than into a branch is what makes this
**repeatable**. `git fetch <bundle> <ref>:refs/heads/testing` works once and
then fails on the next bundle, because git refuses to fetch into a branch that
is currently checked out. Detaching sidesteps branch bookkeeping entirely,
which is right here — the board is a test target, not somewhere work happens.

**It does leave the board detached**, so put it back on a branch when you next
want to pull — a bare `git pull` from here refuses, as above:

    git checkout staging && git pull

`git bundle verify` is worth running first: a bundle only carries the commits
*after* its prerequisite, so if the board's `origin/main` is older than the
laptop's it will list the commits it cannot find. The fix is `git fetch origin`
on the board, then re-verify.

Then confirm the board agrees with the laptop about what it is holding:

    ssh <board> 'cd BasicForth && git describe --tags'   # e.g. v0.15.1-17-g856b333
    git -C ~/Dev/BasicForth-2 describe --tags            # must be identical

If the board's `describe` says *"No names found"*, it has the commits but not
the tags — fetch them explicitly, which a fresh `git clone` would have done
anyway:

    git fetch origin 'refs/tags/*:refs/tags/*'

`basicforth -v` should then match too, once rebuilt.

## Running the suites

On the board, use the **unsuffixed** targets. The top-level Makefile sets
`NATIVE := arm64` when `uname -m` is `aarch64`, so they already dispatch to
the ARM64 build — the `-arm64` suffixed targets exist for cross-testing *from*
x86 under qemu, and are not what you want here:

    make                         # builds native (arm64)
    make run-test                # unit tests
    make run-integration         # expect 0 failures
    make run-pty                 # terminal/editor behaviour
    make run-lessons             # replays every tutorial + examples/*.fs

One thing that bites:

- Ad-hoc runs need `BASICFORTH_PATH=src/forth`. The suites themselves are
  environment-independent, which can be confirmed with `env -u BASICFORTH_PATH`.
  Interactive setup is `. ./setup.sh` from the repo root.

### The board is not faster than qemu

Measured 2026-08-15, the same integration suite both ways:

    qemu-aarch64 on the laptop    83 s     1080 tests
    Pi 400, native               111 s     1149 tests

About **26% slower per test on the board**. A Cortex-A72 at 1.8 GHz loses to a
JIT running on a modern x86, so there is no speed argument for moving ARM64
testing here — and the count difference is the point rather than a footnote:
the board runs 69 tests qemu cannot.

**Run both.** One is local and one is remote, so they overlap for free, and
they answer different questions: qemu says "does it work", the board says
"does it work on this microarchitecture".

## Shell gotcha when driving the board over ssh

Debian's `~/.bashrc` returns early when not interactive:

    case $- in
        *i*) ;;
          *) return;;
    esac

So anything appended to `.bashrc` is invisible to `ssh <board> '<cmd>'`, which
is how most automated runs invoke things. On our Pi, `PATH` and `EDITOR` are
set **above** that guard for this reason. If a command works when you log in
and type it but not when run over ssh non-interactively, this is why.

## Status

Environment set up 2026-08-12; SDL3 added 2026-08-15. All four suites pass
natively, and the board now covers graphics, audio, gamepads and speech
playback as well as the core.

**It paid for itself on the first run.** BasicForth would not start at all on
this Cortex-A72 — `Illegal instruction` before the prompt — while every qemu
suite had been green for months. The cause was `platform_flush_icache`
stepping by the cache line size from the *caller's* address rather than from
the start of the line containing it: `DC`/`IC` act on whole lines, so the
final line of a range was never maintained, and stale bytes in the I-cache
were executed as a zeroed word, which AArch64 defines as permanently
undefined. Fixed by aligning the range down with `BIC` before each loop
(`5af401e`). qemu could not have found it — see the two gaps at the top of
this page.

It also exposed three defects in the suite itself, all of the same family —
the suite quietly assuming the machine it was written on:

- `VISUAL` in the developer's environment outranked the `EDITOR` each `edit`
  test sets, so 18 tests failed with output mentioning neither (`86410e6`).
- A binary that could not start produced ~1000 assertion failures and never
  said why; there is a smoke run before the suite now (`1d931d4`).
- Two `wav-play` tests loaded a file from a Debian package the board does not
  ship, the no-libflite test hard-coded an x86-64 library path, and every
  "is this library installed" gate read `ldconfig` off `$PATH` — which lives
  in `/sbin`, so over `ssh` those gates **skipped** and the run still reported
  `0 failed` (`9baa419`).

That last one is the pattern worth remembering: a second machine mostly finds
bugs in your *tests*, and the dangerous ones fail toward green.
