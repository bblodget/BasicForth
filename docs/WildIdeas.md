# BasicForth — Wild Ideas

Ideas that are exciting but not yet planned. Some may be impractical,
some may become features. The point is to capture them before they're
forgotten.

---

## Standalone Executables from Forth Source

Compile a Forth application into a self-contained binary that boots
and runs without the interactive REPL.

**Option A: Run-only main** — A stripped-down `main_run.s` that loads
core.fs + app.fs, executes a single word (e.g., `snake`), and exits.
No REPL, no prompt. Usage: `./basicforth-run snake.fs snake`

**Option B: Baked-in source** — Embed .fs files into the binary via
`.incbin` so no external files are needed at runtime. The result is a
single self-contained executable: `./snake`

**Option C: AOT compilation** — Compile Forth words to native code at
build time, emitting a binary with no interpreter overhead. Essentially
a Forth cross-compiler. Much more ambitious but Option B gets 90% of
the benefit with 10% of the effort.

**Makefile integration** — A target like `make app SRC=snake.fs ENTRY=snake`
that produces a standalone binary.

## Programming Adventures Youtube Channel

This is not really a wild idea, but instead of having the Youtube channel
be call BlodgetProject...  I like the name "Programming Adventures" better
(at the moment). It's more descriptive of the content and less tied to my
name, which is good if I want to eventually bring in other hosts or rebrand.

It also ties in to my initial experiences of programming as a child.
I remember sitting with with Dad watching him program in BASIC on his
APPLE II, and feeling as if we where moving through computer space,
exploring.  I remember my Mom calling us for dinner, and thinking
she has no idea the adventure we are on.

