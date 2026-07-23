# Module Architecture — Log-Canonical vs File-Canonical

**Status: AGREED 2026-07-10; revised 2026-07-11 with the hyper-static
principle (which decides *what* gets spliced). The staged plan at the bottom
is the roadmap; docs/TODO.md tracks progress. IMPLEMENTED through stage 4
(2026-07-11): `compact` and the propagation machinery are deleted — the
present-tense descriptions of the log-canonical model below are the
historical rationale, not the current system.**

This is the design doc for the editing-workflow arc's Step 4 (module
ownership), expanded to cover a more fundamental question that came out of
building bare `edit`: **what is the source of truth for a module — the
session's capture log, or the file on disk?** The answer decides how
`edit <word>`, `:e`, `save`, and `compact` should work, so Steps 2 and 3 of
the arc are on hold until it's settled.

## The hyper-static principle: `:` binds, `edit`/`:e` mutate

Forth's dictionary is a **hyper-static global environment**
(https://wiki.c2.com/?HyperStaticGlobalEnvironment): `:` never changes an
existing binding — it creates a *new* one, and every already-compiled word
keeps the binding it captured at definition time. Subroutine threading makes
this physical: the call target is baked in. In

```
: thrust 10 ;
: climb thrust 2 * ;
: thrust 25 ;
```

`climb` meaning 20 is not staleness — it is the semantics. The new `thrust`
shadows only for words defined afterward. Used deliberately, this is a poor
man's lexical scoping: helper names can be rebound freely without touching
the words that captured them.

That gives BasicForth two distinct verb classes, and persistence must honor
both:

| Verb | Live semantics | Persistence |
|------|----------------|-------------|
| `:` (redefinition) | **bind**: a new binding; earlier words keep the old one | **append** to the file — replay-faithful |
| `edit <word>` / `:e` | **mutate**: fix the binding itself; all callers follow | **splice in place** + converge |

`:` is `define`; `edit`/`:e` are the explicit `set!`. A mistake gets *fixed*
with the mutation verbs; an intentional layer gets *bound* with `:`. Two
consequences fall out:

- **Append is the faithful persistence for bindings.** The file must replay
  to the live session's state, and in a hyper-static environment the
  *sequence* of bindings is the state. Deduplicating `:`-redefinitions
  last-wins is not merely lossy, it is **wrong**: in
  `: a 1 ;  : b a ;  : a 2 ;` dropping the first `a` breaks `b` (it
  captured that binding — the deduped file doesn't even load). This bug was
  found in the first splice-save implementation and is structurally
  impossible under append.
- **Splice is the faithful persistence for mutations.** An `edit` means
  "that text was wrong"; the file's definition is replaced where it stands,
  and the session converges by reload. Mutation history has no semantic
  value, so nothing accumulates.

`compact` is deprecated with a stronger reason than redundancy: deduping a
hyper-static file *rewires bindings* — it is semantically unsound.

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

- The file accumulates *mutation history*: every `edit` appends the edited
  word plus all of its recompiled callers, so fixing one word ten times
  leaves ten copies (plus callers) in the file, needing periodic `compact`.
- `compact` itself disagrees with the live session: it dedups last-wins and
  emits the latest source at the word's original position, so callers that
  captured an earlier binding come back bound to the *new* code — the
  hyper-static semantics are silently rewired (see the principle above).
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

- **`save` is replay-faithful.** The seeded file text is kept byte-for-byte
  (comments, layout, every binding in order) and session captures append in
  the order they happened — with one exception: a group that came from a
  *mutation verb* (`edit`, later `:e`) splices over the word's definition in
  the file text instead of appending. Bindings accumulate only when you
  intentionally layer them; mutation history never accumulates at all.
- **`compact` retires.** Deliberate bindings are semantics (dedup would
  rewire them), and mutations never pile up — there is nothing left to
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
- **Plain `: helper 200 ;` at the prompt** compiles a new binding; earlier
  words keep the old one, live and across save/reload alike — the
  hyper-static semantics, preserved faithfully in both worlds. When what
  you actually want is "fix it everywhere," that's a mutation: use `edit`
  (or `:e` once it lands).

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

- **Dirty session at edit time.** *Resolved by use testing (2026-07-11):
  the prompt felt naggy, exactly as anticipated — mutations now
  **auto-save** (and reload, so metadata is fresh) with no prompt. An edit
  implies the file is current; checkpoints are git's job (`sh git commit`).
  The discard verbs (`new`/`load`/`bye`) keep their save-first prompt: they
  throw work away by intent, so a last-chance question is right there.*
- **Words with no file (scratch sessions).** A session started bare has no
  current file, and a REPL-defined word isn't on disk. Proposal:
  `edit <word>`/`:e` in a scratch session say "no current file — save
  <name> first". (Today's temp-file edit + propagation would be retired
  with everything else; scratch sessions keep `see`, redefinition,
  `define`, and can adopt a file at any time with `save <name>`.)
- **Forward references from a mutation.** An edited definition that newly
  calls a word defined *later* in the file (e.g. a helper the auto-save just
  appended — the standard "refactor with a new helper" move) forward-
  references when spliced in place, and the reload fails. *Current policy
  (2026-07-11, Brandon's call): warn and proceed* — the splice stays in
  place, a warning names each later-defined word the new text uses (token
  scan; comment mentions can false-positive, warning-only), and the reload's
  line error points at the fix: bare `edit`, move the helper up. Moving the
  *edited word* to the end was tried and rejected — it just relocates the
  forward reference when the word has callers.
  **The designed auto-fix, recorded for when the warning proves a pain:**
  move the *dependencies* up, not the edited word. A freshly-typed helper
  has no meaningful file position yet, and moving a definition *earlier*
  can never break its own callers — so: pull each later-defined dependency
  to just before the edited word (original relative order), splice the
  edited word in place; valid whenever each moved dependency's own deps sit
  earlier, which for new helpers is nearly always. Fall back to move-to-end
  when the edited word has no callers; refuse (live-but-unsaved fallback)
  in the residual contorted case. Needs the splice writer generalized to a
  sorted patch list — the splice-save emitter shape.
- **A broken edit.** Splice + reload with a syntax error leaves a partial
  module and drops to the REPL (existing reload behavior). The loop is
  `edit` → fix → save — same as any compiler error. Acceptable; a future
  nicety could trial-evaluate before splicing. **Future hardening (only if
  use testing shows the fix loop isn't enough):** snapshot the file before
  the splice and, on a failed reload, offer "revert? (y/n)" — a module kept
  in git already has this for free.
- **`is`/`to` assignment lines.** Resolved by the hyper-static principle:
  assignments are order-dependent effects, so `save` keeps the file's lines
  verbatim and appends the session's in the order they happened —
  replay-faithful, no dedup, nothing to work out.
- **Positioning the editor.** We know the word's byte offset; converting it
  to a line number lets `edit <word>` open vi/nano *at the word*
  (`+<line>`). Pure nicety, cheap with the span metadata in hand.
- **Unique temp file.** The old `edit <word>` used the fixed
  `/tmp/basicforth-edit.fs`, so two parallel BasicForth sessions editing at
  the same moment clobbered each other. **Resolved (stage 2) with a
  module-adjacent path instead of the planned pid suffix**: the temp file is
  `<module>.edit.fs`, removed after the cycle — no new syscall, self-describing,
  and collisions then require two sessions editing the *same module*, which
  is already a conflict the temp file is the least of. (A scratch-session
  `define` still uses the /tmp path; scratch sessions have no module to sit
  next to.)

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
| `:` redefinition               | stays hyper-static: binds, appends on save  |
| bare `edit`                    | stays as shipped                            |
| `define`                       | stays as shipped                            |
| `edit <word>` propagation      | replaced by splice + reload                 |
| `(propagate)` + anon machinery | deleted (option 1)                          |
| `save` (append-only)           | append-only, period (mutations splice the file directly, never reach save) |
| `compact`                      | retired (dedup rewires bindings)            |
| `:e`                           | built on splice + reload                    |

## Staged implementation plan (once agreed)

1. **Splice machinery**: `save` keeps the file text and the session's
   bindings/assignments verbatim in order (replay-faithful), and splices
   *mutation-verb* groups — `edit`-originated redefinitions (the edited
   word and its propagation re-logs, tagged at capture time) — over the
   word's definition in the file text. With append-era duplicate bindings
   in the file, a mutation splices the **last** (in-force) one; earlier
   bindings are untouchable semantics. Absorbs Step 3; `compact`
   deprecated.
2. **`edit <word>` v2**: temp-file UX + splice + reload — with a **unique
   temp path** (pid suffix) so parallel sessions can't clobber each other.
   Integration tests rewritten around reload semantics.
3. **`:e <word>`** (Step 2, redefined): inline redefine + splice + reload.
4. **Cleanup pass** — sweep out the log-canonical cruft once 2–3 prove
   stable:
   - core.fs: the propagation body (`(propagate)`, `(prop-*)`, the dirty-set
     walk, `(prop-anon)` and the superseded-group guard) and anything only
     it referenced (`(anon-owner)` etc. stay only if `uses` still needs
     them); the old fixed `(edit-tmp)` path; `compact` and its helpers.
   - Docs: rewrite Line_Editor.md's propagation section for reload
     semantics; retire `compact` from Tools.md/the Manual/Persistence.md.
   - Tests: drop or rewrite the propagation suites.
   - TODO.md: close the absorbed open threads (fixed temp path,
     structure-preserving compact).

   **Done 2026-07-11 — and the sweep went further than planned.** Since
   mutations splice the file directly and reload (re-seeding the log), no
   capture group is ever tagged as a mutation, so stage 1's save-time patch
   machinery was itself dead code: `save` reduced to writing the log
   verbatim (seeded file text + appended bindings, in order), and the
   mutation tags, the patch collector/sorter/emitter, the `(save-impl)`
   indirection, and the seed-extent records all went with the propagation
   body and `compact`. `(eval+log)` survives as `define`'s back end;
   `(anon-owner)` and `(word-in?)` survive for `uses`.
5. **`module <file>`** + ownership rules (`.module` filter, foreign-word
   refusal with hint, dependency splicing).
6. **(gated on use testing)** auto-sync — the file stays in sync as you
   type, explicit `save` and the dirty-guard retire; rollback-on-broken-
   reload if the fix loop proves insufficient.

Each stage lands independently; 1 is pure additive machinery and can ship
behind `save` without touching `edit` at all.
