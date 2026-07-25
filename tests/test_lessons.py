#!/usr/bin/env python3
# BasicForth — Lesson replay tests
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# The lessons in docs/Tutorial/ are executable documentation: every 4-space
# indented block is something a learner types at the prompt. Nothing else
# checks them, so a shipped feature can change under a lesson and leave it
# quietly wrong — this replays each lesson the way a learner walks it (one
# session, steps in order, state carrying from step to step) and fails on any
# error the lesson did not set out to teach.
#
# It also loads every examples/*.fs, since a lesson that points at a demo is
# only as good as the demo.
#
# Usage: test_lessons.py <forth-command...>
#   e.g. ./test_lessons.py ./src/arch/x86/basicforth
#        ./test_lessons.py qemu-aarch64-static -L /usr/aarch64-linux-gnu \
#                          ./src/arch/arm64/basicforth

import os, re, shutil, subprocess, sys, tempfile

if len(sys.argv) < 2:
    print("usage: test_lessons.py <forth-command...>")
    sys.exit(2)
# Each lesson runs in a scratch cwd (it may `save`), so a relative binary path
# would no longer resolve — absolutize it up front, the way test_integration.sh
# does with sv_forth. Non-path arguments (qemu's name, its flags) pass through.
CMD = [os.path.abspath(a) if a.startswith("./") or os.path.exists(a) else a
       for a in sys.argv[1:]]
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LESSONS = os.path.join(REPO, "docs/Tutorial")
LIB = os.path.join(REPO, "src/forth")
# Emulated runs are minutes, not seconds: a lesson that would hang must still
# fail rather than wedge the suite, so the limit scales instead of vanishing.
TIMEOUT = 90 if len(CMD) == 1 else 420

# Per-lesson configuration.
#   skip     — step headings that cannot run headless, each with its REASON.
#              Every skip is printed, so coverage never shrinks silently.
#   expect   — error text the lesson deliberately teaches. Anything NOT listed
#              here is a failure; keep this list short and specific.
#   env      — extra environment (the graphics lessons need a video driver).
DUMMY = {"SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"}
CONFIG = {
    "Chase": {
        "skip": {
            "Refresh the seam — a Forth lesson":  "runs the game until a key",
            "Finishing the loop — collisions":    "runs the game until a key",
            "Swap the brain, live":               "runs the game until a key",
            "Three monsters, three minds":        "runs the game until a key",
        },
        # The lesson's whole point at these two steps: a deferred word with no
        # behaviour yet aborts, and the empty skeleton stops at the first gap.
        "expect": ["greet: uninitialized deferred word",
                   "setup: uninitialized deferred word"],
    },
    "Graphics": {
        "env": DUMMY,
        "skip": {"Where to go next": "launches the bounce demo (blocks on ESC)"},
    },
    "Machine-Code": {
        # `dis nosuchword` is the lesson showing what a typo looks like.
        "expect": ["? nosuchword"],
    },
    "Sprites": {"env": DUMMY},
    "Bitmaps": {"env": DUMMY},
    "Fonts":   {"env": DUMMY},
    "Snake":   {"env": DUMMY},
}

ERROR_RE = re.compile(
    r"(^\? \S)|(stack underflow)|(stack overflow)|(\berror\b)|(cannot )"
    r"|(not found)|(uninitialized)|(out of memory)",
    re.IGNORECASE | re.MULTILINE)

# The graphics lessons need libSDL3 on the host. Under QEMU there is no aarch64
# libSDL3 in the -L sysroot, so those lessons SKIP rather than fail — the same
# rule test_integration.sh applies to its SDL section. Detected from the
# failure itself (the FFI's own message) rather than a hardcoded lesson list,
# so a lesson that starts using SDL is covered without touching this file.
NO_SDL = "dlopen: cannot load library"
SDL_OK = (not any("qemu" in c for c in CMD)) and subprocess.run(
    "ldconfig -p 2>/dev/null | grep -q libSDL3", shell=True).returncode == 0

passed = failed = skipped = 0


def report(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1; print("  PASS  %s" % name)
    else:
        failed += 1; print("  FAIL  %s\n%s" % (name, detail))


def skip(name, why):
    global skipped
    skipped += 1
    print("  SKIP  %s (%s)" % (name, why))


def steps(path):
    """[(heading, [code lines])] in file order."""
    out, head, code = [], None, []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("## "):
            out.append((head, code)); head, code = line[3:], []
        elif line.startswith("    ") and line.strip():
            code.append(line[4:])
    out.append((head, code))
    return [(h, c) for h, c in out if c]


def run(lines, env_extra, cwd):
    env = dict(os.environ)
    env.update({"BASICFORTH_PATH": LIB, "BASICFORTH_SESSION": "1",
                "BASICFORTH_DOCS": os.path.join(REPO, "docs"),
                # a lesson step that opens $EDITOR must not block the suite
                "EDITOR": "true", "VISUAL": "true"})
    env.update(env_extra)
    try:
        p = subprocess.run(CMD, input="\n".join(lines) + "\nbye\nn\n", env=env,
                           cwd=cwd, capture_output=True, text=True,
                           timeout=TIMEOUT)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return "timeout", ""


def unexpected(out, expect):
    """[(error line, the input line the REPL echoed before it)]

    The REPL echoes each piped input line as "> line", so a failure names the
    line that caused it without any marker injection.
    """
    hits, last = [], ""
    for line in out.splitlines():
        if line.startswith("> "):
            last = line[2:]; continue
        if ERROR_RE.search(line) and not any(e in line for e in expect):
            hits.append((line.strip(), last.strip()))
    return hits


def lesson(md):
    name = md[:-3]
    cfg = CONFIG.get(name, {})
    skips, expect = cfg.get("skip", {}), cfg.get("expect", [])
    lines, ran = [], 0
    for head, code in steps(os.path.join(LESSONS, md)):
        if head in skips:
            continue
        ran += 1
        lines += code
    tmp = tempfile.mkdtemp(prefix="lesson-%s-" % name)
    try:
        rc, out = run(lines, cfg.get("env", {}), tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not SDL_OK and NO_SDL in out:
        skip(name, "needs libSDL3")
        return
    hits = unexpected(out, expect)
    detail = ""
    if rc == "timeout":
        detail = "        timed out after %ds — a step is blocking" % TIMEOUT
    elif rc != 0:
        detail = "        exit %s (a crash, not a Forth error)" % rc
    for err, src in hits[:8]:
        detail += "\n        ! %-42s after: %s" % (err[:42], src[:42])
    report("%s (%d steps, %d lines)" % (name, ran, len(lines)),
           rc == 0 and not hits, detail)
    for head, why in skips.items():
        print("        skipped: %s — %s" % (head, why))


# An example that starts its own game blocks forever on a pipe.
EXAMPLE_SKIP = {"snake_start.fs": "launches the game (blocks until a key)"}


def example(fs):
    """Run an example to completion: no Forth error, no crash, no hang.

    The exit CODE is deliberately not asserted — several examples are filters
    (`cat.fs`, `lines.fs`, `sort.fs`, …) that exit 2 with a usage message when
    run without input, which is correct behaviour, not a failure. What this
    guards is that the file still loads and runs under the current core.
    """
    tmp = tempfile.mkdtemp(prefix="example-")
    env = dict(os.environ, BASICFORTH_PATH=LIB + ":" + os.path.join(REPO, "examples"),
               **DUMMY)
    try:
        p = subprocess.run(CMD + [os.path.join(REPO, "examples", fs)],
                           input="bye\n", env=env, cwd=tmp,
                           capture_output=True, text=True, timeout=TIMEOUT)
        out = p.stdout + p.stderr
        if not SDL_OK and NO_SDL in out:
            skip("examples/%s" % fs, "needs libSDL3")
            return
        hits = unexpected(out, [])
        detail = "".join("\n        ! %s" % h[0][:60] for h in hits[:3])
        if p.returncode < 0:            # killed by a signal: a real crash
            detail += "\n        ! died on signal %d" % -p.returncode
        report("examples/%s runs" % fs, p.returncode >= 0 and not hits, detail)
    except subprocess.TimeoutExpired:
        report("examples/%s runs" % fs, False, "        timed out (hung)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


print("--- LESSONS (docs/Tutorial) ---")
for md in sorted(os.listdir(LESSONS)):
    if md.endswith(".md"):
        lesson(md)

print("\n--- EXAMPLES (examples/*.fs) ---")
for fs in sorted(os.listdir(os.path.join(REPO, "examples"))):
    if fs.endswith(".fs") and fs not in EXAMPLE_SKIP:
        example(fs)
for fs, why in EXAMPLE_SKIP.items():
    print("        skipped: examples/%s — %s" % (fs, why))

print("\n%d passed, %d failed, %d skipped, %d total"
      % (passed, failed, skipped, passed + failed + skipped))
sys.exit(1 if failed else 0)
