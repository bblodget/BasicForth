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
256 KB total / ~226 KB free after core.fs). Unlike the data heap, dictionary
space must be
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

**Done — docs browser:** `topics`, `man <topic>`, and `apropos <keyword>` read
the markdown files in `$BASICFORTH_DOCS` so you can read `BasicForth_Manual.md`
and other topics from the REPL. See `docs/Help_System.md`.

**Still wanted — per-word help (Part A):** an interactive way to look up a
defined word. Write inline documentation blocks in the `.fs` source files that a
parser can extract into a help store, then a word like `help <word>` prints that
word's stack effect and description at the REPL. Inspired by the Linux `man`
command and Perl's POD. Open questions: where the help text lives (parsed into
memory at load time vs. read on demand from the source files), and the markup
for the doc blocks.

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
  Read-only; lands with / just after SAVE since it reuses the log. **Done** (and
  since generalised to any word via dictionary source metadata — see above).
- **Stage B — line editor + history**: **Done.** The REPL prompt is now an
  in-line editor (left/right arrows, Ctrl-A/Ctrl-E, mid-line insert/delete) with
  an up/down command-history ring. Implemented in Forth in `core.fs` behind a
  REPL input hook, arrow keys decoded by `platform_key`. See docs/Line_Editor.md.
- **Stage C — `EDIT <word>`**: **Done, then re-done.** The first cut fed `see`'s
  source lookup into the Stage-B line editor as starting text, flattening a
  multi-line `: … ;` onto one (long) horizontally-scrolled line with `\` comments
  rewritten to `( … )`. That solved recall but lost formatting. `edit` now instead
  **spawns an external editor** (`$VISUAL`/`$EDITOR`/`vi`) on a temp file via a new
  `fork`/`exec`/`wait` platform primitive (`(system)`), then recompiles + propagates
  on save — so the full source, multi-line layout and all, survives the round-trip.
  See docs/Line_Editor.md.

The **free-cursor multi-line editor** (see all the lines of a definition at once,
move the cursor freely between rows, soft-enter to split) is no longer needed for
`edit` — the external editor covers it — but remains the obvious path for an
*in-window* editor once BasicForth grows its own graphics surface (see below).
The `(system)` spawn primitive is also the foundation for reusing other Unix
tools: `sh`/`!` to run a command, `history | grep`/fzf, and friends.

## SEE for any word — source-location metadata in the dictionary

**Done (v0.6.0).** Each compiled word's header now carries an 8-byte
`[SrcId:2][Len:2][Off:4]` record stamped at compile time, plus a `.bss` source
table mapping SrcId → absolute file path. `SEE` dispatches on SrcId: file-loaded
words (`core.fs` and any `include`d file) read their byte span straight from the
source file; **primitives** report *primitive (assembly)*; a word typed at the
REPL with no file falls back to the session capture log. See docs/See_Metadata.md
and docs/See.md.

**Still far-future — decompilation.** Reconstructing source from compiled STC
when no source file exists at all (and no capture-log entry). Only worth it if we
ever want `SEE` to work with no source on disk.

## Shell-Like Words (pwd / cd / ls / cat / more)

Navigate and inspect the filesystem from the REPL, so you can hop to another
directory and list or read a file without leaving BasicForth — handy for pulling
up a source file or data file mid-session.

Most of the infrastructure already exists: `pwd` ← `platform_getcwd` (added for
SEE metadata); `ls` ← `(getdents)` / `(each-dir)` (the help browser already
walks directories); `cat` / `more` ← the file words (`open-file`, `read-file`)
plus the man/tutorial pager (`(pg-line)`, `screen-height`). The only new syscall
needed is `chdir` (80 on x86-64, 49 on ARM64) to back `cd`.

**cwd model:** `cd` does a real `chdir`, so `ls`, `cat`, and relative `include`
all agree on "where am I." `session.fs` is **pinned to the startup directory**
(captured as an absolute path at boot, the way SEE already does), so persistence
never wanders no matter where you `cd` to.

**Jumping back:**
- `cd <dir>` — change to `<dir>`.
- `cd` (no argument) — return to the **startup directory** (the session home
  base where `session.fs` lives). Note this differs from a Unix shell, where
  bare `cd` goes to `$HOME`; here the meaningful anchor is where you launched,
  not the OS home.
- `cd ~` — go to `$HOME` (optional `~` expansion, for shell muscle memory).
- `pushd` / `popd` / `dirs` — a small fixed-depth directory stack for deeper hops.

**First cut:** read-only + navigation (`pwd cd ls cat more pushd popd dirs`).
Defer filesystem *mutators* (`mkdir rm cp touch`) as a separate, riskier class —
a later decision, not part of this. Limitation: path tokens come from
`parse-word`, so paths containing spaces won't work in v1.

## Raw ALSA Audio for Appliance Mode

Sound today is SDL3 audio (`sound.fs`, docs/Sound.md) — the right call on a
desktop, where PipeWire holds the hardware PCM device open and a direct
`open("/dev/snd/pcm*")` fails with EBUSY, the same fight-the-compositor
problem that killed the DRM/KMS display backend.

But in a future **appliance / PID-1 mode** (BasicForth as the whole system, no
sound server running) the calculus flips: `/dev/snd/pcmC*D*p` is free, and a
raw ALSA-ioctl backend — `open` + `SNDRV_PCM_IOCTL_*` through the existing
`(ioctl)` gateway, mirroring how drm.fs drove the display — would give sound
with zero dependencies. The fiddly part is `snd_pcm_hw_params` (a ~600-byte
struct of masks/intervals); a `tools/sndoff.c` offset dumper would pin it
down, like drmoff.c/sdl3off.c did. Same words (`snd-open tone beep snd-wait
snd-close`) backed by a different file, so programs wouldn't care.

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

