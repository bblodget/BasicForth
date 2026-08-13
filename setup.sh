# BasicForth development environment — source me, don't run me:
#
#     . ./setup.sh
#
# (The leading "./" matters: POSIX `.` searches $PATH when its operand has no
# slash, so a bare `. setup.sh` is only found by shells that fall back to the
# working directory.)
#
# The root is derived from this file's own location, so the same file works in
# every worktree (~/Dev/BasicForth, -docs, -movefix, …) with no editing — and
# a copy sourced from the wrong worktree can no longer point the library search
# at another checkout's src/forth, which is a genuinely confusing way to lose
# an afternoon.
#
# This is a convenience for interactive work. The test suites do NOT depend on
# it: tests/test_integration.sh and tests/test_line_editor_pty.py set
# BASICFORTH_PATH from their own location, so `make run-integration` and
# `make run-pty` pass in a bare shell.

# Locating this file has to work in whatever shell you use. bash exposes
# BASH_SOURCE — spelled without a subscript, which yields element 0 in bash and
# is ordinary POSIX syntax elsewhere, so a plain `sh` just sees it unset (the
# subscripted `${BASH_SOURCE[0]}` is a bash-only construct that makes dash exit
# with "Bad substitution"). zsh sets $0 to the sourced file. A strict POSIX
# shell offers nothing at all — `.` leaves $0 as the shell's own name — so fall
# back to the working directory, and verify the answer either way. Under a
# strict POSIX sh it is therefore the working directory that decides, so source
# it from the tree you actually mean.
_bf_src="${BASH_SOURCE:-$0}"
case "$_bf_src" in
    */*) _bf_home="$(cd "${_bf_src%/*}" 2>/dev/null && pwd)" ;;
    *)   _bf_home="$(pwd)" ;;
esac
[ -f "$_bf_home/src/forth/core.fs" ] || _bf_home="$(pwd)"
if [ ! -f "$_bf_home/src/forth/core.fs" ]; then
    echo "setup.sh: no BasicForth checkout here (looked for src/forth/core.fs)." >&2
    echo "  In a POSIX sh the script cannot find itself — source it from the" >&2
    echo "  top of the checkout:  cd /path/to/BasicForth && . ./setup.sh" >&2
    unset _bf_src _bf_home
    return 1 2>/dev/null || exit 1
fi
BASICFORTH_HOME="$_bf_home"
unset _bf_src _bf_home
export BASICFORTH_HOME

# basicforth on PATH — the build directory for THIS machine, chosen the same
# way the top-level Makefile picks NATIVE (uname -m, aarch64 => arm64, else
# x86). Hardcoding x86 would leave an ARM64 host — the Genio 510 board, or an
# ARM64 laptop — with a nonexistent directory on PATH and no basicforth to run.
if [ "$(uname -m)" = "aarch64" ]; then
    _bf_arch=arm64
else
    _bf_arch=x86
fi
export PATH="$BASICFORTH_HOME/src/arch/$_bf_arch:$PATH"
unset _bf_arch

# Library search for INCLUDE / REQUIRE: core.fs and friends, then the examples
export BASICFORTH_PATH="$BASICFORTH_HOME/src/forth:$BASICFORTH_HOME/examples"

# Topics for help / tutorials / apropos. Three sections, and only three: the
# rest of docs/ is design and implementation notes, which `help` should never
# offer. Guides holds the user-facing pages that are neither word references
# nor lessons (installing, and whatever joins it) — a library's `needs-lib`
# hint can then say "see help install" and be telling the truth.
export BASICFORTH_DOCS="$BASICFORTH_HOME/docs/Language-Reference:$BASICFORTH_HOME/docs/Tutorial:$BASICFORTH_HOME/docs/Guides"

# Skip the X input method (XIM) handshake: a wedged ibus-x11 silently freezes
# SDL_Init (see docs/Graphics.md "Troubleshooting"). Costs nothing for
# BasicForth — SDL key events don't use XIM.
export XMODIFIERS=@im=none

# The text-to-speech engine voice.fs renders with (docs/Speech.md). Taken from
# PATH, with no install location written down anywhere: pipx (the recommended
# install) puts piper in ~/.local/bin, and a distribution package or an
# activated venv lands on PATH just the same.
#
# That there is nothing to keep in step is the point. Several worktrees source
# this file, so a path into one checkout would send all of them to that one
# copy — and a venv inside a checkout is reachable only from it anyway.
#
# Left unset when there is no engine, which is what makes the suite's
# real-engine test skip with a reason instead of failing. Must be EXPORTED:
# that test reads it from a child process.
#
# Override either half before sourcing, for a different voice or voice store:
#   PIPER_VOICES=/srv/voices PIPER_VOICE=en_GB-alba-medium . ./setup.sh
_bf_piper="$(command -v piper 2>/dev/null)"
if [ -n "$_bf_piper" ]; then
    # %o/%t are voice.fs placeholders, not shell syntax — and the whole
    # template must avoid double quotes, which would end voice-cmd!'s s".
    export VOICE_ENGINE_CMD="$_bf_piper --data-dir ${PIPER_VOICES:-$HOME/.local/share/piper-voices} -m ${PIPER_VOICE:-en_US-lessac-medium} -f %o -- %t"
else
    # Nothing here — so CLEAR it rather than leaving it. Sourcing this file in
    # a second checkout is routine, and a value inherited from the first would
    # outlive it and keep pointing at that checkout's venv: the same
    # cross-worktree leak the search above exists to prevent, arriving by the
    # back door. setup.sh owns this variable, as it owns BASICFORTH_PATH; set
    # your own template for another engine AFTER sourcing.
    unset VOICE_ENGINE_CMD
fi
unset _bf_piper

