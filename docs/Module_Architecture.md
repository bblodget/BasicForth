# Module Architecture — Log-Canonical vs File-Canonical

**Status: DRAFT for discussion (2026-07-10). Nothing here is implemented.**

This is the design doc for the editing-workflow arc's Step 4 (module
ownership), expanded to cover a more fundamental question that came out of
building bare `edit`: **what is the source of truth for a module — the
session's capture log, or the file on disk?** The answer decides how
`edit <word>`, `:e`, `save`, and `compact` should work, so Steps 2 and 3 of
the arc are on hold until it's settled.

## Where we are: the log-canonical model

Today the capture log is the source of truth and the file trails it:

- The log is seeded from the current file at `load`, and every definition,
  direct `is`/`to`, and `edit` **appends** to it.
- `save` writes the log out verbatim — so redefinitions pile up in the file.
- `edit <word>` recompiles the word from a temp file, then **propagates**:
  every transitive caller is recompiled in memory and *re-appended to the
  log*. An edit is therefore the heaviest polluter of the save file — one
  edit appends the word plus all of its recompiled callers.
- `compact` exists to clean up the accumulation, at the cost of dropping
  between-definition comments.

What it does well: **hot editing**. Propagation is surgical — only the
edited word and its callers are recompiled, so live state survives: a
`variable score` mid-game, heap buffers, values set with `to`. Edit a
rendering word between rounds and keep playing.

What it costs:

- The file accumulates redefinitions and needs periodic `compact`.
- Three views of the module can **disagree**: a plain `: helper 200 ;`
  retyped at the prompt leaves callers on the old code (live), `save`+
  `reload` replays the log in order so callers *still* bind the old code,
  but `compact` emits the latest source at the word's original position so
  callers would bind the *new* code. Same module, three behaviors.
- Propagation needs real machinery to stay correct: the `uses` graph walk,
  dependency ordering, `:noname` group re-runs, the superseded-group guard.
  It works, but every future feature has to keep it working.

## The proposal: the file-canonical model

**The file is the module; a session is a running instance of it.** Like a
source file in any IDE: you edit the text, the running state is rebuilt
from it.

The key observation (from bare `edit`): in a Forth file every word is
defined before its callers, so a `reload` rebuilds all callers of a changed
word **by construction** — no graph walk, no ordering logic, no guards.
Propagation machinery becomes unnecessary for the edit path.

Concretely:

- **`save` becomes structure-preserving and in-place.** For each word
  redefined this session, replace its definition span in the file text
  (spans are already in the per-word header metadata); genuinely new
  definitions append at the end. Comments and layout survive. The file
  never accumulates duplicates — this is Step 3's "structure-preserving
  compact" machinery, promoted from a cleanup tool to *how saving works*.
- **`compact` retires.** Nothing accumulates, so there is nothing to
  compact.
- **`edit <word>`** keeps its focused temp-file UX (the editor shows just
  the word, not the whole file) but changes what happens on save-and-quit:
  splice the new text into the file at the word's span, then `reload`.
  No propagation pass. The splice invalidates later words' offsets, but the
  reload immediately re-stamps all metadata — the staleness never escapes.
- **Bare `edit`** already works this way (edit the file, reload). Unchanged.
- **`:e <word>`** (Step 2) becomes: retype the definition inline at the
  prompt, then splice + reload. Same semantics as `edit <word>`, different
  input method. The arm-flag propagation design is dropped.
- **Plain `: helper 200 ;` at the prompt** still compiles in memory with
  stale callers (standard Forth semantics) — but the moment you `save`, the
  file is clean and the next `reload` converges. The three views collapse
  to one. `:e` is the taught way to redefine *and converge immediately*.

## What we give up: hot editing

`reload` forgets the module and rebuilds it, so **runtime state resets**:
variables reload uninitialized, values return to their file-time contents,
heap buffers referenced by module words are orphaned. Under the current
model, `edit render` between game rounds keeps the score; under the
file-canonical model it restarts the game.

How much does this matter?

- **Only *revision* goes cold.** A reload happens when a definition is
  *edited* (`edit <word>`, `:e`, bare `edit`) — not when the session
  *grows*. `define` and `:` compile new words into the running session with
  no reload, so live state survives all additive work. (Confirm by use
  testing.)
- The **defer path still works hot**: `' ambush is brain` or a
  `:noname … ; is brain` typed at the prompt swaps behavior in a *running*
  module without any reload — that's what `defer` is for, and Chase is
  built on it. Hot behavior-swapping remains fully supported; what goes
  away is hot *redefinition of a normal word* with state kept.
- Most edit loops want a clean rebuild anyway (deterministic, no stale
  anything).
- Reload cost is negligible at our scale (core.fs itself compiles in
  milliseconds).

Options:

1. **Reload-only (recommended).** Retire propagation entirely — a large net
   deletion of subtle machinery (`(propagate)`, `(prop-anon)`, the dirty-set
   walk, the anon guards). `defer` covers the live case, and it covers it
   *by design* rather than by machinery.
2. **Keep propagation as an explicit hot verb** (e.g. `edit!` or `hot-edit`)
   alongside reload-based `edit`. Two semantics to explain and maintain;
   only worth it if live-state editing proves indispensable in practice.

Recommendation: option 1, and revisit only if real use misses it. The
machinery stays in git history.

## Hard cases

- **Dirty session at edit time.** `edit <word>`/`:e` end in a reload, which
  discards unsaved captures — so like bare `edit`, they must run the
  dirty-guard *first* ("save first? (y/n)"). Under this model saving is
  clean (no accumulation), so a future refinement could be to auto-save
  before every edit and drop the prompt. Start with the prompt; loosen
  later if it feels naggy.
- **Words with no file (scratch sessions).** A session started bare has no
  current file, and a REPL-defined word isn't on disk. Proposal:
  `edit <word>`/`:e` in a scratch session say "no current file — save
  <name> first". (Today's temp-file edit + propagation would be retired
  with everything else; scratch sessions keep `see`, redefinition,
  `define`, and can adopt a file at any time with `save <name>`.)
- **A broken edit.** Splice + reload with a syntax error leaves a partial
  module and drops to the REPL (existing reload behavior). The loop is
  `edit` → fix → save — same as any compiler error. Acceptable; a future
  nicety could trial-evaluate before splicing. **Future hardening (only if
  use testing shows the fix loop isn't enough):** snapshot the file before
  the splice and, on a failed reload, offer "revert? (y/n)" — a module kept
  in git already has this for free.
- **`is`/`to` assignment lines.** In-place save replaces *definitions*;
  direct assignments are order-dependent lines with no single span to
  replace. Proposal: keep the file's existing assignment lines verbatim,
  and on save append only the *final* binding per defer/value when it
  differs from what the file would produce (this is what `compact` learned
  to do). Needs working out in implementation.
- **Positioning the editor.** We know the word's byte offset; converting it
  to a line number lets `edit <word>` open vi/nano *at the word*
  (`+<line>`). Pure nicety, cheap with the span metadata in hand.

## Refinement candidate: do we need `save` at all?

If the file is canonical, it could simply stay **in sync as you type**:
append each new definition (and direct `is`/`to`) to the file as it lands,
splice on redefinition, no explicit `save`. Then `dirty` never exists —
every "save first? (y/n)" prompt in `edit`/`load`/`new`/`bye` disappears —
and a crash never loses work.

- **Mechanism:** plain `write`/rewrite through the existing file words is
  enough — at human typing speed there is nothing to optimize. A
  memory-mapped file was considered and rejected: a *growing* file under
  mmap needs ftruncate-and-remap gymnastics for no practical gain here.
- **The trade-off to watch in use testing:** today an unsaved session is a
  scratchpad — you can experiment freely and walk away. Under auto-sync
  every experiment lands in the file the moment it compiles. Splicing keeps
  *redefinitions* clean, but an abandoned word needs an explicit delete
  verb (today you just don't save it). Scratch sessions (no current file)
  keep the old freedom either way.
- **Staging:** keep explicit `save` through the first implementation
  stages; adopt auto-sync as a later stage once splice-on-save has proven
  itself and use testing says the scratchpad loss is acceptable.

### Checkpointing (what explicit `save` was really for)

Auto-sync removes the "this is a known-good state" moment. **Decision
(2026-07-10): option 1 — git through `sh` is the convention.** Convenience
words (option 2) can come later if use testing wants them. The candidates,
for the record:

1. **Just use git — it's already inside the session.** The Forth-as-shell
   vision means `sh git init`, `sh git commit -am "brains working"`,
   `sh git log --oneline`, `sh git diff` all work from the prompt today,
   with zero new machinery. This is the recommended answer.
2. **Thin convenience words over git** (later, if use testing finds the raw
   `sh` commands clunky): `snapshot <message>` wrapping
   `git add <file> && git commit -m …` (auto-`init` on first use), and
   `revert` wrapping `git checkout -- <file>` + `reload`. One word, a
   message, real git underneath — diff/log/branches stay a `sh` away.
3. **Numbered snapshot files** (`chase.1.fs`, `chase.2.fs`, … + a revert
   word) — a poor man's git with no dependencies. Rejected for normal use
   (clutter that `ls`/`load` must live around; no diffs; messages need a
   sidecar file), but noted as the fallback design for a git-less
   environment — which is Phase 7 (BasicForth as PID 1 on a minimal image),
   not hypothetical. Build it then, if that day comes.

## Module ownership (the original Step 4)

The model extends naturally to `include`d files. Every header already
carries a `SrcId` — ownership is tracked; we just don't use it yet.

- **module = file; `SrcId` = ownership; current module = save target.**
- `.module` lists only the current module's words (REPL-typed words —
  SrcId 0 — belong to the current module by definition).
- `edit <word>`/`:e` on a word owned by another file: refuse with a hint —
  "orbit belongs to planets.fs — `module planets.fs` to edit it".
- **`module <file>`** switches the current module (edit/save target)
  *without forgetting anything* — unlike `load`, which swaps the world.
- Editing a dependency's word splices into *its* file. And note: `reload`
  of the top module re-runs its `include` lines, so dependency edits
  propagate transitively through a single reload — again correct by
  construction.
- Open question: when the current module switches, what does the capture
  log hold? Under file-canonical the log's role shrinks (it exists to back
  `see`/`save` for REPL-typed words); per-module logs may fall out
  naturally or may not be needed at all. To be settled during
  implementation of `module`.

## What stays, what goes

| Piece                          | Fate                                        |
|--------------------------------|---------------------------------------------|
| `uses`                         | stays — query tool, unchanged               |
| `see`, capture log             | stay — log backs REPL-typed sources         |
| `defer`/`is` hot swapping      | stays — THE live-editing mechanism          |
| bare `edit`                    | stays as shipped                            |
| `define`                       | stays as shipped                            |
| `edit <word>` propagation      | replaced by splice + reload                 |
| `(propagate)` + anon machinery | deleted (option 1)                          |
| `save` (append-only)           | becomes in-place / structure-preserving     |
| `compact`                      | retired                                     |
| `:e`                           | built on splice + reload                    |

## Staged implementation plan (once agreed)

1. **Splice machinery**: replace a word's span in the file text, preserving
   everything else (absorbs Step 3). `save` adopts it. `compact` deprecated.
2. **`edit <word>` v2**: temp-file UX + splice + reload; delete the
   propagation pass and its helpers. Integration tests rewritten around
   reload semantics.
3. **`:e <word>`** (Step 2, redefined): inline redefine + splice + reload.
4. **`module <file>`** + ownership rules (`.module` filter, foreign-word
   refusal with hint, dependency splicing).
5. **(gated on use testing)** auto-sync — the file stays in sync as you
   type, explicit `save` and the dirty-guard retire; rollback-on-broken-
   reload if the fix loop proves insufficient.

Each stage lands independently; 1 is pure additive machinery and can ship
behind `save` without touching `edit` at all.
