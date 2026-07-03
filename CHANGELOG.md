# Changelog

## Unreleased

### `compact` keeps final `is`/`to` bindings
- A definitions-only snapshot lost a deferred word's binding and a `value`'s
  contents — `cat game.compact.fs` had a dead `defer brain` and every brain
  defined but none installed. `compact` now appends, after the deduped
  definitions, the **last logged direct `is`/`to` assignment for each
  value/deferred word in the module** (found with the same log scanner `see`'s
  binding report uses), so the compacted file loads to the same behavior as
  `save`'s output.

### `defer@`, `action-of`, and a defer-aware `see`
- New standard words: **`defer@ ( xt1 -- xt2 )`** reads a deferred word's
  current action; **`action-of <name>`** is the checked, named form. And
  **`see`** on a deferred word now reports its current binding —
  `\ currently: uninitialized`, `\ currently: ' hunt is monster-brain`, or
  (for a `:noname`) `\ currently set by: <the logged assignment line>`. The
  first two read the live action cell; the `:noname` form is recovered from the
  capture log's last direct assignment, so it's best-effort (an `is` run inside
  another word leaves no logged line). See docs/Deferred_Words.md.

### `is`/`to` are type-checked (no more silent code corruption)
- `is` now requires a **deferred** target (`x: not a deferred word` otherwise);
  `to` accepts a **value or deferred** target (`x: not a value or deferred
  word` otherwise). Previously `5 to square` or `' w is square` silently
  overwrote a cell inside `square`'s compiled code. The check rides on the new
  Flags2 word-type code (`value` now tags its words too) and fires at compile
  time inside definitions. `' w to d` on a defer remains allowed, as
  documented. Constants are refused (they were never assignable — the store
  just used to "work").

### Dictionary header: second flags byte (Flags2) with a word-type code
- Each dictionary entry gains a **Flags2** byte between the flags+len byte and
  the name: low nibble = word-type code (0 = ordinary code, 1 = deferred),
  high nibble reserved. The first flags byte was full (3 flag bits + 5 length
  bits), and a type code lets tools identify what a word *is* without
  heuristics — the base for `is`/`to` type checking and a defer-aware `see`.
  `defer` tags its words; everything else is type 0. Internal layout change
  only (the name moved from offset 9 to 10) — BasicForth has no binary image
  format, so nothing external depends on the layout. See docs/Dictionary.md.

### Uninitialized deferred words name themselves
- Running a deferred word before `is` now reports **which** word is empty —
  `setup: uninitialized deferred word` instead of the anonymous message. `defer`
  compiles a small per-word stub after the body that knows its own header; `is`
  overwrites the action cell as before, after which the stub is dead code. No
  change to the happy path or to `is`/`to`.

### Dirty-guard: `new`/`load`/`bye` ask before discarding unsaved work
- BasicForth now tracks whether the module is **dirty** — the capture log holds
  changes `save` hasn't written (a definition, a direct `to`/`is`, an `edit`).
  When it is, `new`, `load`, `bye`, and `bye-code` ask
  `unsaved changes — save first? (y/n)`: **y** saves to the current file first
  (with no current file it hints `save <name>` and cancels), **n** discards, any
  other key cancels back to the REPL. The flag clears on `save` and whenever the
  log is rebuilt from a file (`load`/`reload`/`new`/startup).
- `reload` deliberately stays unguarded — it is the pull-from-disk verb, and a
  save-first there would overwrite the very file edits being pulled in. The
  prompt only appears at a real terminal (new `(tty?)` primitive): pipes and
  scripts proceed silently, so automation never blocks. `bye`/`bye-code` are now
  thin guarded Forth words over the assembly primitives. See docs/Persistence.md.
- `sh <command...>` runs the rest of the input line as a shell command via the
  `(system)` primitive (`/bin/sh -c`), the way you'd type it at a terminal —
  `sh ls -la`, `sh git status`. Output goes to the terminal; the command is
  transient (nothing captured to the module). It complements the built-in
  `pwd`/`cd`/`ls`/`cat` words by reaching the real Linux programs and the full
  shell (pipes, globs, `$VARS`). New **docs/Shelling_Out.md** explains the
  spawn-not-link architecture.

### `edit` opens an external editor (`$EDITOR`) — multi-line, formatting preserved
- `edit <word>` now writes the word's source to a temp file and opens it in your
  editor (`$VISUAL`, else `$EDITOR`, else `vi`); on a clean exit it re-reads the
  file, recompiles the word, and propagates to callers (below). Because the source
  is a real multi-line file, **indentation, line breaks, and `\` comments survive**
  — replacing the previous one-line flattened recall. Works for capture-log and
  file-loaded words alike (a file word's edit is logged like a REPL redefinition,
  so `save` persists it); a primitive or unknown name reports instead of opening
  the editor, and a non-zero editor exit leaves the word unchanged.
- New `(system) ( c-addr u -- status )` primitive runs a command via `/bin/sh -c`
  (x86 `fork`/`execve`/`wait4`; ARM64 `clone`/`execve`/`wait4`), restoring the
  terminal around the child. It's the foundation under `edit` and any future
  `sh`/`!`/`history | grep` words. The edit temp file is a fixed path
  (`/tmp/basicforth-edit.fs`) in this first cut.

### `compact` — a deduped snapshot of the module
- `save` rewrites the whole loaded file (comments and all) plus your edits, so
  redefinitions accumulate. `compact <name>` instead writes each module word's
  latest source **once**, in dependency order (walking the `.module` chain
  oldest-first and resolving each word's in-force source from the log or file),
  to a sibling **`<base>.compact<.ext>`** (e.g. `game.fs` → `game.compact.fs`) so
  you can `diff` it against `save`'s output. It drops between-definition comments
  (definitions only); a structure-preserving compact is future work. Bare
  `compact` uses the current file. See `man Tools` / docs/Persistence.md.

### `edit` recompiles a word's callers (the edit goes live)
- BasicForth is subroutine-threaded, so redefining a word doesn't update its
  already-compiled callers. Now `edit <word>` follows the edit by **recompiling
  every module word that transitively uses it** — found via the `uses` caller
  graph, recompiled from each one's source (capture log or file) in dependency
  order, and re-logged so `see`/`uses`/`save` stay correct. It prints what it
  touched, e.g. `updated: init-game setup chase`. So editing a leaf word is live
  everywhere with no manual recompiling. (Re-typing a `:` definition by hand
  stays a local redefinition.) See docs/Line_Editor.md.

### Modules: named `save` / `load`, replacing the magic `session.fs`
- Your interactive definitions are now a **module** you save to and load from
  **named files** (BASIC's `SAVE` / `LOAD`), instead of an implicit `session.fs`:
  - `save <name>` writes the module to `<name>` (cwd-relative) and makes it the
    current file; bare `save` rewrites the current file — remembered as an
    absolute path, so a later `cd` can't move it (editor-style "save").
  - `load <file>` opens a module mid-session (forget the old, load the new);
    `basicforth <file>` does the same at launch.
  - `new` clears the module to a clean slate (core only).
  - `reload` re-reads the current file (the edit/compile/run loop).
  - `-session` is now the low-level "forget the module's words" helper.
- **Capture is on with a file argument now.** Loading a module and editing it
  interactively works — `see` / `uses` / `save` cover your edits (previously a
  file argument silently disabled capture). A `bye`-script still captures nothing.
- **A broken module** with a compile error: an interactive `basicforth game.fs`
  reports the error and **drops to the REPL** so you can fix it; a non-interactive
  run exits non-zero, like a failing Unix utility.
- The `-session` restore mark now sits at the end of `core.fs`, so
  `-session` / `new` / `load` forget the *whole* module (the loaded file's words
  plus interactive ones).
- `.session` is renamed **`.module`** (breaking change since v0.8.0).
- **Migration:** there is no more `session.fs` auto-load — an existing
  `session.fs` is loaded explicitly with `basicforth session.fs`. `save` / `reload`
  are now cwd-relative (the old startup-directory pinning is gone). `load` / `new`
  / `reload` discard unsaved changes (a "save first?" prompt is planned). See
  docs/Persistence.md.

### `uses <word>` — find which module words reference a word
- `uses <word>` lists the module words whose source mentions `<word>` as a
  whole token (case-insensitive) — a grep over your own definitions, handy
  before renaming something. It reads each word's source the way `see` does —
  from the interactive capture log for words you typed, or from the source file
  for words loaded as a startup argument, via `load`, or via `include` —
  so it covers everything `.module` lists, skipping only `<word>`'s own defining
  line. Pure Forth (reuses the `see` capture log, per-word source metadata, and
  file reader; reads each source file once); no assembly. See `man Tools`.

### New tutorial: `tutorial Chase` — top-down game design
- A second interactive tutorial that teaches how to *design* a program from the
  top down with `defer`: write the whole game's shape first as deferred seams,
  run the empty skeleton to prove the structure, then fill in the parts and give
  each monster its own swappable brain via an execution-token table (the Pac-Man
  trick). Builds a complete terminal chase game. Finished program:
  `examples/chase.fs`; tutorial in `docs/Tutorial/Chase.md`.
### Graphics pivot: SDL3 replaces the direct DRM/KMS backend
- **Removed the DRM/KMS display backend** (`drm.fs` with `drm-open`/`drm-show`/
  `drm-close`/`drm-demo`, `tools/drmoff.c`, and its gated integration test),
  introduced in v0.8.0. It worked — but on any desktop the compositor owns the
  display, so a direct-DRM program can never show a *window*, only take over a
  text VT. The display backend is pivoting to **SDL3** (desktop window now;
  SDL's KMSDRM driver covers the console/board case; SDL_GPU is the 3D path).
  The revised philosophy and roadmap are in docs/Planning.md ("Graphics
  Direction"); the removed code stays in git history.
- **Kept and unaffected:** the device gateway (`(ioctl)`, `(mmap-dev)`,
  `w@`/`w!`/`l@`/`l!`) — it exists for GPIO/I2C/evdev as much as for graphics —
  and all of `graphics.fs` (the backend-agnostic surface + drawing words).
- **New primitive `fill32` ( value addr count -- )**: 32-bit block fill
  (`rep stosl` on x86, store loop on ARM64). `fill-rect` now clips the
  rectangle once and fills each visible row in a single `fill32` burst, so a
  full-screen `clear` is effectively instant instead of taking seconds.

## v0.8.0 — 2026-06-29

### Line editor: `edit <word>`, horizontal scrolling, continuation prompt
- **`edit <word>`** recalls a word's source onto the next prompt, pre-filled and
  editable, so you can tweak and resubmit a definition instead of retyping it.
  Works for words defined this session (capture log) and file-loaded words
  (`core.fs` / `include`d, via the source metadata `see` uses); primitives and
  unknown names report a short message. The source is flattened to one line, and
  a `\` line comment is rewritten as a self-terminating `( comment )` so it does
  not swallow the rest of the definition once everything is on one line.
- **Horizontal scrolling**: a line wider than the terminal now scrolls sideways
  instead of wrapping and scrambling the cursor. The editor paints a one-row
  window onto the line, sliding it to keep the cursor visible.
- **Continuation prompt**: while a `:` definition is open the REPL prompts with
  `... ` instead of `> `, so multi-line definitions read clearly; it returns to
  `> ` once `;` closes the definition.
- All in the shared `core.fs` editor (`(edit-line)`), with the continuation
  prompt printed by `main.s` on both architectures. New `tests/test_line_editor_pty.py`
  (`make run-pty`) covers scrolling and the continuation prompt under a
  pseudo-terminal. See docs/Line_Editor.md.

### `.session` — list the words you've defined this session
- `.session` lists just the words you've added on top of `core.fs` (interactive
  definitions, a reloaded `session.fs`, or anything `INCLUDE`d), newest first,
  with a count — the BASIC `LIST` to `WORDS`' full dump of ~330 built-ins. It
  walks the dictionary chain back to a session boundary (`LATEST` captured on the
  last line of `core.fs`), so it needs no assembly and lists no built-ins. See
  docs/Dictionary.md and `man Tools`.

### Docs
- `man Defining-Words` now notes, at the `value` entry, that a `value` set with a
  direct `to` persists across `save`/`reload` while a `variable`'s `!` contents do
  not — a cross-reference to `man Persistence` at the point you choose between them.

### Graphics: software 2D over DRM/KMS (Phase 5, step 1)
- Put pixels on a modern display straight from Forth — via `/dev/dri/cardN`
  `ioctl`s, with **no libdrm, no X/Wayland, no GPU library**. This is the first
  step of the graphics direction recorded in docs/Planning.md (direct,
  library-free display + software 2D, with a backend-agnostic surface API a
  Vulkan GPU backend can later sit behind).
- New on-demand `src/forth/graphics.fs`: a *surface* (base/width/height/stride)
  plus `set-surface`, `pixel`, `fill-rect`, `clear`, and named colors. 32bpp;
  drawing words are oblivious to where the pixels live (heap buffer or video
  memory), so they're testable by read-back.
- New on-demand `src/forth/drm.fs`: `drm-open` (enumerate → connected connector
  and mode → dumb framebuffer → map → point the surface at it), `drm-show`
  (become DRM master and `SETCRTC` to scan out), `drm-close`, and a `drm-demo`.
- New primitives: `(ioctl) ( fd request argp -- ret )` and
  `(mmap-dev) ( fd offset size -- addr )` — the direct device-control gateway
  (DRM now; GPIO/I2C/evdev later), backed by `platform_ioctl`/`platform_mmap_dev`.
  Also `w@`/`w!`/`l@`/`l!` (16/32-bit memory access) for pixels and ioctl structs.
- Verified on real hardware (2560×1600): drawing + read-back works as an ordinary
  DRM client (even under a compositor); from a text VT, `drm-show` returns 0 and
  the demo renders to the panel. The DRM integration test is gated — it runs on a
  real DRM host and skips under QEMU and where there is no card node.
- Docs: docs/Graphics.md (surface model, DRM words, manual VT/board visual test),
  docs/Planning.md (graphics direction), tools/drmoff.c (struct-offset reference).

## v0.7.0 — 2026-06-27

### Shell-like words: `pwd` / `cd` / `ls` / `cat` / `more` / `pushd` / `popd` / `dirs`
- Navigate and inspect the filesystem from the REPL. `cd` changes the real
  working directory — relative, absolute, bare `cd` (returns to the startup
  directory), and `~` / `~/sub` (expands to `$HOME`); `pwd` prints it; `ls [dir]`
  lists a directory; `cat` dumps a file and `more` pages it; `pushd` / `popd` /
  `dirs` are a directory stack.
- `session.fs` is now pinned to the **startup directory**, so `save` / `reload`
  always use the launch directory no matter where you `cd`.
- New platform call `chdir`; primitives `chdir`, `(cwd)`, `(startup-dir)`,
  `(home-dir)`. All path-taking words share one `~`-expanding parser. Error paths
  abort, so a failed command shows its message and no `ok`. See
  docs/Shell_Words.md.

### Interactive line editor with command history
- The REPL prompt is now an in-line editor at a terminal: move with the
  left/right arrows, jump to the start/end with Ctrl-A/Ctrl-E, and insert or
  delete (Backspace) anywhere in the line — not just at the end.
- The up/down arrows recall previous lines from a command history (the most
  recent 64 lines; consecutive duplicates are not stored). A recalled line can
  be edited before submitting, and Down past the newest entry restores the line
  you were typing. History is in-memory for the session.
- The editor engages only when stdin is a terminal; piped/redirected input still
  uses the plain `ACCEPT` reader, so scripts and the test suite are unchanged.
  The new `BASICFORTH_EDITOR` environment variable overrides the check (`1` on,
  `0` off). `ACCEPT` itself is unchanged.
- Implemented in Forth in `core.fs` (shared by both architectures) behind a new
  REPL input hook in `main.s`; arrow keys are decoded by the platform layer and
  the history ring is heap-allocated. See docs/Line_Editor.md.

### `version` word and `-v` / `--version` flag
- `basicforth -v` (or `--version`) prints the version/banner string to stdout
  and exits 0, before any startup work. Unlike the interactive startup banner,
  it is **not** gated on a tty, so `basicforth --version | cat` still prints.
- New Forth word `version ( -- )` prints the same banner string at the REPL,
  backed by a new `(version-str) ( -- c-addr u )` primitive so the text always
  matches the build. The startup banner (shown only when entering the
  interactive REPL on a terminal) is unchanged.

### `DEFER` / `IS` (vectored words) and `REDO` (recompile a definition)
- `defer <name>` creates a word whose action is an execution token stored in a
  cell; `is <name>` (state-aware, like `TO`) sets it. This gives late binding: a
  high-level word can call deferred parts that are filled in or swapped later
  without recompiling its callers. An unset deferred word aborts with
  *uninitialized deferred word*. See docs/Deferred_Words.md.
- `redo <name>` recompiles a REPL-defined word from its captured source, so
  callers compiled against an earlier version of a leaf it uses pick up the change
  — subroutine threading bakes call targets, so redefining a leaf alone doesn't
  update existing callers. See docs/Redo.md.

### Persist direct `to` / `is` assignments across `save` / `reload`
- The session log previously captured only lines that defined a new word, so a
  bare `to` on a value or `is` on a deferred word — which mutate an existing
  word's cell rather than defining a word — were lost on `save` / `reload` (a
  reloaded deferred word came back uninitialized). Those assignment lines are now
  captured and replayed, via a new one-shot `(assign?)` primitive.

### Fixed: `MOVE` overlap direction and `CMOVE>` zero-count
- `MOVE` now copies in the correct direction for overlapping regions, and
  `CMOVE>` no longer corrupts the stack on a zero count.

## v0.6.0 — 2026-06-27

### `see` shows the source of any word via dictionary source-metadata
- `see <word>` now shows the source of **any** word currently in force — from
  `core.fs`, any `include`d file, `session.fs`, or your interactive session —
  read straight from the word's source file. Assembly primitives are labelled
  *`<name>` is a primitive (assembly)*; an unknown word reports *not found*.
- Every compiled word's dictionary header gains a small 8-byte source-metadata
  block `(source-id, offset, length)`, stamped at **compile time** by the file
  loader (`forth_included` → `build_header`). It sits past `CodePtr`, so `FIND`
  and xt derivation are unchanged. A source-id table (in `.bss`, out of the
  dictionary) maps ids to **absolute** file paths — absolutized at load time via
  a new `getcwd` so `see` re-opens files even if the working directory changes.
- This covers what the interim text-parsing seeded indexer could not — in
  particular words created by **custom defining words** loaded from a file
  (`: my-const create , does> @ ;` then `5 my-const x`). Interactive (unsaved)
  words are still shown from the session capture log. New internal words
  `(find-meta)`, `(source-path)`; new platform call `getcwd`. The dictionary
  arena is also enlarged 64 KB → 256 KB. See docs/See.md and docs/See_Metadata.md.

### Fixed: `examples/snake.fs` could spawn food on the snake
- The fuller Snake example placed food at a random cell with no body check. Its
  collision test is screen-based, so food landing on the just-vacated tail could
  be eaten without the overlap being noticed. `update-food` now places food on an
  empty cell, so food never spawns on the snake or border. (The tutorial's
  `examples/snake-mini.fs` handles the same case in its collision check.)
- The placement search is bounded — a capped number of random tries, then a
  scan for an empty cell, and if no reachable cell is free the game ends (you
  won) — so it can never spin forever on a crowded/small board. Both the random
  and scan paths cover exactly the reachable cells — even columns `2..WIDTH-2`
  (the snake moves in x by ±2 from an even start; `WIDTH-1` is the border) and
  rows `1..HEIGHT-2` — so food is never stranded on an unreachable column nor
  withheld from the last reachable one.

### Added: "Snake" tutorial — build a game step by step
- `docs/Tutorial/Snake.md`, the first interactive tutorial: walked with
  `tutorial Snake`, it builds a playable terminal Snake game one word at a time,
  touching nearly the whole language (stack, defining words, variables,
  constants, arrays/`create`+`allot`, `if`/`case`, `do`/`begin` loops, the
  keyboard, `at-xy` drawing, `ms` timing, `rnd`). Each step ends at the REPL so
  the reader types and tests the piece they just learned.
- The finished program ships as `examples/snake-mini.fs` (the tutorial's answer
  key; a fuller version remains in `examples/snake.fs`). An integration test
  loads it headlessly and verifies the eat-and-grow logic.
- Replaces the thin `Getting-Started` pilot — the starting tutorial now builds
  toward a real project. Tutorial files drop the numeric name prefix (it's
  `tutorial Snake`, not `01-…`); each tutorial is a self-contained subject.

### Added: interactive tutorial (`tutorial` / `next` / `back`)
- `tutorial <name>` walks one of the `BASICFORTH_DOCS` Markdown files **one step
  at a time**, returning to the REPL after each step so you can type the examples
  before advancing with `next` (or reviewing with `back`). Steps are split on the
  file's `## ` headings — no special format, and the same file still reads under
  `man`. The name resolves case-insensitively across the docs sections, exactly
  like `man`.
- `back` clamps at step 1; stepping past the last step prints `-- end of '<name>'
  --` and stays on the last step. Typing `next`/`back` before starting, or naming
  a non-existent tutorial, reports the problem instead of failing silently.
- Built on the existing docs-browser machinery (`(each-dir)`, the `(getdents)`
  scan, `(build-path)`, `read-line`, and the pager line-printer), so an over-long
  step auto-pages. New internal words `(tut-go)`, `(print-step)`, `(tut-in)`,
  `(tut-head?)`. See `docs/Tutorial_System.md`.

### `see` now covers definitions loaded from `session.fs`
*(Superseded by the source-metadata `see` above. The interim text-parsing
indexer — `(index-seeded)` and its ~20 helper words — has now been removed; `see`
relies entirely on the per-word file metadata for `session.fs`/file-loaded words.
The interactive capture path below is unchanged.)*
- `see` previously only showed words you defined *interactively* this session;
  words loaded from `session.fs` (at startup or by `reload`) reported *defined,
  but no source captured*. New `(index-seeded)` closes the gap: after the file
  loads (first REPL tick at startup, end of `reload`) it parses the seeded log
  into definition groups and indexes each, so `see` covers anything that can be
  written to or loaded from `session.fs`.
- The parser is comment/string aware (`\`, `( )`, `." "`/`s" "` are skipped, so a
  `;` inside them doesn't end a definition) and handles `:` definitions plus the
  single-line defining words `variable`/`constant`/`value`/`create`/`marker`/
  `2variable`/`2constant` (matched case-insensitively, so an uppercase `VARIABLE`
  in a hand-edited file still indexes). Each name is resolved to its live `xt` via `FIND`, so
  seeded records key the same way as captured ones. Best-effort: a mis-delimited
  group only makes `see` show slightly wrong text — it never touches the
  dictionary, `save`, or `reload`. See docs/See.md; long-term direction (source
  metadata in the dictionary header) recorded in WildIdeas.

### Changed: `topics` lists each section's topics alphabetically
- `topics` previously printed topic names in filesystem order (effectively
  random). It now collects each section's `.md` names into a heap buffer (the
  getdents buffer is reused across reads, so name pointers into it aren't
  stable), sorts them, and prints them in alphabetical order — so the listing,
  and especially numbered tutorial lessons (`01-…`, `02-…`), read in sequence.
  New internal words `(tn-collect)`, `(tn-sort)`, `(tn-cmp)`.

### Fixed: `see` missed words not defined last on their input line
- The capture index recorded one record per input line, keyed to the final
  `LATEST`, so a line that defined several words (`: a ;  : b ;`) indexed only
  the last one — `see a` reported *not found* even though `a` was a valid
  interactively-defined word. `(capture-line)` now walks the dictionary link
  chain from the new `LATEST` back to the group's baseline and indexes every
  word defined in the group (each sharing that line's captured source). New
  internal word `(dir-add-group)`.
- `see` of a word that is defined but has no captured source (a primitive, a
  `core.fs` word, or one loaded from `session.fs`) now reports *defined, but no
  source captured* rather than the misleading *not found*.

### Added: help-system sections (grouped `topics`, labelled `apropos`)
- Each directory in `BASICFORTH_DOCS` is now treated as a named **section** (its
  last path component). `topics` groups its listing under one header per section
  instead of printing a flat list, and `apropos` tags each hit with its section
  (e.g. `Stack (Language-Reference)`). `man` still searches across all sections.
- A section header is printed lazily, so a directory with no `.md` files adds no
  header. New internal word `(basename)` extracts the section name.
- First user-facing docs landed under this scheme: `Language-Reference/Stack.md`
  and `Tutorial/01-Getting-Started.md`.

### `see` — show a word's source
- `see <name>` prints the source of a word's definition — exactly what you typed
  (spacing, comments, multiple lines), since it reads the session capture log
  rather than decompiling. Covers words defined interactively this session and
  works for any defining word (`:`, `variable`, `constant`, `value`, `create`,
  `marker`).
- `see` resolves the name with `FIND` and matches the **live execution token**,
  so it only ever shows the definition currently in force: a redefinition shadows
  the older source, and a word forgotten by `-session` or a marker (which can
  restore an older same-named word) is reported *not found* rather than showing
  stale source.
- Built on a small directory index over the capture log (3-cell records:
  log-offset, log-length, xt), reset alongside the log in `(seed-log)`. No new
  assembly primitive — the header is read through the existing `(latest@)` view.
  Words loaded from `session.fs` (startup/reload) are not indexed yet (they live
  in the editable file on disk). See `docs/See.md`.

### Added: warn when `core.fs` is not found
- The `basicforth` binary holds only the assembly primitives; everything else
  lives in `core.fs`, loaded at startup from CWD or `BASICFORTH_PATH`. Previously,
  if `core.fs` was reachable nowhere the load was *silently* skipped, leaving a
  baffling REPL with no `cr`/`.`/`if`/`marker`/etc. and no explanation. BasicForth
  now prints a one-line warning to **stderr** in that case, naming the cause and
  the fix (`set BASICFORTH_PATH`). `forth_included` returns 0 for a not-found file
  (silent skip), so detection uses a new `incl_opened` flag it sets only when it
  actually opens a file — an empty or comment-only `core.fs` opens and so does not
  warn. Both architectures; the warning goes to stderr so it never pollutes
  output.

### Added: interactive help system (`man` / `topics` / `apropos`)
- A docs browser reads the `docs/*.md` files in the colon-separated directories
  named by the `BASICFORTH_DOCS` environment variable (same convention as
  `BASICFORTH_PATH`). `topics` lists the available topics; `man <topic>` finds
  `<topic>.md` (case-insensitive) and pages it a screenful at a time
  (space = next page, q = quit); `apropos <keyword>` lists the topics whose file
  contains the keyword (case-insensitive substring).
- New primitives back the feature: `(getdents)` wraps the `getdents64` syscall
  for directory enumeration, and `(docs-path)` exposes `BASICFORTH_DOCS`. The
  getdents and pager line buffers live on the heap (`allocate`), so the feature
  costs little dictionary space.
- See docs/Help_System.md.

### Fixed: `char` / `[char]` could segfault on missing input
- `parse-word` returns `( 0 0 )` when there is no next word; `char`
  (`parse-word drop c@`) and `[char]` both fetched that `c-addr` *without
  checking the length*, dereferencing a NULL (or, at the end of a page-sized
  included file, an unmapped) address. So `: star char * emit ;` then `star` (a
  misuse — `[char]` is the in-definition form), a bare `char`, or an `[char]` at
  the very end of a file all crashed. Fix: the callers now check `u` before
  fetching — `char` returns 0 when there is no word, and `[char]` compiles 0 —
  so the invalid `c-addr` is never dereferenced. `[char] *` and interpret-time
  `char *` are unchanged.

### Fixed: INCLUDE left the interpreter parsing a freed file mapping
- `forth_included` set `source_addr`/`source_len`/`to_in` to the included file's
  lines but never restored the caller's values, then `munmap`ed the file — so
  after the include the outer interpreter parsed from a freed mapping. It only
  worked when `include` was the last token of a line and the file was fully
  consumed; a leftover token, or a compile-time error inside the file (an
  undefined word inside a `:`), dereferenced the freed page and wedged the REPL
  or segfaulted (with the SAVE capture hooks active). `forth_included` now saves
  and restores the source pointers around the line loop on both architectures.
- Bonus: tokens after `include <file>` on the same line now run correctly, and
  `reload` recovers cleanly from a `session.fs` with an error.

### Session reload — edit/compile/run loop
- `-session ( -- )` forgets everything defined since startup (the session
  definitions and anything entered interactively), keeping `core.fs` and the
  session words. `reload ( -- )` does `-session` then re-`include`s the
  (possibly hand-edited) `session.fs`. Built on a restore point recorded just
  past `core.fs` at startup (`(session-mark!)`/`(session-restore)` primitives,
  both arches), so the file needs no marker header.
- `session.fs` now stays *pure definitions*: capture is forward-only (a marker
  run / `-session` moves `LATEST` backward and is not logged), and `reload`
  suppresses its own line. After a clean reload the in-memory log is re-seeded
  from the file, so a later `save` matches the edited file. If `session.fs` has
  an error, `reload` reports it (`reload: …`), leaves the log untouched (so
  `save` can't persist a broken file), and the REPL keeps running.
- Clarified in TODO: `INCLUDED` from inside a colon word is **not** buggy; it is
  `( c-addr u -- )` per ANS (the earlier "underflow" was a stray `included drop`).

### MARKER — dictionary restore points
- `marker ( "name" -- )` defines a word that, when run, restores `HERE` and
  `LATEST` to their values from just before the marker — forgetting the marker
  and every later definition and reclaiming the dictionary space. The modern
  replacement for `FORGET`; the basis of an edit/compile/run loop and (soon) a
  cleanly reloadable `session.fs`. Markers nest.
- Defined in core.fs with `CREATE ... DOES>`, on two small primitives:
  `(latest@) ( -- a )` and `(restore-dict) ( here latest -- )`, on both
  architectures. New docs/Marker.md.

### Fixed: INCLUDE/INCLUDED of an empty or tiny file
- `forth_included` could close a standard file descriptor when loading a 0-, 1-,
  or 2-byte file: x86 `platform_mmap_file` clobbered the callee-saved `%rbx`
  (which `forth_included` used for the fd), so the subsequent close ran
  `close(file_size)` — `close(0/1/2)` = stdin/stdout/stderr. For larger files it
  closed an unopened fd (a harmless leak), which is why it went unnoticed until
  empty-`session.fs` auto-load hit it. `platform_mmap_file` now leaves `%rbx`
  alone, and `forth_included` treats a 0-byte file as a clean no-op (skips
  `mmap`). Empty/whitespace source files now load correctly.

### Session persistence — SAVE (Phase 4)
- `save ( -- )` writes the words you define interactively to `session.fs` in the
  current directory; an interactive session auto-loads `session.fs` at startup
  (after `core.fs`). `save` writes a temporary file and atomically `rename-file`s
  it into place, so a write failure can never destroy an existing `session.fs`.
- New `rename-file ( c-addr1 u1 c-addr2 u2 -- ior )` (ANS FILE-EXT) and a
  `platform_rename` syscall wrapper (`renameat`) on both architectures.
- `write-file` (and thus `write-line`) now loops over `write(2)` until all bytes
  are written; a short write is no longer reported as success, so output — and
  the temp file `save` renames into place — can never be silently truncated. Persistence is source-replay: it records the *source text*
  of definitions, not a binary image. Capture excludes transient actions (only
  lines that advance the dictionary are kept), handles multi-line definitions,
  and discards a definition that errors partway. `save` is idempotent and
  cumulative, and a no-op when nothing was captured (no empty file).
- Active only in an interactive terminal session (stdin is a TTY, no script
  argument); `BASICFORTH_SESSION=1`/`0` forces it on/off. Scripts and pipes
  never auto-load or capture.
- The capture log is heap-backed (grows via `RESIZE`). The REPL drives three
  `core.fs` hook words — `(session-seed)`, `(capture-line)`, `(capture-reset)` —
  registered via a new `(hook!)` primitive; `session.fs` is loaded in asm by
  `main.s` (like `core.fs`). New docs/Persistence.md.

### Dynamic memory — ANS MEMORY wordset (Phase 4)
- `allocate ( u -- a-addr ior )`, `free ( a-addr -- ior )`, and
  `resize ( a-addr1 u -- a-addr2 ior )` provide a heap separate from the
  dictionary, obtained from the kernel on demand. Backed by anonymous `mmap`
  (one mapping per allocation), data-only (no execute permission). `allocate 0`
  is rejected with a non-zero `ior`; `resize` preserves contents up to the
  smaller of old/new and may move the block. Allocations are page-granular.
- New platform call `platform_mmap_anon` (anonymous `PROT_READ|PROT_WRITE`,
  `MAP_PRIVATE|MAP_ANONYMOUS`) on both architectures; `munmap` reused for
  release. `ALLOCATE`/`FREE`/`RESIZE` live in core.fs on top of the
  `(mmap-anon)`/`(munmap)` primitives, with the length-header bookkeeping and a
  portable allocate-copy-free `RESIZE` in Forth — so the internals can later be
  re-backed by a finer-grained allocator behind the same interface.
- New `examples/tac.fs` — the Unix `tac` (reverse the lines of stdin), the
  heap showcase: stdin's size is unknown, so it slurps into an `ALLOCATE`d
  buffer that doubles with `RESIZE` as it fills, then emits the lines in reverse
  and `FREE`s it. No fixed input limit, unlike the fixed-buffer `sort.fs`.

### `read-line` — line-at-a-time file reading (Phase 4)
- `read-line ( c-addr u1 fileid -- u2 flag ior )` returns exactly one line per
  call. It stores at most u1 characters (u2 <= u1) and consumes the line
  terminator without storing it. The terminator is LF; a CR immediately before
  it is removed, so CRLF files read cleanly. `flag` is false only at end of file
  with nothing read (the loop's stop signal); `ior` is 0 (incl. normal EOF) or a
  positive errno. A line longer than u1 fills the buffer and the rest of that
  line is read and discarded, so the next call starts at the following line
  (truncation, a deliberate choice over ANS "continuation"). No state is kept
  between calls, so reading several files or reused fds is always safe. Defined
  in core.fs on top of `read-file` (one byte per read()); a buffered version can
  replace it later behind the same interface.
- New `examples/cat-lines.fs` — the `cat` program rewritten with
  `read-line`/`write-line`, a line-oriented companion to the byte-exact
  `examples/cat.fs` (it normalizes CRLF to LF).

### File-access words (read & write files) (Phase 4)
- `open-file`/`create-file ( c-addr u fam -- fileid ior )`, `close-file
  ( fileid -- ior )`, `read-file ( c-addr u1 fileid -- u2 ior )`, and
  `file-size ( fileid -- ud ior )`. With `write-file` from the previous slice,
  scripts can now read and write data files. fileid is a raw OS fd; `ior` is 0
  on success else the positive errno.
- Access methods `r/o`/`w/o`/`r/w` (= the OS open flags) and `bin` (a no-op on
  Linux), defined in core.fs.
- Platform layer: new `platform_read_file`; `platform_open_file` split into
  `platform_open_file_mode` (flags + mode) with a read-only wrapper, plus
  `platform_create_file`; `platform_fstat` now returns a negative errno on
  failure so `file-size` can report it. `INCLUDED` is unchanged.
- New `examples/cat.fs` — a Forth `cat` (args → open → read loop → write to
  stdout → close; errors on stderr, non-zero exit on failure).
- New `examples/sort.fs` — sort a file's lines into `<name>_sorted.<ext>`
  (slurp with `read-file`, sort with `compare`, emit with `write-line`).

### Fixed: raw mode no longer corrupts the terminal for piped scripts
- BasicForth entered raw mode (echo off) on *every* startup, even for a
  non-interactive script. With `tool.fs | less`, `less` would start while the
  terminal was raw, save that as its "restore-to" state, and on quit put the
  terminal back into raw mode — leaving the shell with no echo.
- Raw mode is now entered **lazily, on the first interactive input**
  (`KEY`/`KEY?`/`ACCEPT`), and only when **stdin is a terminal**. A program
  that never reads input never touches the terminal; and keying off stdin
  (not stdout) means an interactive session still gets raw mode when its
  stdout is piped or redirected. `platform_restore_term` is a matching no-op
  when raw mode was never entered.

### Script arguments and exit status (Unix `#!` Tier 3)
- Command-line arguments are now exposed to Forth, mirroring gforth:
  - `argc` — variable holding the current argument count
  - `argv` — variable holding a pointer to the argument vector
  - `arg ( u -- c-addr u )` — the uth argument as a string (`0 0` if out of range)
  - `next-arg ( -- c-addr u )` — return the next argument and consume it
  - `shift-args ( -- )` — drop the first argument, decrementing `argc`
  - At startup the auto-loaded script is shifted out, so a script's first
    argument is `arg[1]` / the first `next-arg`.
- `bye-code ( n -- )` — exit with status `n`, silently (no "Goodbye!"), so a
  utility's stdout is not corrupted. Plain `bye` is unchanged.
- The startup banner is now printed only when entering the interactive REPL
  (a script ending in `bye`/`bye-code` exits first) and only when stdout is a
  terminal, so a script used as a Unix utility produces clean stdout whether
  its output goes to a terminal, a pipe, or a file. New platform calls:
  `platform_exit`, `platform_isatty`.
- New `examples/echo.fs` — a Forth `echo` utility (executable `#!` script).
- Fixed three integration tests that had been matching substrings in the
  startup banner (`0` from `v0.5.0`, `64` from `x86-64`) rather than real
  command output; they now assert actual output.

### Scripts exit non-zero on error
- A startup script that errors — an undefined word, a failed parse, a stack
  underflow, `ABORT`/`QUIT` — now prints its diagnostic and exits with a
  non-zero status instead of dropping into the interactive REPL, so a Forth
  utility fails like any other Unix program. Errors while loading `core.fs`
  still drop to the REPL (a broken bootstrap is a development problem).
- Internally: a `script_running` flag scopes this to the user script, and
  `rp0` is now initialized before the startup load so a fault during it
  recovers onto a valid return stack (previously `rp0` was only set on REPL
  entry — a latent bug for faults during startup).

### File-output words (stdout / stderr / fileid) (Phase 4)
- `stdin`/`stdout`/`stderr` push the standard fileids (0/1/2); a fileid is a
  raw OS file descriptor.
- `write-file ( c-addr u fileid -- ior )` and `write-line ( c-addr u fileid --
  ior )` write to any fileid, returning an `ior` (0 on success, else the
  positive `errno`). `write-line` appends a newline. This lets a utility write
  diagnostics to `stderr` without corrupting its stdout.
- `TYPE`/`EMIT` are unchanged (still stdout). Internally `platform_write` was
  split into `platform_write_fd ( fd buf len )` with a stdout wrapper; a single
  `write(2)` is issued (a partial write on a pipe counts as success).
- New `examples/lines.fs` — a utility that writes data to stdout and its count
  to stderr, demonstrating the stdout/stderr split.

### BASICFORTH_PATH multi-directory search
- `BASICFORTH_PATH` now accepts a colon-separated list of directories
  (like `PATH`). On a CWD miss, each directory is searched in order and
  the first match is loaded. Empty segments (leading/trailing/doubled
  `:`) are skipped. Applies to `INCLUDE`, `INCLUDED`, the command-line
  file argument, and the startup `core.fs` load.
- Single-directory and unset behavior are unchanged.

### Nested INCLUDED error reporting fix
- A file that `INCLUDE`d another file could report the wrong filename and
  line number for its own later errors: the nested call clobbered the
  `file_name_addr`/`file_name_len`/`file_line_num` globals and the shared
  path-resolution buffer. `forth_included` now saves and restores those
  globals around each line, and the resolved-path buffer is scratch-only.
- On a `BASICFORTH_PATH` hit, error messages now show the filename as
  typed rather than the resolved path (the trade for correct, nesting-safe
  reporting).

### Unix `#!` script support (Tier 1)
- `forth_included` skips a leading `#!` shebang line, so a Forth file can be
  made executable (`chmod +x foo.fs`) and run directly via
  `#!/usr/bin/env basicforth`. The check matches an exact `#!`, so a leading
  `#` decimal literal is unaffected, and the shebang counts as line 1 so
  error line numbers stay accurate. Scripts currently end with `bye` to exit
  (run-and-exit flag and `ARGC`/`ARGV` are planned follow-ups).
- New `examples/hello.fs` — an executable `#!` script demonstrating the
  feature.

### Bug fixes
- `.(` no longer leaks the parsed text onto the data stack (it pushed one
  cell per character). Redefined as the standard `[char] ) parse type`.

### Testing
- 119 unit tests + 309 integration tests (multi-directory, nested-INCLUDE
  error-context, `#!` script, script-argument/`bye-code`, and bundled-example
  cases)

---

## v0.5.0 — 2026-04-12

Snake game port from BareMetalForth, plus platform and Forth additions
to support interactive games, convenient file loading, and flexible
library search.

### Platform Layer
- `platform_key`: ANSI escape sequence parsing — arrow keys (ESC[A/B/C/D)
  return abstract key codes 129-132, standalone ESC returns 27
- `platform_ms_get`: monotonic millisecond timestamp via clock_gettime
- `platform_cursor_off`, `platform_cursor_on`: ANSI cursor visibility

### New Forth Words (asm)
- `MS@` ( -- u ) — monotonic millisecond timestamp
- `CURSOR-OFF` ( -- ) — hide terminal cursor
- `CURSOR-ON` ( -- ) — show terminal cursor
- `INCLUDE` ( "name" -- ) — parse filename and load it (convenience wrapper for INCLUDED)

### New Forth Words (core.fs)
- Key constants: `KEY_ESCAPE` (27), `KEY_UP` (129), `KEY_DOWN` (130),
  `KEY_RIGHT` (131), `KEY_LEFT` (132)
- `random` ( -- n ) — LCG random number generator, seeded from MS@
- `rnd` ( n -- 0..n-1 ) — random number in range

### Command-Line File Loading
- `./basicforth filename.fs` loads a Forth file at startup before the REPL
- Saves argc/argv[1] at `_start`, loads after core.fs

### BASICFORTH_PATH Environment Variable
- Fallback search directory for `INCLUDE`, `INCLUDED`, and startup core.fs
- `BASICFORTH_PATH=src/forth ./basicforth` finds core.fs from any CWD
- CWD is always tried first (existing behavior unchanged)

### Snake Game
- `examples/snake.fs` — terminal-based snake game
- Adaptive frame timing, score overlay, game-over screen
- Works on both x86-64 and ARM64 (tested on Pumpkin board)

### Testing
- 119 unit tests + 295 integration tests

---

## v0.4.0 — 2026-04-12

Core extensions complete, plus words from four additional standard word
sets: Programming-Tools, String, Facility, and Double-Number. Platform
layer extended with terminal query and timing functions, enabling games
and interactive applications.

### Core Extension Words (completing section 6.2)
- `?DO` — skip-if-equal counted loop
- `VALUE`, `TO` — named mutable values with interpret/compile dual behavior
- `:NONAME` — anonymous colon definitions (pushes xt)
- `PARSE` — parse with arbitrary delimiter character
- `PARSE-NAME` — standard alias for PARSE-WORD
- `SOURCE-ID` — input source identifier (0=keyboard, -1=EVALUATE)

### Programming-Tools Words (section 15)
- `WORDS` — list all dictionary words
- `DUMP` — hex+ASCII memory dump
- `?` — fetch and print shorthand

### String Words (section 17)
- `/STRING` — adjust string address and length
- `COMPARE` — lexicographic string comparison
- `CMOVE`, `CMOVE>` — forward and backward byte copy
- `-TRAILING` — remove trailing spaces
- `BLANK` — fill with spaces

### Facility Words (section 10)
- `KEY?` — non-blocking input check
- `MS` — millisecond delay
- `PAGE` — clear screen (ANSI)
- `AT-XY` — cursor positioning (ANSI)
- `SCREEN-WIDTH`, `SCREEN-HEIGHT` — terminal size query

### Double-Number Words (section 8)
- `D+`, `D-` — double-cell addition and subtraction
- `D.` — print signed double-cell number
- `D0=`, `D0<` — double-cell zero tests
- `D=`, `D<` — double-cell comparison

### Platform Layer
- 6 new platform functions: `platform_key_ready`, `platform_ms`,
  `platform_page`, `platform_at_xy`, `platform_screen_width`,
  `platform_screen_height`
- Linux: FIONREAD ioctl, nanosleep, TIOCGWINSZ ioctl, ANSI escapes
- Clean abstraction for future Windows/bare-metal ports

### Testing
- 119 unit tests (C harness)
- 280 integration tests (shell-based, piped I/O)

---

## v0.3.0 — 2026-04-11

Full ANS Forth core word set (section 6.1). All 133 required core words
are now implemented, plus many useful core extension words. BasicForth
is a standards-compliant Forth environment.

### Defining Words
- `CREATE`, `CONSTANT`, `VARIABLE`, `DOES>`, `>BODY`
- `HERE`, `ALLOT`, `,`, `C,`

### Counted Loops
- `DO`, `LOOP`, `+LOOP`, `I`, `J`, `UNLOOP`, `LEAVE`

### Multi-Way Branching
- `CASE`, `OF`, `ENDOF`, `ENDCASE`

### Double-Cell Arithmetic
- `S>D`, `UM*`, `M*`, `UM/MOD`, `SM/REM`, `FM/MOD`
- `DNEGATE`, `DABS` (helpers in core.fs)

### Pictured Numeric Output
- `<#`, `#`, `#S`, `#>`, `HOLD`, `HOLDS`, `SIGN`
- `BASE`, `PAD`, `HLD`, `DECIMAL`, `HEX`
- `.` redefined using pictured output (respects BASE)
- `U.`, `.R`, `U.R`, `*/MOD`, `*/`

### Compiler Words
- `STATE`, `[`, `]`, `LITERAL`, `POSTPONE`, `COMPILE,`
- `[']`, `[CHAR]`, `EXIT`

### System Words
- `>IN`, `SOURCE`, `>NUMBER`, `WORD`, `ENVIRONMENT?`
- `ABORT`, `ABORT"`, `QUIT`

### String Words
- `TYPE`, `S"`, `."`, `COUNT`, `CHAR`, `PICK`
- Unterminated string error detection

### Simple Core Words
- Arithmetic: `LSHIFT`, `RSHIFT`, `2*`, `2/`, `+!`
- Memory: `2!`, `2@`, `FILL`, `MOVE`, `ALIGN`, `ALIGNED`, `CHAR+`, `CHARS`
- Comparison: `U<`
- Stack: `-ROT`

### Core Extension Words
- `0>`, `U>`, `WITHIN`, `ERASE`, `UNUSED`
- `.(` (immediate print)

### Bug Fixes
- ARM64 `+LOOP` off-by-one branch offset (TBNZ +2 → +3)
- `LEAVE` outside DO now detected at compile time
- Stale compiler state (do_depth, leave_count) reset on error
- Unknown-word compile abort restores DSP
- `compile_s_quote` bounds check and unterminated string detection
- `.R` signed-number handling with double-cell DABS
- `.` handles INT64_MIN correctly via DNEGATE
- Missing `.global forth_one_plus` on ARM64

### Architecture
- Per-test timing in integration tests with slow-test threshold
- ARM64 software 128/64-bit division for UM/MOD
- DOES> patching: x86 RET+NOPs → JMP rel32, ARM64 RET → B
- POSTPONE handles both IMMEDIATE and non-IMMEDIATE words

### Documentation
- docs/Defining_Words.md — dictionary layout, CREATE, DOES>
- docs/String_Words.md — inline string compilation
- docs/Pictured_Numeric_Output.md — number formatting, double-cell math
- Updated Core_Primitives.md, Conditionals.md, Forth_Core_Words.md

### Testing
- 119 unit tests (C harness)
- 236 integration tests (shell-based, piped I/O)

---

## v0.2.0 — 2026-04-09

Control flow, file loading, and the core.fs bootstrap. BasicForth can now
load Forth source files and compile definitions with conditionals, loops,
and recursion.

### Features
- Control flow: `IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`, `AGAIN`, `WHILE`, `REPEAT`
- Recursion: `RECURSE` (compile call to current definition)
- Comments: `(` paren comments, `\` line comments
- `EVALUATE` — interpret a string as Forth source
- `INCLUDED` — load and interpret a Forth source file (via mmap)
- Startup auto-load of `core.fs` (silent skip if not found)
- core.fs words: `CR`, `SPACE`, `BL`, `TRUE`, `FALSE`, `MOD`, `/`, `CELL+`, `CELLS`, `<>`, `0<>`
- Control-flow safety: tag checking detects mismatched pairs (e.g., `BEGIN...THEN`)
- Unresolved control flow detected by `;` with clean rollback
- File error reporting with filename and line number

### Architecture
- Inline native branches (not BRANCH/0BRANCH primitives) — true STC
- x86-64: `JZ`/`JMP` rel32 with forward-reference patching
- ARM64: `CBZ`/`B` with bitfield offset encoding and I-cache flush
- Nest-safe longjmp recovery for errors inside EVALUATE/INCLUDED
- FIND returns flag=2 for IMMEDIATE+COMPILE_ONLY words
- Platform file I/O: `open`, `fstat`, `mmap`, `munmap`, `close` syscalls

### Testing
- 119 unit tests (C harness)
- 113 integration tests (shell-based, piped I/O)

---

## v0.1.0 — 2026-04-08

Initial tagged release. Interactive REPL with compiler on ARM64 and x86-64.

### Features
- Interactive REPL with line editing (backspace, Ctrl+C)
- Colon definitions (`: square dup * ;`)
- Integer literals: decimal, `$hex`, `%binary`, `#decimal`, negative
- Arithmetic: `+ - * /MOD ABS MIN MAX NEGATE 1+ 1-`
- Comparisons: `= < > 0= 0<`
- Logic: `AND OR XOR INVERT`
- Stack: `DUP DROP SWAP OVER ROT NIP TUCK 2DUP 2DROP DEPTH ?DUP`
- Return stack: `>R R> R@` (compile-only)
- Memory: `@ ! C@ C!`
- I/O: `EMIT KEY . .S`
- Dictionary: `FIND WORDS IMMEDIATE '`
- Guard pages catch stack overflow/underflow with clean recovery
- ARM64 I-cache flush for compiled code
- Startup banner with version from git tags
- EOF handling for piped input
- BYE word prints "Goodbye!" and exits

### Testing
- 113 unit tests (C harness)
- 75 integration tests (shell-based, piped I/O)

### Build System
- Native architecture auto-detection (`make` builds for host)
- Cross-compile ARM64 from x86 with QEMU support
- Targets: `make`, `make run`, `make test`, `make run-test`, `make run-integration`
