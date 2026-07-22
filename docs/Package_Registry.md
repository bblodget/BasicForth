# Package Registry — Design Notes

Status: **design only, nothing implemented** (2026-07-22). This captures the
shape of a package system for sharing user-generated BasicForth libraries and
programs, so the ideas survive until we build it. Nothing here is locked in.

The guiding spirit: sharing a BasicForth package should feel like passing
someone a program listing from a 1980s magazine, not managing a dependency
tree. One file, readable top to bottom, installed by copying.

## What a Package Is

A package is **one `.fs` file**, following three conventions:

1. **A comment header** — human-readable metadata on the opening lines:

        \ dis — disassemble words via objdump
        \ author: Brandon Blodget
        \ version: 0.2
        \ homepage: https://...

2. **The dep block** — after the header, the leading *executable* lines are
   only dependency declarations, ending at the first line that is anything
   else:

        require ffi.fs
        needs-cmd objdump
        needs-lib libSDL3.so.0

   The dep block is the requirements spec, in executable form. No manifest
   file: the metadata *is* the program.

3. **Optionally, a `run:` line** in the header for programs (see below).

A package may ship a help page alongside it — `dis.md` next to `dis.fs`.
Installed docs land on `BASICFORTH_DOCS`, so `help dis` works for
third-party packages with no new machinery.

### Libraries vs programs

Same format, one header line of difference:

        \ invaders — shoot the descending grid
        \ run: invaders

- **Library**: defines words, returns to the prompt. No `run:` line.
- **Program**: has a `run:` line naming its entry word. `run invaders`
  installs it if needed, `require`s it, and executes the entry word.

Avoid the word "module" for these — a *module* in BasicForth already means
the save/load/`:e` unit. Working name: **package** (boring but clear);
programs could get a retro nickname ("carts") later if the games deserve a
first-class category.

### Saved modules are the distribution format

The pipeline for user-generated content is the workflow users already know:

        build your game at the prompt
        save invaders
        publish invaders          \ future word
        ...someone else: install invaders

What `save` writes is already a single self-contained `.fs` file. Sharing
your program *is* sharing your saved module. This is the BASIC-magazine
story in modern form — and it means the fidelity of `save` output is an
ecosystem concern, not just a convenience (see Prerequisites).

## Dependencies

### Between packages: `require` already does it

A package that needs another states it in the dep block: `require ffi.fs`.
Load-once semantics make diamond dependencies safe. No resolver.

### On the system: `needs-cmd` and `needs-lib` (new words)

`require` can't express "objdump must be on PATH" or "libSDL3 must be
installed". Two new words fill the gap, aborting with a friendly message at
load time:

        needs-cmd objdump        \ "dis needs the 'objdump' command (install binutils)"
        needs-lib libSDL3.so.0   \ dlopen probe

`needs-lib` is nearly free given the FFI. `needs-cmd` needs a PATH search
(stat-based, or via the exec primitive below).

### Checking without loading: `deps` (new word)

The same dep block serves two modes:

- **Hard mode** — a real `require dis.fs` runs the block; first failure
  aborts, so a package never half-loads.
- **Soft mode** — `deps dis` reads only the leading dep block from the file
  (without loading the package) and reports *everything* missing at once:

        deps dis
          require ffi.fs          ok (installed)
          needs-cmd objdump       MISSING — install binutils
          needs-lib libSDL3.so.0  ok

One source of truth, two modes, no per-package boilerplate (a per-package
check word would collide in the flat dictionary and depend on authors
remembering to write it). `install` runs the soft check automatically when
it finishes, so "what else do I need?" is answered immediately.

### Dependency rule: main registry only

Packages may declare `require` deps only on **built-in libraries and
main-registry packages** — never on packages from personal registries. The
moment `brandon/dis` can depend on `carol/hexutils`, installs fan out across
trust boundaries and we're building a real dependency solver. If a package
needs a helper from a personal registry, the fix is social: promote the
helper into main first.

### Versioning: resist it

Version pinning, lockfiles, and solvers are where package managers go to
become miserable. For a hobby-scale ecosystem: a header `version:` for
humans, and at most a `needs-basicforth 0.12` word (minimum interpreter
version). If two packages ever truly need different versions of a third,
the single-file model means a user can keep both files. Fine at this scale.

## Local Layout

        ~/.basicforth/
          lib/               installed packages (.fs) — on BASICFORTH_PATH
          docs/              installed help pages (.md) — on BASICFORTH_DOCS
          registries/
            main/            clone of the main registry
            brandon/         clones of any added personal registries

Startup appends `lib/` to `BASICFORTH_PATH` and `docs/` to
`BASICFORTH_DOCS`. "Installed" means: one file copied into `lib/` (plus its
`.md` into `docs/`). "Removed" means: deleted from there. That's the whole
mechanism.

## Registry Repo Layout

A registry is **any git repo** following this layout — the main registry is
special only in curation, not format:

        registry/
          INDEX                    generated by CI — never hand-edited
          REGISTRIES               main registry only: directory of known
                                   community registries (discovery, not trust)
          packages/
            dis/
              dis.fs               the package (header + dep block at top)
              dis.md               optional help page
            invaders/
              invaders.fs          has "\ run: invaders"
              invaders.md
              screenshot.png       optional extras, ignored by install

- **Dir per package**: costs nothing now, leaves room later (screenshots for
  a web gallery, notes) without bending the "install copies one .fs + one
  .md" rule.
- **INDEX**: one small text file — `name | version | run-word-or-'-' |
  one-line description` — regenerated by CI from the package headers. The
  REPL `packages` listing reads only this file, never walks the tree.
- **CI checks** on the main registry enforce the conventions cheaply: header
  present, dep block parses, name matches directory, deps are
  main-registry-only, `save`-format round-trips.
- **Curation**: a PR into the main registry is the review step. That is the
  trust story for main, and it's free.

## Federation: Flat, One Level, Opt-In

Individuals host their own registries (same layout, their own git repo) and
may list them in the main registry's `REGISTRIES` file — a curated *phone
book*, not a resolution mechanism.

- `add-registry brandon <git-url>` clones it under
  `~/.basicforth/registries/brandon/`. Adding a registry is a deliberate,
  named act — **it means trusting that author with code execution** — and is
  never a side effect of installing something else.
- `registries` lists what you've added; the `REGISTRIES` phone book helps
  you *discover* registries, but nothing is cloned until you opt in.
- Name collisions get the Homebrew-taps answer: bare `install snake`
  searches your registries in order (main first); `install brandon/snake`
  disambiguates. No global namespace authority.
- **No deeper hierarchy** (registries pointing at registries): every level
  adds resolver complexity and diffuses trust ("who vouched for this?"), and
  at this scale buys nothing. One curated hub, flat personal spokes.
- The healthy dynamic: a personal registry is your dev channel; when
  something proves out, a PR promotes it into main. Federation funnels good
  work toward the curated center instead of fragmenting the ecosystem.

## Transport: Git Is the Network Layer

BasicForth never speaks HTTP. All fetching is `git clone` / `git pull` on
the registry clones, shelled out via **one new primitive: run an external
command** (working name `exec` / `system` — design open). Everything else is
file words we already have:

        packages                 list INDEX (all added registries)
        install snake            copy .fs into lib/, .md into docs/; then soft-check deps
        remove snake             delete from lib/ and docs/
        run invaders             install if needed, require, execute run: word
        deps dis                 soft-check a package's dep block
        update                   git pull each registry clone
        add-registry name url    clone a personal registry (explicit trust)
        registries               list added registries
        publish invaders         future: copy saved module into your own
                                 registry clone, commit, push (mechanics open)

The exec primitive is the *only* new low-level capability required — and the
`dis` disassembler needs the same primitive for objdump (see TODO), so one
new word serves both features.

## Prerequisites and Open Questions

1. **The `save`-drops-`create`-data bug is upstream of all of this.**
   ~~If saved modules are the distribution format, a shared game whose
   sprite tables were built across lines after a `create` would be
   silently corrupt on someone else's machine.~~ **RESOLVED 2026-07-22**
   (create-data-capture branch): save now captures lines that fill
   dictionary space, so saved modules round-trip their data.
2. **Exec primitive design** — ~~fork/exec + wait, capture output or
   inherit the terminal?~~ **RESOLVED 2026-07-22**: landed as
   `shellutil.fs` (disasm branch) — quoted command composition +
   `open-pipe` capture; `install`/`update`/`publish` should build on it.
3. **`publish` mechanics** — how much git ceremony to hide (commit message?
   push? auth is git's problem, but the UX needs a shape).
4. **Flat-dictionary name collisions** — two packages defining `open`
   collide silently. Curation softens this in main; the real answer arrives
   with the module system ("what does a package export?"). Revisit then.
5. **Naming** — "package" vs something more retro ("cart") for programs.
6. **1.0 relevance** — the package format (header, dep block, registry
   layout) becomes a compatibility surface the moment two people use it.
   It's one of the things a future v1.0.0 would lock; design accordingly,
   ship deliberately.
