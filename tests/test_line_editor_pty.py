#!/usr/bin/env python3
# BasicForth — Line-editor PTY tests
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# The line editor only engages on a real terminal, and horizontal scrolling only
# triggers when a line is wider than the terminal — neither of which the
# pipe-based integration suite can exercise. These tests run the REPL under a
# pseudo-terminal with a deliberately narrow window so the editor scrolls.
#
# Usage: test_line_editor_pty.py <forth-command...>
#   e.g. ./test_line_editor_pty.py ./src/arch/x86/basicforth
#        ./test_line_editor_pty.py qemu-aarch64-static ./src/arch/arm64/basicforth

import pty, os, sys, select, time, struct, fcntl, termios

if len(sys.argv) < 2:
    print("usage: test_line_editor_pty.py <forth-command...>")
    sys.exit(2)
CMD = sys.argv[1:]
COLS = 16                      # narrow terminal: any line > ~13 chars scrolls

# Point the library search at this checkout, so a `require` inside a test
# resolves from the tree under test rather than from whatever the caller
# happened to export. Without it these tests silently depended on a sourced
# setup.sh — green in a set-up shell, three failures in a bare one.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ["BASICFORTH_PATH"] = os.path.join(REPO_ROOT, "src", "forth")

UP = b"\x1b[A"; DOWN = b"\x1b[B"; LEFT = b"\x1b[D"; RIGHT = b"\x1b[C"
CTRL_A = b"\x01"; CTRL_E = b"\x05"; BS = b"\x7f"

passed = failed = 0

def spawn(rows=24):
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(CMD[0], CMD); os._exit(1)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, COLS, 0, 0))
    time.sleep(0.5)
    drain(fd)                  # discard the banner
    return fd

def drain(fd, t=0.5):
    out = b""; end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.15)
        if not r:
            continue
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d:
            break
        out += d
    return out

def send(fd, data, t=0.25):
    os.write(fd, data)
    return drain(fd, t)

def send_until_done(fd, data, timeout=60.0):
    # For steps whose duration depends on the host — the help scan walks the
    # whole reference corpus, which takes seconds of emulated CPU under qemu
    # and grows with the docs. A fixed drain is a guess that rots; instead
    # queue a sentinel line behind the command and read until its output
    # appears. The sentinel is echoed/executed only after the command
    # finishes, so this is deterministic at any host speed. Not safe for
    # steps that can hit the pager pause (it would eat sentinel chars).
    os.write(fd, data)
    os.write(fd, b'." PTY-STEP-DONE" cr\r')
    out = b""; end = time.time() + timeout
    while time.time() < end and b"PTY-STEP-DONE" not in out:
        r, _, _ = select.select([fd], [], [], 0.15)
        if not r:
            continue
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d:
            break
        out += d
    return out

def report(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1; print(f"  PASS  {name}")
    else:
        failed += 1; print(f"  FAIL  {name}  {detail}")

# 1) A line wider than the terminal is submitted whole (not truncated).
fd = spawn()
out = send(fd, b'." ABCDEFGHIJKLMNOP-OK"\r')
send(fd, b"bye\r"); os.close(fd)
report("long line submitted whole", "ABCDEFGHIJKLMNOP-OK" in out.decode(errors="replace"))

# 2) Editing a scrolled line: Home + prepend (scroll left) and End + append
#    (scroll right). 8 numbers + 7 '+' fully reduce to 44; prepend 1, append
#    '+ .' -> 9 numbers, 8 '+' -> 45. A wrong cursor landing would not give 45.
fd = spawn()
send(fd, b"2 3 4 5 6 7 8 9 + + + + + + +")
send(fd, CTRL_A); send(fd, b"1 ")
send(fd, CTRL_E); out = send(fd, b" + .\r")
send(fd, b"bye\r"); os.close(fd)
report("home/end edit on a scrolled line", "45  ok" in out.decode(errors="replace"))

# 3) Regression: recalling a SHORTER line after the window scrolled on a longer
#    one must still render it (a stale-high scroll offset used to blank it).
fd = spawn()
send(fd, b'." ZQX" cr\r')               # short, uniquely-marked -> history
send(fd, b"111111 222222 +")            # long in-progress line -> window scrolls
seg = send(fd, UP, 0.5)                 # recall the short line; capture only this redraw
send(fd, b"\rbye\r"); os.close(fd)
report("recalled short line renders after scroll",
       '." ZQX"' in seg.decode(errors="replace"),
       "recall redraw was blank")

# 4) Multi-line definition: a continuation prompt ("... ") appears while a
#    definition is open, and a continuation line wider than the terminal scrolls
#    and still compiles correctly.
fd = spawn()
after_colon = send(fd, b": bigsum\r")        # open def -> continuation prompt next
send(fd, b"1 2 + 3 + 4 + 5 +\r")             # long continuation line (scrolls)
send(fd, b";\r")
result = send(fd, b"bigsum .\r")
send(fd, b"bye\r"); send(fd, b"n")           # dirty-guard: discard bigsum
os.close(fd)
report("continuation prompt shown", "..." in after_colon.decode(errors="replace"))
report("long continuation line compiles", "15  ok" in result.decode(errors="replace"))

# --- Dirty-guard: the save-first prompt only engages at a real terminal, so its
#     interactive paths are tested here (the pipe suite covers the bookkeeping).

# 5) A dirty `bye` prompts; answering n discards and exits.
fd = spawn()
send(fd, b": gw1 1 ;\r")
out = send(fd, b"bye\r")
report("dirty bye prompts save-first", "save first? (y/n)" in out.decode(errors="replace"))
out = send(fd, b"n")
report("guard n discards and exits", "Goodbye" in out.decode(errors="replace"))
os.close(fd)

# 6) Any other key cancels (the session survives); y with no current file
#    cancels too, with a hint.
fd = spawn()
send(fd, b": gw2 2 ;\r")
send(fd, b"bye\r")
out = send(fd, b"q")
report("guard other-key cancels", "(cancelled)" in out.decode(errors="replace"))
alive = send(fd, b"gw2 .\r")
report("cancelled exit returns to the REPL", "2  ok" in alive.decode(errors="replace"))
send(fd, b"bye\r")
out = send(fd, b"y")
report("guard y without a current file cancels",
       "no current file" in out.decode(errors="replace"))
send(fd, b"bye\r"); send(fd, b"n"); os.close(fd)

# 7) y with a current file saves, then proceeds with the exit.
import tempfile
gfd, gpath = tempfile.mkstemp(suffix=".fs", prefix="bf-guard-")
os.close(gfd)
fd = spawn()
send(fd, ("save %s\r" % gpath).encode())     # sets the current file (log still empty)
send(fd, b": gw3 3 ;\r")
send(fd, b"bye\r")
out = send(fd, b"y", 0.7)
report("guard y saves then exits",
       "saved to" in out.decode(errors="replace") and "Goodbye" in out.decode(errors="replace"))
try:
    saved = open(gpath).read()
except OSError:
    saved = ""
report("guard y wrote the definition", ": gw3 3 ;" in saved)
try:
    os.remove(gpath)
except OSError:
    pass
os.close(fd)

# 8) `new` is guarded the same way: cancel keeps the module, n discards it.
fd = spawn()
send(fd, b": gw4 4 ;\r")
out = send(fd, b"new\r")
report("dirty new prompts save-first", "save first? (y/n)" in out.decode(errors="replace"))
send(fd, b"q")
alive = send(fd, b"gw4 .\r")
report("cancelled new keeps the module", "4  ok" in alive.decode(errors="replace"))
send(fd, b"new\r"); send(fd, b"n")
gone = send(fd, b"gw4 .\r")
report("n on new discards the module", "? gw4" in gone.decode(errors="replace"))
send(fd, b"bye\r"); os.close(fd)

# 8a) Ctrl-D on an empty line submits "bye", so it exits through the dirty
#     guard like a typed bye. Mid-line and on a continuation line it is
#     ignored (text there compiles into the open definition, so a stuffed
#     bye would not run). Terminal-only: pipes never reach the line editor.
fd = spawn()
send(fd, b": gw5 5 ;\r")
out = send(fd, b"\x04")
report("ctrl-d when dirty prompts save-first",
       "save first? (y/n)" in out.decode(errors="replace"))
out = send(fd, b"n")
report("ctrl-d guard n discards and exits", "Goodbye" in out.decode(errors="replace"))
os.close(fd)
fd = spawn()
out = send(fd, b"\x04")
report("ctrl-d on a clean session exits", "Goodbye" in out.decode(errors="replace"))
os.close(fd)
fd = spawn()
send(fd, b"7 8 +"); send(fd, b"\x04")
out = send(fd, b" .\r")
report("ctrl-d mid-line is ignored", "15  ok" in out.decode(errors="replace"))
send(fd, b": gw6\r"); send(fd, b"\x04"); send(fd, b"6 ;\r")
out = send(fd, b"gw6 .\r")
report("ctrl-d on a continuation line is ignored",
       "6  ok" in out.decode(errors="replace"))
# `[` interprets INSIDE an open definition (STATE=0, prompt "> "), so STATE
# alone can't gate the exit — the open definition's hidden header must too.
send(fd, b": gw7 [\r"); send(fd, b"\x04"); send(fd, b"] 7 ;\r")
out = send(fd, b"gw7 .\r")
report("ctrl-d inside [ ... ] is ignored",
       "7  ok" in out.decode(errors="replace"))
send(fd, b"bye\r"); send(fd, b"n"); os.close(fd)

# 7c) Regression: an ABORTED definition used to leave its half-built header as
#     LATEST with F_HIDDEN set, so the guard believed a definition was open for
#     the rest of the session and Ctrl-D silently did nothing — the feature was
#     dead after any typo inside a `:`. Both abort routes.
for label, setup in (("after an aborted definition", [b": gw8\r", b"nosuchword\r"]),
                     ("after cancel;",               [b": gw9\r", b"cancel;\r"])):
    fd = spawn()
    for line in setup:
        send(fd, line)
    out = send(fd, b"\x04", 0.6).decode(errors="replace")   # should submit bye
    if "save first? (y/n)" in out:          # abandoned work may or may not dirty
        out += send(fd, b"n", 0.6).decode(errors="replace")
    report("ctrl-d works %s" % label, "Goodbye" in out)
    try:
        os.close(fd)
    except OSError:
        pass

# 8b) Data laid down AFTER a `create` — rows of `l,` or `,` on their own lines —
#     used to be dropped from `save` silently, because capture only recorded a
#     line that moved LATEST. It now also records a line that moved HERE, so
#     both forms round-trip: the colon-word idiom the lessons teach, and the
#     bare rows. Only testable here: the log records interactive lines, not
#     piped ones.
mfd, mpath = tempfile.mkstemp(suffix=".fs", prefix="bf-art-")
os.close(mfd)
fd = spawn()
send(fd, b"require graphics.fs\r", 0.7)
send(fd, b"magenta constant __\r")
send(fd, b"green constant GG\r")
send(fd, b": inv-art\r")            # a multi-line colon def: captured as one group
send(fd, b"  __ l, GG l,\r")
send(fd, b"  GG l, __ l, ;\r")
send(fd, b"create inv inv-art\r")   # single line, moves LATEST: captured
send(fd, ("save %s\r" % mpath).encode(), 0.7)
try:
    art = open(mpath).read()
except OSError:
    art = ""
report("colon-built art table survives save",
       ": inv-art" in art and "__ l, GG l," in art and "create inv inv-art" in art)
# The bare form now round-trips too: `create` logs, and the rows log because
# they moved HERE. (Regression guard for the silent-data-loss bug.)
send(fd, b"create bare\r")
send(fd, b"  7 l, 8 l,\r")
send(fd, ("save %s\r" % mpath).encode(), 0.7)
try:
    art2 = open(mpath).read()
except OSError:
    art2 = ""
report("bare create keeps its data rows (HERE moved)",
       "create bare" in art2 and "7 l, 8 l," in art2)
send(fd, b"bye\r"); os.close(fd)
try:
    os.remove(mpath)
except OSError:
    pass

# 8c) The Bitmaps lesson's module flow: save, then change a word with :e and
#     see it MUTATED in place rather than appended. Terminal-only, because :e
#     needs an active session and the capture log only records typed lines.
bfd, bpath = tempfile.mkstemp(suffix=".fs", prefix="bf-bitmaps-")
os.close(bfd)
fd = spawn()
send(fd, b"require graphics.fs\r", 0.7)
send(fd, b': inv-art  s" ..####.." row,  s" .#....#." row, ;\r')
send(fd, b"create inv inv-art\r")
send(fd, ("save %s\r" % bpath).encode(), 0.7)
send(fd, b':e inv-art  s" ..####.." row,  s" #......#" row, ;\r', 0.9)
try:
    saved_bm = open(bpath).read()
except OSError:
    saved_bm = ""
# exactly one definition, carrying the NEW art -- a plain ':' would append a
# second copy and leave the old rows in the file.
report("lesson :e mutates art in place, not appended",
       saved_bm.count("\n: inv-art") + saved_bm.startswith(": inv-art") == 1
       and "#......#" in saved_bm and ".#....#." not in saved_bm)
send(fd, b"bye\r"); os.close(fd)
try:
    os.remove(bpath)
except OSError:
    pass

# 9) Markdown rendering is terminal-only, so it can only be tested here: on a
#    PTY, help output is rendered — the "## " heading comes out bold with the
#    hashes stripped, the indented example cyan, attributes reset by line end.
#    (The pipe suite asserts the complementary half: piped output stays plain.)
os.environ["BASICFORTH_DOCS"] = os.path.join(
    REPO_ROOT, "docs", "Language-Reference")
fd = spawn()
out = send_until_done(fd, b"help allot\r")
txt = out.decode(errors="replace")
report("help heading bold, hashes stripped",
       "\x1b[1mallot" in txt and "## allot" not in txt)
report("indented example cyan", "\x1b[36m" in txt)
report("attributes reset", "\x1b[0m" in txt)
out = send(fd, b': t9 s" a *b* c" (mk-span) cr ; t9\r')
report("*italic* span rendered",
       "\x1b[3mb\x1b[0m" in out.decode(errors="replace"))
send(fd, b"\r")                # continue past a pager pause, or just re-prompt
send(fd, b"bye\r"); os.close(fd)

# 10) The startup banner is gated on stdout being a terminal, so its extra
#     lines are invisible to the pipe suite and can only be checked here.
#     Line 1 is the version, line 2 the copyright + no-warranty notice that
#     points at `license`, line 3 what to type next. The pipe suite asserts
#     the complementary half: `-v` stays exactly one line for scripts.
pid, fd = pty.fork()
if pid == 0:
    os.execvp(CMD[0], CMD); os._exit(1)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
time.sleep(0.5)
banner = drain(fd, 0.8).decode(errors="replace")
send(fd, b"bye\r"); os.close(fd)
report("banner line 1: version", "*** BasicForth" in banner)
report("banner line 2: copyright and no warranty",
       "Copyright (C) 2026 Brandon Blodget" in banner and "No warranty" in banner)
report("banner line 3: what to type next",
       "`license'" in banner and "`help'" in banner and "`bye'" in banner)

# 11) LIST pages the capture log, and the pause only exists on a terminal: the
#     pipe suite sees the text but never the --more-- bar, so the pause and the
#     q-quits path can only be tested here. A short window makes a nine-line
#     program overflow one screenful.
fd = spawn(rows=8)                          # pause after screen-height-1 = 7 lines
for i in range(1, 10):
    send(fd, (": a%d %d ;\r" % (i, i)).encode(), 0.2)
paged = send(fd, b"list\r", 0.8).decode(errors="replace")
after_q = send(fd, b"q", 0.5).decode(errors="replace")
still_live = send(fd, b"1 2 + .\r", 0.4).decode(errors="replace")
send(fd, b"bye\r"); send(fd, b"n\r"); os.close(fd)
report("list pauses at a screenful", "-- more" in paged,
       "no --more-- bar in: %r" % paged)
report("list q quits mid-program", ": a9 9 ;" not in after_q,
       "kept printing after q: %r" % after_q)
report("prompt is live after quitting the pager", "3  ok" in still_live,
       "got: %r" % still_live)

print(f"\n{passed} passed, {failed} failed, {passed + failed} total")
sys.exit(1 if failed else 0)
