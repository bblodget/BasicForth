# BasicForth — TODO

Detailed progress tracker organized by phase. Check items off as they're
completed. See Planning.md for high-level vision and design decisions.

---

## Up next

The bucket. Add to it during the week as things come up; on release day, take
what's done and leave the rest here.

Releases are cut on Sunday by convention — a week's work, whatever that turned
out to be. **This is a guideline, not a rule:** a good set of items early in the
week is a reason to release early, and a quiet week is a reason to skip. Nothing
here blocks a release; an unfinished item just stays in the bucket. See
`docs/Versioning.md` for how a release is actually cut, and `CHANGELOG.md`'s
`## Unreleased` for what has already landed.

Each item carries a **Done when** line, because release day's only real question
is *in or out* and that needs an observable answer rather than a judgment call.

**Before taking an item, check who already has it:**

```
git branch --format='%(refname:short)  %(worktreepath)'
```

Branches and worktree paths are shared between all worktrees of the repo, so
that command sees work in progress *now*. This file cannot: a claim written
here lives on a branch, and no other worktree sees it until that branch merges
— by which point the work is done. So name a branch after the item you're
taking, and let the branch list be the claim.

**Put your worktree number in the branch name: `<n>-<item>`** —
`2-files-lesson`, `3-make-install`. Worktrees are numbered by their directory
(`BasicForth` is 1, the main checkout and the one holding every worktree's
objects; `BasicForth-2`, `BasicForth-3` after that), so the number is read off
`git worktree list` rather than recorded anywhere that can go stale.

The number is not for ownership — it is so the branch list answers *which
session* at a glance, without matching long paths by eye. Marking the same thing
in this file was tried and dropped: a `[2 working]` beside an item is invisible
to the other worktrees until it merges, needs a second merge to say `done`, and
costs a conflict on the one file all three edit.

### `[ENGINE]` — one at a time

An item tagged **`[ENGINE]`** touches `src/arch/*/*.s` or `src/arch/*/core.fs`
— the hand-mirrored pair. That is the same criterion that already decides
whether a branch needs a full suite run before merge, so it is one rule under
one name, not a new judgment call.

**Take at most one `[ENGINE]` item at a time.** Not because the files
necessarily collide — two emitters can sit far apart — but because two
unreviewed engine changes landing in the same Sunday sweep cannot be told
apart when something breaks, and each costs a five-suite two-arch run. Sequence
them instead; there is always non-engine work to run alongside.

**Name the branch `engine/<n>-<item>`** — `engine/2-evaluate-propagation`. The
tag in this file is documentation and arrives only at merge time; the branch
prefix is the part that enforces anything, because refs are shared the moment
they exist:

```
git branch --list 'engine/*'
```

Anything listed means an engine item is live — take a different one. Docs,
lessons, tests and tooling carry no such limit and run in parallel freely.

### Queued

- [ ] **Finish the Dark Star port.** Nearly done — needs polish. A good stress
      test of the engine, and historically our best bug-finder: the `CASE`
      miscompile and the bare `unresolved control flow` message both came out
      of it. Lives in a private repo outside this tree for now.

- [x] **Word the voice-engine skip so it names its remedy — DONE 2026-08-16**
      (branch `2-suite-skip-wording`). Both fixes taken: the suite now derives
      the engine with `command -v piper` the way `setup.sh` does, and every
      remaining skip names what to do. Verified on both arches: the Pi, where
      the misreading happened, now runs the test at 1180/1180 with no skips
      without sourcing `setup.sh` at all.
      Detail: §Future / Hardening.

- [x] **Audit the integration suite for assertions that cannot fail — DONE
      2026-08-17** (branch `2-test-harness`). Every candidate converted; a
      re-measure finds **zero** remaining. Six assertions were rewritten
      because conversion showed they had been asserting things the system does
      not do. `assert_contains` now names the unsafe helper, `assert_result` is
      the documented default, and `--section` runs one section in about a
      second. The PTY suite has the same flaw and is NOT swept — see below.
      Detail: §Future / Hardening.

- [ ] **`[ENGINE]` ARM64: diagnose `to <local>` at 6.5 ns against x86's 0.54.**
      Done when: the two hypotheses in the entry are separated by re-measuring
      with a `drop` in the loop on the Pi, and the result is either a fix or a
      written explanation. Not a bug until that distinction is made.
      Detail: §Performance / Optimizer.

- [ ] **`[ENGINE]` `SOURCE-ID` conformance.**
      Done when: `source-id` answers a file id inside an `included` file and -1
      inside `evaluate`, with a suite case for each. `(loading?)` already covers
      every internal caller, so this is a conformance gap, not a live bug.
      Detail: §Future / Hardening.

- [x] **`[ENGINE]` Include-relative resolution, and a word for the loading
      file's directory — DONE 2026-08-20** (branch `engine/1-include-here`,
      merged `dd0e801`). `require`/`include` look beside the requiring file
      first; `my-dir` and `path-join` shipped with it, and Dark Star now loads
      and runs installed, from any directory, with all 14 speech WAVs. The
      acceptance case below was met with a decoy present.
      Original entry follows.
      `include` searches CWD then `BASICFORTH_PATH` and
      nothing else, so a multi-file package cannot find its own siblings once
      it is installed somewhere other than the directory you are standing in —
      and an asset (`r/o bin open-file` in wavcore.fs) is not searched for at
      all. Dark Star only works today because you `cd` into it first. This is a
      **prerequisite for `install`**, discovered while rewriting the package
      design; it is not needed by the user package dirs, which stand alone.
      Order matters: the including file's directory goes **first**, ahead of
      CWD, or a stray `art.fs` in the working directory hijacks the package's
      own. The two orders agree wherever things work today, so this costs no
      compatibility — and `core.fs` already records a `font.fs` in the launch
      directory shadowing the library of that name and recursing to the guard
      page.
      Done when: a package in `~/.basicforth/packages/<n>/`, whose entry file is
      linked into `lib/`, loads its own sibling `.fs` and opens its own asset
      from an unrelated working directory — including one holding a decoy file
      of the same name.
      Detail: `docs/Package_Registry.md` §Multi-file packages.

- [x] **`[ENGINE]` Rename `docs/Tutorial` to `docs/Tutorials` — DONE
      2026-08-21** (branch `engine/1-tutorials-rename`). Clean break, no dual
      spelling. All eight suite runs green on both arches.

      **The name now lives in one place.** The plan counted four `s" Tutorial"`
      basename sites; factoring them turned up a fifth literal (the
      `docs/Tutorial` path appended to `BASICFORTH_DOCS`) and a sixth check of
      exactly the same kind — `s" Guides"`, which exempts single-word headings.
      `core.fs` now has one `(lessons-sub)`, with `(lessons?)` deriving the
      basename from it rather than agreeing by hand, plus `(guides?)`.
      `(lessons-sub)` sits deliberately OUTSIDE the `(-ud-)` marker: defined
      inside it, the startup words are forgotten once they have run and every
      help lookup then failed with `? (lessons-sub)`.

      Five places outside Forth still spell it out — `setup.sh`, the `Makefile`
      install target, and `tmpl_docs` in both `main.s`. Four languages, no
      shared constant; the install test is what checks them against each other.

      **The migration is quieter than expected**, measured rather than assumed:
      a directory still named `Tutorial` drops out of `tutorials` and its pages
      appear in bare `help` as an ordinary section, but `tutorial <Name>` still
      finds a lesson in it — `(tut-go)`'s second pass searches every docs
      directory when the strict pass misses. So a stale directory half-works
      instead of failing outright.
      Original entry follows.
      The section headings are `Language-Reference`, `Guides`, `Packages`
      and `Tutorial` —
      three count nouns plural and one singular. Worse, the *word* that lists
      them is `tutorials`, so the interface already carries both spellings for
      one thing. `Language-Reference` stays singular because it is a mass noun.

      **Do it before any package format names the directory.** A package ships
      `docs/Tutorial/` in its own repo; the moment that is written down,
      renaming becomes a compatibility break for every published package, and
      `Package_Registry.md` §6 flags the package format as a v1.0 lock. Cheap
      now, expensive later. That is the whole argument for the timing.

      Tagged `[ENGINE]` because it is **not** a documentation rename:

          src/forth/core.fs         4x  `s" Tutorial"` basename switches --
                                        BEHAVIOURAL. A directory is recognised as
                                        holding lessons by that exact name; miss
                                        one and lessons silently stop being found
          src/arch/*/main.s         the tmpl_docs template a derived install path
                                        is built from -- hand-mirrored asm
          src/arch/*/Makefile       install file lists
          Makefile, setup.sh        install target, BASICFORTH_DOCS
          tests/*                   suite paths (integration, lessons)
          docs/Tutorial/            the directory itself (git mv)
          ~10 more                  prose

      **Clean break, no dual spelling.** One name, no exceptions. The cost is
      that an existing `~/.basicforth/docs/Tutorial` must be renamed by hand,
      and today that is one machine. Know about the transient first: a shell
      that sourced the OLD `setup.sh` running the NEW binary has
      `BASICFORTH_DOCS` pointing at a directory that no longer exists, so
      lessons vanish until it is re-sourced. Self-correcting, but alarming if it
      happens mid-session and you have forgotten this note.

- [x] **`tutorials` lists the title's first word, not the name you type —
      DONE 2026-08-21**, folded back into `engine/1-tutorials-rename` after the
      rename made it visible in a real listing. The listing prints the filename
      in a 20-wide column, then the title's text after its em dash; a longer
      name pushes its description right rather than being cut. `::` confirmed as
      the package scope separator (a hyphen is a legitimate page-name character,
      `Machine-Code.md`). Suite: three new cases, and the two existing ones that
      caught the output change. Note one of the three — that a listed name
      starts its tutorial — passes against the OLD code too: it pins the other
      half of the contract rather than detecting this bug.
      Original entry follows.
      Measured against the shipped Greeting package, where it is live and not
      theoretical:

          > tutorials
            Greeting — Your First Installed Package
          > tutorial Greeting
          no tutorial named Greeting (try TUTORIALS)

      The name that works is `greeting::tutorial` — the filename. The listing
      prints the page TITLE, `tutorial <name>` matches the FILENAME, and nothing
      keeps the two equal. It stays invisible for bundled lessons only because
      `Snake.md` happens to be titled `# Snake`. A listing's job is to tell you
      what to type, and deriving that from prose is what let them drift.

      Decide the output shape first — name and description in two columns keeps
      the descriptions, which are why anyone reads the list. It changes output
      for every bundled lesson, so it needs the docs sweep that any output
      change needs.

      It also raises a question it does not own: a package's lesson is
      `<pkg>::tutorial.md`, so the honest name to print is `greeting::tutorial`.
      Whether a package should instead name the file for what you type is a
      `Package_Registry.md` convention, not engine work.
      Done when: every name `tutorials` prints is a name `tutorial <name>`
      accepts, for a bundled lesson and an installed package alike, with a suite
      case that would fail if the listing went back to the title.

- [ ] **`help` should say where the live definition came from.** When two pages
      document the same word, `help` gathers both — correctly — but prints them
      in docs-path order, which need not match the dictionary. Measured
      2026-08-19: after a package redefines `depth`, `depth .` answers the
      package's while `help depth` prints core's entry **first**. The reader
      takes the first as the answer and it is the one that no longer runs.
      Reordering the path cannot fix it: the docs path is static and the
      dictionary order is dynamic — it depends on what you required this
      session, and in what order.

      **Do not try to mark which entry is the live one.** That was the first
      design and it cannot work: `(find-meta)` answers with the defining **`.fs`
      file**, help entries come from **`.md` pages**, and nothing links the two.
      No page declares which source file it documents — `Stack.md` opens with
      `# Stack Manipulation` and never mentions `core.fs` — so there is no
      mapping to look the answer up in. Adding one would mean a new header field
      on all thirty-odd existing pages, for a problem this size.

      Report the fact instead of inferring the match. After printing the
      entries, add one line naming where the live definition actually came
      from — the same lookup `where` does:

          help depth
            Stack:          ## depth  ( -- +n )   ...
            bignum-depth:   ## depth ( -- n )     ...
            depth is currently defined in bignum.fs

      That needs no mapping, cannot be wrong, and gives the reader exactly the
      fact they were missing. It handles the cases `see` already distinguishes:
      a primitive says so, a word typed this session says so.
      Small, standalone, not packaging-specific, and it makes shadowing
      *visible* — the property missing when `dice.fs` redefined `seed`.
      Done when: `help <word>` names the source of the definition currently in
      force, a primitive and a REPL-defined word each report sensibly, and a
      suite case covers a word documented on two pages where the live one is
      NOT the first entry printed.

- [ ] **Warn when a loaded file redefines a word that came from a different
      file.** The `redefined` warning is deliberately off during file loads —
      `core.fs` redefines on purpose, module reloads replay whole files, and
      skipping the scan keeps loads cheap. But that also makes a library
      silently shadow a core word, which `dice.fs` did to `seed` for months.
      Narrower rule: warn only when the *previous* definition came from a
      **different source file**, which leaves all three of those cases quiet.
      This is the **probe** for the namespaces question: it measures how often
      collisions actually happen before anyone designs a mechanism for them.
      Right now that judgement rests on one anecdote.
      Watch the cost — the gate currently skips a `find` per definition during
      loads, and this reinstates it.
      Done when: a library redefining a word from another file says so at load
      time, `core.fs` and a module reload stay silent, and the load-time cost is
      measured rather than assumed.

- [ ] **A `Files` lesson.**
      Done when: `tutorial Files` replays green under `make run-lessons` on both
      arches and no step pages.
      Detail: §Module System / Forth-as-Shell, use-testing queue.

- [x] **`[ENGINE]` Propagate errors out of `EVALUATE`.** DONE 2026-08-16,
      both arches, all eight suite runs green. Mechanism: a `THROW` of `-260`,
      joining the silent set, raised by `forth_evaluate` in assembly and by the
      *Forth* `included` wrapper for loads. It is deliberately NOT raised by
      the assembly `forth_included`: a first version added a throwing entry
      point there, and it skipped the wrapper's bookkeeping, stranding every
      failed file on the loading stack so no retry could ever run. Loads
      therefore propagate from the layer that owns the cleanup.
      `interpret_line`'s abort decision was not touched. Design, the three
      rejected alternatives, and the two defects found after the acceptance
      table was green: `docs/Abort_Routes.md`. **Still wants a Pi run** before
      it is believed — qemu models neither weak ordering nor the incoherent
      I-cache.
      Original entry follows.
      The engine's worst
      failure class. **Wider than this entry first said** — brackets and
      definitions have nothing to do with it, and the minimal case is one line
      at a bare prompt (measured 2026-08-16 against `v0.16.0-14-gbad2f78`):

          > s" nosuchword" evaluate                  \ ` ok`. No error at all.
          > s" nosuchword" evaluate 7 .              \ `7  ok` — the line runs on
          > : q s" nosuchword" evaluate 42 . ;  q    \ `42  ok`
          > : z 1 [ s" nosuchword" evaluate ] 2 + . ;  z   \ `3  ok`

      Root of two filed items — the swallowed error and the compiling arm that
      takes the enclosing definition — and both dissolve if the status
      propagates. **Scope is all four forms** (decided 2026-08-16): the third
      line above is the one that constrains the design, because `evaluate`
      compiled into a definition and run later has no surviving status
      register, so the channel cannot be the return value.
      `INCLUDED` is the near miss to copy from and not break — it *does* report
      `file:line: ? token`, and it *does* return 1; the outer line prints ` ok`
      and carries on regardless, because the single site that could consult that
      status (`.Lil_found_execute`) never looks at it. Nothing upstream is
      missing — which is why the fix is not "return the error properly".
      **The abort-route enumeration is committed: `docs/Abort_Routes.md`.**
      It lists every route, which are gated by nesting depth and which are not,
      and the six constraints any fix has to satisfy. This is the most bug-dense
      area in the engine (seven wedges so far, three of them found in error
      paths during the 2026-08-16 STATE sweep), and `recovery-anchor-is-global`
      records an obvious-looking fix here that segfaulted. Best done early in a
      cycle, not late: a mistake here is silent, and a week of other sessions on
      the tree is the detector.
      **Only one engine change per week** — this and user package dirs both
      edit hand-mirrored asm and both need a full suite run; do not run them in
      parallel worktrees.
      Done when: the seven-row acceptance table in `docs/Abort_Routes.md` §The
      pins passes on both arches. **Reporting the error is only half** — an
      error that prints and then lets the line finish is not propagated, which
      is precisely what `INCLUDED` does today. Three rows cover that half and no
      existing test does; one of them (`' bad catch .` returning non-zero) is
      the strongest single check, being the difference between the error being
      *announced* and it having *happened*. Two rows are regression guards, for
      `INCLUDED`'s `file:line:` prefix and for the deliberate rule that a typo
      leaves the data stack alone.
      **Not "the pins are inverted"** — of the four assertions in that cluster,
      one (`a nested error while compiling still takes the outer definition`)
      expects `MISSING` and still expects `MISSING` after the fix, for the
      opposite reason, so it would read as confirmation while proving nothing.
      Detail: §Future / Hardening.

- [x] **`[ENGINE]` User package dirs — DONE 2026-08-19.** `~/.basicforth/lib`
      joins the file search path and `docs/{Packages,Tutorial}` join the help
      path, appended so nothing installed can shadow a bundled library, topic or
      lesson. `$BASICFORTH_PACKAGES` relocates the root and, pointed at a path that
      does not exist, disables the mechanism — which is how the suites stay
      independent of what the developer has installed.
      Three decisions the entry asked for, all settled by measurement rather
      than argument: the policy lives in `core.fs` behind three tiny primitives
      (`(forth-path)`, `(forth-path!)`, `(docs-path!)`) so **neither `main.s`
      changed**; the reference directory is `Packages` and not a mirror of
      `Language-Reference`, because `help` iterates directories and a mirror
      printed the heading twice; and append beat prepend for the reason
      `dice.fs` redefining `seed` records.
      Two defects fixed on the way, both verified failing first: `deps` asked
      the *environment* for `BASICFORTH_PATH` instead of the interpreter, so on
      an installed binary it could not find a file `require` loads; and a docs
      directory that would not open left the previous one collected, so `help`
      reprinted that whole section.
      **The one that was nearly missed:** 2816 bytes of `allot` broke
      `include core.fs`. That test reloads this file into the same dictionary,
      which at the time left about **3200 bytes spare out of 256 KB** — a 1.2%
      margin nobody knew was that thin. Three rounds to get clear of it: heap
      instead of `allot`; a `marker` around the startup machinery so it is
      forgotten once it has run (which also meant erasing the reclaimed span,
      since a fresh session had always found it clean and the suite asserts
      that); and finally **moving the block to the middle of the file**, because
      a marker fixes the FINAL cost and not the PEAK — at the end of a second
      load the peak was 3374 bytes against 3270 available.
      The dictionary is 512 KB since 2026-08-20 (see below), so those figures
      are history, not current numbers. The doubling is not: anything permanent
      in core.fs is still paid for twice by that test.

- [x] **The dictionary headroom for a second `core.fs` load — RESOLVED
      2026-08-20 by raising the dictionary to 512 KB.** `DICT_SPACE_SIZE`,
      one `.equ` per arch. Free space went from 131 KB to 384 KB, and the
      `include core.fs` margin from **54 bytes to 256 KB**.
      Found 2026-08-19 by walking into it, and nearly walked into again the
      next day: sibling-path resolution plus `2constant`/`2variable` took the
      margin from 3219 bytes to 54 in an afternoon of individually small
      additions.
      **The number that alarmed was the wrong one, and that is the lesson.**
      3219 bytes was never a user's budget — a user had 131 KB. It was the
      margin of one integration test that does `include core.fs`, loading a
      SECOND full copy, which is why every byte added to core.fs cost two
      against it. Reporting a test's headroom as though it were the product's
      constraint made a 1.2% cost look like an emergency for two days.
      The doubling has not gone away, only the pressure: anything that defines
      words, uses them and forgets them should still sit EARLY in core.fs,
      because a `marker` bounds the final cost and not the peak.
      One test had to change with it — a dictionary-exhaustion case allotted a
      hardcoded 300000 bytes, sized to overflow 256 KB, and silently stopped
      overflowing. It derives the size from `unused` now.

- [ ] **`where <word>` — which file did this come from?** Reshaped 2026-08-18;
      the original entry asked for `deps <word>` to fall back to a dictionary
      lookup, and that is the wrong place for it. The need is real — *"I have
      `dis`, where did it come from?"* — but it is a source-metadata question,
      not a dependency question, and answering it inside `deps` puts a
      name-resolution rule in the layer that handles filenames.
      Separate them instead:

          > where dis
          disasm.fs
          > deps disasm.fs

      `where` answers with exactly the argument the file words want. It is about
      ten lines of Forth reusing what `see` already does — `(find-meta)` yields
      `( off len srcid )` and `(source-path)` maps the srcid to a filename — and
      it handles the same four cases `see` does: not found, primitive, typed
      this session, from a file.
      Named `where`, not `which`: `which` is the shell's word for executables on
      `$PATH`, and BasicForth has a shell vocabulary already.
      Caveat that survives the reshaping: srcids come from a **64-entry table**
      and `src_register` answers 0 once it is full, so a word from the 65th file
      must say it does not know rather than name the wrong file.
      Done when: `where dis` answers `disasm.fs`, the four `see` cases each
      report sensibly, and the 65th-file case says why it cannot answer.

      Related but NOT settled, and deliberately not queued: whether the file
      words should be strict about extensions. Today `deps sdl3` works and
      `require sdl3` does not, which is an inconsistency — but the fix removes
      working behaviour, so it wants a deliberate decision rather than a drive-by.
      The argument for strictness is one rule with no exceptions (`include`,
      `require`, `required`, `deps` all take a filename; extensions always;
      paths allowed), with package *names* living one layer up in
      `install`/`run`. See `Package_Registry.md` §Naming rules.

- [x] **`make install` — DONE 2026-08-17.** `install` / `uninstall`, `PREFIX`
      and `DESTDIR`, both arches, all eight suite runs green. The binary derives
      `<prefix>/share/basicforth/...` from `/proc/self/exe` when the environment
      does not set it, so an installed copy needs no `setup.sh` and the tree
      stays relocatable; the environment still overrides, which is what keeps
      checkouts and suites unaffected. `help installing` is the user page.
      **Note for the package-dirs item below:** the derivation is the hook it
      wanted — `~/.basicforth/lib` now has somewhere to sit *beside*, and the
      layout is fixed in one place (the templates in `main.s`, checked against
      the Makefile by the install test).

### Bigger than a week

Real features that need a design conversation before they are task-sized —
parked here so they stay visible without pretending to be queue items.

- **Namespaces.** The flat dictionary is the deepest unsolved problem in the
  package design, and the case for fixing it is **composition**, not tidiness: a
  package author can test against core and their declared dependencies, but
  cannot foresee what *else* is installed on a user's machine. N packages each
  individually correct, combined into something nobody tested. `dice.fs`
  redefining `seed` for months is the small version of it.

  **Hyper-static binding is not a substitute**, and it is easy to believe it is.
  Measured 2026-08-19:

      > : a 1 ;   : b a . ;   : a 2 ;
      redefined a
      > b     1        \ b still calls the OLD a
      > a .   2

  It protects code *already compiled* and does nothing for code compiled after,
  so a shadow is invisible going forward — and the `redefined` warning is gated
  off during file loads (`in_load` in `build_header`), so a library's shadow is
  silent by construction.

  **The mechanism is already specified: Forth 2012's Search-Order word set** —
  `WORDLIST`, `GET-ORDER`/`SET-ORDER`, `GET-CURRENT`/`SET-CURRENT`,
  `DEFINITIONS`, `SEARCH-WORDLIST`, with `ONLY`/`ALSO`/`PREVIOUS`/`FORTH` as the
  ergonomic layer. It is a *list* rather than a tree, but a list of
  `[package, root]` gives exactly the upward walk with siblings invisible. What
  is unsettled is the interface, not the machinery. Cost to watch: dictionary
  search is hand-mirrored assembly and the compiler's hottest path — though
  hyper-static binding means it is a compile-time cost, not run-time.

  **Two interfaces considered and parked, both 2026-08-19:**

  - **HP 48/28-style directories** — enter a package by name, path shown in the
    prompt, lookup walks up to the root, siblings invisible. Fits the project's
    lineage, and it is where the idea came from. Parked because BasicForth
    already has a real `cd` for the OS filesystem, and the observation that
    prompted the idea was that `cd`/`ls`/`cat` are *already* disorienting — a
    second navigation concept, with a second current location and one prompt,
    makes that worse rather than better.
  - **Scoped help** (`package <name>` as a scope selector). Much cheaper, but it
    scopes *documentation* without scoping *words*, so the directory is a lie
    the first time someone types a scoped word from the root.

  **What is already measured and waiting.** Four namespaces are shared with no
  mechanism keeping them apart: the dictionary, the help index, the
  `on-start`/`on-stop` lifecycle hooks (found by plain `find`, so a package
  defining either takes over the user's), and lesson filenames. And help
  currently **disagrees with the dictionary** about which definition is live:

      > depth .              0
      > require bignum.fs
      > depth .              99      \ the package won -- the dictionary is last-wins
      > help depth                   \ prints CORE's entry first, then the package's

  The reader takes the first entry as the answer and it is the one that no
  longer runs. Note what that rules out: making help prefer the bundled entry
  does not prevent shadowing, it only makes help contradict execution.

  **Why not now.** There are zero third-party packages, so there is no evidence
  to design against, and `Package_Registry.md` §6 flags the package format as
  one of the things a v1.0 would lock — a wrong answer here is maintained
  forever. Revisit when a second package exists and something actually collides.
  The two cheap partials queued above — naming the source of the live
  definition in `help`, and warning on a cross-file redefinition — would inform
  that decision without committing to any of this.

- **Sockets.**
- **The GPU backend.** The stated ceiling of the project; SDL is the chosen
  path to it.

### Parked

- **The optimizer.** Closed deliberately on 2026-07-25 because the base under it
  was still moving; that reasoning has not changed. §Performance / Optimizer.
- **A `defer`/`is` lesson.** After `Files` — the two would overlap on file
  loading, and shipping them together doubles the review.

---

## Known Bugs

- [x] **Unbalanced `CASE` arms compile silently; mixing `CASE` parts with
  `IF`/`DO`/`BEGIN` segfaults.** FIXED 2026-07-29 (branch staging-debug).
  Found 2026-07-29 during the Dark Star port:
  a stray `ENDOF` in a `DecodeLevel` dispatch loaded without complaint and
  surfaced as a `stack underflow` at run time, several steps from the cause.
  **Pre-existing on `main` (`2b68ee6`) — verified in a scratch worktree, so
  this is not from the staging branches.**

  Two separate faults. First, an unbalanced arm compiles quietly and emits
  **wrong code** — not merely a leak. The branch targets are mis-resolved, so
  an arm runs another arm's body and the case value is never consumed:

      : bad  case 0 of 11 endof 1 of 22 endof endof endcase ;   \ extra ENDOF
       ok
      9 9 0 bad .s     <3> 9 9 11          <- correct by luck
      9 9 1 bad .s     <5> 9 9 11 9 9      <- ran arm ONE, and leaked
      9 9 5 bad .s     <8> 9 9 11 9 9 9 9 5

  An `OF` with no `ENDOF` is equally quiet (`: bad2 case 0 of 11 endof of
  endcase ;`, and `: bad3 case 0 of 11 endcase ;`).

  Second, closing a non-`CASE` construct with a `CASE` word **segfaults the
  process** — not an abort, a core dump, so a file load takes the session
  with it:

      : a6  if 1 endcase ;       Segmentation fault
      : a7  if 1 endof ;         Segmentation fault
      : a8  do 1 endcase ;       Segmentation fault
      : a9  begin 1 endcase ;    Segmentation fault

  The checker already exists and covers everything else, which is what makes
  this look like an oversight rather than a design gap — `: t if ;` and
  `: t begin ;` give `unresolved control flow`, `: t if until ;` gives
  `? mismatched-control-flow`, and even a `CASE` missing its `ENDCASE`
  (`: t case 0 of 11 endof ;`) is caught. It is only the arm-level bookkeeping
  *inside* `CASE` that goes unchecked.

  Likely root cause and fix: `ENDOF`/`ENDCASE` cannot tell an arm's pending
  branch address from the `CASE` marker itself, so they resolve whatever is on
  the control-flow stack and walk off it when the type is wrong. Making the
  `CASE` marker a distinguishable tagged value — the way the `IF`/`BEGIN`
  mismatch check already distinguishes its own — should fix the silent
  mis-resolution and the segfault together. Worth checking whether the
  `mismatched-control-flow` machinery can simply be extended to cover the
  `CASE` words rather than adding a parallel one.

  **The diagnosis held, with one correction: it needs THREE tags, not one.**
  The whole family was untagged — `CASE` pushed a bare `0` sentinel and
  `OF`/`ENDOF` pushed raw addresses — while every other control-flow word
  pushes an `(address, tag)` pair. So:
  - `CF_CASE` (sentinel), `CF_OF` (consumed only by `ENDOF`), `CF_ENDOF`
    (consumed only by `ENDCASE`). One `CASE`-marker tag would NOT have caught
    the extra-`ENDOF` case, because that bug is `ENDOF` failing to tell its own
    pending `OF` branch from a previous arm's exit branch — a distinction only
    two separate arm tags can make.
  - The segfaults were exactly `patch_forward` receiving a TAG as an address
    (`if 1 endcase` → writes to address 1, `do … endcase` → address 3). With
    everything tagged they are checked, never patched.
  - `ENDCASE`'s scan is now bounded by `colon_dsp`, so a missing `CASE` cannot
    walk off the compile-time stack. That upgrades `: bad endcase ;` from
    "the underflow guard happens to catch it" to a proper mismatch error.
  - Reuses the existing `cf_check_tag` / `mismatched-control-flow` machinery as
    hoped; no parallel checker.

  Also found while reviewing, beyond the original report: `: bad case 1 of if 2
  endof then endcase ;` — an `IF` opened inside an arm and closed out of order
  — was a fifth segfault shape, and the likeliest of them to be typed for
  real. The *unpaired* forms (`endcase` alone, `of … endof` with no `CASE`)
  were never silent: they hit the stack-underflow guard and the session
  survived. 12 tests added; well-formed nesting both ways (`CASE` in `IF`,
  `IF` in an arm) is asserted alongside, since the first ARM64 attempt broke
  *correct* code rather than letting broken code through — `STP` pushed the
  pair with the tag below the value. Both arches now use the identical
  two-`STR` push idiom `IF` uses.

- [x] **Crash sweep before v0.15.1 (2026-08-10).** Ran malformed and
  accidental-mistake inputs through both a file load and the prompt, asserting
  on signal rather than output. Three crash, all of them standard-UNDEFINED
  behaviour where the fault comes from the CPU or libc, not from us:
  `0 execute` (an integer as an xt), `0 @` (null dereference), `12345 free`
  (a pointer libc never allocated). None is reachable from well-formed code.
  Recorded so nobody re-investigates them as bugs. **Nothing was found in the
  family of the include crash** — no case where ordinary correct usage faults.
  A bounds-checked `execute` would turn the first into a clean error, but that
  is a feature, not a fix.

- [x] **A control-flow closer with nothing open reports `stack underflow`, not
  `mismatched-control-flow`.** RESOLVED 2026-08-11. `cf_check_tag` now bounds
  its read by `colon_dsp` before comparing, so a closer with nothing open takes
  the mismatch path instead of walking off the compile-time stack. Two things
  the plan below did not anticipate:

  **`WHILE` had to be fixed separately.** It inlined the tag compare rather
  than calling `cf_check_tag` (it only peeks, and the author evidently thought
  the helper consumes — it does not). So `: q while ;` alone still reported a
  stack underflow after the one-place fix. It now calls the helper like its
  siblings. A "one place, both arches" fix is only one place if every caller
  actually goes through it — grep the jumps to the error label, not just the
  calls to the helper.

  **The wording changed too, and it uses the token the interpreter already
  banked.** `forth_interpret_line` stores every word in `err_token` before
  `FIND`, so at `cf_check_tag` the token is literally `then`. The old code
  threw that away and overwrote it with the string `"mismatched-control-flow"`,
  printed under the default `? ` prefix — which is the *undefined-word* marker,
  so `: q then ;` read as if `then` did not exist. Now `err_pfx` points at
  `msg_cf_mismatch` (which was defined in both arches and used nowhere) and the
  token is left alone: `mismatched control flow: then`, and `file:line:` in
  front on a load. `cf_mismatch_name` is gone.

  **Caveat: the token is the last word the OUTER interpreter parsed.** That is
  the closer for ordinary source, but the *enclosing* word when a closer is
  reached at run time via `' then execute` — which reports
  `mismatched control flow: plain`. Executing a compile-only word outside a
  definition is already undefined, and naming the closer exactly would mean a
  name argument at eleven call sites in each arch; judged not worth it. If that
  ever matters, the cheap route is passing the closer's dictionary entry to
  `cf_check_tag` and reading the name out of the header — no new strings.

  **A sibling defect, found by using it (2026-08-11).** With the closer fixed,
  Brandon deleted a `then` from Dark Star and got a bare `unresolved control
  flow` with no location, followed by `dark-star.fs:213: ? say` — the first
  *call* to the word whose definition failed on line 167. `.Lsemi_unbalanced`
  printed with `platform_write` and then `ret`ed, so the line never reported an
  error: no `file:line:` prefix (the loader prints that only on a non-zero
  return) and no stop, leaving the rest of the file to compile against a
  missing word. It now sets `err_pfx`/`err_token` and jumps to `.Lcf_abort`,
  which already performed the identical rollback the label open-coded.
  Two things worth keeping:
  - **The location and the stop are the same bit.** They looked like separable
    changes and are not; `jnz .Lincl_error` both prints the prefix and ends the
    load. Any "report it but keep going" variant means a second copy of the
    reporting code.
  - **Read a name out of a header only if the header is yours AND has one.**
    `F_HIDDEN` alone was not enough: `:NONAME` builds a real hidden header with
    an *empty* name (type `T_NONAME`), so the first version printed a bare
    `unresolved control flow: `. Name bytes start at **+10** — flags at +8,
    Flags2 at +9 — and must be copied out before `.Lcf_abort` reclaims them.

  Original report follows.

  Noticed 2026-07-29 while fixing the `CASE` bug
  above, and deliberately left alone there because it is not a `CASE` problem —
  it is uniform across the family:

      : q1 then ;      stack underflow
      : q2 until ;     stack underflow
      : q3 repeat ;    stack underflow
      : q4 loop ;      stack underflow
      : q5 endof ;     stack underflow

  `cf_check_tag` reads the top of the compile-time stack before checking
  anything, so with nothing pushed it touches the guard page and the fault
  handler reports first. Survivable and honest — the session recovers, no
  wrong code is emitted — but it names the wrong cause, and a beginner who
  types `then` with no `if` gets a message about the data stack.

  Fix: bound `cf_check_tag` by `colon_dsp` the way `ENDCASE` now is, and
  report `mismatched-control-flow` when the definition has no open construct.
  One place, both arches; the reason it wasn't folded into the `CASE` fix is
  that it changes the message for five existing words and their tests. Worth
  checking `: q1 then ;` at the prompt *and* mid-file, since the file path is
  where a wrong diagnosis costs the most.

  **How to raise it (learned 2026-08-10 doing the definition-open guard).**
  The protocol is: store the offending token in `err_token_addr`/`err_token_len`
  and the wording in `err_pfx_addr`/`err_pfx_len`, then jump — the CALLER
  prints, which is what gets the `file:line` prefix on a load for free.
  `msg_cf_mismatch` ("mismatched control flow") already exists in both arches,
  so no new message is needed. (This line originally claimed it was "already
  used by a site immediately above `.Lcf_abort`" — it was not used anywhere;
  what that site used was the separate `cf_mismatch_name` token string. Wrong
  in a way that did not matter, but recorded so the entry is not read as
  evidence for anything.)

  **Jump to `.Lcf_abort`, not `.Lcf_longjmp`.** A definition is open by
  definition here. `.Lcf_abort` restores `colon_dsp`/`saved_latest`/
  `saved_here`, drops the partial header and resets `state`/`do_depth`/
  `leave_count`; the bare `.Lcf_longjmp` is for interpret-mode errors and
  leaves the dictionary alone, which would strand the open definition as a
  hidden LATEST. Note that some sites choose between the two by testing
  `STATE` — that test is wrong wherever `[` can be in play, since `[`
  interprets *inside* an open definition.

  **Test obligation:** the message, and that the session can still define a
  word afterwards. The second is not implied by the first — that is exactly
  how the definition-open guard first went wrong.

- [x] **`:noname` inside a colon definition wedges a file load.** RESOLVED
  2026-08-10, in two halves and neither was `:noname`. The wedge was fixed
  2026-07-26 (below). The remaining "stack underflow" half was a
  MISDIAGNOSIS: `: v :noname 42 ; drop 5 ;` compiles `:noname` as a call (it
  is not immediate), `;` closes `v`, and the underflow is the following `drop`
  on an empty stack — correct behaviour. `: v :noname 42 ;` alone leaves depth
  0 and no error.

  What the entry was really masking: **`include` of any file that leaves items
  on the data stack SEGFAULTED the session** (v0.15.0 and earlier). `included`
  in core.fs held ( c-addr u ) on the data stack across the load, so the file's
  values landed on top of the path and `(inc-mark)` read them as an address and
  a length. `1 2 3` in a file was enough. Fixed by keeping the path on the
  return stack, which also nests for a file that includes another file.
  Original entry follows. Found
  2026-07-25 during the interaction sweep, while checking a Codex review
  claim. `:noname` nested in an open definition is not supported — fair
  enough — but it fails badly rather than cleanly:

      > : v :noname 42 ; drop 5 ;
      stack underflow

  At the **prompt** that is survivable: the abort returns to interpret and
  the session carries on (`cancel;` then reports "nothing to cancel", which
  is itself a small lie — there *was* nothing left open by then). Loading the
  same line **from a file** is not: the definition is left open, STATE stays
  compiling, and every subsequent REPL line is swallowed by the continuation
  prompt, with no abort to recover it — the session is done.

      $ cat n3.fs
      : val :noname drop ; 8 ;
      > val .
       ok
      ... depth .          <- continuation prompt; val was never defined
      ...

  Two things to settle: `:noname` in compile state should be a clean error
  (`:noname: already compiling` or similar) rather than an underflow; and a
  load that ends with a definition still open should close/abandon it and
  report, the way a line error already recovers. The second is the more
  valuable half — it is a general guard, not a `:noname` special case, and it
  would catch any file that ends mid-definition. Related: the `:e` body guard
  refuses `:noname` for exactly this reason (see CHANGELOG, `:e refuses a body
  that opens its own definition`); that guard is a patch over this hole at one
  entry point, not a fix for it.

  **The second half is FIXED 2026-07-26 (branch load-unclosed)** — and it
  turned out the `:noname` route was the exotic way in. The everyday one is a
  **missing `;` at the end of a file**, which loaded "successfully" and left
  the caller compiling: every line typed afterwards was swallowed into the
  unterminated word, `bye` included, so the session could only be escaped with
  Ctrl-D. `forth_included` only ever reported errors raised *per line*, and
  "the file just stopped" is not one.
  - `.Lincl_done` now checks before returning success, in both arches. The
    test is `state ≠ 0` **or** LATEST still hidden — STATE alone would miss a
    file ending `: foo [`, since `[` interprets inside an open definition (see
    the Ctrl-D work). On a hit it reports, abandons the definition with the
    same six-store recovery the line-error path already uses, and returns 1,
    so main.s's existing policy applies unchanged: drop to a now-usable REPL
    when interactive, exit non-zero for a script.
  - The report **names the unfinished word** (`unc.fs: definition not closed:
    bad (missing ;)`) rather than giving a line number, which at EOF points
    one line past the end. In a long file the name is the question you have.
  - **A load can begin inside an open definition** (`: foo [ include lib.fs ]
    42 ;`), and that one belongs to the caller. The first version blamed the
    file for it *and rolled it back*, destroying work in progress — worse than
    the bug being fixed (caught by the Codex stop gate). So `forth_included`
    now saves LATEST and STATE on entry, with the same nesting discipline as
    the source context, and fires only when the file itself left something
    open. Recovery is scoped to match: STATE is restored to the caller's
    value, not zeroed, and the dictionary rolls back only for a definition
    this file opened — a stray `]` has nothing to roll back, and
    `colon_dsp`/`saved_here` would be stale from some earlier `:`.
  - +8 integration tests both arches: the report, interactive recovery,
    non-zero script exit, an interactive `include`, the stray `]`, an unclosed
    *nested* include (inner reports, outer load continues), a load begun inside
    an open definition, and a well-formed file as the false-positive guard.

  - **Not** fixed here, and worth knowing why: a nested file's `:` overwrites
    `saved_latest`/`saved_here`/`colon_dsp`, so an outer file's rollback can
    restore the wrong point and leave its unfinished definition behind,
    hidden. The obvious fix — save and restore them per load, like the source
    context — is **wrong**, and was tried and reverted. Those three are not a
    per-definition snapshot; they are the global fault-recovery anchor, which
    `;` deliberately moves *forward* after every completed definition ("a
    completed definition is a consistent recovery point", forth_semicolon).
    Rewinding it per load would roll a later guard fault back past everything
    the load defined. Including `colon_dsp` is worse still: the rewind spans
    the `core.fs` load itself, so the next `abort` restores a data stack
    pointer of 0 and the process segfaults — 7 integration tests caught it.
    A real fix has to distinguish "anchor" from "current definition's
    rollback point", which today are the same three variables.

- [x] **`include` inside `[ ... ]` mid-definition leaves the outer word
  undefined.** FIXED 2026-08-10. Root cause was general: a definition's code is
  compiled straight into the dictionary at HERE, so ANY new header built while
  one is open lands in the middle of that code, and `;` then clears HIDDEN on
  the newcomer instead of on the word being defined. `build_header` and
  `build_header_anon` now refuse when LATEST is hidden ("definition still
  open"), before touching saved_latest/saved_here — STATE is not the test,
  since `[` interprets inside an open definition. Original entry follows.

- [ ] ~~**`include` inside `[ ... ]` mid-definition leaves the outer word
  undefined**, and can strand a hidden entry. Pre-existing (verified against a
  build without the unclosed-definition work): the require sentinel
  `(inc:<name>)` is defined by the Forth `included` wrapper *after* the load
  returns — so inside `: foo [ include lib.fs ] 42 ;` it lands between `foo`
  and the chain end, LATEST becomes the sentinel, and `;` unhides *that*
  instead of `foo`. `foo` stays hidden and unreachable, and its `:` also
  re-clobbers `saved_latest`, so a later rollback restores the wrong point.
  Reproduce with a *well-formed* library, which shows it has nothing to do
  with unclosed definitions:

      \ out3.fs
      : keeper 7 ;
      : foo [ include fine.fs ] 42 ;
      \ keeper . -> 7    fine . -> 4    foo . -> ? foo

  Fix directions: define the sentinel before the load rather than after (it
  would need un-defining on failure), or record the load some way that does
  not touch the dictionary while a definition is open. Worth settling before
  anything else leans on `saved_latest` surviving a nested load.

  Still open, the first half: `:noname` in compile state should say so rather
  than underflow.

- [x] **A stray `;` at the prompt was accepted in silence.**
  FIXED 2026-07-26 (branch semicolon-guard). Spotted in a user transcript
  during the Dark Star port: `f DrawTimeBar s ;` printed ` ok`. Every other
  compile-only word (`if`, `then`, `begin`, `loop`, `does>`, `recurse`,
  `exit`) reports `compile only` when typed outside a definition — `;` was
  the one exception, because `forth_semicolon`'s state guard fell through to
  a bare `ret` commented "silently ignore". Harmless in effect (verified: no
  `ret` compiled, `here` unmoved, prior definition intact), but it hid a typo.
  The fix is the `F_COMPILE_ONLY` flag its siblings already carry: the outer
  interpreter executes an immediate+compile-only word while compiling and
  rejects it while interpreting, and `postpone` already handles that flag
  combination (`find` returns 2), so no new mechanism was needed. The
  assembly guard stays as the backstop for `' ; execute`, which bypasses the
  interpreter's check. +5 integration tests both arches.
- [x] **The font tests borrow `BASICFORTH_PATH` from the environment.**
  FIXED 2026-07-24 (branch env-setup). Found while running the suite in a
  bare env: the Fonts section drives the binary through `assert_output`,
  whose `run_forth` set no environment, so `font-terminus-8x16.fs`'s
  `require fontcore.fs` resolved only because `setup.sh` had been
  sourced. `run_forth` now sets `BASICFORTH_PATH="$FORTH_LIB"` for every
  test (a test needing a different path still sets its own on the command,
  which wins), which also covers anything added later without the author
  having to think about it.
  - **It was not only the font tests.** Three `dis`/`shellutil` cases that
    bypass `run_forth` to control `TMPDIR` had the same gap, and one of
    them — "dis cleans up its temp file" — was a *false pass* in a bare
    env: `disasm.fs` failed to load, so nothing ran, so no temp file was
    left, so it passed. It now actually exercises `dis`.
  - The PTY suite had it too: three of `list`'s new cases `require
    graphics.fs`. `test_line_editor_pty.py` now derives `REPO_ROOT` from
    its own path and exports `BASICFORTH_PATH` (matching how it already
    handled `BASICFORTH_DOCS`).
  - **A tracked `setup.sh` now sits at the top of the tree** (`. ./setup.sh`)
    and derives `BASICFORTH_HOME` from its own location, so one file is
    correct in every worktree instead of a hand-edited copy per tree that
    can silently point at another checkout. It lives at the root rather than
    in `testing/` so that directory can stay wholly ignored — a file inside
    an ignored *directory* cannot be re-included, so keeping it there would
    have meant `testing/*` plus a negation rule. Documented in the Manual
    beside the env-var table, with the `./` spelled out (POSIX `.` searches
    `$PATH` when the operand has no slash).
    Sourcing is portable: `${BASH_SOURCE[0]}` is a bash-only construct that
    makes dash exit with `Bad substitution`, so it uses the unsubscripted
    `${BASH_SOURCE:-$0}` (element 0 in bash, merely unset in `sh`, and $0 is
    the sourced file in zsh) and then *verifies* the result against
    `src/forth/core.fs`, falling back to the working directory for a strict
    POSIX `sh` — which cannot show a script its own path — and reporting
    that rather than exporting a wrong root. It also picks the `PATH` entry
    by `uname -m` (the Makefile's NATIVE test) instead of hardcoding
    `src/arch/x86`, which on the ARM64 board would have put a nonexistent
    directory on `PATH`. Both caught by the Codex stop gate.
  - Verified with `env -u BASICFORTH_PATH -u BASICFORTH_DOCS -u
    BASICFORTH_HOME`: 810 x86 / 802 arm64 integration and 34/34 PTY on both
    arches, where the bare env previously failed 10 + 1 + 3.

- [x] **A `require`/`include` cycle blows the stack instead of stopping.**
  FIXED 2026-07-24 (branch require-cycle), as designed below: a "currently
  loading" list separate from the loaded sentinel, so a file already in progress
  is skipped and only becomes "loaded" on completion — the retry-after-failure
  behaviour is untouched. Almost entirely core.fs (one primitive, below).
  **The skip prints `require: <name> is already loading — skipped`**, against
  the original "clean no-op" plan: Brandon's live test showed why. The skip
  leaves the library's words undefined, so silence surfaces as an unexplained
  `? sdl-scale` three lines later, with the actual cause (his module shadowed
  the library name) nowhere in sight. One line of noise for a legitimate ring
  is the cheaper trade.
  Basenames are packed as counted strings into one 1024-byte buffer;
  `included` saves the buffer length on the return stack and restores it on the
  way out, so the pop is free and nesting handles itself. Beyond the buffer it
  aborts with `require: loads nested too deep` instead of overflowing.
  - **The unwinding worry turned out not to exist**, which is what let the fix
    stay this small. A first attempt cleared stale entries at an "outermost"
    load, detected by `source-id 0=` — wrong twice over: `source-id` is 0
    *inside* an included file too (files are mmap'd, there is no fileid), so it
    cleared the list at every level and the guard never fired; and the REPL's
    `(capture-reset)` hook, the other candidate, runs only in an interactive
    session, so a piped script would have gone unprotected. Neither is needed:
    the assembly `INCLUDED` recovers from a line error — or an explicit
    `abort"` — at its own recovery point and **returns normally**, so the
    restore always runs. Verified with `catch`, which sees 0 both times. The
    one exit that skips it is our own cannot-open `abort`, which now pops first.
  - **The startup file needed one piece of assembly.** `main.s` loads the
    command-line file (and core.fs) by calling the assembly `INCLUDED`
    *directly* — that path wants the silent skip when the file is absent — so
    the Forth wrapper never runs for it and nothing was on the list when the
    file's first line executed. `basicforth game.fs`, where game.fs requires
    game.fs, therefore stopped recursing one level down but still ran the whole
    body **twice**: every definition, and every error, doubled (Brandon's live
    test showed `? sdl-scale` printed twice). Fix: a new primitive `(cur-src)
    ( -- id )` exposing `cur_source_id` — which `INCLUDED` already saves and
    restores around each nested load — so when a load starts with an empty
    list, `(ldg-seed)` records the file the interpreter is already reading.
    Ten lines of assembly per arch plus a DEFWORD; no platform symbol, so no
    unit-test stub. `(source-path)` turns the id into the name.
  - Integration tests (+8, both arches): self-require, self-include, the skip
    message, a two-file ring, that the mark does not outlive the load (`include`
    still force-reloads after), that a missing file stays reportable on a retry,
    that a startup file requiring itself runs its body once, and the
    too-deep abort. They fail
    against the old core.fs (stack overflow), so they pin the bug, not just the
    behaviour.

  Original report:

  Found 2026-07-23 while a user's own module, saved as `font.fs`, sat in the
  launch directory: `require` searches the current directory first, so
  `require font.fs` matched *their* file, whose own `require font.fs` line then
  matched itself — infinite recursion until the 512-cell data stack hit its
  guard (`stack overflow`, then a rollback that left `unused` unchanged, which
  is the tell). Root cause: load-once records a file as loaded only *after* it
  finishes, so a cycle never trips the (inc-recorded?) check. Fix: a
  "currently loading" set distinct from "loaded" — if asked to load something
  already mid-load, skip it (a clean no-op), then promote to "loaded" on
  completion. Turns the stack overflow into, at worst, a plain `? word` for an
  undefined name. Keep the retry-after-failure behaviour (a *failed* load must
  still be retryable), so track "loading" separately, do not just pre-mark
  "loaded". Own branch — this is `require` robustness, not a font issue.
  Mitigated meanwhile by naming libraries so they are unlikely to be shadowed
  (`font-terminus-8x16.fs`, not `font.fs`), but the guard is the real fix.

- [x] **A module reload leaves live external resources unreachable.** FIXED
  2026-07-22 (branch module-hooks) with the `on-start`/`on-stop` module hooks
  below — a module defines `: on-stop sdl-close ;` and the handles are released
  *before* the rollback, while they are still valid, so the orphan is never
  created. The analysis below stands as the reason the fix took that shape;
  what follows it is the original report.
  Reproduced 2026-07-20 under a PTY with the dummy video driver: open a
  window, `save`, then `:e` any word — `sdl-win`/`sdl-ren`/`sdl-tex` all go
  from non-zero to **0** while the real OS window still exists. Nothing can
  draw to it or close it; `sdl-close` sees zeros and skips the destroys
  (it still calls `SDL_Quit`, so close+reopen does recover).
  - **Mostly by design, and worth stating that way.** `:e`/`edit`/`load` roll
    the dictionary back and replay the module file, so the live state is
    whatever the file rebuilds. Runtime values set at the prompt survive only
    because a **direct** interactive `to`/`is` is captured — `4 to sdl-scale`
    comes back, but `sdl-win` was assigned *inside* `sdl-open`, so it was
    never logged and there is nothing to replay. (The rollback also drops the
    `(inc:sdl3)` sentinel so `require sdl3.fs` re-runs, re-executing
    `0 value sdl-win`; either path loses it.)
  - **The part that is not just state loss:** a reset counter is recoverable,
    an orphaned OS window is not. The same shape applies to `snd-open`'s audio
    stream and any fileid held in a library value. So the goal isn't
    "reload must preserve everything" — it's that reload shouldn't strand a
    resource with no way to reach or release it.
  - Fix candidates: have `sdl3.fs`/`sound.fs` initialise handles only when
    unset, so a re-include doesn't clobber a live one (smallest, but per
    library); give `require` a "loaded, do not re-run" mark that survives
    rollback; or have reload carry forward pre-existing `value`s. Worth
    deciding deliberately, since it defines what "edit while it runs" means.
  - ~~Until then, don't `:e` with a window open~~ — with `on-start`/`on-stop`
    defined you can: the Bitmaps lesson now teaches the hooks and `:e`s a
    shape with the window up, which closes and reopens it by itself.

- [x] **`save` silently drops data laid down after a `create`.** FIXED
  2026-07-22 (branch create-data-capture): `(capture-line)` now logs a line
  that moved **HERE** forward as well as one that moved LATEST. A line that
  filled dictionary space changed the program, so a faithful replay needs it;
  it gets no SEE record, because it defines nothing. Both `u>` tests, so
  rollbacks (marker, `-session`) are still excluded, and lines that move
  neither pointer are still dropped — which is what keeps a module file from
  becoming a transcript.
  - **Measured before choosing the rule:** every ordinary transient leaves
    HERE at 0 — `.s`, `words`, `see`, `.module`, `type`, `.`, `hex`, `within`,
    `pad blank`, `help`, `apropos`, `pwd`, `ls`, `sh`, `dis`, and critically
    `save`/`list`/`reload`/`-session`, so the module verbs cannot write
    themselves into the file. Only `require`/`include` (which also moves
    LATEST, so already captured) and `align` (0–7 bytes, real dictionary
    state) move it. The failure directions are asymmetric: a false positive
    writes one harmless extra line, a false negative silently corrupts a
    saved program.
  - **Rejected:** restricting it to "while a `create` is the newest header".
    More fragile (what counts as create-made? `variable` is create+allot) and
    it would drop a meaningful `allot` after a colon definition. The simple
    rule is easier to explain and to predict.
  - Fallout, all handled: the integration test asserting a bare `100 allot`
    is NOT captured was inverted (it is now, correctly); PTY block 8b, which
    deliberately pinned the broken behaviour, now pins the fix; and the
    Sprites/Bitmaps lessons no longer justify the colon-word art idiom by
    "loose rows would vanish" — they justify it by the real remaining reason,
    that a named word can be retyped with `:e`. Bitmaps now teaches the loose
    form first and moves to the word form when it needs a name.
  - `keep` is still needed, for lines that move *neither* pointer:
    `320 180 sdl-open`, `1000 hi-score !`. The two split cleanly along "did
    you change the dictionary or not".

  Original report:

  The capture log records a line only when LATEST moves *forward* (see the
  comment at `(capture-line)` in core.fs) — deliberate, so transient actions
  and marker runs aren't logged. The side effect: a table built as

        create inv
          __ l, GG l, ...        \ these rows define nothing

  logs as a bare `create inv`. The data is gone from the module, `list` shows
  only `create inv`, and a reload leaves the word pointing at whatever
  dictionary bytes follow it — no error, no warning, wrong pixels. Found
  2026-07-20 when Brandon saved his Sprites-lesson session and `list` showed
  `create inv` / `create inv2` with all the art missing.
  - Note this is only a problem *across lines*: `create days 31 , 28 , ...`
    on ONE line is captured whole (LATEST moved forward on that line), which
    is why the Arrays lesson's table survives.
  - Workaround in use: put the data in a colon word and run it —
    `: inv-art  __ l, GG l, ... ;` then `create inv inv-art`. A multi-line
    `:` is captured as one group, so it round-trips. The Sprites lesson now
    teaches this form and explains why.
  - Interim step 2026-07-22 (branch module-hooks): `keep` gave it an explicit
    opt-out before the real fix landed.

- [x] **PTY suite fails 4 tests under QEMU (arm64): harness timing, not a
  product bug.** `make run-pty` is 19/19 on x86 but 15/19 on arm64, failing
  "help heading bold", "indented example cyan", "attributes reset", and
  "*italic* span rendered". Diagnosed 2026-07-20: **nothing is broken on
  arm64.** Given a longer wait, the arm64 binary under a PTY emits byte-for-byte
  the same output as x86 — `ESC[1m` bold, `ESC[36m` cyan, `ESC[0m` reset,
  hashes stripped. The suite uses **fixed sleeps**, and
  `send(fd, b"help allot\r", 0.7)` allows 0.7 s; under emulation that step
  needs **between 3 and 6 seconds**, because `help <word>` scans every
  Language-Reference page for `## ` entries naming the word — the same
  growing-corpus cost that already forced an integration-suite timeout from
  2 s to 5 s. The italic failure is collateral: it runs on the stream the
  timed-out help step left desynced.
  - Cheap fix: raise that one timeout (and ideally scale the fixed sleeps when
    running under QEMU, as the integration suite does).
  - Better fix: replace fixed sleeps with drain-until-expected-substring plus a
    generous deadline, so the suite is fast on native and correct under
    emulation instead of trading one for the other.

  Done 2026-07-22, the better fix: the harness queues a sentinel line
  (`." PTY-STEP-DONE" cr`) behind `help allot` and reads until its output
  appears — deterministic at any host speed, no sleep to retune as the
  corpus grows. 22/22 on both arches. (By then the step needed ~10 s under
  qemu, not 3–6.) The same session also buffered the docs browser's file
  reads (read-line's one-syscall-per-byte × the whole corpus — ~546k reads
  per `help <word>`, now ~213), which is a big native win (`help allot` sys
  time 134 ms → 2 ms) but did NOT fix qemu: emulation cost is the
  per-character Forth scan itself, not the syscalls.

- [x] **`MOVE` (core.fs) copied the wrong direction on overlap.** `MOVE
  ( addr1 addr2 u )` must be overlap-safe (memmove semantics), but the original
  definition picked the copy direction backwards: `src < dest` (shift right)
  copied low→high and `src > dest` (shift left) copied high→low — both clobbered
  the overlap, producing a byte "smear". Latent because non-overlapping copies
  and `u <= 1` were unaffected, which covered every caller at the time. Found
  2026-06 while building the line editor. Fixed on the `fix-move-cmove` branch
  (swap the two branches; overlap unit test).
- [x] **`CMOVE>` (core.fs) unbalanced the stack when `u = 0`.** The zero-length
  path ran only `2drop`, but the stack still held `( c-addr1 c-addr2 u )` (3
  cells), leaving `c-addr1` behind. (`CMOVE` handled `u = 0` correctly.) Latent
  because no caller passed `u = 0`. Found 2026-06 (same investigation). Fixed on
  the `fix-move-cmove` branch (drop all three cells; `0 CMOVE>` / `0 CMOVE`
  depth tests).
- [x] **`include <directory>` segfaulted.** `open(2)` succeeds on a directory;
  the raw `mmap` syscall then fails returning -errno (-19, ENODEV), but
  `INCLUDED` checked for exactly -1 — so the error code became the file base
  address. Also, an `fstat` error fell into the "empty file → success" path.
  Both checks now route any negative return to the existing cannot-open error
  path. Found 2026-07-06 (a test bug passed a directory to `include`), fixed
  2026-07-10 on the `include-dir-segfault` branch (both architectures;
  integration tests: error message + session survives).
- [x] **`include` of a missing file silently prints ` ok`.** `forth_included`
  deliberately returns success on ENOENT (after the BASICFORTH_PATH search)
  because startup uses the same path for optional files — `main.s` tells the
  cases apart via the `incl_opened` flag. But at the REPL it swallows typos:
  `include exmaples/bounce.fs` says ` ok` and defines nothing (found 2026-07-11
  during the sound review). Fixed 2026-07-19 on the `require` branch, exactly
  as planned: `(inc-opened?)` exposes `incl_opened`; core.fs wrappers over
  `include`/`included` report `cannot open <name>`; the startup loads call the
  assembly entry directly and keep the silent-skip. Integration tests for
  both `include` and `require` of a missing file.

---

## Phase 1: Hello World — COMPLETE

- [x] Minimal static ELF binary (ARM64)
- [x] Write to stdout via SYS_write
- [x] Verified on Genio 510 (native) and QEMU (cross-compile)
- [x] Makefile with as + ld, auto-detects native vs cross

---

## Phase 2: REPL Foundation — COMPLETE

- [x] Terminal raw mode (ioctl TCGETS/TCSETS)
- [x] Platform layer (platform_emit, platform_key, platform_bye, platform_write)
- [x] Data stack (pure memory, DSP points to top item)
- [x] Stack primitives (DUP, DROP, SWAP, OVER)
- [x] Arithmetic (+, -, NEGATE)
- [x] Memory access (@, !, C@, C!)
- [x] KEY, EMIT, ACCEPT (line input with backspace and echo)
- [x] Number parsing (decimal, hex, negative)
- [x] Dictionary structure (DEFWORD macro, linked list, 21 entries)
- [x] FIND (case-insensitive dictionary lookup)
- [x] PARSE-WORD, EXECUTE
- [x] DOT, DOT-S, BYE
- [x] Outer interpreter REPL (PARSE-WORD → FIND → EXECUTE → NUMBER → error)
- [x] Multi-architecture (ARM64 + x86-64) for all of the above
- [x] C unit test harness (both architectures)
- [x] Documentation (Manual, Dictionary, Outer Interpreter, Testing Framework)

---

## Phase 3: Dictionary & Compiler — IN PROGRESS

### 3a. Compiler Foundation — COMPLETE

- [x] STATE variable (0 = interpreting, non-zero = compiling)
- [x] compile_call ( xt -- ) — emit a CALL/BL instruction into dict space
- [x] compile_ret — emit RET (x86) or LDP+RET epilog (ARM64)
- [x] compile_prolog (ARM64) — emit STP to save LR in compiled words
- [x] LIT — push the next inline value onto the stack at runtime
- [x] compile_literal ( n -- ) — compile LIT + value into a definition
- [x] `:` (COLON) — parse name, create dictionary header, switch to compile mode
- [x] `;` (SEMICOLON) — compile RET, link new entry, switch to interpret mode
- [x] Update outer interpreter to check STATE (compile vs interpret)
- [x] IMMEDIATE — mark most recent word as immediate
- [x] `'` (TICK) — parse next word, push its xt
- [x] Unit tests for LIT
- [x] Error recovery: errors during compilation reset STATE, restore LATEST/HERE
- [x] Linker flag `ld -N` for RWX segments (dict_space must be executable)
- [x] CHECK_DICT macro — software bounds check before dictionary writes
- [x] Refactored TOS-in-register to pure memory stack (eliminated phantom item bug)
- [x] Hardware guard pages (mprotect PROT_NONE) for stack underflow/overflow
- [x] SIGSEGV signal handler with ucontext register recovery to REPL
- [x] Per-definition rollback (saved_latest/saved_here in forth_colon)
- [x] DROP dummy load to trigger guard page on empty stack
- [x] Error handling documentation (docs/Error_Handling.md)

### 3b. Control Flow — MOSTLY COMPLETE

- [x] Inline branch compilation (not BRANCH/0BRANCH primitives — true STC)
- [x] compile_0branch, compile_branch, patch_forward (internal helpers)
- [x] IF / ELSE / THEN — conditional compilation
- [x] BEGIN / UNTIL — post-test loop
- [x] BEGIN / AGAIN — infinite loop
- [x] BEGIN / WHILE / REPEAT — pre-test loop
- [x] RECURSE — compile call to current definition
- [x] Control-flow stack tags (CF_ORIG/CF_DEST) for mismatch detection
- [x] Balance check in `;` for unresolved forward references
- [x] Nest-safe longjmp recovery for errors inside EVALUATE/INCLUDED
- [x] FIND flag=2 for IMMEDIATE+COMPILE_ONLY words
- [x] Integration tests for control flow (20 tests)
- [x] Documentation (docs/Conditionals.md)
- [x] DO / LOOP / +LOOP / I / J / UNLOOP — counted loops
- [x] +LOOP boundary-crossing detection (handles non-exact increments)
- [x] LEAVE — exit DO loop early

### 3c. More ASM Primitives — COMPLETE

- [x] `*` (multiply)
- [x] `/MOD` (division with remainder, divide-by-zero and INT64_MIN/-1 safe)
- [x] ABS, MIN, MAX
- [x] 1+, 1-
- [x] Comparisons: `=`, `<`, `>`, `0=`, `0<`
- [x] Logic: AND, OR, XOR, INVERT
- [x] Stack: ROT, NIP, TUCK, 2DUP, 2DROP, DEPTH, ?DUP
- [x] Return stack: `>R`, `R>`, `R@` (F_COMPILE_ONLY)
- [x] Dictionary entries for all new primitives
- [x] Unit tests for all new primitives
- [x] ARM64 I-cache flush (platform_flush_icache, CTR_EL0 cache line detection)

### 3d. Defining Words — MOSTLY COMPLETE

- [x] HERE ( -- addr ) — push dictionary free-space pointer
- [x] ALLOT ( n -- ) — reserve n bytes (bounds-checked both directions)
- [x] `,` (COMMA) — compile a cell into dict space
- [x] `C,` — compile a byte into dict space
- [x] CREATE ( "name" -- ) — compile push-data-address code, aligned data field
- [x] CONSTANT ( x "name" -- ) — compile push-value code
- [x] VARIABLE ( "name" -- ) — defined in core.fs as CREATE 1 CELLS ALLOT
- [x] build_header refactor — shared by :, CREATE, CONSTANT
- [x] DOES> — attach runtime behavior to CREATE'd words

### 3e. core.fs Bootstrap — MOSTLY COMPLETE

- [x] Comments: `(` and `\` (asm, IMMEDIATE)
- [x] EVALUATE ( c-addr u -- ) — interpret a string as Forth
- [x] File I/O: platform_open_file, platform_fstat, platform_mmap_file, platform_munmap, platform_close_file
- [x] INCLUDED ( c-addr u -- ) — load Forth file via mmap, line-by-line
- [x] Startup auto-load of core.fs (silent skip if not found)
- [x] core.fs initial words: CR, SPACE, BL, TRUE, FALSE, MOD, /, CELL+, CELLS, <>, 0<>
- [x] Line-by-line error reporting: filename:line: ? token
- [x] Derived stack words: 2OVER, 2SWAP, PICK
- [x] Derived arithmetic: */
- [x] String words: TYPE, COUNT, S", ."
- [x] SPACES
- [x] Double-cell arithmetic: S>D, UM*, M*, UM/MOD, SM/REM, FM/MOD
- [x] Pictured numeric output: <#, #, #S, #>, HOLD, SIGN, BASE, PAD, HLD
- [x] Formatting: U., .R
- [x] */MOD (redefined with M* FM/MOD), DECIMAL
- [x] Batch 1: LSHIFT, RSHIFT, U<, 2/, +!, 2!, 2@, 2*, CHAR+, CHARS, FILL, MOVE, ALIGN, ALIGNED, CHAR, -ROT
- [x] Batch 2: STATE, [, ], LITERAL, ['], [CHAR], EXIT, POSTPONE, COMPILE,
- [x] Batch 3: >BODY, >IN, SOURCE, ABORT, QUIT, ABORT", >NUMBER, >DIGIT?, WORD, ENVIRONMENT?
- [x] Batch 4: CASE/OF/ENDOF/ENDCASE, UNUSED, 0>, U>, WITHIN, ERASE, U.R, HOLDS, .(
- [x] Batch 5: ?DO, VALUE/TO, :NONAME, PARSE, PARSE-NAME, SOURCE-ID, WORDS
- [x] `+to ( n "name" -- )` — add to a value (2026-07-25, branch plus-to).
  A gforth-style extension, not Forth 2012; wanted while porting Dark Star,
  whose TurboForth source uses `+TO` throughout. Implemented by *deferring to*
  `to` rather than reimplementing it: parse the name to fetch the current
  contents, rewind `>in` to where the name began, then let `to` re-parse and
  store. Consequences worth keeping: `immediate` (it parses, so it must run
  while the enclosing definition compiles) and `state`-driven (the fetch and
  the `+` are performed when interpreting, compiled when compiling), which is
  what makes one word serve both. Every error path is `to`'s verbatim — a
  variable, an unknown name, and a missing name all produce exactly what a bare
  `to` produces, so there is no second message to maintain.
  - Two implementation notes for anyone revisiting it: `parse-word`, not
    `PARSE-NAME`, because `+to` sits above the point in core.fs where that
    alias is defined; and the empty-name case must be guarded before `find`,
    which misbehaves on a zero-length name (it produced a bare `stack
    underflow` instead of `to`'s message).
  - A test gotcha, since it bit while writing them: a line error rolls the
    dictionary back to the start of **that line**, so a fixture written as
    `0 value x 1 +to zz` loses `x` as well. Put the fixture on its own line.
  - Deliberately no `-to`: gforth has none, `-5 +to x` reads fine, and one word
    is easier to teach than two.
- [x] String words: /STRING, COMPARE, CMOVE, CMOVE>, -TRAILING, BLANK
- [x] Programming-Tools: ?, DUMP, H.2, H.ADDR
- [x] Facility: KEY?, MS, PAGE, AT-XY, SCREEN-WIDTH, SCREEN-HEIGHT (platform layer)
- [x] Double-Number: D+, D-, D., D0=, D0<, D=, D<

---

## Infrastructure — COMPLETE

- [x] GitHub repository (private, github.com/bblodget/BasicForth)
- [x] README.md, LICENSE (GPL-2.0-only)
- [x] Copyright headers (SPDX) on all source files
- [x] Makefile: native arch auto-detection, run/test/clean/help targets
- [x] Makefile: QEMU auto-detection for cross-arch run targets
- [x] deploy_template.sh for remote board deployment
- [x] Startup banner with version from `git describe --tags --dirty`
- [x] Versioning with git tags (see docs/Versioning.md)
- [x] CHANGELOG.md
- [x] EOF handling in platform_key (clean exit on piped input)
- [x] Empty line re-prompts (instead of exiting)
- [x] BYE prints "Goodbye!" before exit
- [x] Integration test suite (shell-based piped I/O)
- [x] Native build and test on Pumpkin board (clone from GitHub)

---

## Phase 4: File System and Storage

- [x] Output handles (step 2): `stdin`/`stdout`/`stderr` (fileid = raw OS fd),
  `write-file`/`write-line ( c-addr u fileid -- ior )`. `platform_write` split
  into `platform_write_fd` with a stdout wrapper; `TYPE`/`EMIT` unchanged.
  Lets a utility write to stderr without corrupting stdout.
- [x] Generic file-access words (step 3): `open-file`, `create-file`,
  `close-file`, `read-file`, `file-size`, and `r/o`/`w/o`/`r/w`/`bin`. fileid =
  raw OS fd, `ior` = 0/positive errno (same model as the output words). New
  `platform_read_file`; `platform_open_file` generalized to
  `platform_open_file_mode` (+ read-only wrapper) and `platform_create_file`;
  `platform_fstat` reports errors. Example `examples/cat.fs`.
- [x] `read-line ( c-addr u1 fileid -- u2 flag ior )` (step 4): one line per
  call — at most u1 chars stored (u2 <= u1), terminator (LF, preceding CR
  stripped) consumed not stored; `flag` false only at EOF with nothing read. A
  line longer than u1 fills the buffer and the rest is discarded so the next
  call starts at the following line (truncation, chosen over ANS continuation);
  no cross-call state, so multiple files / reused fds are always safe. Defined
  in core.fs on top of `read-file` (one byte per read()), so no new asm/platform
  code — a buffered version can replace it later behind the same interface.
- [x] Dynamic memory — ANS MEMORY wordset (`ALLOCATE`/`FREE`/`RESIZE`): a heap
  *separate* from the dictionary, obtained from the kernel on demand via
  anonymous `mmap` (one mapping per allocation, data-only/no-exec). New
  `platform_mmap_anon`; `munmap` reused. `ALLOCATE`/`FREE`/`RESIZE` defined in
  core.fs over `(mmap-anon)`/`(munmap)` primitives, with a one-cell length
  header and a portable allocate-copy-free `RESIZE`, so the internals can be
  re-backed by a finer allocator later. `ALLOCATE 0` returns a non-zero `ior`;
  page-granular, so suited to a few large buffers. This unblocks later ideas
  that need scratch storage (SAVE session log, help text, text-processing lib).
  Still deferred (harder, separate step): *growing the dictionary itself* — a
  `PROT_EXEC` mapping with a movable `HERE` (see WildIdeas / Future-Hardening).
- Block storage / `LOAD` / `LIST` / `THRU` (Forth screens) — **Won't do.** Block
  screens are a historical storage model; BasicForth already loads source from
  files via `INCLUDE`/`INCLUDED`, and the Phase 4 file-access words cover real
  file I/O, so block storage adds little.
- [x] SAVE / persistence of user definitions — source-replay. `save` writes
  interactively-defined words to `session.fs`; an interactive session auto-loads
  it at startup (after core.fs). Capture excludes transient actions (LATEST/STATE
  delta — bare ALLOT/,/C, are not captured), handles multi-line defs, discards
  errored defs; idempotent and
  cumulative. Heap-backed log; REPL hooks `(session-seed)`/`(capture-line)`/
  `(capture-reset)` registered via `(hook!)`; gated to interactive tty sessions
  (`BASICFORTH_SESSION=1`/`0` overrides). See docs/Persistence.md.
  - Persists definitions and direct `to`/`is` assignments (see below), but not
    other runtime state: a `variable`'s contents reload uninitialized, and
    assignments made *indirectly* (a `to`/`is` inside a called word) are not
    saved. Redefinitions accumulate in the file.
  - [x] Persist direct `to`/`is` assignments across `save`/reload. `forth_to`
    (shared by `to` and `is`) sets a one-shot flag in its interpret-mode store
    path; `(capture-line)` reads it via the new `(assign?)` primitive and logs
    the line even though no new word was defined (no SEE record), and
    `(capture-reset)` clears a stale flag from an errored line. A `to`/`is`
    *inside* a called word compiles a store (not `forth_to`), so calling it is
    not over-captured. Still not persisted: indirectly-set state, and `redo`'s
    recompilation (the record is repointed in place; source-replay order doesn't
    encode the rebuild) — both documented in docs/Deferred_Words.md, docs/Redo.md.
- [x] `MARKER` — dictionary restore points (modern replacement for `FORGET`).
  `marker <name>` defines a word that rewinds `HERE`/`LATEST` to before the
  marker, forgetting it and all later definitions. `CREATE ... DOES>` in core.fs
  over `(latest@)`/`(restore-dict)` primitives. See docs/Marker.md. (`FORGET`
  deferred — obsolescent, footgun-prone; BareMetalForth also did marker-only.)
- [x] Session integration for `MARKER`: `-session` forgets the session
  definitions (rewinds to a restore point recorded just past core.fs, so core.fs
  and the session words survive) and `reload` does `-session` + re-`include`
  session.fs — the edit/compile/run loop. session.fs stays *pure definitions*:
  capture is forward-only (a marker run / `-session` moves LATEST backward and is
  not logged) and `reload` sets a one-shot skip flag. Implemented with an
  external restore point (`(session-mark!)`/`(session-restore)` globals) rather
  than a marker-in-the-file, so the file needs no `marker -session` header. See
  docs/Persistence.md.
- [x] `SEE` — source lister. `see <name>` prints a word's definition source
  (exactly as typed; multi-line and comments preserved). Resolves the name and
  matches the live xt, so it shows the definition currently in force and never
  stale source: a redefinition shadows the older one, and a word forgotten by
  `-session`/a marker reports not found. Works for any defining word; no new asm
  primitive. See docs/See.md.
  - [x] **Dictionary source metadata → `see` for *any* word.** Each compiled
    header carries an 8-byte `[SrcId:2][Len:2][Off:4]` record stamped at compile
    time, and a `.bss` source table maps SrcId → absolute file path. `see`
    dispatches on SrcId: `≥1` reads the byte span straight from the source file
    (so `core.fs` and any `include`d file are covered, attributed by *file
    position* not name — no wrong-source edge); `0xFFFF` reports *primitive
    (assembly)*; `0` (typed at the REPL, no file) falls back to the session
    capture log. New primitives `(find-meta)`/`(source-path)`; `platform_getcwd`
    + `make_absolute` keep paths re-openable after a CWD change. This supersedes
    and retired the old post-load seeded text-parser (which recognised
    definitions by defining word and so missed custom-defining-word words and had
    a rare redefinition wrong-source edge — both now gone). See
    docs/See_Metadata.md. Shipped v0.6.0.
- [~] ~~Bug: `INCLUDED` from inside a colon definition underflows the stack~~ —
  **not a bug.** `INCLUDED` is `( c-addr u -- )` per ANS (it leaves nothing on
  the stack; errors are printed, not returned as an ior). The earlier "underflow"
  was an erroneous `included drop` — the `drop` underflowed after the file
  loaded. `: load s" foo.fs" included ;` (no `drop`) works fine, which is what
  `reload` relies on. The SAVE startup still loads session.fs in asm, but that's
  now just a convenience, not a workaround.
- [x] **Fixed: `INCLUDE`/`INCLUDED` left the outer interpreter parsing a freed
  mmap.** `forth_included` overwrote `source_addr`/`source_len`/`to_in` with the
  file's lines but never restored the caller's values, then `munmap`ed the file.
  After the include the outer `forth_interpret_line` parsed from the (now freed)
  mapping. It only "worked" when `include` was the last token of a line *and* the
  file was fully consumed (so `to_in >= source_len` → no deref); any leftover
  token, or a compile-time error inside the file (which leaves `to_in` mid-line),
  dereferenced the freed page — wedging the REPL or **segfaulting** once the SAVE
  capture hooks were active. Fix: `forth_included` now saves the source pointers
  before the line loop and restores them on every loop-exit path (both arches).
  Bonus: tokens after `include <file>` on the same line now run correctly.
- [x] **Help system — docs browser (`man` / `topics` / `apropos`).** Reads the
  `*.md` topics in the colon-separated directories named by `BASICFORTH_DOCS`.
  `topics` lists them, `man <topic>` finds `<topic>.md` (case-insensitive) and
  pages it a screenful at a time, `apropos <keyword>` lists the topics whose file
  contains the keyword. New primitives: `(getdents)` (wraps `getdents64` for
  directory enumeration) and `(docs-path)` (exposes `BASICFORTH_DOCS`); getdents
  and pager buffers are heap-allocated. See Help_System.md. (Per-word
  `help <word>` is deferred to a later "Part A" — see WildIdeas.md.)
- [x] **Interactive tutorial (`tutorial` / `next` / `back`).** Walks a
  `BASICFORTH_DOCS` Markdown file one `## `-heading step at a time, returning to
  the REPL after each step so the reader can type the examples. Reuses the
  docs-browser machinery (file resolution, `read-line`, the pager line-printer).
  See Tutorial_System.md.
- [x] **First tutorial content: "Snake".** `docs/Tutorial/Snake.md` builds a
  playable terminal Snake game step by step, exercising nearly the whole
  language. Finished program in `examples/snake-mini.fs` (load-tested in the
  integration suite). Tutorials are self-contained subjects with descriptive,
  prefix-free names (`tutorial Snake`).
- [x] **Dictionary space raised 64 KB → 256 KB** (`DICT_SPACE_SIZE`, both arches,
  BSS only). The shared dictionary was nearly full once large examples
  (`examples/sort.fs`) loaded alongside `core.fs`; `unused` now reports ~226 KB
  free.

---

## Phase 5: Graphics and Sound

See docs/Planning.md "Graphics Direction" for the philosophy/roadmap and
docs/Graphics.md for the API.

- [x] Direct device gateway: `(ioctl)` / `(mmap-dev)` primitives
  (`platform_ioctl` / `platform_mmap_dev`), plus `w@`/`w!`/`l@`/`l!` 16/32-bit
  memory access. (step 1b-i)
- [x] Backend-agnostic 2D surface + primitives in `graphics.fs` (`set-surface`,
  `pixel`, `fill-rect`, `clear`, named colors); 32bpp. (step 1a)
- [x] `fill32` fast block-fill primitive; `fill-rect` clips once and fills each
  row in one burst (full-screen `clear` is instant).
- [x] ~~DRM/KMS software-2D backend~~ — built and hardware-validated in v0.8.0,
  **removed** in the SDL pivot (a desktop compositor owns the display, so DRM
  could never show a window; SDL's KMSDRM driver covers the console case).
  In git history: `src/forth/drm.fs`, `tools/drmoff.c`.
- [x] FFI: dynamic-link build (`gcc -nostartfiles`, dictionary mprotect'd RWX),
  `(dlopen)` / `(dlsym)` / `(ccall)` primitives (up to 6 integer/pointer args),
  `ffi.fs` wrappers, libc-based integration tests, docs/FFI.md + `man ffi`.
  Deferred: float args/returns, >6 args, C-to-Forth callbacks.
- [x] `sdl3.fs`: init/window/renderer/streaming-texture bindings; lock-texture →
  `set-surface`; present (`sdl-frame` / `sdl-show`); poll-event
  decoding (`sdl-poll`/`sdl-event-type`/`sdl-key`); `tools/sdl3off.c` verifies
  constants/offsets. Dummy-driver integration test (headless).
  (Shipped vsync-paced; changed to the `sdl-fps` timer 2026-07-20 — vsync
  blocks the present under a compositor, see docs/Graphics.md "Frame pacing".)
- [x] Animation demo: `examples/bounce.fs` — bouncing square, one step per
  frame, ESC/q/close to quit
- [x] Interpreted `s"` and `."` (ANS transient-buffer semantics) — STATE-smart
  redefinitions in core.fs; two alternating 256-byte buffers; compile path
  delegates to the ASM primitives so compiled code is unchanged
- [ ] SDL3 in the Pumpkian board image (build from source; bookworm has no
  libsdl3 package) — done in the Pumpkian repo
- [x] More primitives: `line` (Bresenham), `rect`, `circle`/`fill-circle`
  (midpoint), `blit`/`blit-key`/`grab` sprites (packed 32bpp, color-key
  transparency); `sdl-scale` pixel size (320×180 at 4× = 1280×720 window,
  nearest-neighbor GPU stretch); bounce.fs demo updated
- [x] Font / text rendering (show characters on the framebuffer) — done
  2026-07-23 (branch `fonts`). `require font-terminus-8x16.fs` gives `text`/`glyph` over
  `stamp`; Terminus 8×16 CP437, generated to `src/forth/font-terminus-8x16.fs` by
  `tools/psf2font.py`, OFL 1.1 (`fonts/OFL.txt`). `tutorial Fonts`. The
  chosen size was **8×16, not the 10×18** BareMetalForth used: PSF1 is always
  8-wide (1 byte/row = native `stamp` stride), and a thresholded TTF was the
  reason 10×18 was needed there — Terminus is a purpose-drawn bitmap, crisp at
  8-wide. ~~`stamp-scale`/`text-scale` deliberately deferred to the next batch.~~
- [x] Integer sprite/text magnification — done 2026-07-24 (branch `stamp-scale`).
  `stamp-scale ( color src x y w h n -- )` in `graphics.fs` draws each set bit of
  a 1-bit sprite as an `n×n` **`fill-rect` block** (not `n²` `pixel` calls — the
  per-sub-pixel path the perf notes warned against); `n<2` delegates straight to
  `stamp`, so 1× is a zero-cost drop-in. Text scaling is a **sticky `font-scale`
  value** (default 1, `sdl-scale` idiom) that `glyph`/`text` read — so their
  stack signatures are unchanged and every existing lesson/test/example keeps
  working; `text` scales the pen advance too. Integer scales only (fractional
  nearest = lumpy, smooth = blurry + fights the crisp aesthetic; arbitrary whole-
  screen scaling belongs at the GPU present, not per-sprite software). Docs:
  `help graphics` (`stamp-scale`), `help fonts` (`font-scale`); +8 integration
  tests both arches. The `text-scale` word was folded into `font-scale` (a value
  reads cleaner than a per-call arg and keeps `text`'s signature stable).
  Same branch, a font-architecture refactor: `text`/`glyph`/`font-scale`/
  `>glyph`/`font-w`/`font-h` moved into a shared engine **`fontcore.fs`** that
  draws a *current font* (values set via `font! ( data w h -- )`), so a font
  data file is now just its glyph table + a selector word named after it
  (`terminus-8x16`), which registers itself and is called on load. Multiple
  fonts can coexist and you switch with the selector word; `font!` derives the
  row stride from the width, so fonts wider than 8px work. `psf2font.py` emits
  the data+selector form (names derived from the output filename). Prompted by
  Brandon: the old single-file design would have duplicated the engine per font
  and the words would redefine each other. Engine file named `fontcore.fs`
  (not `font-*` — that pattern reads as a font family; not the collision-prone
  `font.fs`).
- [x] A second font — done 2026-07-26 (branch `font-vga-8x8`).
  `require font-vga-8x8.fs` → the IBM PC 8×8 character-ROM face, selector
  `vga-8x8`, generated from `/usr/share/consolefonts/Uni2-VGA8.psf.gz` (218 of
  256 CP437 codes present — block and box drawing all there, so nothing had to
  be synthesized; the gaps are the control range plus five symbols). Public
  domain, so no
  OFL-style obligation: Debian's console-setup copyright states "All console
  fonts are public domain by nature". Prompted by the Dark Star port, whose
  TI-99 info panel is laid out for 8-pixel text and came out double height on
  Terminus. `psf2font.py` now reads the cell height from the PSF header
  (PSF1 charsize / PSF2 h) rather than assuming 16, cross-checks it against
  the size in the output filename, and keeps per-family license text in a
  `FONT_INFO` table — an unknown family is an error, so no font can ship under
  a header describing a different one. Regenerating Terminus through the new
  script gives a byte-identical file (the check that the refactor was clean).
  +8 integration tests both arches, a `tutorial Fonts` step on switching, and
  `help fonts` on choosing. The multi-font design above needed no change to
  carry a second font. The one engine addition came out of the port too:
  **`>xy ( col row -- x y )`** in `fontcore.fs`, a character-cell-to-pixel
  converter, because hand-written pixel layout is what makes a font switch
  break. It scales by `font-scale` as well as the cell size — `text` advances
  by `font-w font-scale *`, so a hand-rolled `col font-w *` silently overlaps
  at any scale above 1 (the first draft of the docs example had exactly that
  bug). Named for what it returns, not `gotoxy`: `at-xy` already moves the
  terminal cursor, and this moves nothing.
- [x] Sound output via SDL3 audio: `sound.fs` — `snd-open`/`snd-close`,
  `tone` (queued integer square wave, S16 mono 44100), `beep`, `snd-wait`,
  `tone-amp`; no-ops when the device isn't open (games degrade to soundless
  via `snd-open drop`); wall blips in bounce.fs; dummy-driver integration
  tests; docs/Sound.md + `man sound`.
  **`snd-open?` retired 2026-08-06** (branch sound-api): `snd-open ( -- ior )`
  now, 0 = success, idempotent, with `snd-ready?` as the real predicate and
  `snd-why` for SDL's reason. The `?` had read as a question while the word
  opened — asking it opened a second device and leaked the first — and its
  true-means-success flag fought `abort"`, which fires on true. Default
  `snd-channels` 16 → 64 at the same time; measured cost of the extra 48
  streams is ~100 KB and <1 µs per `snd-pump`.
- [x] Game controllers via SDL3's gamepad API: `pad.fs` — `pads`/`pad-open`/
  `pad` (four slots, so two players work), `pad-held?`/`pad-axis`,
  `pad-dx`/`pad-dy` (d-pad + left stick merged to -1/0/1, d-pad wins on
  disagreement), `pad-dead`, `pad-has?`, `pad-map`; buttons named by position
  (`pad-south`, not `pad-a`); answers 0/false with nothing plugged in so games
  still run keyboard-only; `examples/gamepad.fs` readout; `help pad`
- [ ] **Rumble — `SDL_RumbleGamepad`.** Deliberately left out of the first
  `pad.fs`; the two-player karate port will want it, and it is easier to land
  BEFORE the Gamepad tutorial is written than to retrofit the lesson after.
  Low/high-frequency intensities plus a duration in ms; a no-op on pads
  without motors. Note SDL3 has **no** `SDL_GamepadHasRumble` (that was SDL2):
  capability is a property now — `SDL_GetGamepadProperties` then
  `SDL_PROP_GAMEPAD_CAP_RUMBLE_BOOLEAN`, with a separate
  `..._TRIGGER_RUMBLE_BOOLEAN` for the trigger motors. Verify offsets and
  names with tools/sdl3off.c as `pad.fs` did, rather than porting SDL2 habits.

  **The capability property LIES on the F310** (measured 2026-08-07): SDL
  reports `CAP_RUMBLE=1` and `SDL_RumbleGamepad` returns success for low, high
  and both motors — and the pad, which has no motors at all, does nothing. The
  flag comes from the kernel `xpad` driver advertising force-feedback for the
  XInput protocol generically, so it describes the DRIVER, not the device.
  Consequences: (a) a `pad-rumble?` predicate built on that property would
  confidently tell F310 owners their pad rumbles — either find better grounding
  or document it as "the driver claims it can"; (b) a test asserting the call
  succeeds passes on hardware with no motors, so it proves nothing (a test
  must be run against the BROKEN build before it is trusted); (c) **the dev hardware cannot
  verify this feature at all**, which is why the tutorial was written first,
  reversing the note above.
- [ ] **Hotplug auto-reopen.** Today a game must notice `pad?` went false and
  call `pad-open` itself (documented under Hotplug in `help pad`). An
  opt-in "reclaim slot n when a controller reappears" would remove that
  boilerplate — but it needs a policy for which slot a returning pad belongs
  to, which is why it is not in the first cut.
- [x] **Gamepad tutorial** — `docs/Tutorial/Gamepad.md`, 20 steps, shipped
  2026-08-07. Substrate before sugar: the stick's resting offset and a
  deliberately-too-small dead zone come before `pad-dx`, so the merged word
  reads as a fix rather than magic. "The reader may have no controller" became
  a SUBJECT of the lesson (`pad-open`'s ior, the one-word input dispatcher) instead
  of a hole worked around — which also makes the headless replay in
  `tests/test_lessons.py` simply the no-controller path, verified by hiding
  /dev/input under `bwrap`. No window is needed, so every step is a single-shot
  query at the prompt and the lesson needs no skip entries.
- [x] **Speech, tier 1: rendering** — `voice.fs`, `voice-render ( text u path u
  -- ior )` drives an external TTS engine to write a WAV, which `wav-load`
  then plays like any other sample. The engine is a settable command template
  (`voice-cmd!`) with `%t`/`%o` placeholders, both shell-quoted, so switching
  engines is one line and **nothing in the repo binds to a TTS engine**.
  Requires only `shellutil.fs` — no FFI, no SDL, no decoder — so it runs on
  the board and under QEMU, and its tests use a stand-in shell script rather
  than needing a TTS installed. `help voice`, `docs/Speech.md`.
- [x] **Speech, tier 2: speaking — SHIPPED 2026-08-10** (`speech.fs`). `say
  ( c-addr u -- )` synthesizes into memory through flite and plays on a
  `sound.fs` channel; `talking?` is that channel's own `ch-playing?`. Speech
  keeps its own channel, so successive says queue instead of overlapping and a
  phrase never waits behind a sound effect. Binding is lazy, so `require` never
  aborts on a machine without libflite. `say` BLOCKS while synthesizing —
  7 ms for "Go!", 38 ms for a sentence, against a 16.7 ms frame — which is why
  `voice.fs` stays the answer inside a game loop.
- [x] **Dark Star phrases — SHIPPED 2026-08-09.** 14 phrases rendered with
  piper into a `voice/` directory beside the game, played through `wav.fs`, so
  the game gained no new runtime dependency and self-rendered audio sidesteps
  the rights question hanging over the original's art.
- [ ] SDL_GPU 3D backend behind the surface API (SDL3-only API; see Planning.md)
- [ ] Game demos (snake, sprites)

---

## Phase 6: Robotics

- [ ] GPIO access via /dev/gpiochip (Pumpkin 40-pin header)
- [ ] I2C / SPI sensor communication
- [ ] Real-time control loops

---

## Phase 7: Custom Linux Distribution

- [ ] Minimal Linux image with BasicForth as /sbin/init (PID 1)
- [ ] Boot straight to Forth prompt
- [ ] Built-in editor for standalone development

---

## Phase 8: Threading and Locals

- [x] **The REPL's data stack was half a worker's.** RESOLVED 2026-08-11.
  `DATA_STACK_SIZE` was 4096 bytes (512 cells) while `thread-dstack` in
  `src/forth/threads.fs` was 8192 — two numbers, in two files, in two
  languages, that nothing explained. Noticed while sizing the locals stack.

  Fixed by making it **one constant, not two equal ones**: `DATA_STACK_SIZE`
  is 8192 in `src/config.inc` and `threads.fs` reads it back through
  `(dstack-size)`, so a REPL/worker difference can no longer be expressed.
  Two constants that are *supposed* to stay equal is the arrangement that
  produced the drift; one makes it unrepresentable. Raised rather than
  lowered: no working program breaks by being given more room, whereas
  halving the workers' could break one that works today.

  `THREAD_RSTACK_SIZE` stays alone — the REPL's return stack is the process
  stack (~8 MB) from the kernel, so there is nothing to unify it with.

  Nothing in the suites depended on the old figure (the `4096`s in the tests
  are a page-size fixture, a pty read buffer and a path length); two doc pages
  stated it and were updated. The worry that made this a separate item — that
  the guard-page tests fault against this size — turned out not to bite: those
  tests overflow by looping until they fault, so the size only changes how
  long they take.

- [x] **Locals word set (section 13).** SHIPPED 2026-08-11..13, both arches, in
  three stages: the runtime frame and its unwind contract; `{: … :}` with
  open-coded references; then `to`, the shadow note, and the rest of the
  declaration (`|`, `--`). See docs/Locals.md for what the building of it
  corrected in the design, and docs/Language-Reference/Locals.md for the user
  page. `does>` is refused, deliberately.
  **ARM64 timings: DONE 2026-08-15** on the Pi 400, and they earned their hour.
  The "open-coding beats a call" claim held — a reference is 0.62 ns against
  2.24 ns for the `dup` it replaces — but the measurement found the FRAME
  costing 28 ns a call, flat in the number of locals, because its cell count
  travelled as a `LITERAL`. Fixed (staging `115f09d`), and the literal itself
  the day after. A reference is still six instructions on ARM64 to x86's four,
  since finding LP takes four instructions there and one on x86; that is the
  one gap left, it is explained rather than open, and an X20 experiment to
  close it was built and rejected. All of it in docs/Locals.md.
  Original research entry follows.

- [ ] Locals word set (section 13) — Gforth-style separate locals stack
  - **Researched 2026-08-10: see docs/Locals.md.** Verdict: build it, runtime
    frame, separate stack, `lp` in the existing TLS block. Measured on x86: a
    primitive call ~1 ns, so the `rot over swap` a 3-arg word does today costs
    ~3 ns — but a `variable`-style access costs 4–5 ns, so **a local reference
    must be open-coded, not a create/does> word**, or locals make such words
    SLOWER than the juggling they replace. Risk is the unwind contract, not the
    syntax: a separate stack is not unwound by `.Lcf_longjmp` or the recovery
    anchor, so a frame leaks silently on every error unless released by hand.
    EIGHT reset paths, not the obvious two — uncaught throw, QUIT, dict_full,
    the interpret-line longjmp, the guard-page SIGSEGV (which resumes by
    rewriting the ucontext, so it does not grep like the others), the recovery
    anchor, REPL re-entry, thread start. The rule to hold: anything reaching
    `repl_loop` with a reset return stack resets `lp` too. Plus a NINTH,
    compile-time: the list of local names is per-definition state like STATE,
    so an abandoned definition must clear it or the next one inherits stale
    names. `does>` must reject local references (the frame is dead by then).
  - Separate locals stack (not return stack) to avoid conflicts with >R/R>
  - **Syntax decided 2026-08-10: Forth 2012 `{: a b c :}`**, not `{ … }`
  - **Core, not a library** — five of the eight reset paths are in assembly,
    so a require'd .fs could never hold the unwind contract
  - Locals shadow the dictionary; warn when the name is an existing WORD,
    since `{: i :}` silently steals the DO loop index
  - Each local name compiles to a locals-stack-relative fetch
  - TO works with locals (compile a locals-stack-relative store)
  - Reentrant and thread-safe (each thread gets its own locals stack)
  - Required for safe multi-threaded Forth words
- [ ] Threading support — **decided 2026-07-22: pthreads via the FFI, not
  raw clone; design in docs/Threading.md.** The binary is already
  dynamically linked and `pthread_create` lives in libc (glibc ≥ 2.34);
  SDL already threads this process (`bye`'s exit_group fix paid for that).
  - Per-arch asm trampoline: pthread entry sets up the thread's own data +
    return stacks and DSP register, then EXECUTEs the xt
  - `thread ( xt -- tid ior )` / `join ( tid -- ior )`
  - v1 rule (documented, not enforced): the REPL thread owns the
    dictionary — workers run compiled words only, no `:`/`create`/
    interpret-`s"`/`save`
  - Channels as the blessed communication path: `chan`/`ch!`/`ch@`/`ch?`
    (ring buffer + pthread mutex/cond)
  - [x] **Step 0 DONE 2026-07-31 (branch tls):** `base`/`sp0`/`handler`
    moved to thread-local storage (`%fs` / `TPIDR_EL0`, local-exec model).
    BASE is no longer read-only in workers, and adding another per-thread
    variable is now a one-line change.
  - [x] **Step 1 DONE 2026-07-31 (branch threads):** per-arch trampoline,
    `thread ( xt -- t ior )` / `join ( t -- ior )` in `src/forth/threads.fs`,
    and the `is_repl` gate so a worker's THROW no longer restores its
    snapshot of the ten shared input-source globals over the REPL's line.
    Uncaught throw in a worker ends only that thread (the trampoline runs
    the xt through `catch`) and surfaces as join's ior. 7 integration tests
    on both arches; `help concurrency`.
  - [x] **Step 1.5 DONE 2026-08-01 (branch threads):** thread registry
    (linked through the context blocks, no extra allocation), `threads`
    listing word with running/finished state, `join ( t -- result status )`
    splitting the worker's throw code from a join failure, and a spent
    handle now reported as -60 instead of crashing. Reference page renamed
    to Concurrency.md so `help threads` reaches the word, not the page.
  - [x] **Worker stack fences DONE 2026-08-01:** PROT_NONE pages below the
    data stack, between the stacks, and above the return stack, via a new
    `(prot-none)` primitive. Unfenced the stacks were neighbours and an
    overrun corrupted the other one silently.
  - Still to settle: **channels** (`chan`/`ch!`/`ch@`/`ch?`) as the blessed
    communication path — step 2; a thread-aware SIGSEGV handler (wanted for a
    nicer report now that fences make the failure loud); per-thread locals
    stack; stack sizing (fixed constants today)
  - [x] **`seed` is thread-local — DONE 2026-08-11** (branch tlsseed).
    `random`/`rnd` are usable from workers now. The cell moved out of the
    dictionary into the TLS block on both arches, exposed by an ASM word
    `seed ( -- a-addr )` exactly like `base`, so `42 seed !` and `0 seed !`
    read and behave as they always did — per thread.

    Both halves of the old defect measured before and after: two workers
    drawing 2000 values each shared **1707** of them (one interleaved stream,
    with lost updates, since the read-modify-write was never atomic) and now
    share **0**. The performance half was the 2026-08-06 finding, 4 threads
    **4x slower** than 1 from a single contended cache line.

    The design question was seeding, as flagged: `.tdata` is a constant image,
    so every worker would have started from the same number and replayed the
    same sequence — independent but identical, which is *harder* to spot than
    the shared cell, because from inside one thread it looks perfect. The
    trampoline therefore seeds each worker from `entropy`, falling back to the
    context-block address scrambled by the golden-ratio constant — a fallback
    that had to be per-thread too, since a constant there rebuilds the bug.

    The seeding sits **before** the trampoline switches stacks, which is the
    last point where the C stack's ABI-guaranteed alignment is still in hand.
    Seeding after the switch calls on the worker's *return* stack, aligned only
    as far as `ctx.rtop` happens to be — and AArch64 faults on a misaligned
    `SP` rather than tolerating it. x86-64 also pads by 8 so `RSP` is 16-byte
    aligned at the `call`; measured at the call site, 8 without the pad and 0
    with it. Note the engine's Forth-side calls into the platform layer are
    *deliberately* not SysV-aligned — `RSP` is the Forth return stack there —
    so an alignment tripwire in `platform_random` fires on ordinary startup and
    proves nothing about this path.

    Writing the test taught the same lesson twice: the obvious check, "the
    worker's value differs from the REPL's", **passes with the fix removed** —
    a single shared seed also hands the worker a different (merely *next*)
    value. It proved nothing. The real guard is cross-process: run twice and
    require the worker's first draw to differ between runs.

    `examples/dice.fs` was then simplified onto it: each worker sets its own
    `seed` instead of `allocate`ing a cell and freeing it. Same results for
    the same seed, and the same speed (200M battles: 82.1/21.1/6.68 s at
    1/4/16 workers, against 82.2/21.3/6.69 s before), which is the point worth
    recording — a TLS cell is per-thread memory, so there is no false sharing
    to reintroduce.

    **The dictionary is case-insensitive, so dice.fs's `value SEED` had been
    silently redefining the core `seed` for months.** Harmless until the file
    wanted the core word, then `seed !` wrote through an integer and
    segfaulted. Renamed to `RUN-SEED`. Note the redefinition warning is
    interactive-only — loading from a file says nothing, so a user library can
    shadow a core word with no sign at all.

- [x] **`random` is splitmix64, not xorshift64 — DONE 2026-08-11** (branch
  tlsseed). Two reasons, and the first is the one that made it worth doing:
  - xorshift64 has a **fixed point at 0**, so `0 seed !` killed the generator
    dead. That needed a special case inside `random` and a paragraph in
    `help random` explaining why zero was not like other seeds. splitmix64 has
    no bad state — the guard, the paragraph, and the `1 or` idiom in every
    seeding example all deleted.
  - xorshift64 is **F2-linear**: the 64 bits of one output are linear
    combinations of each other, so slicing one draw into several numbers is
    wrong. `examples/dice.fs` found it the hard way, with a tail ~50% too
    heavy while matching on a naive counter, the mean AND the standard
    deviation.

  Speed is a wash (20M draws: xorshift 1086/1061 ms, splitmix 1221/1027 ms) —
  in STC you are timing dispatch, not the multiplies. Nothing asserted a
  literal random value, so no documented output moved.

  Testing it took three attempts, which is the part worth remembering. Property
  tests (repeats, differs, non-zero) pass on **any** self-consistent generator.
  A marginal-uniformity test also passes on both, because xorshift64's fields
  are individually uniform and only jointly dependent — that is exactly why
  dice.fs's mean and sd looked right while its tail was wrong. What works is
  (a) the published **reference vectors**, pinning the algorithm itself, and
  (b) **xor-additivity**: F2-linearity means `f(a) xor f(b) = f(a xor b)`
  exactly, which xorshift64 satisfies and splitmix64 does not. Instant, and it
  names the real property.

  `examples/dice.fs` then lost 28 lines and got 13% faster (200M battles:
  71.8/18.5/6.44 s at 1/4/16 workers, from 82.1/21.1/6.68 s), because it could
  finally delete its private splitmix64, the state address threaded through
  `battle`/`4roll`/`escape`, the `allocate`/`free` pair, and a dozen lines of
  `/dev/urandom` handling that `entropy` replaces with one word.

---

## Future / Usability

- [x] **`help <word>` missed 53 names across six libraries — DONE 2026-08-11**
  (branch helpcov). The reference audit swept the core dictionary, the
  wav/audio tree and `speech.fs`, but no further — and a library this audit
  does not `require` is invisible to it. Found 2026-08-10 when `help on-stop`
  answered "no help". The real count was **53**, not the ~40 estimated —
  and not the 51 first claimed here, which was arithmetic over two partial
  measurements rather than one measurement of the whole. Verified by running
  the finished audit against a worktree of the pre-change commit:
  - **31 in `pad.fs`** — the button, axis and event constants, described in
    `Pad.md`'s at-a-glance block but with no `##` entry. Given **7 grouped
    headings** (`## pad-south pad-east pad-west pad-north ( -- b )` and so
    on): a heading indexes every name before its `( `, verified to at least
    15, so one entry covers a whole family without 31 stubs. Chosen over
    teaching the audit that at-a-glance names count, which would have turned
    the audit green while `help pad-south` still failed — the audit is the
    proxy, `help <word>` is the contract.
  - **12 raw SDL names** (11 in `sdl3.fs`, plus `SDL_INIT_GAMEPAD` in
    `pad.fs`), split by the rule below. Documented: `sdl-width`,
    `sdl-height`, `sdl-event`, `sdl-error`. Parenthesised: `(sdl-win)`,
    `(sdl-ren)`, `(sdl-tex)` and the five raw SDL enums.
  - **10 more the estimate never counted**, found by measuring every library
    rather than the two named: 3 in `fontcore.fs`, 5 in `threads.fs`, and the
    two font **selector words** `terminus-8x16` / `vga-8x8` — which only
    became visible once the audit loaded the font files themselves, and are
    the last two names anyone would guess were missing, since switching fonts
    is the headline feature of that page. Of those, `running` and `finished`
    became `(running)`/`(finished)` — internal ctx.state values, and as bare
    names in a flat dictionary two of the likeliest words for a game to want.
  - **A third broken heading separator**, the cause of the whole `fontcore`
    group: `## font-w ( -- n ) · font-h ( -- n )` — a middle dot, where the
    earlier fix was for `/`. The indexer stops at the first `(`, so every
    name after it was lost. Only two headings used it; both converted.

  The audit now `require`s **every** `src/forth/*.fs`, and a second check
  proves it rather than asserting it: each `require` leaves an `(inc:<file>)`
  guard word, so the dictionary reports what was loaded and an unswept file
  fails by name. Worth knowing why that check exists — the first version of
  this fix listed five libraries and claimed in a comment that the rest came
  in transitively. `graphics.fs` did (via `sdl3.fs`); `shellutil.fs`,
  `voice.fs` and `disasm.fs` were simply never loaded. The hole the audit
  exists to close had reopened inside the fix for it, hidden behind a comment.

  The rule applied, unchanged from the `snd-dev`/`snd-stream` case: a name a
  user is expected to pass to something is API and needs a `##` entry; a
  handle or an internal enum is `(parenthesised)`.

  An earlier bug from the same session was already fixed: four entries used a
  `## a ( eff ) / b ( eff )` heading, so `help pad-closeall`,
  `help pad-hasaxis?`, `help pad-dy` and `help on-stop` all failed. The
  supported form is `## a b ( eff )`.

- [x] **`docs/Install.md` — one page from `git clone` to a working setup —
  DONE 2026-08-11** (branch install). Leads with the property that was
  invisible before: nothing is required to build but `binutils`, `gcc` and
  `make`, because every library is `dlopen`ed on demand and a missing one
  costs exactly its own feature. Covers clone, all three build cases, the
  four test targets, `. ./setup.sh` and what it exports, first run, and the
  optional libraries with what each one buys. `README.md` and
  `docs/BasicForth_Manual.md` lost their duplicate §Prerequisites and point
  at it; `Graphics.md`, `Speech.md` gained cross-references.

  Facts pinned down while writing it, each verified on this machine:
  - **`gcc` is required to BUILD, not just for unit tests** — both the README
    and the Manual said "for unit tests". It links the binary
    (`$(CC) -nostartfiles -no-pie … -ldl`), which is what makes the FFI's
    `dlopen` work at all. The claim had been wrong in two places at once.
  - **SDL3 has no apt package on Ubuntu 22.04 / Debian bookworm.** Built
    3.4.12 from source into a scratch prefix to check the recipe end to end,
    and confirmed with `LD_DEBUG=libs` that BasicForth loaded *that* build,
    then opened a window and drew on it. cmake's default prefix is
    `/usr/local`; `sudo ldconfig` afterwards is required, not optional.
  - **cmake's "Enabled backends" summary is the check that matters.** SDL
    builds happily with no video or audio backend when the dev headers are
    missing, and the failure only shows up later at `sdl-open`. SDL's own
    `docs/README-linux.md` has the per-distribution package list, so the page
    points at it rather than copying a list that would rot.
  - **A missing library does not degrade gracefully in the way you might
    assume.** `require sdl3.fs` prints `sdl3.fs: needs the library
    libSDL3.so.0 -- see help install` (it was `dlopen: cannot load library`
    before `needs-lib`) and the session continues — but loading *stops
    there*, so the words are simply
    absent and a later `snd-open` reports `? snd-open`. Verified under
    `bwrap` with `/usr/local/lib` hidden. The page says so, since "why is
    this word missing" is the question that actually gets asked.
  - `help`/`tutorial` without `BASICFORTH_DOCS` answer
    `(BASICFORTH_DOCS not set)` — quoted literally, since that string is what
    someone will search for.

- [x] **REPL "option B": emit the newline lazily, before the first byte of
  output — DONE 2026-07-28** (branch lazy-newline). The one untried idea from
  the 2026-07-26 format review; Brandon chose to build it the same day rather
  than park it. Today the line editor emits a newline the moment you press
  Enter, so a line that prints nothing still costs two screen lines: the
  command, then ` ok` alone. Instead, set a *pending newline* on Enter and
  let the first output byte flush it:

      > : hello ." Hello World" ;  ok    <- silent line: one line, not two
      > hello
      Hello World ok
      > list
      : row ( n -- ) 8 .r cr ;           <- listing NOT jammed onto the command
      …
       ok

  Why it is the interesting one: it buys gforth's compactness **without**
  the jamming that killed the straight-inline experiment, because the
  newline comes from the system rather than from every display word having
  to start with `cr`. Nothing changes about how anyone writes Forth here —
  no leading-`cr` sweep, no change to the `cr`-goes-last convention.

  **It changes exactly one case.** ` ok` still appends wherever the cursor
  is; all that moves is *when* the newline after your input is emitted:

  | line | today | option B |
  |------|-------|----------|
  | silent (`: foo 1 ;`) | `> : foo 1 ;` + ` ok` on its own line | `> : foo 1 ;  ok` |
  | output ending in `cr` (`hello`) | output line, then ` ok` | identical |
  | output not ending in `cr` (`6 `) | `6  ok` | identical |

  "Silent" is broader than one-line definitions, which is why it earns its
  keep: `variable`/`constant`/`create`/`value`, `to`/`+to`, a successful
  `include`/`require`, lines that only push — **and the closing line of a
  multi-line definition**, which is the one line quiet-compile still spends
  an ` ok` on. A four-line definition goes 5 screen lines → 4, on top of the
  9 → 5 quiet-compile already bought.

  - **Mechanism**: one flag. The REPL arms it after reading a line, and the
    first thing written afterwards flushes it. The invariant to hold onto:
    **` ok` is the only message allowed to append — everything else flushes
    first.** Output flushes, errors flush, *and prompts flush*. That last
    one is what prevents the `>  >  > ` sideways pile-up the straight-inline
    experiment produced: press Enter on an empty line and the next prompt
    does the flushing, so it still lands on a fresh line.
  - **The risk is completeness, not design.** There are at least three write
    paths (`platform_emit`, `platform_write`, `platform_write_fd`) and both
    the interactive and piped input paths; any one that skips the check
    yields `Hello World> ` jamming. Enumerate every caller before patching —
    the same shape as the four-abort-path bug of 2026-07-27, where fixing
    them one at a time kept half-working. Note `platform_write_fd` must
    flush only for stdout: a write to a *file* must not emit a stray
    newline to the terminal.
  - **Errors: let them flush** (so `? name` keeps its own line, exactly as
    today). Then `tests/test_lessons.py` needs no change — its
    `unexpected()` skips lines starting with `> `, and with errors flushing
    they never land there. The compact alternative
    (`> nosuchword ? nosuchword`) reads well but *would* require fixing that
    attribution first, or lesson rot goes undetected.
  - Integration expectations are mostly unaffected: the ~75 `assert_output`
    cases ending in `"N  ok"` all produce output, so they behave as before.
    Silent-line cases move from a bare ` ok` line to `<command>  ok`.

  **As built.** The prediction held: exactly one test in 843 changed — the
  quiet-compile case that counted bare ` ok` lines, which now asserts the ok
  lands on the definition's closing line (`loop ; ok`) and on neither
  continuation line. Errors flush, so `test_lessons.py` needed no change.
  Implementation is a single `pending_nl` flag in platform_linux.s, paid by
  `platform_emit` (always) and `platform_write_fd` (**fd 1 only** — a write to
  a file must not push a byte to the terminal), plus `platform_exit` so the
  shell prompt never lands on a half-finished line. The flag is cleared before
  the flushing write so paying it cannot recurse. Set by `forth_accept` (which
  covers direct `ACCEPT` callers) and by the REPL after the line-editor hook;
  `(edit-line)` and the Ctrl-D `bye` path stopped emitting their own newline.
  Gotcha that cost a red run: core.s now references a symbol owned by
  platform_linux.s, so the C unit-test harness fails to LINK until
  `pending_nl` is stubbed in **both** `tests/test_helper_*.s` — the standing
  rule for any core.s reference to a platform symbol.

- **DECIDED 2026-07-28: keep ` ok`.** Removing it entirely was considered —
  the symmetry argument is real (gforth reasoned that an `ok` makes a prompt
  redundant; the reverse holds too, and printing *both* is the one redundant
  combination). Rejected because `ok` is the most recognizable trait of a
  Forth REPL: a `> ` prompt reads as house style, no `ok` at all reads as
  "not a Forth". Recorded so it is not re-litigated. Two notes if it ever
  comes back: (1) it needs option B's flag anyway, or output without a
  trailing newline jams into the next prompt (`Hello World> `); (2) the
  version that would pay for itself is dropping `ok` *and* showing stack
  depth in the prompt — `> ` when clean, `<2> ` when two items are stranded
  — which is Forth-literate rather than Forth-ignorant, cheap in asm
  (`(sp0 - dsp)/8`), and surfaces the leftover-stack bug that bites
  beginners. Also worth knowing for the record: classic BASIC printed `Ok`
  with **no** prompt character, so dropping `ok` is shell/Python-like, not
  BASIC-like.

- [x] **Lesson replay suite — DONE 2026-07-25** (branch lesson-fixes):
  `make run-lessons` (`tests/test_lessons.py`, both arches) replays every
  lesson in one session with state carrying between steps, plus every
  `examples/*.fs`. Skips print their reason; per-lesson `expect` lists the
  errors a lesson teaches; SDL lessons SKIP under QEMU / without libSDL3 by
  the integration suite's rule. First full run: no lesson had rotted after a
  week of merges (fonts, stamp-scale, delete, ctrl-d, require-cycle,
  list-log), and the prose-rot grep for retired messages was clean too. It
  did surface two Chase sketch blocks that read as typeable (`erase` gave a
  real `stack underflow`) and the Graphics `bounce.fs` pointer that only
  resolves with `examples` on `BASICFORTH_PATH` — both fixed, and `help
  files` now documents the search order. Maintenance cost: the skip table
  needs an entry when a new lesson step blocks on a key.

- **KNOWN BEHAVIOUR (recorded 2026-07-25, not a bug):** a multi-line
  definition whose FIRST line aborts leaves the following lines to be
  **interpreted**, not compiled — the abort ended compile state, so the body
  runs as commands. Usually that just prints `stack underflow`; found during
  the lesson sweep by pasting the FFI page's two-line example without
  `require ffi.fs` first, where the orphaned second line reached `(ccall)`
  with a garbage pointer and **segfaulted**. Inherent to line-at-a-time
  interpretation (gforth behaves the same), and `(ccall)` is an unguarded
  escape hatch by design — calling an arbitrary address is the feature. Worth
  knowing rather than fixing: pasting a definition is not as safe as typing
  one, because a typo on line 1 turns the rest of the paste into commands.
  If it ever becomes worth guarding, the shape would be "an aborted `:` line
  swallows the rest of the pasted input", which needs a way to tell a paste
  from typed lines (bracketed paste on a PTY) — not obviously worth it.

- [x] **Remove the stale `compact` references from the docs.** `compact` was
  **deleted** in `724edd3` ("Stage 4 cleanup: delete propagation, compact, and
  the mutation-tag save path") — `grep -rn compact src/` finds nothing, so the
  word does not exist. But the docs still present it as shipped and usable:
  - this file marks it `[x]` under Module System / Shipped ("`compact <name>` —
    deduped, dependency-ordered, definitions-only snapshot");
  - `docs/Persistence.md`, `docs/Module_Architecture.md`,
    `docs/See_Metadata.md`, `docs/Core_Primitives.md` and
    `docs/BasicForth_Manual.md` all reference it.

  Anyone following those instructions gets `? compact`. Sweep all six, and say
  in the TODO entry *why* it went (the mutation model made a
  dedupe-and-reorder snapshot unsound — `save` is replay-faithful by design),
  so the idea isn't silently lost if it's ever wanted again. Found 2026-07-22
  while checking how `keep` would interact with it.

  Done 2026-07-22. Persistence.md and the Manual already carried the "there
  is no `compact`" note; See_Metadata.md and Core_Primitives.md only use
  the word as an adjective. Real fixes: this file's Shipped entry now
  records the deletion and why; Module_Architecture.md's status header now
  says the log-canonical sections are historical rationale. Bonus (missed
  by the case-sensitive grep above): the `:NONAME` header comments in both
  arches' core.s justified real headers via "COMPACT can replay it" — now
  "the capture log can replay it". CHANGELOG entries are dated history and
  stay.

- [x] **A way to put a non-definition line into the module — `keep`.** Done
  2026-07-22 (branch module-hooks), as designed below: `keep` sets the same
  "log it anyway" flag a direct `to`/`is` sets, folded into `(cap-assign)` at
  the top of `(capture-line)` so the existing branch does the work. Resolved
  open questions: the name is **`keep`**; it may appear **anywhere on the
  line** (the flag is read after the whole line runs); a multi-line group
  cannot contain one (it is interpretation-only in practice); and `list`/`see`
  show kept lines like any other, which is what makes the file readable.
  The one design call worth recording: `keep` acts **only when `source-id` is
  0**, so the token replayed from the saved file is inert — nothing has to
  strip it out, and re-saving a reloaded module stays byte-identical (tested).

  Original write-up — the reasoning that led here:

  The capture log records a line only when LATEST moves forward, so setup lines
  are invisible to `save`: `320 180 sdl-open` never reaches the file, and
  neither do rows of `,`/`c,`/`l,` after a `create`. Brandon's ask
  2026-07-20, after a reload stranded his window and he had to hand-edit
  `sdl-close` / `320 180 sdl-open` into the file to make reloads work.
  - He suggested a marker comment, `sdl-close   \ __log__`. A plain word
    reads better and needs no comment-scanning: `320 180 sdl-open  keep`.
  - **The mechanism already exists.** `(capture-line)` (core.fs) logs a group
    when LATEST moved forward **or** when `(cap-assign)` reports a direct
    `to`/`is` ran on that line — i.e. there is already a "log this line even
    though it defined nothing" path. `keep` sets the same kind of flag.
  - Solves more than graphics: module setup lines, and the
    data-after-`create` gap above (`%00111100 c,  keep`), though the
    colon-word idiom stays the nicer answer for art.
  - Open: the name (`keep`, `+log`, `stet`); whether it must be last on the
    line or may appear anywhere; what it means inside a multi-line group; and
    whether `list`/`see` should show kept lines differently from definitions.

- [x] **Module lifecycle hooks — `on-start` / `on-stop`.** Done 2026-07-22
  (branch module-hooks). A module defines either name and `(mod-hook)` looks it
  up and runs it; neither is predefined, so a module that wants neither is
  unaffected. Where they went, and why those spots:
  - `on-stop` is the first thing `-session` does. That is the single chokepoint
    every rollback funnels through, so one call covers `reload`, `load`, `new`,
    `:e`, `edit` and a bare `-session`.
  - `on-start` runs at the end of `(open-module)` (the module must define it
    before it can be called) **and** at the end of `(session-init)`, since the
    startup file loads before that boot hook — without the second call a fresh
    `basicforth game.fs` would not open the window a `reload` does.
  - Errors are caught: `error in on-start hook: n`, and the load continues. A
    hook that fails must not leave you with neither the old module nor the new.
  - Re-entrancy: `(hook-busy)` is held for the hook's whole dynamic extent, so
    an `on-start` that calls `reload` finds the inner hooks suppressed instead
    of recursing. `(capture-reset)` clears it each REPL line in case a hook
    faults past the `catch` (a guard-page fault longjmps, it is not a throw).
  - Resolved open questions: they run on any load/reload, **not** at `bye`
    (process exit releases what the OS knows about), and **not** on a `marker`
    rollback (a marker is a dictionary tool, not a module verb).
  - Gotcha found while building this, worth remembering: **`find` leaves
    `( c-addr u 0 )` on failure**, not `( xt 0 )` — it keeps the name. The
    first `(mod-hook)` dropped one cell and leaked one per hook lookup, which
    surfaced as two unrelated module tests failing on stack depth. The
    Language-Reference entry said `( c-addr u -- xt n )` flatly and its own
    example leaked; both fixed.

  Original write-up — the reasoning that led here:

  A module cannot currently react to being loaded or reloaded, which is why a
  live window does not survive `:e` (see the reload/resources bug under Known
  Bugs). Brandon's idea 2026-07-20.
  - `on-start` after a load/reload — re-acquire resources (`320 180 sdl-open`).
  - `on-stop` **before** the reload — and this is the half `keep` cannot do.
    Putting `sdl-close` at the top of the file runs *after* the rollback, when
    the handles are already zeroed; it only works today because `sdl-close`
    ends in `SDL_Quit`, which destroys every SDL window whether we still have
    a handle or not. That bluntness would not save a leaked fileid or audio
    stream. A pre-rollback hook still holds valid handles and can release
    them properly, so no orphan is created in the first place.
  - Open: names; whether they run on plain `load`/`include` or only reload;
    whether `on-stop` runs at `bye`; ordering against the file body; and what
    happens if a hook errors — now that `catch`/`throw` exist, a reload can
    wrap each hook in `catch` and report rather than abort the whole load.

- [ ] **`see <table>` should show the data rows, not just the `create`.**
  Fallout from the create-data fix above, deliberately left for a later batch.
  A line that moves HERE is now logged, but it gets **no SEE record** (it
  defines no word), so `see inv` on a table built as `create inv` + loose rows
  prints only `create inv` — the rows are in the file and reload correctly,
  they just aren't part of what `see` considers the word's source. The
  colon-word idiom (`: inv-art … ; create inv inv-art`) shows in full, which
  is one more reason the lessons still teach it.
  - Shape of the fix: when a HERE-only line is logged and LATEST has not moved
    since the last group, **extend that group's `(dir)` record length** to
    swallow the line instead of adding nothing. The record is `[log-off,
    log-len, xt]` and the new text is appended contiguously, so it is a
    length bump on the newest record — but check the multi-line and
    `(dir-add-group)` (several words on one line) cases before assuming that.
  - Decide what happens when data rows are separated from their `create` by an
    unrelated captured line; probably stop extending at the first such line.

- [x] **`on-start` should be able to tell a boot from a reload.** DONE
  2026-07-25 (branch booting) as **`booting? ( -- flag )`**, the readable-flag
  shape rather than either option sketched below.
  - **Asking beats being handed an argument.** `on-start ( boot? -- )` would
    make hooks mandatory-arity: a module that ignores the flag silently leaves
    a cell on the stack. `booting?` keeps `on-start ( -- )`, so a module that
    does not care is untouched — the "keep the no-hook case free" requirement
    below, extended to the hooks that exist but do not ask. `on-stop` can take
    the same treatment later (teardown-for-an-edit vs for `bye`) without
    inventing a second convention.
  - **The line is start vs re-start, not boot vs everything.** True at startup
    *and for `load`*; false for `reload`/`edit`/`:e`/`delete`. `load <file>` is
    already documented as "a clean swap, like `basicforth <file>` mid-session",
    so having the two disagree would be a wart — and this way `load game.fs` is
    the interactive way to test the boot path. That answered Brandon's question
    about adding a separate `boot <file>` verb: not needed, and the module-verb
    family is already at eight words.
  - Implementation: `(boot?)` set by `(session-init)` and `load`, read by
    `booting?`, retired by `(start-hook)` right after `on-start` returns so a
    later `reload` cannot inherit it. `(open-module)`'s load-error path clears
    it too (no hook runs there), and `(capture-reset)` clears one left by a
    faulted load, the same safety net `(hook-busy)` has.
  - The double-reload case is covered by construction: a dirty `:e` reloads
    twice (auto-save, then splice) and both are restarts, so a self-launching
    module runs itself once per session, not twice per edit. Pinned by a test.
  - +3 integration tests; `help booting?`; the hazard below (a hook that never
    returns never gives you a prompt) is now written down in `help modules`.

  Original write-up — the reasoning that led here:

- [~] **`on-start` should be able to tell a boot from a reload.** Today
  `(mod-hook)` calls `on-start` identically at startup, after `load`, and after
  every `reload` — including the ones `:e`/`edit` perform — so a module cannot
  say "launch the game when I'm started, but only reopen the window when I'm
  edited". Brandon's ask 2026-07-22, from testing whether a module could
  autostart a game: it can (`basicforth invaders.fs` boots straight into it,
  which is the Phase-7 appliance feel and worth keeping), but the same line
  then re-runs the game on every edit. A `:e` on a dirty module reloads
  **twice** — auto-save reload then splice reload — so one edit ran the demo
  twice over.
  - **There is no workaround today, which is why this needs solving in the
    hook.** Everything the module owns is rolled back and replayed, and so is
    every library it `require`s (the `(inc:…)` sentinel goes too), so there is
    no surviving flag a hook could test to spot a re-entry. Checked before
    filing.
  - Two shapes, roughly equal work: pass the reason in — `on-start ( boot? -- )`
    or a richer reason code (boot / load / reload) — or add a separate
    `on-boot` that only fires from `(session-init)`. The flag generalises
    better (a module can branch); the second name is easier to explain and
    keeps `on-start` zero-stack. Leaning **flag**, since `on-stop` may
    eventually want the same treatment (tearing down for an edit vs for `bye`).
  - Whatever the shape, keep the no-hook case free: a module defining neither
    must stay unaffected, and a hook must not become mandatory-arity.
  - Related caution to document alongside it: a hook that never returns never
    gives you a REPL, because it runs mid-reload. Fine for a game loop with an
    exit key; a hazard for an unconditional `begin … again`.

- [ ] **TCP sockets library — the plumbing under chat, BBS, and anything
  networked.** Design in **docs/Sockets.md** (2026-07-22). Platform-layer
  raw syscalls, both arches — sockets are fds, so `read-file`/`write-file`/
  `close-file` already work on them; new words are only `tcp-connect`/
  `tcp-listen`/`tcp-accept`/`fd-nonblock`/`fd-poll`/`ip` plus internal
  sockaddr/htons plumbing. Design rule: **non-blocking + poll is the paved
  road** — the chat prompt-peek then needs zero concurrency. DNS is the
  sneaky gap (getaddrinfo is libc, not a syscall): v1 numeric IPs, v1.5
  `getent hosts` via shellutil.fs. Tests via socketpair/UNIX-domain +
  loopback TCP, never the real network. TLS: never build it.

- [ ] **Community arc — chat client, then a BasicForth BBS.** Ideas in
  **docs/Community.md** (2026-07-22): community lives inside the tool.
  IRC first (line-based plaintext, Strings-lesson-difficulty parsing,
  ~150-line client, real people on day one); REPL experience escalates
  pull (`msgs`) → prompt-peek (deferred hook before ` ok`) → live
  (needs threading). Destination: a BBS written in BasicForth itself,
  merged with the package sources — boards + packages + door games.
  Network games ride the same sockets (lockstep: send inputs, not state;
  ladder = high-score server → turn-based → LAN tron → BBS lobbies).
  Sequencing: sockets.fs → chat v1 (no threads) → package stages →
  threading → BBS.

- [ ] **Packages — sharing user-generated libraries and programs.**
  Design in **docs/Package_Registry.md**, rewritten 2026-08-19 and marked as
  a sketch to be corrected by building it. A package has a comment header +
  leading "dep block" (`require` / `needs-cmd` / `needs-lib`); a saved
  module is its entry file (`save` → `publish` → `install`); a **source**
  is a git repo holding a manifest, and each manifest entry points at the
  package's **own** git repo at a pinned full commit SHA. No phone book —
  people advertise their own sources — but one default source ships
  preconfigured. Git is the only network layer, over shellutil.fs.
  **Dark Star is the intended first package**, and the doc says to update
  itself from what that teaches. Prerequisites landed: shellutil.fs is the
  exec/capture plumbing, `save` round-trips `create` data, and the user
  package directories shipped 2026-08-19. Still outstanding:
  include-relative resolution, without which a multi-file package cannot
  find its own siblings once installed.
  Implementation stages (each independently useful, in order):
  - [x] exec primitive — landed as shellutil.fs ((cmd-run)/(cmd-open)/
    (cmd-line1) over `open-pipe`, quoted interpolation via (cmd+q))
  - [x] `needs-cmd` / `needs-lib` — polite system-requirement probes at
    load time. Done 2026-08-13 (branch needslib). The name is one word and
    the rest of the line is an install hint, cut at a `\` so ordinary
    comments still work. New `(exec?)` primitive (faccessat X_OK **and**
    newfstatat S_IFREG — X_OK alone accepts a directory); `needs-lib`
    probes with a real `dlopen` and keeps the handle for the bind that
    follows. Not yet adopted by the built-in libraries — that is its own
    step, since each one currently fails its own way.
  - [x] `deps <name>` + the soft forms `wants-cmd` / `wants-lib`. Done
    2026-08-14 (branch deps). A soft requirement is a **declaration, not a
    check**: it parses its line and does nothing else — no probe, no
    message, no abort — so speech.fs keeps answering `speech-open
    ( -- ior )`, voice.fs keeps treating piper as a default that
    `voice-cmd!` replaces, and disasm.fs keeps re-probing for objdump on
    every `dis` (installing binutils mid-session still works without a
    reload). All three now carry a dep block; `needs-*` in any of them
    would have broken a published contract.
    `deps` re-runs the block with a mode flag set, so the same word that
    would act at load time reports instead — one parser, not two. It
    follows `require` into the files named there, because the flat answer
    can lie (`require sound.fs  found` is no comfort where sound.fs itself
    cannot load), and nested files print **only if something in them is
    missing**. File-only resolution for now: `.fs` appended if absent,
    CWD then BASICFORTH_PATH. A word-name fallback via the header's
    srcid — `deps dis` finding disasm.fs the way `see` does — was
    considered and deferred: it can only answer for words you already
    have, and the main question ("what will this need *before* I load
    it?") can only go through the file.
  - [x] user package dirs — DONE 2026-08-19. `~/.basicforth/lib` +
    `docs/{Packages,Tutorial}` appended at startup, so a third-party
    package is require-able and answers `help` from any directory.
    `$BASICFORTH_PACKAGES` relocates the root and disables the mechanism when
    it names nothing, which is what keeps the suites independent.
  - [x] `[ENGINE]` include-relative resolution + a word for the loading
    file's directory — DONE 2026-08-20 (`dd0e801`). Beside-first resolution,
    plus `my-dir` and `path-join`; Dark Star runs installed from any directory
  - [ ] the default source — manifest format, pinned full commit SHAs,
    client-side index generation
  - [ ] REPL package words — `packages` / `install` / `remove` / `run` /
    `update` (git clone/pull via shellutil.fs)
  - [ ] federation — `add-source` / `sources` / `name/pkg` disambiguation.
    No phone book: sources are advertised by their own authors
  - [ ] `publish` — saved module → your own source clone → commit, then
    STOP and print the `git push` for the human to run

- [x] **`:` should say when it redefines an existing word.** Done 2026-07-22
  (branch redefined-warning), gforth's exact text: `redefined foo`. One
  check in `build_header` (both arches) covers every named defining word;
  `:noname` enters below the parse and never warns. The suppression trap
  below was solved by gating on `cur_source_id != 0` BEFORE the dictionary
  scan — so startup/include/require/module reloads are both silent and
  free. `evaluate` at the prompt warns (so `redo foo` confirms itself —
  a feature), EXCEPT `:e`: it requires the word to exist, so the note is
  noise there — `(ce-go)` arms a one-shot `(redef-quiet)` flag that
  `build_header` consumes (Brandon's call after live-testing the
  `redefined 3beep :e: warning:` mashup). Field evidence arrived the same
  day it shipped: gforth
  printed `redefined count` three times during the count-to-a-billion
  session while BasicForth silently shadowed the standard word `count`.
  Two follow-ups filed the day it shipped (Brandon's live testing):
  - [x] **`delete <name>` — remove a definition from the module file and
    reload.** Done 2026-07-24 (branch delete-word), exactly as designed
    2026-07-22 (design walk: undo-def → forget → this): file-level,
    Brandon's idea — edit the truth. `delete 3beep` splices the word's
    newest group OUT of the module file ((edit-span?) + (edit-splice)
    with `(es-nu)=0`; a recorded span includes its trailing newline, so
    no blank line is left) and reloads; prints `deleted 3beep`. Pure
    core.fs — no assembly. Rejected shapes stand: surgical dictionary
    removal (unsafe in STC — callers hold compiled `call` addresses);
    FORGET retroactive-marker semantics (the over-forget foot-gun is why
    Forth 2012 dropped it for `marker`). `rm` stays reserved for files.
    - Newest-group-only shipped: deleting a redefinition RESURRECTS the
      previous definition — "undo my redefinition", the wish that started
      this. A depended-on word's deletion surfaces the dependent as an
      honest `? name` on replay. Guards mirror `edit` (unknown/primitive/
      not-in-module/no-file), with the same reload-to-converge retry;
      a dirty session auto-saves first via (edit-sync).
    - Deferred until use testing asks: delete ALL of a name's groups
      (word fully gone) — maybe a flag or a second word.
    - Test-fixture gotcha for the suite: don't name a fixture word `base`
      (or any core word) — after the delete, the dependent silently
      rebinds to the primitive and the `? name` never comes.
  - **DECIDED (2026-07-22): library-word entries stay lean; the topic
    header is the setup pointer.** `help beep` shows no require/snd-open
    info — that story lives in the page preamble, which a word lookup
    never prints. Considered per-entry setup lines and rejected them (a
    beep fix was written and reverted): every `help <word>` now opens
    with its `<Topic>:` header, so `help sound` is one obvious hop away,
    and per-entry boilerplate across Sound/Graphics/SDL3/FFI isn't worth
    the maintenance. Revisit only if users demonstrably don't follow the
    header hop.
  Original notes: today a
  redefinition is completely silent — no message from `:`, `create`, `value`
  or anything else. gforth prints `redefined foo`, and that is genuinely
  useful: it catches a name collision you did not intend, and confirms the
  one you did. Brandon's ask 2026-07-20.
  - Found because **the docs already claimed this message exists**: the
    Graphics lesson told readers "(the `redefined scene` message is normal)"
    and a draft of the Bitmaps lesson said the same. Both corrected — but the
    fact that it read as obviously-true to two of us is an argument for
    adding it.
  - **Implementation trap:** core.fs itself redefines words while loading —
    `*/` (double-width intermediate), `.` (base-aware), interpreted `s"`/`."`
    (STATE-smart wrappers over the ASM primitives), `.s`. A naive warning
    would spew several lines on every startup. So it must be suppressed while
    loading core.fs (or generally while `included` is running) and only speak
    for interactive definitions — which is also where it is useful.
  - Decide whether `create`/`value`/`constant`/`defer` warn too, and where it
    writes (stdout with the `ok` flow, like other REPL messages).
  - Lessons that redefine on purpose (Graphics redefines `scene`, and any
    edit-a-word flow) should then mention the message — i.e. the shipped docs
    become correct rather than wrong.

- [x] **Settable SDL window title.** Done 2026-07-22 (branch module-hooks),
  exactly as planned below: `sdl-title ( c-addr u -- )` copies into a static
  128-byte `(z-title)` in the dictionary (NOT a `>z` result — SDL only borrows
  the pointer, and that scratch is reused), defaults to `BasicForth`, is sticky
  across `sdl-close` like `sdl-scale`, and calls `SDL_SetWindowTitle` when a
  window is already up so it retitles live. Over-long names truncate to 127
  rather than abort — a title is cosmetic. `sdl-open` now passes `(z-title)`.
  The Bitmaps lesson names its window in `on-start`. Original write-up:

  `sdl-open` hardcoded `s" BasicForth" >z`, so every window was named
  BasicForth; a game should be able to name itself. Brandon's ask 2026-07-20.
  - Prefer `sdl-title ( c-addr u -- )` that works **before or after**
    `sdl-open`: SDL3 has `SDL_SetWindowTitle(window, zaddr)` which can be
    called on a live window, so setting it after open should retitle
    immediately rather than wait for the next open.
  - Needs its own title buffer in the dictionary (say 128 bytes) — do NOT
    hold onto a `>z` result, that scratch buffer is reused and would be
    clobbered. sdl3.fs already hit this and keeps static NUL-terminated
    strings (`(z-wm-ping)`, `(z-off)`) for the same reason.
  - Default stays "BasicForth"; sticky across `sdl-close` like `sdl-scale`.
    Then `examples/bounce.fs` and the lesson windows can title themselves.

- [x] **Binary (1-bit) sprites + a draw colour — `stamp`.** Designed with
  Brandon 2026-07-20, SHIPPED in v0.12.0 (branch `binary-sprites`); this box
  was left unchecked by mistake and closed 2026-07-23. `stamp`, `row,` and the
  Bitmaps lesson are all live; `glyph`/`text` in `font-terminus-8x16.fs` now build on it. The
  design notes below are kept as record (`stamp-scale` has since shipped
  too — 2026-07-24, and fonts were indeed its designated trigger; it landed
  as a word taking `n`, not a sticky value, so the two-composing-scales
  worry below never materialized for sprites). A sprite is a **monochrome
  bitmap** and
  the colour is supplied at draw time: `stamp ( color src x y w h -- )`, with
  0-bits transparent. This is the TI-99/4A model — TMS9918 sprites are 1-bit
  patterns with a per-sprite colour attribute — and TurboForth exposes it as
  `SPRITE ( sprite# y x pattern colour -- )` with `SPRCOL`/`SPRPAT` to change
  either half independently.
  - **The authoring half already works, no new syntax needed.** `%` binary
    literals and `c,` give you the graph paper directly in the source:

        create ship
          %00111100 c,
          %01000010 c,
          %10100101 c,   \ ...one byte per row, 8x8 = 8 bytes

    Verified: `%00111100` is 60. Hex (`$3C c,`) stays available when compact
    beats legible. What's missing is only the *drawing* word.
  - **Fix MSB-first** (leftmost pixel = high bit) so the literal reads as the
    picture, and document it — get it backwards and everyone's art mirrors.
    Row stride is `ceil(w/8)` bytes. Rows in plain reading order: do NOT copy
    TI's 16x16-from-four-8x8-characters column-major quirk, that's a VDP
    artifact. Since `stamp` takes `w h`, any size works.
  - **Memory:** a 16x16 sprite is 32 bytes mono vs 1024 full-colour, 32x
    smaller — a real win against a fixed dictionary, and it means art can
    live in the dictionary instead of needing `allocate`.
  - **Decided: no per-sprite scale initially.** TI's `CALL MAGNIFY` was a
    single global 1-4 (8x8/16x16 x 1x/2x, pixel-doubling — size but not
    resolution), which is the same idea as our `sdl-scale` one layer up.
    `sdl-scale` already delivers the chunky look, and re-authoring a 32-byte
    sprite is cheap, so a `stamp-scale` value only buys "same art at two
    sizes in one frame". Left out to avoid two composing scales confusing
    people (`4 to sdl-scale` + `2 to stamp-scale` = 8x). It is a
    **non-breaking** addition later (a `value` defaulting to 1).
    **Trigger to add it: fonts** — re-authoring a whole font at 2x is not
    cheap, so if `text` wants big/small sizes, that is when it arrives.
  - **Biggest payoff is fonts.** A 1-bit bitmap plus a colour IS a glyph; a
    96-char 8x8 font is 768 bytes. If this lands first, text rendering is a
    thin loop over `stamp` rather than a separate subsystem — worth doing
    before the font item below.
  - Later if profiling wants it: `expand ( color src dst w h -- )` to bake a
    1-bit sprite into a normal 32-bpp one for fast repeated `blit-key`.
    Start with direct drawing; the memory win is the point.

- [x] **Zero-padded numeric output (`u.0r`)** — done 2026-07-22 (branch `u0r`),
  as `: U.0R >r 0 <# #S #> r> over - begin dup 0 > while [char] 0 emit 1-
  repeat drop type ;` beside `U.R` in core.fs — the same word with a different
  pad character. Notes from building it, against the design below:
  - **No BASE save/restore after all.** The note below anticipated a word that
    sets `hex` itself; `u.0r` just follows the current base and leaves it
    alone, which is what makes it work for colors *and* bitmap rows. The
    save/restore pattern still belongs to `h.2`/`h.addr`, which do switch.
  - **The `#` prefix is what makes the motivating example work.** Written as
    `binary inv c@ 8 u.0r`, it fails: in base 2 the width literal `8` has no
    reading. `binary inv c@ #8 u.0r` is correct — `#` forces decimal. Worth
    knowing before reaching for a wrapper word.
  - **`.hex`/`.bits` wrappers were considered and dropped.** They would have
    set the base internally so no `#` was needed, but they buy one character
    over `hex … u.0r decimal` and hide two things the lessons already teach
    (the base words and the `#` prefix). Substrate before sugar; revisit only
    if the explicit form proves annoying in practice.
  - Bitmaps' bit-check now reads `binary inv c@ #8 u.0r decimal` → `00111100`,
    replacing a paragraph that conceded `.` prints `111100`. The old step had
    *two* byte checks (`inv c@ .` → `60`, then the bits); `u.0r` collapses them
    into one, because `00111100` matches the `..####..` you typed and needs no
    apology. That step ran past a page, so it split in two — "A more readable
    way" (the art) and "Same bytes underneath" (the check). "Changing a shape
    later" split the same way, into the `:e` mechanics and "Why the window
    blinked" (the reload/hooks payoff). 17 steps → 19; every step now fits a
    28-row terminal, and only 15/16 spill at 24.

  Original design notes, kept for the reasoning — print a number right-justified
  to a fixed width, padded with **zeros** instead of spaces. Brandon's ask
  (2026-07-20): `hex __ .` prints `FF00FF` but `hex GG .` prints `FF00`, so
  colors won't line up and the channels are hard to read; he wanted `00FF00`.
  - `.` prints the shortest form, so the zeros are gone before you can pad.
    The workaround is pictured numeric output with a fixed count of `#` —
    `0 <# # # # # # # #> type` — which is correct but too much ceremony to
    retype at a prompt, so every user reinvents it.
  - We already ship `.r ( n width -- )` and `u.r ( u width -- )`, both
    **space**-padded (see Language-Reference/Printing.md). A zero-padded
    sibling is the obvious gap; `u.0r ( u width -- )` reads consistently with
    them, though the name is ours, not standard.
  - Implementation is pure Forth on the existing pictured-output words, and
    must save/restore `BASE` (`#` reads it) — a color-printing word that
    leaves the REPL in hex is the classic bug here.
  - Motivating uses: `$RRGGBB` colors at width 6, and 32-bit pixels read with
    `l@` at width 8 (where you also see the unused X byte, `0000FF00`). If
    this lands, the Sprites lesson can use it directly.
  - **Second sighting, 2026-07-20, and the more damaging one:** walking the
    Bitmaps lesson, the obvious way to check a row of art is
    `binary inv c@ . decimal` — which prints `111100`, not `00111100`. The
    lesson has just told the reader that byte *is* `%00111100`, so the check
    that should confirm it appears to contradict it. Bitmap art is 8 bits
    wide by definition; this is exactly where fixed-width output earns its
    keep. `binary inv c@ 8 u.0r` would read as the picture.

- [x] **`help <word>` should name the topic page each entry came from.** Done
  2026-07-22 (branch help-topic-header), as designed below: lazy bold
  `<Topic>:` header + blank line before each file's first matched entry,
  printed by `(hw-head)` with the name passed via `(hw-t)`/`(hw-tn)` (set in
  `(hw-in)` where the dirent name is on the stack; the getdents buffer is
  not re-read while `(page-entry)` runs, so the pointer stays valid). Routed
  through a factored `(pg-count)` so the header's two lines count toward the
  `--more--` pause. Piped output stays escape-free ((attr!) self-gates).
  Original notes: today
  a word lookup drops you into an entry with no sense of where you landed —
  and the topic page is exactly where the related words are. Brandon's ask
  (2026-07-20), after `help allocate` gave no hint that `help Memory` existed.
  - **Decided form: a topic header before the entry**, not a footer, because
    `help <word>` prints entries from EVERY page documenting that word (that
    is how `help begin` shows all three loop forms) — a header labels each
    group at the point you start reading it:

        Memory:

        allocate ( u -- a-addr ior )
        Allocate u bytes. On success a-addr is the block and ior is 0.

  - **Implementation is cheap but has one wrinkle.** `(hw-in)` (core.fs) has
    `name namelen` on the stack exactly where `(page-entry)` reports a hit,
    and `.md` is stripped with a plain `3 -` (see `(collect-in)`). BUT
    `(page-entry)` *streams* — it prints lines as it scans, so it cannot know
    there is a hit until it is already inside the file. So the header must be
    printed **lazily**: on the first heading match, emit the topic name just
    before that heading line. Pass the name in via a variable pair, the way
    `(md-dir)`/`(md-dirn)` already are.
  - Check the pager interaction (`(pg-quit)`) and whether the header should be
    bold; the entry heading itself already renders bold.

- [x] **`catch` / `throw` — recoverable errors** — done 2026-07-21 (branch
  catch-throw), as planned: new asm on both arches + a `handler` chain global.
  `catch ( xt -- 0 | n )` pushes an exception frame on the return stack
  (chain link, DSP, and — standard-required — the input-source spec + file
  error context, so a throw across `evaluate`/`included` leaves the
  interpreter parsing the right buffer); `throw` unwinds to it. `abort` is
  now `-1 throw` and `abort"` throws -2 (so both are catchable; -1/-2 stay
  silent when uncaught, other codes report `uncaught exception: n`).
  Handler-staleness
  rules: `repl_loop` clears per line (covers fault recovery + dict_full),
  `quit`/uncaught-reset clear directly, and the compile-error longjmp walks
  the chain unlinking only frames inside the abandoned region. Guard faults
  and interpreter errors are NOT throws (v1 — noted in Exceptions.md
  scope/next as a possible later mapping to standard codes). Unit +
  integration tests both arches; docs/Exceptions.md, Error_Handling.md,
  `help catch`/`help throw` (Interpreter page), Manual section. Deferred:
  retiring `?`-variants (lessons teach them); a throw out of `included`
  leaks the file mmap/fd (same class as the fault-time include leak above).
  Also fixed en route (found live-testing the Exceptions lesson): `'` of an
  undefined word silently pushed 0, and `catch`/`execute` jumped through it
  — segfault, PC=0, outside the guard pages so no recovery (pre-existing on
  main; a typo'd `' name catch` was the day-one way to hit it). Tick now
  errors `? name` like every other lookup: interpret mode keeps the stack
  (new `.Lcf_longjmp` entry below the compile-state restore), compile mode
  abandons the definition — which also retires the old bogus "unresolved
  control flow" report at `;` after a typo'd tick.

- [x] **`dis` — disassemble a word via `objdump`** — done 2026-07-22
  (`disasm` branch): pure-Forth `src/forth/disasm.fs` (`require disasm.fs`),
  no core changes. Two paths keyed off the header's `CodeLen` field (which
  it turned out already solved the bounding problem — `;`/create/does>
  fill it; primitives carry 0): dictionary words dump `xt..xt+CodeLen` to a
  `mktemp`-made `/tmp` file (0600, unpredictable — no symlink target) and
  decode with `objdump -D -b binary -m <arch> --adjust-vma` (the same shell
  command rm's the file; all spliced paths are shell-quoted); primitives use
  `objdump -d --start-address=<xt>` on the running binary, stopping at the
  next symbol header. The STC payoff works: every call/bl target is
  reverse-looked-up through the LATEST chain and annotated `\ dup`. The
  binary is found via `0 arg` (argv[0], resolved against `(startup-dir)`;
  fallback `readlink /proc/$PPID/exe`) and its arch read from the ELF
  header's `e_machine` — both chosen because a shelled-out child under
  qemu is a *native* process (uname/readlink/PPID all lie); with
  `aarch64-linux-gnu-objdump` preferred for aarch64 targets, `dis` works
  correctly under qemu too. Probes run once on first use and retry until
  they succeed; without objdump it degrades to a one-line message.
  The shell plumbing (quoted command builder, pipe capture, the guarded
  mktemp pattern) was extracted to **`src/forth/shellutil.fs`** — a
  require-able library so future sh-integration tools reuse reviewed code
  instead of re-rolling quoting (see docs/Shelling_Out.md).
  The Machine-Code tutorial lesson (`tutorial machine-code`) shipped
  2026-07-22 — STC, primitives, literals, jumps, the create stub,
  reading `catch`; output described in prose since dict addresses vary
  per session/build. Stage 2 shipped 2026-07-22 (`dis-stage2` branch):
  the dict path now scans for the compiler's two inline-data idioms
  (call lit + value:8; s"-runtime + len:8 + chars, 4-aligned on arm64)
  and lists alternating code spans (objdump --start/--stop-address over
  one temp file) and data spans printed as data — `\ literal: 5`,
  `\ s" hi there"`, and an xt-valued literal named as `\ xt: dup` — so
  listings stay truthful through literals and strings on both arches.
  Idiom addresses self-calibrate at load from two `:noname` probes (read
  back out of their own compiled bytes; failure degrades to whole-range
  stage-1 listings). `see <primitive>` now suggests `dis` alongside
  `help`.
  docs/Disassembler.md, `help tools` entry, Manual section, integration
  tests (skip without objdump / without an aarch64-capable objdump under
  qemu).
- [x] **Include guards + dependency includes (`require`)** — done 2026-07-19
  (`require` branch): `require`/`required` load a file only if not already
  loaded; the ledger is a dictionary sentinel `(inc:<basename>)` defined
  after each successful load (self-heals across `marker`/`new`/`load` — a
  forgotten library is require-able again; no `[defined]`/`[if]` needed).
  Libraries declare their own dependencies (sdl3.fs → ffi+graphics,
  sound.fs → ffi, bounce.fs → sdl3+sound), so one `require sdl3.fs` or
  `include bounce.fs` brings up the whole stack. A second
  `require sdl3.fs` under a live window preserves `sdl-win`/`sdl-scale`
  (tested). Missing files now error — see the Known Bugs entry above.
  One new primitive: `(inc-opened?)`; everything else pure core.fs.
- [x] `BASICFORTH_PATH` colon-separated directory search
  - Supports multiple directories separated by `:` (like PATH,
    LD_LIBRARY_PATH).
  - `BASICFORTH_PATH=/path/to/lib:/path/to/examples`
  - Each directory searched in order when a file is not found in CWD;
    first match wins. Empty segments are skipped.
- [x] Fix `incl_path_buf` for nested INCLUDED calls
  - `forth_included` now saves/restores `file_name_addr`, `file_name_len`,
    and `file_line_num` around the `forth_interpret_line` call, so a nested
    INCLUDE no longer corrupts the parent's error context (it was reporting
    the wrong file AND line).
  - `incl_path_buf` is now scratch-only: on a fallback hit the error name
    stays the original (as-typed) filename rather than the resolved path, so
    no error-reporting state depends on the shared buffer.

---

## Shell-Like Words (pwd / cd / ls / cat / more) — COMPLETE

Navigate and inspect the filesystem from the REPL — hop to another directory
and list or read a file without leaving BasicForth. Most infrastructure already
exists; only `chdir` is a new syscall. See `docs/WildIdeas.md` for the full
write-up. Read-only + navigation first; filesystem mutators (`mkdir`/`rm`/`cp`/
`touch`) are deferred as a separate, riskier class.

- [x] `chdir` platform primitive
  - New syscall wrapper: `SYS_chdir` (80 on x86-64, 49 on ARM64), stubbed in
    both `test_helper_*.s`. Forth bridge `chdir ( c-addr u -- ior )` copies the
    path to a NUL-terminated buffer (over-long → `-ENAMETOOLONG`).
- [x] Capture the startup directory at boot
  - `_start` `getcwd`s into `startup_dir` before `core.fs` loads. `(startup-dir)`
    exposes it. `session.fs` is now pinned to it: `core.fs` builds absolute
    `<startup>/session.fs(.new)` for seed-log / SAVE / RELOAD, so persistence
    never wanders after a `cd`. Regression test guards it.
- [x] `pwd ( -- )` — prints the cwd (← new `(cwd)` primitive over `getcwd`).
- [x] `cd ( "path" -- )` — `chdir` to the parsed token.
  - `cd` with no argument → returns to the startup directory; a failed cd reports
    the offending path.
  - [x] `cd ~` → `$HOME` (`~` / `~/sub` expansion). HOME is captured at boot
    (`(home-dir)`); a leading `~` is expanded in `cd`. HOME unset → `cannot access ~`.
- [x] `ls ( "[dir]" -- )` — list a directory (current by default; optional `<dir>`
    arg supported), one entry per line, skipping `.`/`..` (← `(getdents)`).
- [x] `cat ( "file" -- )` — dump a file to stdout (← chunked `read-file`).
- [x] `more ( "file" -- )` — paged file view (← the existing `page-file` pager).
    Named `more` because `page` already means clear-screen.
- [x] `pushd` / `popd` / `dirs` — a fixed-depth (16) directory stack. `pushd <dir>`
    saves the current dir (absolute) and cd's; `popd` returns to it; `dirs` lists
    current + saved (top first). Stack buffer is heap-allocated lazily.
- [x] Integration tests + docs: `docs/Shell_Words.md` + a "Shell-Like Words"
    Manual section; `platform_chdir`/`platform_getcwd` added to Platform_Layer.md;
    Persistence.md updated for the session.fs startup-dir pin. Documented limit:
    `parse-word` path tokens can't contain spaces in v1.
- [ ] **Design note — rewrite over `sh`, or remove? (2026-07-20)** Question:
    now that `sh` exists, should ls/cat/pwd/cd/etc. shell out to the system
    tools, or be dropped entirely (use `sh` directly)? **Leaning KEEP-NATIVE.**
    These are raw-syscall (getdents/getcwd/chdir/read), so they work with **no
    `/bin/sh` and no coreutils** — exactly what the Phase-7 boot-to-Forth
    appliance (PID 1 / bare metal) needs, where there's no shell to exec. Both
    alternatives couple core navigation to external binaries and move the wrong
    way for that goal. Right model: native words for the core navigation you
    always want; `sh` as the escape hatch to the long tail (grep/sed/find/git)
    the system happens to provide — the two roles don't overlap. Only reconsider
    a word that is BOTH rarely-used AND expensive to maintain. If pursued: audit
    the set against that test, drop any dead weight, document the division in
    Shell_Words.md.

---

## Module System / Forth-as-Shell

The vision: BasicForth as a *shell* with Forth as the shell language — `cd`
around, `load` a module, interact with it live (`.module`, `see`/`edit`/run
words, `save` back). Shipped across v0.9.0 (2026-07-04) and the merges since;
see docs/Persistence.md, Line_Editor.md, Deferred_Words.md, Shelling_Out.md.

### Shipped

- [x] Named modules replace the magic `session.fs`: `save <name>` / bare
  `save`, `load`, `new`, `reload`, `-session`; `.session` renamed `.module`;
  capture turns on with a file argument.
- [x] `uses <word>` — whole-token, case-insensitive reference search across
  the module's sources (capture log or file), the "what do I touch if I
  rename this?" tool.
- [x] Modal `edit <word>`: spawns `$VISUAL`/`$EDITOR`/`vi` on a temp file via
  the new `(system)` primitive (fork/execve/wait4; clone on ARM64), so
  multi-line formatting survives; on save it recompiles the word and
  **propagates** to every transitive caller (STC bakes call targets).
- [x] `sh <command>` — run a shell line from the REPL (transient, not
  captured); `(system)` is the underlying primitive.
- [x] `compact <name>` — deduped, dependency-ordered, definitions-only
  snapshot written next to the append-only `save` file; final `is`/`to`
  bindings preserved. **Since deleted** (`724edd3`, Stage 4 cleanup): the
  file-canonical model made a dedupe-and-reorder snapshot unsound — dedup
  rewires hyper-static bindings, and with mutations splicing the file
  directly nothing accumulates to compact. `save` is replay-faithful by
  design. Rationale in docs/Module_Architecture.md.
- [x] Dirty-guard: `new`/`load`/`bye` prompt "save first? (y/n)" when the
  module has unsaved changes.
- [x] Typed dictionary headers (Flags2 byte: code/defer/value/noname);
  type-checked `is`/`to`; `defer@`/`action-of`; `see` reports a deferred
  word's current binding.
- [x] `:noname` headers — anonymous definitions carry real source metadata
  (empty name, unfindable by construction), so `see`/`compact`/`edit` handle
  `:noname`-bound defers exactly (multi-line included); fixed the multi-line
  group re-evaluation segfault.
- [x] `uses` + edit-propagation treat `:noname` actions first-class: live
  groups reported as `(:noname is <name>)` and re-run on propagation, with a
  guard so superseded groups are never re-fired.
- [x] Tutorial UX: steps clear the screen; `tutorial <name> [step]` and
  `step [n]` jump/replay (a `value` works as a bookmark argument);
  `end-tutorial`; tty-only pager pause; Chase tutorial (24 steps) and
  `examples/game-template.fs`.
- [x] Robustness fixes found by live use: xorshift64 `rnd` (the old LCG's
  low bit alternated), tabs count as whitespace in the tokenizer, `edit`
  with an untouched file is a no-op (vi `:q!` exits 0).

### Next: the editing-workflow arc (planned 2026-07-08)

Motivating find: a plain interactive redefinition (`: helper 200 ;`) does NOT
propagate — callers silently keep the old code (STC bakes call targets; only
`edit` recompiles callers). Worse, it makes the three persistence views
disagree: live behavior and `save`/`reload` keep callers on the old code,
but `compact` emits the latest source at the word's original position, so
callers would bind the NEW code. `:e` closes the gap and becomes the taught
way to redefine. The full symmetry grid:

|                        | inline | $EDITOR         |
|------------------------|--------|-----------------|
| new word               | `:`    | `define <word>` |
| redefine + propagate   | `:e <word>` | `edit <word>` |

- [x] **Step 1a: `define <word>`** — open `$EDITOR` on a template
  (`: word\n    ;`), evaluate + log on exit, exactly the modal-`edit`
  machinery minus the source lookup. Refuse an existing word ("already
  defined — use edit"), symmetric with `edit`'s errors.
- [x] **Step 1b: bare `edit`** (no argument) — open the *current module
  file* in `$EDITOR`; on exit, if the file changed, `reload` it (unchanged →
  no-op, reuse the `(s=)` compare). Dirty-guard first: unsaved captured
  changes would be lost by the reload, so prompt "save first? (y/n)" like
  `load`/`new`. Requires a current module.

Building Step 1b surfaced a simpler model — reload-based editing makes
propagation correct by construction and stops the save file from
accumulating redefinitions. The original Steps 2–4 were re-planned as the
**file-canonical model, AGREED 2026-07-10 in docs/Module_Architecture.md**
(that doc has the full rationale and hard cases). The staged roadmap:

- [x] **Stage 1: splice machinery** — `save` honors bind vs mutate (the
  hyper-static principle, added to Module_Architecture.md during this
  stage): file text and `:` rebindings kept verbatim in order
  (replay-faithful), `edit`-originated mutations (tagged at capture)
  spliced over the binding they edited; `compact` deprecated.
- [x] **Stage 2: `edit <word>` v2** — temp-file UX + splice + reload
  (replaces propagation). The edit targets the word's newest definition in
  the module file, verifies the span still holds the expected text before
  rewriting (atomic .new+rename), and reloads; the dirty-guard runs before
  any reload (non-interactive sessions refuse instead of discarding).
  Deviation from plan: the temp path is module-adjacent (`<module>.edit`,
  removed after) rather than pid-suffixed — no new syscall, and collisions
  then require two sessions editing the SAME module, which is already a
  conflict. Propagation is now uncalled (deleted in Stage 4).
- [x] **Stage 3: `:e <word>`** — inline redefine + splice + reload.
  Mechanism: `:e` validates the target, arms a one-shot completion hook,
  and EVALUATEs ": <name>" so the rest of the input compiles as a normal
  definition; on completion the group (":e" rewritten to ":") splices the
  file and reloads. Splice failure falls back to a plain unsaved binding.
- [x] **Stage 4: cleanup pass** (2026-07-11) — deleted the propagation body
  (`(propagate)`, `(prop-*)`, `(pmd-*)`; `(eval+log)` survives as `define`'s
  back end with its own `(el-src)` scratch), `compact` + helpers, and the
  whole mutation-tag path: with mutations splicing the file directly, no
  capture group is ever tagged, so `(dir-tags)`/`(cap-tag)` and the entire
  splice-save patch machinery (`(sv-*)`) were dead — `save` is now literally
  "write the log verbatim" (the log = seeded file text + appended bindings),
  and the `(save-impl)` indirection and seed-extent records went with it.
  Dropped the 3 compact tests; fixed the stale ?DO-vs-DO asm comments (both
  arches emit identical code — equal bounds zero-trip for both).
- [ ] **Stage 5: `module <file>` + ownership** — `.module` filters by
  SrcId, foreign-word refusal with a hint, dependency edits splice into
  their own file (one reload propagates through the `include` chain).
- [ ] **Stage 6 (gated on use testing): auto-sync** — the file stays in
  sync as you type; explicit `save` and the dirty-guard retire;
  rollback-on-broken-reload if the fix loop proves insufficient.
  Checkpointing convention meanwhile: **git through `sh`**.

### Use-testing queue (Brandon's v0.10.0 notes, 2026-07-13)

- [x] Quick wins (one branch): edit temp file is `<module>.edit.fs` (editors
  filetype-detect Forth); `list` pages the current module file (BASIC's
  LIST, with a dirty-session note); `cancel;` abandons the definition being
  typed (immediate; disarms a pending `:e` — before this, the only cancel
  was typing an undefined word to force an error).
- [x] **Investigated + fixed: session broken after a stack underflow +
  aborted reload** (2026-07-13). Root cause: guard-fault recovery jumps to
  the REPL loop, abandoning whatever multi-step word was in flight.
  Cascade: (open-module) reseeded the log AFTER evaluating, so a faulted
  reload left the log holding the PREVIOUS module — a later `save`
  silently reverted the file, wiping on-disk edits (the reported data
  loss; the repeated "stack underflow" was each bare-edit quit re-running
  the same faulting reload until a save reverted the bad line away along
  with the user's work). Fixed: (1) (open-module) seeds the log BEFORE
  evaluating — save is always file-faithful; (2) `;` and (restore-dict)
  re-anchor the recovery snapshot (both arches), so a fault keeps every
  definition completed before the bad line and a fault after a forget
  can't resurrect forgotten words. Deferred (bounded, needs a fault-time
  cleanup registry): a faulted include leaks its open fd and read
  buffers.
- [x] **Language Reference coverage audit** — entries written (branch
  reference-gaps, 2026-07-18: all 79 gaps closed; survivors are 8 internals:
  hld lit >digit >digit? fill32 einval page-file chdir — the test's
  exclusion list). DONE (branch help-system, 2026-07-18): the regression
  test lives in test_integration.sh ("every word has a Language-Reference
  entry" — live `words` vs `## ` heading tokens), and `binary` is defined
  beside decimal/hex (name `bin` is taken by the file-access modifier).
- [x] **`help` / `tutorials` interface** (design agreed 2026-07-18; SHIPPED
  2026-07-18, branch help-system — all points below as specified, `man` and
  `topics` retired, docs swept, integration tests for all three behaviors):
  - Bare `help`: list every BASICFORTH_DOCS section except Tutorial (which
    gets a "type tutorials" pointer), topics **aligned in ~3 columns**
    (pad names to a fixed field width — the lister already sorts into a
    buffer), plus a 2-line footer: `help <topic>`, `help <word>`.
  - `help <name>`: exact topic match first → print the page **preamble**
    (top of file to the first `## ` heading — title, short intro,
    at-a-glance table); else scan `## ` heading tokens across the
    reference pages → print just that word's entry block (heading to the
    next `## `). Pages are already written to this convention.
  - Topic match folds case AND hyphen/underscore (fixes the old
    `man help-system` cross-reference bug below).
  - New `tutorials` word lists tutorials ("start one with: tutorial <name>").
  - Retire `man` and `topics`; keep `apropos`. Sweep remaining `man <topic>`
    references in docs/ root pages + Manual when the words land
    (Language-Reference already says `help ...`).
- [x] **Markdown-aware pager** (branch markdown-pager, 2026-07-19) — help
  pages and tutorials render on a terminal: headings bold (hashes
  stripped), indented blocks + `` `code` `` cyan, `**bold**` bold,
  `--more--` bar reverse video. Two layers, as planned:
  - *Platform*: one call `platform_text_attr` (semantic codes: 0-15 =
    VGA/QBasic color — full 16, unlike BareMetalForth's 6 — 16 bold,
    17 reverse, 18 reset), ANSI on Linux, self-gated on isatty(stdout);
    `platform_exit` resets attributes. Forth words: `color`/`bold`/
    `reverse`/`normal` (+ `(attr!)` primitive).
  - *Forth*: render pass `(mk-line)` in the `(pg-line)` choke point, gated
    on the new `(otty?)` (stdout tty — NOT `(tty?)`/stdin, so
    `script <in >tty` still renders and `tty> | pipe` never does) and on
    `(mk?)` (help/tutorial pages opt in; `more`/`list` page Forth source
    and stay plain). Piped output byte-identical, enforced by tests both
    ways (pipe suite: no ESC bytes; PTY suite: rendering present).
- [x] **`list` should page the capture log, not the file** (found 2026-07-19
  walking the Arrays lesson): `list` shows the module *file*, so a word
  defined since the last `save` is missing — surprising next to bare
  `edit`, whose dirty-guard save makes it look always-current. Since the
  file-canonical model, the log IS "the file's text plus the lines added
  since", so listing the log shows the always-current view with no
  fidelity loss and retires the `(unsaved changes - save to include
  them)` note. Implementation note: the log lives on the heap, and
  `list` pages a fileid through `page-file` — either give the pager a
  page-from-memory entry point or list the log line-by-line through
  `(pg-line)` directly.

  DONE 2026-07-24 (branch list-log), the page-from-memory option:
  `(page-mem) ( c-addr u -- )` sits beside `page-file` with the same
  screenful loop and `q`, driving `(pg-line)` over slices of the block in
  place — so listed lines are no longer capped at the 256-byte `(pg-buf)`
  the file path copies through. Loop bookkeeping in `(pm-a)`/`(pm-u)`,
  mirroring `(rd-eval-lines)`. Two consequences beyond the filed one:
  the dirty note is gone (nothing left to warn about), and a **scratch
  session can `list`** — the log accumulates from boot whether or not a
  file exists (that is what a bare `save <name>` writes), so you can list
  before you have ever saved, the way BASIC does. Empty log →
  `nothing to list — define a word, or load <name>`. Paging is
  terminal-only, so the pause/`q` paths are PTY tests, not pipe tests.
  Found and fixed en route: a module file with **no trailing newline** ran
  its last line together with the first line captured this session —
  `save` wrote `: tail 2 ;: extra 5 ;`, one unparseable line, real data
  loss. `(seed-log)` now tops up the newline; the log is line-structured
  by contract, and both suites assert it.
- [ ] **`:e`/`edit` dependency re-ordering** (the warning is proving
  annoying): move the fix's later-defined dependencies up to just before
  the edited word; move-to-end when the word has no callers. Design in
  Module_Architecture.md ("Forward references from a mutation").
- [x] **Topic lessons** (branch arrays-lesson, 2026-07-19) — decided lessons
  are just tutorials: same engine, same `tutorial` command, a shorter
  writing style (one idea + one thing to type per step) rather than a new
  word. First lesson: `tutorial Arrays` (`create`/`allot`/`cells`, the
  `nth` idiom, `,`-tables, `erase`, byte arrays — `allot`'s narrative
  home). `tutorials` listing upgraded to show each file's
  `# Name — description` title line, so lessons and projects distinguish
  themselves by description, not by category machinery. Second lesson:
  `tutorial Strings` (branch strings-lesson, 2026-07-19 — the addr/len
  pair, slicing, compare, the transient-buffer gotcha; fixed en route:
  Tutorial dirs now win a `tutorial <name>` clash with a same-named
  reference page). More lessons as needed: files, defer/is, modules,
  FFI/graphics (`require sdl3.fs` makes the setup one line now).
  **`tutorial Modules` DONE 2026-07-25** (branch modules-lesson): 15 steps
  over save → `list` → `:e` → `delete` → `reload` → `uses` → `keep` →
  `on-start`/`booting?` → `new`, built around one score-keeper saved as
  `score.fs`. Writing it paid for itself twice: reading the replay
  transcript (not the pass/fail) caught a step that defined `on-start` and
  reloaded WITHOUT saving — the hook vanished, so the lesson would have
  taught behaviour BasicForth does not have — and a step printing a
  reloaded variable exposed the uninitialised-`variable` bug, fixed on its
  own branch (merge `3fe7970`).
  **`tutorial Printing` DONE 2026-07-26** (branch printing-lesson): 13 steps
  — `.`/`cr`/`space`/`spaces`/`emit`, `.r` columns, `u.0r` as a clock, the
  base gotcha, then pictured output introduced one word at a time (`<# #>`,
  `#s`, `hold`, `#`, `sign`, `holds`) building up to a `money` word printing
  `$12.34`. Scoped against two neighbours: text (`."`, `type`) belongs to
  `tutorial Strings`, bases to `help numbers`. Caught while replaying:
  **`[char]` is compile-only**, so the prompt-level examples need plain
  `char` — which turned into a teaching point, since the lesson already
  contrasts the two inside a definition.
  **`tutorial Sound` DONE 2026-08-07** (branch sound-lesson): 28 steps built
  on one idea — sounds on the *same* channel queue, sounds on *different*
  channels mix — measured rather than asserted (`time` on two tones is 0.65 s,
  on two channels 0.35 s). Then down a level: fill a buffer by hand, `ch-put`
  it, wrap the same bytes in a 44-byte RIFF header and hand them to
  `wav-from`, so the lesson ships no binary asset and `wav-from` earns its
  place. A lesson that hands memory back has to survive its own ending: the
  buffer words carry null guards and the cleanup zeroes what it frees, because
  "your definitions stay" plus a bare `free` is a dangling pointer waiting for
  the reader. Writing it turned up more than it cost: **`abort"` did nothing
  outside a definition** (fixed on its own branch); `snd-open?` read like a
  predicate but *opened*, leaking a device and 16 streams when called as one
  (retired — `snd-open ( -- ior )` with `snd-ready?` as the real predicate);
  and two names that said the wrong thing, **`snd-vol` → `tone-amp`** and
  **`snd-alloc` → `next-ch`**. Plus six documentation errors no suite could
  see, including `>body` claiming `constant` worked and `docs/Sound.md` still
  describing the pre-float-FFI volume implementation. Remaining: files,
  defer/is, FFI/graphics.
- [x] **`.s` ignores BASE** (found 2026-07-16 debugging 1d-life; fixed
  2026-07-19, branch markdown-pager): redefined base-aware in core.fs over
  `depth`/`pick`/`u.r`, same `<3> 1 2 3 ` format (the depth tag follows
  BASE too). Sibling audit: `u. .r u.r` already BASE-aware; `dump`/`h.2`/
  `h.addr` intentionally hex (and save/restore BASE); asm error-message
  line numbers deliberately decimal.
- Rejected: shelling out to the real `man` (our docs are markdown; the
  board may not have man/less; our pager works everywhere).

### Open threads

- [ ] **`(c-callback) ( xt -- fnptr )` — a Forth word C can call** (design note
  in WildIdeas.md, 2026-08-07). The FFI calls outward; this is the missing
  direction. **Not blocked on anything conceptual**: `forth_thread_tramp` is
  already exactly this shape — pthread invokes it as a plain C function and it
  installs a DSP, its own stacks, and a `CATCH` wrapper. What is missing is a
  trampoline with a second signature, stacks that persist across many calls
  rather than one per thread, and an FFI that can hand an address *out*.
  **The reason to want it is a synthesiser, not fades.** Every sound today must
  have a length known before it starts, because `tone` renders the whole thing
  up front. `SDL_SetAudioStreamGetCallback` inverts that: SDL asks for bytes,
  you supply them from one small reused buffer — which makes endless notes,
  live parameter changes, and summed voices expressible at all. Measured
  2026-08-07: Forth generates square-wave samples at **~833x real time**
  (1.2 ms of CPU per second of audio), so the time budget is not the hard part;
  the discipline is (no `allocate`, no blocking, no dictionary writes on
  someone else's real-time thread).
  For **fades specifically this buys nothing** over a plain pump thread — both
  run `snd-pump` off the main thread with identical races. If fades ever do go
  on a callback, use `SDL_AddTimer` rather than the audio callback: the audio
  one holds the stream's lock while `snd-pump` wants to set gains (safety
  unverified), is per-stream, and stops when the device pauses. Either way
  **shutdown is the sharp edge**: `snd-close` destroys 64 streams, and a pump
  already in flight is calling into them. `SDL_RemoveTimer` is not documented
  to wait for a running callback; a Forth pump thread can be stopped and
  `join`ed first, but `join` returns a status and can fail, and a failed join
  means the pump may still be live — in which case `snd-close` must leave the
  streams alone rather than tear down blind (`threads.fs`: "a leak is
  recoverable; a use-after-free is not"). Neither route makes shutdown free;
  the thread at least makes the failure testable.
- [ ] **Heap library — allocation tracking and leak hunting** (design note in
  WildIdeas.md, 2026-08-07). `heap-count` / `heap-bytes` / `.heap`, plus a
  snapshot-run-compare idiom. Measured en route: **the kernel cannot be the
  bookkeeper** — 20 separate 4096-byte `allocate`s add exactly *one* entry to
  `/proc/self/maps`, because adjacent anonymous mappings coalesce, and freeing
  one in the middle pushes the count back up. So tracking belongs with the
  allocator, and the decision is a redefining library (misses everything
  already compiled, including `wavcore`/`sound`) versus two `defer` hooks in
  core (catches all of it for one indirect call). `allocate!`/`free!` were
  considered and **left out** — gforth has neither, and the "use a `variable`
  so `free!` applies" convention trades a once-per-cleanup mistake for a
  once-per-use one.
- [x] **Pipes / output capture** — `open-pipe ( c-addr u fam -- fileid ior )`
  / `close-pipe ( fileid -- wretval wior )` (gforth-compatible) run a command
  with a pipe over its stdout (`r/o`) or stdin (`w/o`); the fileid works with
  the ordinary `read-line`/`write-line`, and `close-pipe` reaps the child and
  returns its exit status. `platform_popen`/`platform_pclose` +
  `(popen)`/`(pclose)`, both arches. Unlocks `history | grep`-style words and
  fzf pickers for `edit`/`load` (still to build, module arc). See
  docs/Shelling_Out.md.
- [x] Ctrl-D exits without the dirty-guard prompt (EOF exits inside
  `platform_key`), so unsaved work can be lost silently.

  Done 2026-07-24 — with a corrected diagnosis: at the interactive REPL
  Ctrl-D was never exiting at all (raw mode delivers byte 4, which the
  editor's ignore-controls branch swallowed); the `platform_key` EOF exit
  only fires for pipes (silent proceed is the documented guard policy) or
  a vanished terminal (nothing to prompt). So nothing was being lost — the
  Ctrl-D affordance was simply missing. Now: Ctrl-D on an empty line (no
  definition open) submits `bye`, echo and all, so it flows through the
  dirty guard exactly like a typed bye; mid-line and while a definition is
  open it stays ignored (continuation text compiles, so a stuffed bye
  would not run). Open-definition detection needs LATEST's F_HIDDEN bit,
  not just STATE — `[` interprets inside an open definition (Codex catch).
  `platform_key` untouched on both arches. PTY tests cover all five paths.
- [x] ~~`man` doesn't map hyphens↔underscores~~ — obsolete: `man` was retired
  in v0.11.0 and its replacement `help <topic>` folds case AND `-`/`_`.

---

## Unix `#!` Script Support

Run a Forth file as an executable Unix script:
`chmod +x foo.fs` then `./foo.fs`, where the file begins with a
`#!/usr/bin/env basicforth` line. The kernel-level shebang mechanism and
command-line file loading already work; these tiers fill the gaps.

- [x] Tier 1 — Skip a leading `#!` shebang line
  - `forth_included` skips a leading `#!` first line (exact two-byte `#!`
    check, so a leading `#` decimal literal is unaffected; the shebang
    counts as line 1 so error line numbers stay accurate). Mirrored on
    x86-64 and ARM64.
  - Scripts that end in `bye` work end-to-end; see `examples/hello.fs`.
- [~] Tier 2 — Run-and-exit flag (no implicit REPL) — DECIDED NOT TO DO
  - The idea: a flag (e.g. `basicforth -s file.fs`) loads the file then exits
    instead of dropping into the REPL, so scripts need no explicit `bye`.
    Shebang form would be `#!/usr/bin/env -S basicforth -s`; no flag keeps
    today's "load then REPL" behavior (used by snake.fs).
  - Decision (2026-06): not worth it. GNU Forth (gforth) has no run-and-exit
    flag either — its documented way to exit after processing is to append
    `-e bye`, i.e. the same `bye` convention we already support. Ending a
    script with `bye` (see `examples/hello.fs`) is the mainstream Forth
    answer and is good enough.
  - The only thing a flag would add over the `bye` convention is clean
    exit-on-error with a non-zero exit status (a script that errors before
    `bye` currently drops into the REPL rather than failing).
  - UPDATE (2026-06): that remaining gap is now closed without a flag. A
    `script_running` flag is set around the startup script load; an error
    during it — a line error returned by INCLUDED, or a fault/ABORT/QUIT that
    recovers into repl_loop — exits non-zero instead of entering the REPL.
    (`rp0` is now initialized before the startup load so a fault there recovers
    onto a valid return stack.) core.fs load errors still drop to the REPL.
- [x] Tier 3 — Script arguments and exit codes  (DONE)
  - Enables writing Unix utilities / filters in Forth (read args + stdin,
    return a status). Both invocation forms give the same argv layout:
    `argv[0]`=interpreter, `argv[1]`=auto-loaded script, `argv[2..]`=user args:
    - `basicforth snake.fs level1.txt`
    - `./snake_start.fs level1.txt`  (shebang launcher that includes snake.fs)
  - Capture the full `argv` vector + `argc` at `_start` (we already save
    `argc` and `argv[1]`); this is startup/asm-word work, NOT a syscall — no
    new platform function needed for arg access.
  - Expose to Forth, mirroring gforth (variables + words) for portability:
    - `argc` — VARIABLE holding the current arg count (`argc @`)
    - `argv` — VARIABLE holding a pointer to the arg vector (`argv @` → char**)
    - `arg ( u -- c-addr u )` — uth arg as a string; `0 0` if out of range
    - `next-arg ( -- c-addr u )` — return arg[1] and consume it; `0 0` when empty
    - `shift-args ( -- )` — delete arg[1], shift the rest left, decrement
      `argc` (O(1): copy arg[0] forward, advance `argv`, dec `argc`)
    - At startup the auto-loaded script is shifted out, so `arg[0]` is the
      interpreter and the first user arg is `arg[1]` / first `next-arg`.
  - `bye-code ( n -- )` — exit with status n, silent (no "Goodbye!") so a
    utility's stdout isn't corrupted; plain `bye` keeps its message. This is
    the ONLY real platform-layer addition (an exit-with-status syscall
    wrapper); also closes the Tier 2 exit-on-error gap.
  - Mirror x86-64 and ARM64. Integration tests (args + `$?`); doc + example
    `examples/echo.fs` (a Forth `echo`).
  - Also added (option 2 of the banner decision): the startup banner now
    prints only when stdout is a terminal, so a utility's piped/redirected
    stdout is clean. New platform calls: `platform_exit`, `platform_isatty`.
  - NOTE: an arg gives you the *string*; reading that data file is separate —
    see Phase 4 (expose file-read words).

---

## Performance / Optimizer

Fallout from the 2026-07-22 count-to-a-billion play session. **The numbers
now live in docs/Performance.md** — re-measured 2026-07-24, best-of-five,
and that page is the one to update when the items below land. Headline for
planning purposes: our `loop` compiles fully inline (pop/pop, inc, cmp, je,
push/push, jmp — index+limit on the hardware return stack), so an empty
counted loop runs at unoptimized-C speed and 2.5× gforth-fast. The per-word
tax is where we lose: **0.84 ns per body word for us** (call/ret +
read-modify-write at `(%r15)`) **vs gforth-fast's 0.45 ns** (dearer
dispatch, but TOS in a register). The lines cross between one and two body
words, so gforth-fast wins from a two-word body on and the gap widens with
length.

- [x] **Docs: a performance note.** DONE 2026-07-24 (branch perf-docs) —
  `docs/Performance.md`: the cross-system table, the `dis` walkthrough of
  all three loop shapes, the body-word scaling series against gforth-fast,
  practical guidance, and the planned optimizer work. Plus a Manual
  section ("How Fast Is It"), and `time <word>` shipped as a built-in so
  the "time it, then `dis` it" demo is two words at the prompt. Two
  findings worth keeping: the honest C++ baseline is `-O0` *matched for
  work* (counter-only 0.36 s vs accumulator 0.47 s — at `-O2` the loop is
  deleted and the benchmark reports 0.00 s), and the per-word tax is
  linear and easy to measure by growing the body with `1+ 1-` pairs.
### DEFERRED — the optimizer path is closed for now (decided 2026-07-25)

**Nothing in this section gets built yet.** Not because the work is wrong,
but because the base underneath it is still moving. Eleven features landed
in the week to 2026-07-25 — fonts, `stamp-scale`, `delete`, the `redefined`
warning, `u.0r`, `list`-pages-the-log, `booting?`, Ctrl-D, `time`, the
require-cycle guard, module lifecycle — and several of them *interact*
(`delete` + `redefined` + `save`; `booting?` + `:e` + `reload`). Each is
tested on its own; the combinations are unproven. Use testing and settling
the interface come first.

The specific hazard is not lost time, it is **ambiguous debugging**: an
optimizer that miscompiles surfaces as "this new feature is broken", and
the hunt starts in the feature, not the compiler. Optimizers want a stable,
well-covered base underneath precisely so a regression tells you which
layer moved. Building one now taxes the debugging of everything else.

**The intent is a dedicated optimisation pass once the feature set settles**
(confirmed 2026-08-16), not a series of opportunistic tweaks. Two consequences
worth acting on when it opens: start by reading what other Forths already do —
see the Mecrisp item at the end of this section — and expect the items here to
share machinery rather than each carry its own, since the inliner and constant
folding both want the same "what did I just compile" state.

**Re-entry conditions** — reopen when *both* hold:

1. The module/editing interface has stopped changing shape (the use-testing
   round below has run and its interface complaints are addressed), and
2. A profile of a **real program** — a game, a robotics loop, not a
   microbenchmark — shows word dispatch among the top costs. `time` shipped
   2026-07-24 precisely so this is cheap to measure. Today's evidence is an
   *empty* 1e9 loop, which is the one case where dispatch dominates because
   nothing else is happening; in a body that does real work the relative tax
   falls, and in a 60 fps frame or a 1 kHz control loop it may not appear at
   all.

Condition 2 is the one to take seriously. If a real profile says dispatch
is irrelevant, this whole section should be closed rather than built.

When it does reopen, the first move is the **registerized `loop`**, not the
inliner: it is local to one construct, copies no machine code, needs no
candidate table, and leaves `dis`'s annotation untouched. Smaller win, far
smaller risk surface.

- [ ] **Peephole inliner: open-code short primitives at the call site.**
  *(Deferred — see above.)*
  `call 1+` becomes `addq $1,(%r15)` — which is 4 bytes where the call is
  5, so the inline form is *smaller* as well as faster. Same for
  dup/drop/swap/over/@/!/lit/+/-/1+/1-/= and friends — a table of copyable
  bodies, or "inline if the primitive is under N bytes and ends in ret".
  Measured payoff: the 0.84 ns/word tax drops toward zero, putting loop
  bodies below gforth-fast at every size (and closing most of the 9×
  begin/until gap to C). Interacts with `dis` (annotator would show fewer
  names) and `see` metadata — keep the capture log source-faithful. Design
  wrinkle to settle first: primitives carry `CodeLen = 0`, which is also
  `dis`'s primitive-vs-dictionary dispatch flag, so body lengths need
  either real CodeLen values (plus a new `dis` rule) or a curated table.
  - **Where it would hook in (read 2026-07-25, good news).** Exactly *one*
    site per arch compiles a normal word reference: `src/arch/x86/core.s`
    ~2171 and `src/arch/arm64/core.s` ~2344, both `compile_call` with the
    xt in hand. The other 15 `compile_call` uses are structural (`lit`,
    `DOES>`, defer stubs, `compile,`) and stay calls. So the change is
    `if inlinable(xt) then emit_body else compile_call` in two places —
    structurally small, not a bolt-on. `see` is unaffected (source comes
    from the capture log, not the code), and redefinition semantics don't
    change, since STC already binds at compile time.
  - **The risk is in the bytes, not the structure.** (a) A curated byte
    table duplicates definitions that live in `core.s`, so editing a
    primitive and forgetting the table yields *silently wrong compiled
    code* — the worst failure class here. Mitigate with a startup (or
    test-time) assertion that each entry matches the real bytes at that
    xt, turning silent drift into a loud failure. (b) Bodies must be
    position-independent: `1+` is fine, but **`lit` cannot be inlined
    naively** — it reads its operand relative to its return address, which
    is the whole trick — and anything with a rip/pc-relative operand or an
    internal call/jmp is out. Per-candidate, per-arch audit, not an
    assumption. (c) Scanning for the terminating `ret` is safe on ARM64
    (fixed-width) but not on x86, where `0xC3` can occur *inside* another
    instruction.
  - **It costs `dis` its readability, and that is a teaching feature here.**
    `call 0x401967  \ 1+` is what the Machine-Code tutorial, docs/
    Disassembler.md and the planned video all rely on; inlining replaces
    named calls with anonymous instructions. Recoverable by annotating
    inlined spans (`\ 1+ (inlined)`), but that is more work inside `dis`'s
    scanner, which already does idiom-splitting. Count it in the price.
- [ ] **Registerized `loop` for empty/rstack-free bodies.** *(Deferred —
  see above; this is the one to do FIRST when the path reopens.)* The emitted
  loop parks index+limit on the return stack every iteration
  (push/push/jmp → pop/pop) solely so `i` works inside the body. When the
  body is empty — or provably never touches the return stack or `i` — keep
  the pair in registers: the loop becomes inc/cmp/jne, which IS the C -O0
  loop. Smaller win than the inliner (0.41 s → ~0.36 s on the empty
  benchmark) but a cute, self-contained peephole.

- [ ] **Constant folding.** *(Deferred — see above.)* `1024 4 *` written in
  ordinary code should compile to `4096`, not to two pushes and a call. This is
  the automatic cousin of `[ 1024 4 * ] literal`, and the distinction is worth
  keeping straight: `[ … ]` is a *semantic escape* — it runs arbitrary code at
  compile time, including a file read — while folding is the compiler noticing
  that operands are already known and a word is pure. They overlap on exactly
  one case, constant arithmetic; neither subsumes the other.
  - **The 2026-08-16 literal change made this cheap.** A number now compiles
    through one choke point, `compile_literal_imm`, which knows the value it
    emitted and how many bytes it took. So a fold is not a compiler pass: keep
    the last one or two (value, address, size) triples, and when a foldable
    word arrives with literals immediately behind it, rewind `HERE` and emit a
    single literal. That is a small amount of compile-time state, in the one
    place that already has it.
  - **Three hazards, in order of how quietly they bite.** (a) *Which words are
    foldable* is a curated list — `+ * and or xor lshift rshift` yes, anything
    touching memory, I/O or the return stack no — and a wrong entry silently
    miscompiles, the same failure class as the inliner's byte table. (b)
    *Boundaries*: the literals must be genuinely adjacent in the instruction
    stream and not jumped into, so a branch target, a `[`, or an immediate word
    between them all forbid the fold. Tracking "what was compiled last" is easy;
    knowing nothing can *arrive* at that address is the real work. (c) `dis`
    readability again — folded code stops resembling the source, which the
    Machine-Code tutorial trades on.
  - **Interaction worth checking early:** folding and the peephole inliner want
    the same "what did I just compile" state, so whichever lands first should
    put that state somewhere the other can use rather than growing its own.

- [ ] **Read other Forths' optimisers before starting the pass.**
  **Mecrisp** (<https://mecrisp.sourceforge.net/>, Matthias Koch) is the one to
  study first: it compiles to native code on small targets and does constant
  folding and peephole optimisation in a compiler that stays remarkably small,
  which is the shape this project wants — not a separate optimising pass over an
  IR, but a compiler that emits better code as it goes. Worth understanding what
  it folds, what it refuses to fold, and how it decides, before designing ours.
  Note the target difference when reading: Mecrisp-Stellaris is Cortex-M, where
  code size and flash matter more than branch prediction, so its trade-offs are
  not automatically ours. gforth's `compile,`-time behaviour and CMForth are the
  other obvious references.

### Measured 2026-08-15 on the Pi 400 — the literal is the engine's slowest step

`tests/bench-locals.fs`, run natively on both arches (ARM64 numbers are the Pi
400 at 1.8 GHz, ondemand but pinned at max throughout; run-to-run spread ~1%).
Per-access, with the shared `drop` subtracted:

| | ARM64 | x86-64 |
|---|---|---|
| local reference | 0.62 ns (~1.1 cyc) | 0.10 ns |
| `dup` | 2.24 ns | 0.82 ns |
| colon call | 1.94 ns | 0.80 ns |
| **LITERAL** | **10.6 ns (~19 cyc)** | **1.68 ns** |
| `variable @` | 15.1 ns | 9.9 ns |
| locals frame, build+release | 27.8 ns | 7.2 ns |

The open-coded reference is vindicated: ~1 cycle, cheaper than the `dup` it
replaces and far cheaper than a call, even at ARM64's 6 instructions to x86's
4. What the trip actually found is below.

**The `LITERAL` row is history as of 2026-08-16.** It is what justified the
work below, and is kept for that reason — but a number now compiles to an
immediate, and the row is indistinguishable from a bare call+ret on both
arches. Re-measured figures are in docs/Locals.md, "The literal was fixed too".
The whole-word locals-vs-juggling result moved by less than the run-to-run
spread, so nothing below needs revisiting.

- [x] **Inline the locals frame instead of calling it.** DONE 2026-08-15
  (branch `locals-frame`): `(lframe,)` emits the build open-coded and
  `compile_local_release` the release, on both arches. Frame build+release
  **27.8 ns → 0.4 ns on ARM64**, 7.2 → 0.4 on x86; the whole-word case went
  15.2 → 6.4 ns on x86, which now BEATS the juggled spelling's 8.6. Verified on
  Pi 400 hardware, not QEMU, since this writes code at run time. **The ARM64
  whole-word case is still 26.0 vs 19.6 and the parts do not explain the
  residual — see the next item.** Original report follows.

  The frame costs 27.8 ns per call on ARM64 and is FLAT in the
  number of locals — a frame of 1 costs what a frame of 3 does. That flatness is
  the tell: the cell count reaches `(lframe)`/`(lunframe)` as a runtime
  `LITERAL`, twice per call, and two literals are ~21 of the 28 ns. The count is
  a compile-time constant, so it should never be pushed at all. Emit the frame
  open-coded, the way references already are: read LP, adjust, straight-line
  moves into the slots, zeros written directly into the `|` slots (each of which
  currently costs its own literal — `{: a | x y z :}` pays three more).
  Consequence today, measured with the same function written both ways:
  `(a+b)*(b+c)` runs **49.0 ns with locals vs 19.6 ns juggled on ARM64**
  (15.2 vs 8.6 on x86), so a word needs ~17 references before locals break even.
  This is NOT an ARM64 defect — x86 has it at 1.8x and the Pi only magnified it
  3.5x. It was invisible because the x86 timing done when locals shipped
  measured *references*, never a whole word.

- [x] ~~**ARM64: a locals word still loses to juggling, and the parts do not say
  why.**~~ EXPLAINED and CLOSED 2026-08-15, not by a fix. Counted rather than
  guessed: the locals spelling is 196 bytes / 49 instructions against the
  juggled one's 36 / 9 plus 3-instruction primitives — 2.1x the instructions
  for 1.35x the time, at *better* IPC. A reference is six instructions on
  ARM64 and **four of them just find LP** (`MRS` + two `ADD`s + load), where
  x86 does it in one `mov %fs:`. That difference is the whole gap.
  **An X20 LP-cache was built and rejected** (branch discarded): references
  6 → 2 instructions, `f-locals` 26.4 → 23.0 ns, code 27% smaller, all Pi
  suites green including fault recovery — and **no measurable change on a
  realistic workload** (an `acc` loop with `to s`: 0.213 s → 0.214 s), because
  real loop bodies are dominated by primitive calls, not references. A
  synthetic row that moves while the workload it stands for does not is the
  signal to stop. Full write-up, including what a *global* X20 reservation
  would and would not buy and why its failure mode is a silent frame leak, is
  in docs/Locals.md. **Reopen only if a real workload shows locals costing
  something on ARM64** — not on the strength of a microbenchmark.

- [x] **Compile a literal as an immediate, not as `call lit` + inline data.**
  DONE 2026-08-16 (branch `literal-immediate`, merge `84cf285`), on both
  arches. A 10M-iteration loop of `i 5 * drop` went **0.172 s → 0.065 s on
  ARM64** and 0.033 → 0.020 on x86; a loop containing a constant is now faster
  than the same loop containing a `dup`, where it used to be two and a half
  times slower. The readers were scoped first as the plan required — `dis` now
  decodes the immediate forms — and `compile_literal`'s *other* job, allocating
  a patchable cell at a known offset for `>body`/`TO`/`IS`/`CREATE`, is
  unchanged: those keep the call form, because there the cell is storage rather
  than a value, which is why docs/Defining_Words.md needed no edit. `[']` and
  `POSTPONE` keep it too, deliberately — they are cold, and `dis` naming what
  they point at (`\ xt: dup`) is what the Machine-Code tutorial teaches. So the
  win is on plain numbers, which is where the volume is. Original report
  follows.
  The single biggest lever in the engine, because literals are in nearly every
  word: every number, `[']`, `postpone literal`. `forth_lit` finds its operand
  through its own return address and returns past it, so **every literal
  mispredicts the return-stack predictor** — that is where the 19 cycles go.
  Emitting "materialise the immediate, bump DSP, store" instead removes the call
  entirely. **This is not the `lit`-cannot-be-inlined case noted above**: that
  rules out copying `lit`'s BODY into the caller, which really is impossible
  since the body depends on the return-address trick. Emitting a different
  instruction sequence has no call and no return address, so the objection does
  not apply. The size is close to free: ARM64 is 12 bytes today (BL + 8-byte
  value) and 12 bytes inlined for a small value (`movz`/`sub`/`str`); on x86 a
  value fitting a signed 32-bit immediate gets *smaller*, and only full 64-bit
  values grow ~4 bytes.
  **Scope the readers of compiled code FIRST.** `dis` decodes the current shape
  by recognising `call lit` plus payload (it prints `\ literal: 3`), and
  anything else that walks compiled code will too — find them all before
  touching the emitter, or every word in the system decompiles wrongly. Same
  class as a message change breaking a consumer keyed to the old format.
  Do this AFTER the frame fix, which proves the inlining machinery on a smaller
  blast radius.

- [ ] **ARM64: `to <local>` looks disproportionately expensive.** Ten
  `a to a` pairs — a reference and a store, both open-coded, no call in either —
  cost **6.5 ns per pair on ARM64 against 0.54 ns on x86**, a 12x gap where the
  reference alone shows only 6x. Either the ARM64 store emitter has a
  pathological sequence (a redundant TLS read? a needless dependency chain?), or
  the row is an artifact of being the one measurement with no `drop` in it and
  so no serialising call between iterations. Not diagnosed — the number is
  recorded here rather than explained. Check the emitted bytes first, and
  re-measure with a `drop` in the loop to separate the two hypotheses before
  changing anything.

## Future / Hardening

- [x] **Sweep the other libraries for public-looking names with no help entry
  — DONE 2026-08-11** (branch helpcov, with the `help`-coverage item above).
  The reference audit only ran over the CORE dictionary, so anything that
  appears after a `require` was invisible to it — `sound.fs` had `snd-dev` and
  `snd-stream`, raw SDL handles with undecorated names and no documentation,
  and nothing noticed. Brandon spotted it by trying `help snd-dev`.
  The audit now loads every `src/forth/*.fs`, with a companion check that
  fails by name if a library is not swept — see the `help`-coverage item for
  why asserting transitive coverage in a comment was not enough.
  The rule applied: a name a user is expected to pass to something is API and
  needs a `##` entry; a handle or an internal SDL enum is `(parenthesised)`.

- [x] ~~**Sweep for `STATE`-only tests that mean "is a definition open".**~~
  DONE 2026-08-16. Every `state` read on both arches was classified. Most are
  legitimate — an IMMEDIATE word choosing compile-vs-interpret behaviour is
  exactly what STATE is for, and so is the locals lookup, since a local does not
  exist at compile time and must NOT resolve inside `[ ]`.
  **Two were bugs, both in error paths that decide whether to abandon a
  definition.** `: foo [ nosuchword` left the partial header alive, so the next
  `:` was refused — naming the wrong word, because the guard reports the name
  being defined and not the one actually open — and only `] ;` could recover,
  while the identical typo one word to the left abandoned the definition
  cleanly. The compile-only path was worse: it jumped straight to the error
  return and never consulted STATE at all, so `: foo [ if` did the same. Both
  now use the two-part test, and the compile-only exit routes through the shared
  abort decision instead of past it.
  **Found while fixing it, NOT fixed, filed below:** an error inside a nested
  `EVALUATE` is swallowed — the line reports ` ok` and a broken word gets
  defined. The first version of the fix made that worse by abandoning the outer
  definition mid-line while the line kept compiling, so the abort is now gated
  to the outermost `interpret_line`.
  **Considered and deliberately kept:** the continuation prompt is STATE-only,
  so `: foo [ ` shows `> ` rather than `... `. That is arguably correct — you
  really are interpreting — and the line editor's scroll margin tracks STATE the
  same way, so changing one would desynchronise the pair.
  Original report follows.

- [ ] ~~Sweep for `STATE`-only tests that mean "is a definition open".~~ Three
  wedges in one week came from conflating them, because `[` interprets *inside*
  an open definition: the definition-open guard (2026-08-10), the locals-list
  clears, and `dict_full`'s rollback (2026-08-13) — the last of which left a
  partial header alive and then refused every subsequent definition, silently.
  The correct test is `STATE` **or** `F_HIDDEN` on LATEST; `main.s` has had the
  right idiom, with the reasoning in a comment, since the ` ok` suppression was
  written. Grep both arches for `state` reads that decide whether to roll back,
  abort, or suppress, and check each against `: t [ … ] ;`.

- [ ] **An error inside a nested `EVALUATE` is swallowed.** Found 2026-08-16
  during the STATE sweep, pre-existing and unrelated to it.
  **Nesting turned out not to be the condition** — see the Up next entry: a
  bare `s" nosuchword" evaluate` at the prompt is silent too, and so is an
  `evaluate` compiled into a definition. The example below is one symptom of a
  wider fault, not the boundary of it. Every abort route is enumerated in
  `docs/Abort_Routes.md`, which is the precondition artifact for the fix.

      : foo 1 [ s" nosuchword" evaluate ] 2 + . ;   \ prints ` ok`

  No `? nosuchword`, no failure — and `foo` is defined, built from whatever
  survived. The nested `interpret_line` returns an error status that `EVALUATE`
  discards, so the outer line carries on as though nothing happened.
  **This is why the STATE-sweep abort had to be gated to the outermost level.**
  Aborting from a nested error tore the enclosing definition down while its own
  line kept compiling into the hole — trading a silent wrong answer for a
  silent vanishing, which is worse. The real fix is propagation: an error inside
  `EVALUATE` should abort the whole line the way one at the top level does, and
  that means `EVALUATE` (and the `INCLUDED` path beside it) passing the status
  up rather than dropping it. Pinned by a test in the meantime, so the current
  behaviour cannot change without someone noticing.

  **The same nesting flaw exists on the compiling arm, and is older.** When
  `STATE` is non-zero the abort is not gated at all, so an error inside a
  nested evaluation rolls back to the *global* anchor and takes the enclosing
  definition with it:

      : foo 1 [ s" : inner nosuchword" evaluate ] 2 + . ;
      \ both foo and inner vanish, silently, and the line still prints ` ok`

  Verified identical before and after the 2026-08-16 sweep, so it is not that
  change's doing — but it is why the gate added there covers only the
  STATE-0 route. Gating this arm as well is NOT the fix: skipping the abort
  would leave a hidden header and `STATE` set, wedging the session harder than
  the bug it avoids. The anchor (`saved_latest`/`saved_here`/`colon_dsp`) is
  global by design — see the recovery-anchor note — so the real repair is the
  same one: propagate the error out of `EVALUATE` so the outer line aborts too,
  rather than trying to unwind one level from the inside.

- [ ] **Is the `incl_entry_latest` guard before `drop_partial_header` dead
  code?** Found 2026-08-16 while making the propagation tests non-vacuous.
  `forth_included`'s unclosed-definition path compares LATEST against
  `incl_entry_latest` before dropping a partial header, so it never unlinks a
  definition inherited from the caller — a case that once segfaulted. Deleting
  that comparison changes no observable behaviour, because the equality test at
  the top of `.Lincl_err_tail` short-circuits first, and it always can: since
  `build_header` refuses the included file's own `:` while a definition is
  open, the file cannot create a header of its own, so LATEST cannot diverge by
  that route. Either the guard is now unreachable and should be deleted with a
  note, or there is a path to it nobody has found — and the second is the one
  worth ruling out first, given the history.
  **The test that was supposed to cover this had been vacuous for months** for
  a related reason: it drove the load with `include`, and the *Forth* `included`
  wrapper refuses outright when a definition is open, so the assembly was never
  reached. It now uses `(included?)`, which bypasses that guard, and says in
  its comment exactly how far its coverage goes.

- [ ] **`SOURCE-ID` answers 0 inside an INCLUDED file.** Found 2026-08-12 while
  gating the locals shadow warning: it returns 0 at the prompt *and* during a
  file load, so it cannot distinguish the two, which is most of what the word
  is for. Forth 2012 says SOURCE-ID is 0 for the user input device, -1 for
  EVALUATE, and a file id when INCLUDED-ing.
  Nothing depends on the broken behaviour today — both the `redefined` and the
  locals shadow warning gate on the internal `cur_source_id`, now reachable
  from Forth as `(loading?)`. So this is a conformance gap rather than a live
  bug, but it is a trap: the obvious word for "am I loading a file" silently
  answers no.
  **Three plausible substitutes are all wrong**, worth recording since each
  looks right under casual testing:
  - `(ldg-n)` is pushed by the *Forth* `included` wrapper, so a script named on
    the command line bypasses it and reads as though someone were typing.
  - `cur_source_id` is SEE metadata from a 64-entry table; `src_register`
    answers 0 once it is full, so the 65th file of a session loads with the
    flag clear. **The `redefined` warning had gated on this for months** and
    would have started firing mid-load on a big enough session.
  - `source-id` itself, per the entry above.

  All three now read `in_load`, a flag `forth_included` sets and restores
  around each file, exposed to Forth as `(loading?)`. It cannot run out and it
  covers every path a file arrives by. Each wrong gate passed a test against
  `included`; only testing the *other* paths — command line, and a session past
  64 files — separated them.

  Two things `in_load` itself needed, both the same shape as bugs the locals
  work already hit:
  - **It is saved on the loader's frame, and an uncaught `THROW` abandons that
    frame.** An aborted load left the flag set for the rest of the session,
    silencing both warnings at the prompt. Cleared on the paths that reset to
    the REPL, exactly like `locals_count`.
  - **`dict_full` reaches the REPL by two routes**, and its "were we
    compiling?" test guards only one. Clearing the flag under that test skipped
    the interpreting case, so a dictionary exhausted mid-load wedged it. Both
    clears are unconditional now. x86 only: ARM64 already had them above.
  - **...and that test was wrong for the ROLLBACK too**, which is the bigger
    find. `[` interprets *inside* an open definition, so a dictionary exhausted
    within `[ … ]` left the partial header alive — and the definition-open
    guard then refused **every later definition**, wedging the session with
    nothing on screen to explain it. A pre-existing bug, older than the locals
    work, exposed only because moving the locals clear raised the question of
    what else that test was guarding. `dict_full` now checks LATEST's hidden
    bit alongside `STATE` and drops the header, as `.Lcf_abort` does. Fixed on
    both arches. This is [[state-is-not-definition-open]] for the third time in
    a week: **"are we compiling" is never the same question as "is a definition
    open"**, and every place that conflates them is a latent wedge.
  - **On x86 the save changed the parity of `forth_included`'s entry pushes**,
    and the line loop counts its own 16-byte alignment from there ("3 pushes +
    an 8-byte pad"). An odd push silently inverts what that padding achieves,
    so the flag is pushed as a pair. ARM64 was unaffected — `STP` is already a
    16-byte pair, which is the rare case where the fixed-width architecture is
    the more forgiving one. Fixing it means returning the file id from the
  loader, and checking `EVALUATE` reports -1 while it is at it.

- [x] **A skip whose reason depends on how the suite was invoked reads as a
  fact about the machine — FIXED 2026-08-16** (branch `2-suite-skip-wording`).
  The integration suite is deliberately
  environment-independent — it never sources `setup.sh` — so the real-engine
  render test skips with `(VOICE_ENGINE_CMD not set)` on a machine that has
  piper installed and working. During the v0.16.0 verification that was read as
  "piper is not on the Pi", and reported as such, when in fact sourcing
  `setup.sh` first makes the test run and PASS: the Pi then matches x86 exactly
  at 1180/1180 with no skips anywhere. Two fixes worth considering, and they
  are not exclusive: word the skip so it names the remedy
  (`VOICE_ENGINE_CMD not set — source setup.sh`), and have the suite derive the
  engine the way `setup.sh` does (`command -v piper`) so the capability, not
  the caller's shell, decides. Found 2026-08-16. The general point is the one
  in `derive-dont-record`: a skip is a claim about the world, and this one was
  really a claim about the command line.

  **Both fixes landed.** The suite derives the engine itself when
  `VOICE_ENGINE_CMD` is unset — `command -v piper`, the same source `setup.sh`
  reads, so the two are independent derivations rather than a copied value and
  cannot drift into pointing at different installs. Three skip reasons replace
  the one: no engine (says to install piper or export the variable), piper but
  no voices directory (names the directory), and the pre-existing double-quote
  case. The voices check is there so a half-finished install skips with the
  missing half named instead of failing a render for what is not a code fault.

  Verified on x86 across all four paths, including the one that matters most:
  with the fix removed the same run SKIPs at 1179 and with it PASSes at 1180,
  so the change is not vacuous.

  **Confirmed on the Pi**, the machine the wrong conclusion was drawn on, with
  the same before/after pair and no `setup.sh` sourced: 1179 and a
  `(VOICE_ENGINE_CMD not set)` skip before, 1180 passed with **zero skips in
  the whole run** after. `~/.local/bin` is on the Pi's non-interactive PATH,
  which is what lets the derivation find piper where the bare variable could
  not.

- [ ] **Audit the integration suite for assertions that cannot fail.**
  `assert_output` matches by substring, and `run_forth` captures the **echoed
  input** along with the output (`> 5 5 <= .` then `-1  ok`). So any assertion
  whose expected text also occurs in its input passes unconditionally —
  `assert_output "x" '-1 1 <= .' "-1"` is green against a completely broken
  `<=`. Multi-line inputs are worse: their `... ` continuation echoes drag in
  whatever the source text contains, which is how a differential test expecting
  `"0"` passed while reporting 7 mismatches (its echo contained `0=`).
  Found 2026-07-30 while negative-testing the new comparison words — the tests
  looked thorough and several were vacuous.
  `assert_result` (strips the echo, then matches) now exists and is used by the
  comparison block; the rest of the suite has **not** been swept. The sweep is
  mechanical: for each `assert_output`, check whether `$expected` is a substring
  of `$input`, and convert the hits. Worth doing as one pass, because a green
  test that cannot fail is worse than a missing one — it is a standing claim
  that something is covered.
  **The stricter follow-up was MEASURED 2026-08-18 and rejected.** Making
  `assert_result` compare exactly rather than by substring sounds obviously
  right and is not. Counting how many of the 216 passing call sites each rule
  would break:

  | rule | breaks | verdict |
  |------|--------|---------|
  | expected must equal a whole line | **205** | dead — every test would have to carry `"  ok"` |
  | expected must start a line | 12 | churn: the 12 are legitimately mid-line (`parse delim` keeps a leading space, `cursor-on` trails ANSI) |
  | output contains an error marker | 14 | noise: 12 of 14 provoke errors deliberately and assert on `-260`, the stack, or abandonment |

  **Do not re-derive this.** Substring matching stays.

  **What IS worth keeping is the fourth rule, as a DETECTOR rather than a
  gate**: flag an assertion whose expected text occurs *only* inside an error
  line. That is the precise shape of the trap. It flags 4; three legitimately
  assert about an error, and the fourth was real — `parse space` asserted
  `hello` and was matching `? hello`, the error saying `hello` is undefined. It
  had never tested `PARSE`. Fixed the same day.

  **The two detectors see different things and neither subsumes the other.**
  The echo detector looks for the needle in the *input*; this one looks for it
  in the *failure*. `hex input` and `parse space` were both invisible to the
  first. Re-run both after a batch of new tests; the recipe for each is above.

  **Sized 2026-08-17** by instrumenting the helper to log whenever
  `$expected` occurred in `$input`, rather than parsing the file: **112 of 525**
  are candidates. Candidates, not verdicts — some still bite for other reasons,
  and each conversion needs the broken-build check before it counts.

  **The PTY suite had the same flaw — SWEPT 2026-08-18** (branch
  `2-pty-sweep`). Of 35 checks, exactly **one** was vacuous: "long line
  submitted whole" asserted the very string it typed, so the echo satisfied it
  and it would have held even if the line were never submitted — the one thing
  it exists to prove. It now types a long line ending in `111111 222222 + .`
  and asserts **333333**, an answer that appears nowhere in the input and that
  only a line delivered *whole* can produce.

  Five more looked suspect to the detector and are sound on inspection, which
  is the useful half of the result: one asserts the redraw after a history
  recall (the editor RE-PRINTING the line is program output, not echo), and
  four read the saved **file**, where the typed text arriving is the point.
  **A needle that was typed is a candidate, never a verdict** — the question is
  always whether the program had to do something to produce it.

  Proven the same way as the shell sweep: type the line but never press Enter,
  and the old needle PASSES while the new one FAILS. `report()` now carries a
  note saying to assert on something the program computes, since a PTY has no
  prompt prefix to strip and so no `assert_result` to hide behind.

  **Not a language problem.** The PTY suite is Python and reproduced the defect
  independently, so rewriting the shell suite in something else would not have
  prevented a single one of these. The fix is echo-stripping helpers and a
  default that is safe.

  **SWEPT 2026-08-17.** All 111 candidates converted; a re-measure reports
  zero. 102 kept passing — they had been matching real output and are now
  safe. **Six were asserting things BasicForth does not do**, and each is worth
  recording, because none is a typo:

  - `define after a stray then` / `... stray loop` expected a definition later
    on the SAME line to run. An abort ends the line, so it never did. Split
    across two lines they test what their names claim — that the session
    survives — and pass.
  - `stray ; inside evaluate` expected `42`, i.e. the calling word running on.
    That was TRUE before the propagation fix merged the same day and false
    after. The test could not notice, so the change went unremarked by the one
    assertion aimed at it. Now split: the error is reported, and the caller
    stops.
  - `hex input` and `hex $ prefix` both wrote `: hex 16 base ! ;`, redefining
    `hex` instead of calling it, so the base never changed. One matched its own
    echo; the other matched the `? FF` error. Now `hex FF . decimal` and
    `$FF .` → `255`, whose answer differs from its input text.
  - `parse no delim` ran `41 parse hello type`, where PARSE with no delimiter
    swallows the rest of the line — including the `type` meant to print it.
    Nothing was ever printed. Split across two lines it types `hello`.

  **Proven non-vacuous, not assumed.** `.(` was broken to print nothing: the
  two `dot-paren` assertions FAIL under `assert_result` and PASS under
  `assert_contains`, same break, same run. That is the whole bug in one
  experiment.

- [ ] **The EVALUATE error-wording bracketing has no probe that still bites.**
  `assert_output "a nested evaluate does not leak its error wording"` worked by
  raising a wording-*less* error after a nested `EVALUATE`, and the only such
  site reachable at run time was `cf_check_tag`. Since 2026-08-11 that site
  sets its own wording, so it overwrites any leak instead of exposing one —
  the test now asserts the wording is right, which is worth having but is not
  what its name claims. To restore the probe, find another site that sets
  `err_token` but not `err_pfx` and is reachable inside one outer token:
  `.Lsq_no_close` (unterminated `s"`) is one; `.Lto_not_found` and
  `.Lpostpone_not_found` are others. Then verify it the only way that counts —
  remove the bracketing and watch the test go red. Noted rather than fixed
  because the honest fix is a new test, not an edit to this one.

- [ ] **A stale binary against a new `core.fs` now produces WRONG OUTPUT, not
  an obvious failure — make the mismatch loud.** Found the hard way
  2026-07-29: Brandon's Dark Star session on `staging` printed everything
  appended to the command line —

      > helloHello World ok
      > 1 2 + .3  ok
      > stackclear? stackclear

  Reproduced exactly by pairing **main's binary with staging's core.fs**, so
  the diagnosis is certain. Cause: the owed-newline change (2026-07-28) split
  one behaviour across both halves — `core.fs`'s line editor stopped emitting
  the newline on Enter, and the binary took over paying it in `platform_emit`
  / `platform_write_fd`. Neither half is wrong alone; mixed versions mean
  *nobody* emits it.

  Two properties make this nastier than the old "stale binary lacks a
  feature" case:
  - **It only shows interactively.** A pipe uses `forth_accept` inside the
    binary, and the old one still echoes the newline — so every suite passes
    while the terminal is visibly broken. Our tests structurally cannot catch
    it.
  - **Three worktrees make it easy to hit.** Merging into `staging` updates
    `src/forth/core.fs` in that tree, but the binary there is whatever `make`
    last produced; `PATH` and `BASICFORTH_PATH` can even come from different
    checkouts.

  Diagnosis today is manual: `basicforth -v` reports `git describe` **at
  build time**, so compare it with `git describe` in the tree
  `BASICFORTH_PATH` points at.

  Fix worth building: **a protocol number, not a version string.** The binary
  exposes a small integer (bump it only when the core.fs↔binary contract
  changes — the owed newline would have been bump #1); `core.fs` asserts it
  is at least what this core.fs expects and otherwise prints one clear line
  ("basicforth: binary is older than core.fs — run make"). One comparison,
  one message, no build-system cleverness, and it stays quiet forever when
  the two match. Comparing full version strings is the wrong shape: they
  differ harmlessly all the time (dirty trees, different tags).

- [ ] Replace `ld -N` with `mprotect` on dict_space at startup
  - Currently we use OMAGIC (`ld -N`) to make all segments RWX so compiled
    code in dict_space can execute.  The proper approach is to keep normal
    segment permissions and call `SYS_mprotect` on just the dict_space pages
    to add PROT_EXEC.  See BareMetalForth Lesson 37 for background.
  - **There is now a performance argument too, not just a hygiene one**
    (measured 2026-07-29, written up in docs/Performance.md): storing into
    a `variable` in a tight loop costs ~28 ns against ~2 ns for `to` on a
    `value`, despite compiling to the same three calls. The store lands in
    a cell adjacent to the stub being executed, in a region that is both
    writable and executable — the pattern a CPU treats as self-modifying
    code, paid for with pipeline machine clears. Moving the store target to
    the heap recovered most of the gap, which supports the mechanism.
    Separating code from data pages is exactly what would remove it, so
    this item may be worth more than its "proper approach" framing suggests.
- [ ] Guard page after dict_space for dictionary overflow detection
  - Currently dict_space uses a software CHECK_DICT macro.  A guard page
    would provide zero-cost hardware detection, consistent with the data
    stack approach.
