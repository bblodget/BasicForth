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

## Growing the dictionary at runtime

The mmap-backed data heap (ANS MEMORY wordset: `ALLOCATE`/`FREE`/`RESIZE`) is
now implemented — see Phase 4 in TODO.md. That covers dynamic *data*: session
buffers for `SAVE`/persistence, help text, and text-processing scratch.

What's still a wild idea is the harder, separate piece: *growing the dictionary
itself* when it runs out of space (today it's one fixed `DICT_SPACE_SIZE` arena,
~57 KB free after core.fs). Unlike the data heap, dictionary space must be
**executable** (compiled words run from it), so this needs a `PROT_EXEC`
mapping — or `mprotect` to add exec, see Future/Hardening in TODO.md — plus a
movable or chained `HERE` and guard-page handling. Could be a second mmap region
that `HERE` spills into, or a relocation of the whole arena. Needs more
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

I also think it would be useful if we can search and read the markdown files
that are in the docs folder.  This would provide a way to access to
BasicForth_Manual.md and read up on other topics.

## Interactive Line Editor + EDIT (recall and re-edit definitions)

Today `ACCEPT` only handles backspace and echo. The dream is a mini-readline:
type a line, move the cursor with the arrow keys, insert/delete in the middle,
and recall previous input with up/down — the way you edit in a modern shell.
Built on top of that, an `EDIT <word>` that recalls a word's *last definition*
back into the editable input line so you can tweak it and resubmit, instead of
retyping it from scratch.

This pairs naturally with SAVE/persistence and `SEE`: the session log already
holds the source text of every definition (indexed by name at capture time), so
`SEE <word>` (read-only display) is the cheap first step, and `EDIT <word>` is
the same lookup piped into the line editor.

Staging:

- **Stage A — `SEE <word>`**: print the last captured source for a word.
  Read-only; lands with / just after SAVE since it reuses the log.
- **Stage B — line editor + history**: upgrade `ACCEPT` to parse arrow-key
  escape sequences (`ESC [ C/D`, etc.), support mid-line insert/delete with
  redraw, and keep an input-history ring (up/down recalls previous lines). We
  are already in raw mode with `platform_key`, so the bytes are available; this
  is the substantial piece and deserves its own design pass.
- **Stage C — `EDIT <word>`**: recall a definition into the editable line.

A nice simplification for Stage C: to Forth, newlines are just whitespace, so a
multi-line `: … ;` can be recalled as a *single* (long) line and edited with the
Stage-B editor — no true multi-line editing needed. The only cost is horizontal
scrolling for long lines, a normal line-editor detail.

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

