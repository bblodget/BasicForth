# Testing on Real ARM64 Hardware

Day to day, the ARM64 build is cross-compiled on an x86-64 laptop and exercised
under `qemu-aarch64`. That catches most things, but **qemu does not reproduce
ARM64's weak memory ordering**: it will happily run code whose loads and stores
are only correct under x86-64's stronger TSO model. The threading and audio
channel code is exactly the kind that can pass every suite in emulation and
still be wrong on hardware.

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

## Getting the source onto the board

**Do not rsync a git worktree.** We develop in several worktrees at once
(`BasicForth-movefix`, `BasicForth-docs`, …), and a worktree's `.git` is a
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

    git -C ~/Dev/BasicForth-movefix bundle create /tmp/delta.bundle origin/main..HEAD
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

`git bundle verify` is worth running first: a bundle only carries the commits
*after* its prerequisite, so if the board's `origin/main` is older than the
laptop's it will list the commits it cannot find. The fix is `git fetch origin`
on the board, then re-verify.

Then confirm the board agrees with the laptop about what it is holding:

    ssh <board> 'cd BasicForth && git describe --tags'   # e.g. v0.15.1-17-g856b333
    git -C ~/Dev/BasicForth-movefix describe --tags      # must be identical

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

Environment set up 2026-08-12. **The suites have not yet been run on the
board** — that is the next step, and the reason it exists.
