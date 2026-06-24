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

## malloc / Heap (dynamic memory)

Today all memory is one fixed `DICT_SPACE_SIZE` arena (~57 KB free after
core.fs), with no heap. Idea: add an ANS MEMORY wordset (`ALLOCATE`/`FREE`/
`RESIZE`) backed by `mmap(MAP_ANONYMOUS)` — a heap *separate* from the
dictionary, allocated from the kernel on demand with no libc. That would unblock
several other ideas: session-source buffers for `SAVE`/persistence, storage for
the interactive help text, and scratch space for the text-processing library.

A separate, harder step would be *growing the dictionary itself* when it runs
out of space (movable `HERE`, guard-page handling) — treat the mmap heap as the
first, simpler piece and dictionary growth as a later maybe. Needs more
discussion before it's firmed up.

## Perl-style Text-Processing Library

A Forth vocabulary that makes BasicForth pleasant for the kind of quick text
munging people reach for Perl or awk for. Candidate words: line and field
splitting / joining, `fields`, `substr`, simple match / replace, and maybe a
tiny glob or regex engine. The Phase 4 file words (`read-line`, `write-line`,
`open-file`, …) are the foundation; this layers ergonomic string/text helpers
on top so a `.fs` script can slice columns, filter lines, and reformat data in
a few words.

## Interactive Help System (man / perldoc style)

An interactive way to look up information about defined words. Write inline
documentation blocks in the `.fs` source files that a parser can extract into a
help store, then a word like `help <word>` / `man <word>` prints that word's
stack effect and description at the REPL. Inspired by the Linux `man` command
and Perl's POD. Open questions: where the help text lives (parsed into memory
at load time vs. read on demand from the source files), and the markup for the
doc blocks.

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

