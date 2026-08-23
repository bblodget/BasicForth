# Packages — Design Notes

Status: **a sketch, to be corrected by building it.** The dependency words
(`needs-cmd`, `wants-cmd`, `deps`) shipped in August 2026; the user package
directories are the next piece. Nothing about distribution is implemented.

Read the rest as reasoning rather than specification. Most of it has never met
a real package, and the parts that sound most settled are the ones least tested
— several claims here have already had to be walked back once they were checked
against the source rather than against intuition.

**Dark Star is the intended first package**, and deliberately so: it is the
hardest case we have, and it exercises every mechanism below at once. It is
multi-file with committed assets, so it tests include-relative resolution and
asset paths. It holds an SDL window and an audio stream, so it tests the
lifecycle question. It launches, so it tests the entry point. It already lives
in its own repo outside this tree, so it tests the sources model rather than a
monorepo. Expect it to invalidate parts of this document; that is what it is
for. Update the doc from what the implementation teaches, not the other way
around.

The guiding spirit: sharing a BasicForth package should feel like a BBS file
area, not a dependency tree. You browse what a place carries, you download it
because you trust the place, and what you get is source you can read top to
bottom. Discoverability matters — an ecosystem nobody can browse is not an
ecosystem — but it comes *from* trusted sources rather than from a global
index everyone can write to.

The BBS analogy carries its warning with it. File areas were also how trojans
spread, and what worked against that was not a scanner: it was a sysop who
looked at what they hosted, and a small enough community that reputation meant
something. That is the whole of the trust story below.

## Terminology

Five words, each answering exactly one question. They are not synonyms and the
docs should not treat them as such.

| word | means | not to be confused with |
|---|---|---|
| **module** | the words *you* have defined this session, and the file `save` writes | anything to do with distribution |
| **package** | the unit a source distributes and `install` fetches | module |
| **library** | code you `require` — it defines words and returns | program |
| **program** | code with a `run:` entry word — you run it | library |
| **source** | a git repo holding a manifest of packages | the packages themselves |

**"Module" is already taken**, and firmly: `help Modules` opens with *"Your
interactive work is a **module**: the words you've defined on top of core,
which you can write to a file and load back."* There is a shipped lesson, a
Language-Reference page, and `save` / `load` / `new` / `keep` / `on-start`
built on that meaning. Reusing it for distributable code would make the
Modules lesson incoherent, so distributables are **packages**.

**"Registry" is retired.** It described a single curated repo that held package
files. Under the sources model below there is no such thing — there are
sources, one of which happens to be the default. Two words for one concept is
the confusion this table exists to prevent.

### Two independent axes

*Library vs program* says what a file **is**. *Bundled vs installed* says where
it **came from**. They do not interact, which is why no word has to do both
jobs:

|  | **bundled** — ships in the BasicForth repo | **installed** — fetched from a source |
|---|---|---|
| **library** | `sound.fs`, `graphics.fs` | a third-party FFI binding |
| **program** | `examples/snake.fs` | `dark-star` |

## What a Package Is

A package is **one `.fs` entry file**, following three conventions. It may be
*only* that file — the common case, and the one the spirit above is about — or
that file may sit in a repo alongside artwork, sound assets and further `.fs`
files it `require`s. The conventions describe the entry file either way; the
package's manifest entry names which file that is.

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

Neither is a *module* — see Terminology. Programs could get a retro
nickname ("carts") later if the games deserve a first-class category.

#### `run:` is not `on-start`

The module lifecycle hooks already shipped, so it is worth saying why a program
needs a `run:` line as well.

| | `on-start` / `on-stop` | `run:` |
|---|---|---|
| what it is | a word the module defines | a line of header metadata |
| who fires it | the interpreter, automatically | nothing — it names what `run` should call |
| when | `basicforth game.fs`, `load`, and every reload or `:e` | only when a person asks |
| purpose | reacquire resources a rollback stranded | say which word starts the program |

`on-start` exists for the half `keep` cannot cover: a reload rolls the
dictionary back, so an SDL window or an audio stream the old module was holding
is left with no handle to reach it. The hook runs while those handles are still
valid. `booting?` then lets one hook tell a first start from a rebuild:

        : on-start  booting? if  play  then  320 180 sdl-open ;

That is a *lifecycle* answer, not an entry point, and two consequences follow.

**`run` must not be `load`.** `load` is a clean swap — it fires `on-stop`,
asks the dirty-guard, and discards the current module to adopt the file as the
new one. Playing a game should not cost you the session you were working in, so
`run` installs if needed, `require`s, and calls the entry word.

**Which means `on-start` does not fire under `run`.** `(start-hook)` is reached
only from `load` and from the startup-file path; `require` never calls it. So a
game that launches itself with `on-start booting? if play then` — correct for
the `basicforth game.fs` workflow — starts nothing at all when the same file is
installed and run as a package. **Put the launch in the entry word**, and let
`on-start` call that word if you want both workflows. The `run:` line names it
either way, which is also how `packages` knows an entry is a program rather
than a library.

### A saved module becomes a package

The pipeline for user-generated content is the workflow users already know:

        build your game at the prompt
        save invaders
        publish invaders          \ future word
        ...someone else: install invaders

What `save` writes is already a single self-contained `.fs` file, so the
module you built at the prompt *is* the entry file a package needs — no export
step, no build. This is the BASIC-magazine story in modern form, and it means
the fidelity of `save` output is an ecosystem concern rather than a
convenience (see Prerequisites). A package that grows assets grows a repo
around that file; it does not stop being one.

## Dependencies

### Between packages: `require` already does it

A package that needs another states it in the dep block: `require ffi.fs`.
Load-once semantics make diamond dependencies safe. No resolver.

### On the system: `needs-cmd` and `needs-lib` — **shipped** 2026-08-13

`require` can't express "objdump must be on PATH" or "libSDL3 must be
installed". Two words fill the gap, aborting with a friendly message at load
time. The name is one word and the rest of the line is an install hint, cut at
a `\` so an ordinary comment still works:

        needs-cmd objdump         install binutils
        needs-lib libSDL3.so.0    see help install

`needs-lib` probes with a real `dlopen` and keeps the handle for the bind that
follows. `needs-cmd` walks PATH by the shell's rules, and asks both
`faccessat(X_OK)` and `newfstatat` — on a directory, X_OK means "searchable",
so `/bin` passes the first test on its own.

### Requirements a package can live without: `wants-cmd` / `wants-lib` — **shipped** 2026-08-14

Aborting is wrong for a file designed to run without the thing. `disasm.fs`
re-probes for objdump on every `dis`, so installing binutils mid-session works
without a reload; `voice.fs` names piper only as a default `voice-cmd!`
replaces; `speech.fs` answers an `ior`. The soft forms take the same line and
do nothing with it at load time — no probe, no message:

        wants-cmd objdump         install binutils
        wants-lib libflite.so.1   install flite

A soft requirement is a **declaration, not a check**. It exists so `deps` can
report the one optional dependency worth knowing about, and it stays silent
because a file that declares one is a file that is fine without it.

### Checking without loading: `deps` — **shipped** 2026-08-14

The same dep block serves two modes:

- **Hard mode** — a real `require dis.fs` runs the block; first failure
  aborts, so a package never half-loads.
- **Soft mode** — `deps dis` reads only the leading dep block from the file
  (without loading the package) and reports *everything* missing at once:

        deps sdl3.fs
          require ffi.fs            loaded
          require graphics.fs       found
          needs-lib libSDL3.so.0    MISSING -- see help install
        sdl3.fs will not load: 1 requirement missing.

One source of truth, two modes, no per-package boilerplate (a per-package
check word would collide in the flat dictionary and depend on authors
remembering to write it). It is one parser, not two: `deps` re-runs the block
with a mode flag set, and each word takes a reporting branch through the same
parse and the same probe it would use at load time.

`deps` follows `require` into the files named there — the flat answer can lie,
since `require sound.fs  found` is no comfort on a machine where sound.fs
itself cannot load — and prints a nested file's section **only if something in
it is missing**. A file already loaded is not followed: its requirements were
met when it got there.

`install` should run the soft check automatically when it finishes, so "what
else do I need?" is answered immediately.

### Dependency rule: the default source only

Packages may declare `require` deps only on **bundled libraries and packages
from the default source** — never on packages from a source the user added
themselves. The moment `brandon/dis` can depend on `carol/hexutils`, installs
fan out across trust boundaries and we're building a real dependency solver.
If a package needs a helper from someone's personal source, the fix is social:
get the helper into the default source first.

### Versioning: resist it

Version pinning, lockfiles, and solvers are where package managers go to
become miserable. For a hobby-scale ecosystem: a header `version:` for
humans, and at most a `needs-basicforth 0.12` word (minimum interpreter
version). If two packages ever truly need different versions of a third,
the single-file model means a user can keep both files. Fine at this scale.

## Naming rules: filenames below, names above

Two layers, two rules, no exceptions in either.

> **`include`, `require`, `required`, `deps` take a filename.** Filenames carry
> their extension. Paths are allowed.
>
> **`install`, `remove`, `run`, `packages` take a package name.** No extension,
> no paths.

        require dark-star.fs        \ a file, here, now
        install dark-star           \ a package, from a source

The name-to-file mapping is real at the package layer and owned there. It never
leaks downward, so nothing in the file layer has to guess.

This is deliberately stricter than what shipped: `deps sdl3` worked while
`require sdl3` did not, which is a flexibility that costs more than it gives.
The language survey is not encouraging for leniency. C's `#include <stdio.h>`
is a filename, extension and all. C++ has *two* rules — names for the standard
library, filenames for your own headers — and it is a well-known wart that
`import std;` exists to end. Python's `import math` is not a filename at all;
it is an identifier, and the loader owns the mapping to a `.py`, a `.so`, a
package directory or a zip entry — which is precisely the package layer above,
not the file layer. Ruby's optional extension is routinely confusing, and Node
made extensions optional, grew a baroque resolver, and then **re-imposed
mandatory extensions for ESM**. Forth 2012 sits with C: `INCLUDED ( c-addr u )`
takes a filename.

`INCLUDED` and `REQUIRED` — the `( c-addr u )` words — stay strict in every
case. Retrying a filename a program computed with a suffix appended would be
both surprising and non-standard. The leniency, where it exists, belongs to the
parsing words.

**`where` bridges the layers.** Strictness only costs something if finding the
filename is work:

        > where dis
        disasm.fs
        > deps disasm.fs

`where` reads the per-word source metadata `see` already uses, so it answers
with exactly the argument the file words want. It is also the honest answer to
*"am I running my working copy or the installed one?"* — the question that
bites everyone who develops a package they have also installed.

## Local Layout

        ~/.basicforth/                  $BASICFORTH_PACKAGES overrides this root
          lib/<package>/                the package's files -> BASICFORTH_PATH
          docs/Packages/                reference pages   -> BASICFORTH_DOCS
          docs/Tutorials/               lessons           -> BASICFORTH_DOCS
          packages/<name>/              the package's cloned repo
          sources                       the source list
          installed                     the install manifest
          index                         cached package index

**Shipped 2026-08-19**, the three directories above the line. The rest is still
design.

Startup appends each of those four directories to the matching variable, if it
exists. `$BASICFORTH_PACKAGES` names the root; failing that `$HOME/.basicforth`;
failing that the whole mechanism sits out, which is what makes a run under
`env -i` — and every test suite — unaffected.

**The docs directories are named for the role they play**, and that is not
cosmetic. The help system decides a directory's *role* from its **basename**:

        : (lessons-sub) ( -- c-addr u )  s" docs/Tutorials" ;
        : (lessons?) ( dir-a dir-u -- flag )
            (basename) (lessons-sub) (basename) (ci=) ;
        : (tuts-in) ( dir-addr dir-u -- )    \ tutorials: only the lessons sections
            2dup (lessons?) 0= if 2drop exit then

A directory called `Tutorials` holds lessons and is skipped by `help`'s topic
listing; anything else is a reference section displayed under its basename. So a
package ships its lesson into `docs/Tutorials/` and its page into
`docs/Packages/`, and `help`, `tutorials` and `tutorial <Name>` all work with no
new machinery. A single flat `docs/` would have shown up in `help` as a section
named "docs" and could never have carried a lesson at all.

**The reference directory is `Packages`, not a mirror of `Language-Reference`.**
Mirroring was built first and the output settled it: `help` iterates
*directories*, not section names, so a second directory called
`Language-Reference` printed that heading twice and read as a bug. A section of
its own also attributes what it lists, which matters because a topic collision
**appends** rather than shadows — `help sound` can print a bundled page and an
installed one, and you want to see which is which. Package pages therefore take
the Language-Reference shape, `## word ( stack )`, rather than the single-word
Guides shape.

**Append, never prepend.** The resulting search order is:

1. the current directory (for `require`)
2. `BASICFORTH_PATH` — the environment, or the install tree derived from
   `/proc/self/exe`
3. `~/.basicforth/lib`

An installed package therefore cannot shadow a bundled library, a package page
cannot shadow a bundled help topic, and a package lesson cannot shadow a
bundled lesson — one rule covering code and docs alike. The precedent is
`dice.fs`, which redefined `seed` for months without anyone noticing.

**Local development falls out of it.** Working in `~/Dev/dark-star`, the
current directory wins, so you get your working tree. A checkout with
`setup.sh` sourced keeps using the checkout. `$BASICFORTH_PACKAGES` points the
whole user tree at a scratch directory when you want to test the installed
path without disturbing your own. The one trap — you `cd` elsewhere and
silently get the installed copy — is what `where` answers today, and what a
`link`-style development install would fix properly later.

## Sources

A **source** is a git repo containing a manifest of packages. The model is
apt's `/etc/apt/sources.list`: a list of places you have chosen to trust, each
of which advertises what it carries.

        ~/.basicforth/sources
        default   https://github.com/basicforth/packages
        brandon   https://github.com/bblodget/basicforth-packages

The manifest inside a source lists packages, and **each entry points at the
package's own git repo**:

        \ name      repo                                        commit (full SHA)  run
        dark-star   https://github.com/bblodget/basicforth-dark-star  4f1c9a2be7d0518c3a6b8e94d217f0c5a83be612  dark-star
        hexutils    https://github.com/carol/hexutils            b83d17e6a05c9f24178be3d0c916a4f7e25b8d31  -

### Why packages live in their own repos

The earlier design put package files *inside* the registry repo, one directory
each. That breaks on the first real program. Dark Star has its own history, its
own issues, and fourteen committed speech WAVs; "install copies one `.fs` and
one `.md`" cannot express it, and folding it into someone else's tree throws
away everything that makes it a project.

It also fixes publishing. Under a monorepo, shipping means opening a PR against
a repo you do not own. Here you push your own repo and add one line to your own
manifest — ask-permission becomes just-do-it, which is the right default for a
hobby ecosystem.

### Multi-file packages need a resolution rule we do not have

> **Shipped 2026-08-20.** Beside-first resolution, `my-dir` and `path-join` all
> landed; Dark Star runs installed, from any directory, with its fourteen WAVs.
> The section below is the reasoning that produced them, kept because it also
> explains the ordering. One correction from building it is in item 8: the
> resolution does **not** read through a symlink, and the install layout is
> what makes that a non-issue.


**This is a prerequisite, not a detail.** Today `include` resolves a name
against the current directory, then each `BASICFORTH_PATH` segment, and nothing
else — there is no include-relative rule:

        .Lincl_open_err:                \ core.s -- CWD was already tried above
            mov basicforth_path(%rip), %rbp

Dark Star works right now only because you `cd` into its directory first, which
makes CWD the package directory by accident. Install it and the accident goes
away: `lib/dark-star.fs` runs `require art.fs`, the search looks in whatever
directory the user is standing in and then in `lib/` — and `art.fs` is in
`packages/dark-star/`, so it fails. Assets are worse, because a WAV is opened
by a literal relative path with no search at all.

Adding each package directory to `BASICFORTH_PATH` is not the answer; the path
would grow without bound and every package's internals would become globally
visible. Two mechanisms are needed instead, and both are ordinary:

1. **Include-relative resolution**, and it must come **first**. When a file
   `require`s something, try the directory of the file *currently being
   included*, then the current directory, then `BASICFORTH_PATH`. This is C's
   rule for `#include "..."`, Ruby's `require_relative`, and what Python
   package-relative imports do.

   The tempting order is CWD first, on the grounds that it is strictly additive
   and cannot disturb anything that works today. That argument does not
   survive contact: **the two orders agree in every case that currently
   works.** A file that requires a sibling while you are standing in its
   directory resolves identically either way, because the file's directory *is*
   the current directory. They diverge only when the two differ and both hold
   the name — which is precisely the hijack, not a case worth preserving.

   And the hijack is not hypothetical. `core.fs` records it happening:

        (This is not hypothetical; a user module named font.fs in the launch
        directory shadowed the library of the same name and required itself.)

   That one recursed until the data stack hit its guard page. Package internals
   carry exactly the names that collide — `art.fs`, `util.fs`, `level.fs`,
   `sound.fs` — so with CWD first, running an installed package from your own
   working directory is a coin flip on whose file it gets.

   What the strict order gives up is overriding a package's internals by
   standing in a directory. That is a development gesture, and a `link`-style
   install is the right mechanism for it; hijack-by-chdir is not. A `require`
   typed at the prompt is unaffected either way — there is no including file,
   so it is CWD then `BASICFORTH_PATH`, exactly as today.

2. **A word for the loading file's own directory**, so a package can build
   absolute asset paths at load time rather than hoping about CWD.
   `(source-path)` and `(cur-file@)` already carry what it needs.

Both are engine work — the search loop is in assembly — and `install` cannot
ship before them. The earlier monorepo design never met this because it defined
a package as a single file that was copied to a single flat directory.

### No phone book

An earlier draft had the main registry carry a `REGISTRIES` file listing other
people's registries, described as "discovery, not trust". That disclaimer
cannot do the work asked of it: a listing inside the official repo reads as an
endorsement no matter what the text beside it says. So there is no directory of
other people's sources. **People advertise their own** — in a README, on the
project site, in a forum post — and adding one is unambiguously the user's own
act.

**But one default source ships preconfigured.** apt does not hand you an empty
`sources.list`; it points at debian.org. A new user types `packages` and sees
something, which is the on-ramp. Everything beyond that is opt-in.

### Trust, and why the commit is pinned

Be clear-eyed about what this model gives up. In a monorepo, the curator
reviews the actual code in a pull request. Here the curator vouches for a
*URL*, and the code behind it can change afterwards without them knowing —
the AUR problem.

**A pinned commit is what restores it — and it must be a full commit SHA, not
a tag.** A tag is a mutable pointer the package author can move at any time, so
pinning one pins nothing; an abbreviated SHA is a prefix, not an identity. A
full SHA is content-addressed: git verifies it on checkout, so the tree the
curator read is provably the tree that runs, and moving to a newer one is a
deliberate edit to the manifest rather than something that happens to you.

That is the *only* guarantee in this design that a mechanism actually
enforces. Everything else below is a matter of someone having looked.

### What "approved" means in the default source

Curation is the sysop's job, and it should be a *reading*, not a rubber stamp.
BasicForth is unusually well placed for this: a package is small, single-file
where it can be, plain source with no build step, no minification and no binary
blobs. Someone — or something — can genuinely read the whole thing. That is a
structural advantage over ecosystems where review means auditing a tarball
nobody opens.

**Declare capabilities, and declare them for the whole package.** The dep block
already says what a package needs from the machine; capabilities are the same
idea one step on — what it *touches*:

        Uses:      file-write (~/.basicforth)
        Unbounded: shell-out (git)

**Two tiers, and which tier a thing goes in is the whole point.** Revised
2026-08-23. An earlier version was one flat list with `ffi` in it beside
`file-read`, as though they described the same kind of thing.

A **bounded** capability is an effect the language mediates, so the declaration
can be close to complete: `file-read`, `file-write`, `network`. A qualifier
carries most of the information — `file-write (~/.basicforth)` is a very
different claim from `file-write` unqualified.

An **unbounded** capability escapes the language entirely. Anything reachable
this way can do everything on the bounded list without touching a single word
that would show up in it:

- **`ffi`** — `dlopen` plus a call to an arbitrary symbol. Opens sockets and
  writes files without using a network or file word.
- **`shell-out`** — `system` or `open-pipe`. Runs any program, which can do
  anything the user can. No symbol lookup required; it is the *easier* escape
  of the two.
- **`evaluate` over text the package did not write** — computed source, so a
  scanner cannot see what will run.

        Uses:      file-read
        Unbounded: ffi (libSDL3.so.0, libflite.so.1), shell-out (piper)

**The tier is promoted out of `Uses` because it bounds what `Uses` is worth.**
A package with an empty `Unbounded:` line has made claims the language can
mostly keep; one with anything on it has made claims that are a courtesy. That
distinction is the single most useful thing a reader can be told, and a flat
list hides it — every entry then carries the same unstated caveat, so the
caveat stops meaning anything.

**A qualifier there is intent, not a limit.** `shell-out (git)` says what the
author meant to run; it does not stop the package running something else, and
`ffi (libSDL3.so.0)` does not stop it dlopening anything else. The
parenthetical is useful — it tells a reader what to expect and what to check —
but it must not be read as a bound, which is exactly the mistake an earlier
draft of this section made by leaving `shell-out` in the bounded tier because
it *looked* qualified.

Naming the specifics costs nothing extra: the libraries are already in the dep
block as `needs-lib`, and the commands as `needs-cmd`.

**The declaration covers effective behaviour, not one file's text.** If a
package `require`s something that shells out, the package shells out and must
say so. A user asking "will this thing run commands on my machine?" is asking
about the thing they installed, not about which file the call happens to sit
in, and a declaration scoped to one file would let a package disclaim
everything by moving it one `require` away. That would make the line worse than
useless: it would be a disclaimer wearing the costume of a disclosure.

This is why **bundled libraries need capability lines too** — `shellutil.fs`
and `disasm.fs` shell out, `sdl3.fs` and `sound.fs` open native code — since a
package's declaration is only as good as what it can inherit and restate.

The obvious operations are a short list — shelling out (`shellutil.fs`,
`open-pipe`), native code (FFI, `dlopen`), file writes and removals, network
access, and `evaluate` over text the package did not write — though it is a
list of what we have thought of, not a closed set. Keep it short: Android's
permissions became noise because there were too many and each was vague, and
this design's advantage is that the list is small and the source is readable.

**Prefer deriving it to trusting it, and be honest about the limit.** A
declaration is forgettable — the `dark-star` entry declared `-`, meaning plain
Forth, while requiring SDL3 and shipping a shell-out — so the useful check is
mechanical: scan a package's files, transitively, for those names and compare
the result with what it declared. Cheap, and it catches the honest mistake,
which is the common one.

It cannot be a guarantee. Forth resolves words at run time and can `evaluate`
text it computed, so a determined author can put anything beyond the reach of a
scanner; and once anything on the unbounded tier is in play, the language is
not the boundary at all.
Three levels, and it is worth not confusing them:

- **the declaration** — cheap, and only as good as the author's care
- **a static scan** — catches forgetfulness, not evasion; the right tool for
  curation, and the one that would have caught the `dark-star` entry
- **runtime enforcement** — would need a real sandbox, and FFI defeats it

So the scan is a curator's aid and a cross-check, not a proof. What makes the
model work is still that the code is small and someone reads it.

**It is triage, not a test.** It says where to look first. It does not decide
anything, and both directions are weak:

- **A clean scan means nothing obvious turned up.** Forth is close to the worst
  case for static analysis: word names can be built at run time and reached
  through `evaluate` or `find`/`execute`, a name can be assembled byte by byte,
  the dictionary can be walked and an xt executed without the name ever
  appearing, and immediate words run during compilation. Nothing stops a
  package from calling `open-pipe` with the string `open-pipe` nowhere in its
  source.
- **A hit is not a finding either.** A token in the source is not a call. It
  may sit in a comment, in a string the package prints, or inside a name the
  package defines itself. And the commonest cause of a genuine mismatch is not
  deceit but a declaration the author forgot to update — which is worth a
  question, not an accusation.
- **The scan is file-local; the declaration is not.** That asymmetry is
  deliberate, and it means the two differ in normal, honest cases: a package
  that declares `shell-out` because a dependency does it will show nothing in
  its own text. A declaration *broader* than the file's own scan is therefore
  expected and is not a signal. Only the other direction — the file plainly
  reaching for something the declaration omits — is worth a question.

One part of this *is* mechanically checkable, because a package may only depend
on bundled libraries and default-source packages, so every dependency has a
declaration. A tool can compose the declared capabilities of everything a
package loads and check that the package's own line covers the union — which
catches the common, honest failure: a package that gained a dependency and
forgot to widen its declaration.

**It cannot reuse `deps`' traversal to do it.** `deps` stops at a file that is
already in memory:

        2dup (inc-recorded?) if                 \ in memory: its own deps were met
            s" loaded" (dp-okw!)  true (dp-line)  exit  then

That file is reported and never queued, so `deps` does not descend into it.
This is correct for the question `deps` asks — *can this load here, now* — where
an already-loaded file has demonstrably met its own requirements. It is wrong
for capability composition, which is a property of the package rather than of
the session: reuse that walk and the union silently shrinks to whatever the
reviewer had not already loaded, reporting "clean" for the worst reason.

So the union needs a traversal that ignores what is loaded, and the check must
run in a **fresh interpreter** — which curation would want regardless, since a
reviewer's session state must not be able to influence a verdict. Same
dependency graph, different traversal rule, and the difference is invisible if
nobody writes it down.

What stays uncheckable is a file doing something it never declared. So the
capability line is **documentation, not a control**. Its value is that it gives
a reader a stated intent to read *against*, and it makes a deliberate lie
something a person can point at afterwards. That is worth having. It is not
worth reporting as a check that passed.

**An AI review is a reasonable part of the gate, and should be described as
what it is.** Having an assistant read a candidate package before it enters the
default source is a good use of the tool: the source is plain and unminified,
the idioms are few, and "does this do what its header claims, and is anything
here obfuscated" is a question worth asking of every line. Two limits belong
next to that:

- **It is not a guarantee**, and it must not be presented to users as one.
  Record what was checked, not a verdict — *"reviewed at commit `4f1c9a2be7d0...`;
  shells out to git, no FFI, no writes outside its own directory"* stays true
  and checkable, where *"this package is safe"* rots the moment anything
  changes.
- **A reviewing model is itself an attack surface.** A package author can write
  text in a comment aimed at whatever reads the file. The file is read as data,
  never as instructions — and a reviewer who has observed something does not
  get talked out of it by prose in the file claiming otherwise. (This does not
  make the scan the senior partner; per above it decides nothing. It means
  neither the scan nor the narrative gets to overrule what was actually read.)

**The review attaches to a commit, not to a name** — which is the second reason
the manifest pins one. "Approved" means *this tree was read*, so a version bump
is a new reading, and `update` showing `git log <old>..<new>` is what tells a
user their reviewed tree has moved.

### What none of this provides

Stated plainly, so no later reader has to infer it:

- **There is no sandbox.** A package is `require`d into the same flat
  dictionary as everything else, with the same access to the FFI, the shell and
  the filesystem that any other Forth source has. `install` cannot restrict a
  package's capabilities, and no mechanism proposed here changes that.
- **A review is a reading, not a proof.** It covers the tree that was read, by
  whoever read it, to whatever depth they went.
- **The multi-file repo cuts against reviewability**, and honestly so. "One
  file you can read top to bottom" was the earlier design's premise; a package
  that is a repo with assets and several `.fs` files is more work to read, and
  the review burden scales with it. A default source may reasonably prefer
  small packages for exactly this reason.

What *is* enforced is narrow and worth keeping straight: the pinned SHA makes
"the tree that was read" and "the tree that runs" the same tree. Everything
else is people looking at code.

For sources the user added themselves, none of this is enforced and the doc
should not pretend otherwise. What we can do is **recommend** reading a package
before first running it, and note that handing it to an AI assistant is one
practical way to do that — engine-neutral, the way `voice.fs` takes any speech
engine rather than binding to one. Adding a source is already the moment the
user chooses whom to trust; the recommendation just says out loud that the
choice was real.

### Name collisions across sources

Bare `install snake` searches sources in listed order, default first;
`install brandon/snake` disambiguates. That is the Homebrew taps answer, and
Homebrew's own experience is the warning: bare-name resolution got messy enough
that they now require the full tap name outside core. The failure is not the
collision you can see — it is that the default source drops `snake`, and your
next `update` silently repoints a bare `snake` at somebody else's different
package.

**The install manifest is what prevents that.** `~/.basicforth/installed`
records, per package, where it came from:

        \ name       source    version   commit
        dark-star    brandon   1.2       4f1c9a2be7d0518c3a6b8e94d217f0c5a83be612

Without it, "installed" means only *files are present in `lib/`*, and then
`update` cannot say which of your packages have new versions, `remove` cannot
tell a package from a file you dropped in by hand, and nothing records which
source you actually got. With it, all three are well defined and resolution
never switches sources behind your back.

## Transport: Git Is the Network Layer

BasicForth never speaks HTTP. Fetching is `git clone` / `git pull`, shelled out
through `shellutil.fs`, which already provides quoted command composition,
`(cmd-run)`, `(cmd-open)` capture and `(sh-rm)`. There is no `delete-file` or
`mkdir` primitive, so `cp`, `rm` and `mkdir -p` shell out the same way.

**No assembly work is required for any of this.** The one engine-level piece
the whole arc needs is the user package directories above; everything else is
Forth over `shellutil.fs` and git. That makes the distribution design cheap to
build and cheap to change our minds about.

        packages                 list what the sources carry
        search <term>            match against cached descriptions
        install <name>           fetch a package and link it into lib/ and docs/
        remove <name>            unlink it and drop it from the manifest
        run <name>               install if needed, require, execute the run word
        update                   git pull each source, and report what changed
        add-source <name> <url>  add a source (an explicit act of trust)
        sources                  list added sources
        publish <name>           stage a package into your own source clone

### `update` is the supply-chain surface, and must not be silent

`add-source` is the trust decision, granted once — and `update` then pulls new
code under that grant forever. That is how supply-chain compromises land in
every ecosystem that has had one.

The fix is nearly free, because git is already there: **`update` prints
`git log --oneline <old>..<new>` for each source that moved.** A silent code
update becomes a reviewable one at zero infrastructure cost. Together with the
pinned commit in the manifest and the recorded commit in `installed`, that also
gives reproducibility without a lockfile or a solver: reinstalling exactly what
you had is one `git checkout`.

### `publish` never pushes

`publish <name>` copies the package into your own source clone, writes the
manifest entry, and commits — then **stops and prints the `git push` for you to
run**. The irreversible outward-facing step belongs to the human.

### The index is a client-side cache

An earlier draft had CI generate an `INDEX` file inside the registry. Personal
sources have no CI, so that needs either a second code path or a chore. Invert
it: **the client builds the index locally when it updates**, caching it in
`~/.basicforth/index`.

One code path serves every source, a source's own CI-generated index becomes a
pure optimisation, and a spoofing surface closes — a source can no longer
describe a package as one thing in an index while shipping another in the
`.fs`.

## What Stays in the BasicForth Repo

> **The repo ships what its own tests and lessons depend on.**

Measured 2026-08-18: all sixteen files in `src/forth/` are referenced by a
lesson, a suite, or an example. There are no orphans, and 412K total. Nothing
moves out.

Three reasons, in increasing order of importance:

1. **Coverage.** The integration suite has SDL, sound and speech sections.
   Move those files out and either the suite loses the coverage or the repo has
   to install a package in order to test itself.
2. **The on-ramp.** `tutorial Graphics`, `Sprites`, `Bitmaps`, `Fonts` and
   `Sound` all `require` bundled libraries. As packages, every one of those
   lessons gains an install step and stops working offline — against the
   standing rule that a lesson's promised output must hold in every environment
   it claims to support.
3. **Version skew.** These files are welded to the engine: FFI offsets, `>z`,
   the audio primitives. A stale binary against a newer `core.fs` already
   produces silently wrong output that no suite catches. Independently
   versioned packages would multiply that failure mode by twelve, with a
   network fetch in the middle.

So moving them out would not dogfood the package system; it would strip the
safety net off twelve files at once. **The right first package is Dark Star** —
already outside the repo, a program rather than a library, and carrying the
multi-file shape that proves the sources model works.

The forward-looking half of the rule: a **new** library that no lesson teaches
and no suite tests should start life as a package, not in `src/forth/`. The
rule then says when it has earned promotion into the repo — when a lesson or a
suite starts depending on it.

## Shared Global Namespaces

Packages write into four namespaces that everyone shares, and none has a
mechanism to keep them apart.

**The dictionary is flat and case-insensitive.** Forth's hyper-static global
environment helps less than it first appears: it protects code that is
*already compiled*, and does nothing for code compiled afterwards. Measured:

        > : a 1 ;   : b a . ;   : a 2 ;
        redefined a
        > b     1        \ b still calls the OLD a
        > a .   2

So when `dice.fs` redefined `seed`, nothing already written broke — and every
word written after it silently got dice's version. Worse, the `redefined`
warning is gated off during file loads (`in_load` in `build_header`), so a
library shadow is silent by construction.

**The lifecycle hooks are ordinary global names.** `(mod-hook)` finds
`on-start` and `on-stop` with a plain `find`, so a package that defines either
silently takes over the hooks for the user's own module — and in a flat,
case-insensitive dictionary the last definition loaded wins. A package should
not define them at all; if it must reacquire something on reload, that is a
design question the module system has not answered for installed code yet.

**The help index is the third one.** A `##` heading with no stack effect to
stop the token scan turns *every word of the heading* into a help topic — which
is why Guides headings must be a single word, enforced by the suite. A package
author has no such suite, so `## Getting started with sound` would quietly
create four topics in every user's `help`.

**Installed lessons are the third, and the worst behaved.** Every `Tutorials`
directory is scanned, and the *filename* is the lesson's name — there is no
section to attribute it to, because the help system recognises a lessons
directory by that exact basename. Measured 2026-08-19 with a package lesson
called `Sound.md` beside the bundled one:

        tutorials
          Sound — One at a Time, or All at Once        <- bundled
          Sound — a PACKAGE lesson that collides       <- the installed one
        tutorial Sound   ->  opens the BUNDLED one

So the installed lesson is **listed and unopenable** — strictly worse than
either winning or being hidden, because the listing advertises something the
user cannot reach. And two *packages* shipping the same filename is worse
still: the second `install` overwrites the first's file on disk.

**Half of that is fixed as of 2026-08-21**, by the `pkg::page` naming rule
below plus a change to the listing. `tutorials` used to print each file's
*title line* while `tutorial <name>` matched its *filename*, so a package
lesson advertised a name that did not work — `greeting::tutorial.md`, titled
`# Greeting — …`, listed as `Greeting` and `tutorial Greeting` answered *no
tutorial named Greeting*. The listing now prints the name you type, with the
description beside it:

        tutorials
          Sound               One at a Time, or All at Once     <- bundled
          mypkg::sound        a package lesson, and it opens

What remains is the genuine case: two packages shipping the *same* filename
into the same directory, which `install` must refuse rather than resolve.

**The flat layout is forced, so a naming rule has to carry it.** The obvious
escape — a directory per package under `docs/Packages/` — does not work:
`(collect-in)` reads one directory with `getdents` and filters for `.md`, with
no recursion, so a page one level down is invisible. Measured: neither listed by
`help` nor found by `help <word>`. Appending each package's own directory to
`BASICFORTH_DOCS` instead is the unbounded-path-growth answer already rejected
under Local Layout.

So:

- **Every file a package installs is named for the package**, not for its
  topic — `<package>::<page>.md`, as in `greeting::lang-ref.md` and
  `dark-star::instructions.md`. Naming just the *entry* file that way is not
  enough: the whole point of a package being its own repo is that it may carry
  several pages and several lessons, and they share one flat directory with
  every other package's. The prefix is what makes that survivable, and it
  doubles as the scope that keeps two packages' `sound` pages apart.

  **`::` rather than a hyphen**, decided 2026-08-21. A hyphen is a legitimate
  character in a page name — `Machine-Code.md` is a bundled lesson — so a
  hyphen prefix cannot be told from a name that merely contains one. `::`
  appears in no ordinary filename, which makes the prefix unambiguous rather
  than merely conventional. The cost is that the name you type is long and not
  pretty; the benefit is that it is always *right*, and that a package can
  carry as many pages and lessons as it likes without inventing new rules.
- **Two different failures need two different responses**, and it is worth not
  blurring them:
  - **Another package's file of the same name** is a genuine overwrite, in a
    directory `install` owns. It must **refuse**, and say which package holds
    the name. This is the only collision in the system that destroys something.
  - **A bundled name** is not in that directory at all — it is on
    `BASICFORTH_PATH` or `BASICFORTH_DOCS`. Nothing is overwritten; the
    installed file simply loses every lookup while still appearing in listings.
    `install` can only see this by resolving the search path, and the right
    response is a **warning**, since the package installs and works — only that
    one page or lesson is unreachable.

The answer for now is not a namespace mechanism; it is **visibility**:

- **`install` lints a package's `.md`** for well-formed headings, and refuses
  or warns. Catching it where the author can still fix it beats catching it in
  a stranger's `help` output six months later.
- **Warn when a loaded file redefines a word that came from a different file.**
  Narrower than un-gating the `redefined` warning, so `core.fs`'s deliberate
  redefinitions and module reloads stay quiet. This is the *probe*: it measures
  how bad collisions actually are, before anyone designs for them.

Wordlists and the Forth 2012 Search-Order word set are the standard answer if a
real namespace is ever wanted. That is a bigger-than-a-week conversation, and
an expensive one to get wrong — see open question 6.

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
3. **Naming** — ~~"package" vs something more retro ("cart")?~~
   **RESOLVED 2026-08-18**: see Terminology. Module, package, library,
   program, source. "Registry" retired.
4. **`publish` mechanics** — how much git ceremony to hide. Settled that it
   never pushes; the commit message and the manifest edit still need a shape.
5. **Flat-dictionary and help-index collisions** — see Shared Global
   Namespaces. Two probes proposed, no mechanism chosen.
6. **1.0 relevance** — the package format (header, dep block, manifest
   layout) becomes a compatibility surface the moment two people use it.
   It is one of the things a future v1.0.0 would lock; design accordingly,
   ship deliberately.
7. **Does a duplicated section name print its heading twice?**
   ~~Decide by looking at the output once the directories exist.~~
   **RESOLVED 2026-08-19: yes, it does**, so the user's reference pages went
   into a section of their own, `Packages`. See Local Layout. The separate,
   confirmed bug where a **nonexistent** directory made `help` reprint the
   *previous* section is fixed: `(collect-in)` returned before resetting its
   collection, so the previous directory's topics and heading were printed
   again.
8. **Copy or symlink? — ANSWERED 2026-08-21: symlink the package's
   *directory*.** A package is a whole repo cloned into `packages/<name>/`, but
   the search path must stay a fixed set of entries rather than growing per
   package. So `lib/<package>` is a symlink to the package's source directory,
   and its files are reached as `require <package>/<file>.fs`.

   A **copy** is ruled out: the copy would sit in `lib/` with none of its
   siblings, so beside-first resolution would look in the wrong directory.

   This entry used to ask whether resolution should *read through* a symlink,
   and assumed it would have to. It does not. Whether it *should* is still
   open — resolving would make the file-linked layout work too, at the cost of
   a `readlink` per include, and nothing yet needs it. What is settled is that
   linking directories works today and makes the question moot.

   (An earlier draft of this entry justified the behaviour by saying that
   resolving would break "a copy in the directory you are standing in still
   wins". That is wrong and worth recording as wrong: **beside-first beats
   CWD**, which is the whole point of the ordering — a package's own `art.fs`
   is supposed to win over a stray `art.fs` where you happen to be standing.
   Resolving the link would change *which* directory counts as beside, not
   whether CWD outranks it.)

   Measured 2026-08-21 with a **decoy**, because the obvious experiment proves
   nothing: link the entry file alone, leave its sibling behind, and the load
   fails — but a plain *copy* fails identically, so "cannot open helper.fs"
   does not implicate symlinks at all. Put a different `helper.fs` beside the
   link instead, and the two explanations predict different output:

           lib/pkg/entry.fs -> real/entry.fs   +  a DECOY lib/pkg/helper.fs
           require pkg/entry.fs  ->  the DECOY loads, not real/helper.fs

   So resolution uses the path the file was *reached by*. Linking the directory
   puts the siblings on that path; linking the files individually does not.
   **`install` must therefore link directories**, and the trap to know about is
   that a one-file package survives the wrong form — it has no siblings to
   miss — so the mistake ships looking fine.
9. **Rename this file?** It is `Package_Registry.md` and describes no registry.
   `Packages.md` matches the terminology. Cheap with `git mv`, and this doc is
   not on `BASICFORTH_DOCS`, so nothing in `help` depends on the name.
