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
send(fd, b"bye\r"); os.close(fd)
report("continuation prompt shown", "..." in after_colon.decode(errors="replace"))
report("long continuation line compiles", "15  ok" in result.decode(errors="replace"))

print(f"\n{passed} passed, {failed} failed, {passed + failed} total")
sys.exit(1 if failed else 0)
