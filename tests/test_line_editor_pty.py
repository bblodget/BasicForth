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

UP = b"\x1b[A"; DOWN = b"\x1b[B"; LEFT = b"\x1b[D"; RIGHT = b"\x1b[C"
CTRL_A = b"\x01"; CTRL_E = b"\x05"; BS = b"\x7f"

passed = failed = 0

def spawn():
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(CMD[0], CMD); os._exit(1)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, COLS, 0, 0))
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

# 8b) The capture log only records a line that moved LATEST forward, so data
#     laid down AFTER a `create` (rows of `l,` or `,`) is dropped from `save`
#     silently — see TODO "save silently drops data laid down after a create".
#     The Sprites lesson works around it by building the art in a colon word,
#     which IS captured; this pins that the workaround keeps saving. Only
#     testable here: the log records interactive lines, not piped ones.
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
# The bare form is the one that loses data: create logs, the rows do not.
send(fd, b"create bare\r")
send(fd, b"  7 l, 8 l,\r")
send(fd, ("save %s\r" % mpath).encode(), 0.7)
try:
    art2 = open(mpath).read()
except OSError:
    art2 = ""
report("bare create drops its data rows (documented gap)",
       "create bare" in art2 and "7 l, 8 l," not in art2)
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
    os.path.dirname(os.path.abspath(__file__)), "..", "docs", "Language-Reference")
fd = spawn()
out = send(fd, b"help allot\r", 0.7)
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

print(f"\n{passed} passed, {failed} failed, {passed + failed} total")
sys.exit(1 if failed else 0)
