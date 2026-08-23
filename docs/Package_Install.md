# Adding a Package — the User Story

**Status: design, nothing built.** Written 2026-08-22. This is what the
packaging verbs sketched in `Package_Registry.md` look like from the user's
side, start to finish.

---

## The story

    > add-source brandon https://github.com/brandonblodget/basicforth-packages
    Adding a source is a decision to trust it. Packages from here run with
    your permissions, and a source can change what it offers at any time.
    Add brandon? (y/n) y
    brandon: 12 packages.

    > packages
    default:
      hexutils                    Hex dump and patch words
      sprites                     Sprite sheets and animation
    brandon:
      dark-star                   A puzzle game, ported from TurboForth
      starfield                   A parallax starfield demo

    > packages dark-star
    dark-star           brandon
      A puzzle game, ported from TurboForth
      version 1.2
      repo    https://github.com/bblodget/dark-star
      commit  4f1c9a2be7d0518c3a6b8e94d217f0c5a83be612
      needs   libSDL3.so.0
      wants   flite
      run     dark-star
      not installed

    > install dark-star
    From brandon, pinned at 4f1c9a2b.
      clone   -> ~/.basicforth/packages/dark-star
      link    -> ~/.basicforth/lib/dark-star
      page    -> help dark-star::instructions
      lesson  -> tutorial dark-star::tutorial
      command -> ~/.local/bin/dark-star
    Install? (y/n) y
    Cloning... done.
    dark-star installed.
      require dark-star/dark-star.fs     to use it here
      dark-star                          to run it from a shell

The listing carries that state from now on, and picks up `outdated` when a
source's pin moves past yours:

    > packages
    default:
      hexutils                    Hex dump and patch words
      sprites                     Sprite sheets and animation
    brandon:
      dark-star    installed      A puzzle game, ported from TurboForth
      starfield                   A parallax starfield demo

The same verbs from a shell, via `chip`:

    $ chip add-source brandon https://github.com/brandonblodget/basicforth-packages
    $ chip install dark-star --yes
    $ chip packages

---

## The verbs

| Command                   | What it does                                  |
|---------------------------|-----------------------------------------------|
| `add-source <name> <url>` | trust a source, and fetch its manifest        |
| `sources`                 | list the sources you have added               |
| `packages`                | all packages, `installed` / `outdated` marked |
| `packages --outdated`     | just what has moved on                        |
| `packages <name>`         | the detail view above                         |
| `install <name>`          | show the plan, ask, clone at the pin          |
| `install <name>@<sha>`    | that exact commit                             |
| `remove <name>`           | undo an install                               |
| `upgrade [<name>]`        | move to the source's newer pin                |
| `rollback <name>`         | back to the pin before the last upgrade       |
| `hold <name>` / `unhold`  | keep a package where it is                    |
| `refresh`                 | refetch manifests now                         |

**`chip`** — *CHIP Handles Installing Packages* — is the command-line front
door: a separate executable that reads argv and calls these same words. It
ships inside the BasicForth repo, installed by `make install`, so there is no
bootstrap problem. `--yes` skips the prompts, as does a non-terminal stdin.

The verbs live in a bundled `pkg.fs`, so `require pkg.fs` gives them to the
REPL. One implementation, two front doors.

---

## How it behaves

**Sources refresh themselves.** A manifest older than a day is refetched as
part of whatever command you ran, which is announced but needs no action:

    > packages
    (brandon: manifest is 6 days old, refreshing... 12 packages)

**Everything is pinned to a full commit SHA.** The clone is not tracked — no
branch, no pull. Only `upgrade` moves a pin, and it shows what it is moving:

    > upgrade dark-star
    dark-star   brandon
      installed  1.2   4f1c9a2b   2026-08-12
      source has 1.4   9e21b70c   2026-08-20
      needs      libSDL3.so.0, flite        (unchanged)
    Upgrade? (y/n)

This is the supply-chain surface, so it is never silent. `upgrade` with no
argument does every outdated package, listing them first and skipping held
ones. `install` on something already installed refuses and points at `upgrade`.

**A version number is for reading; the SHA is what is enforced.** A manifest
carries both. Versions are not selectable — `install sprites@1.1` does not
exist.

**`install <name>@<sha>` installs a tree nobody curated.** That is not a
different version; it is stepping outside the one guarantee the design
enforces, since the curator read the *pinned* tree and no other. So it warns,
asks, and stays visible afterwards:

    > install dark-star@a71c3f90
    a71c3f90 is not the commit brandon curated (9e21b70c).
    Nobody has reviewed this tree. Install anyway? (y/n)

The package then shows as `unpinned` in `packages`, the way a held one shows as
`held`. Its uses are real — reproducing a bug, an author testing before
curation — but it should never happen by accident.

**`upgrade` keeps the old clone, and that is what makes `rollback` work.**
Recording the previous SHA is not enough: a force-push, a rewritten branch or a
deleted repo and that commit names nothing, so rollback would fail exactly when
it is needed — right after an upgrade that broke you.

**Clones are stored by commit and never move:**

    <root>/packages/<name>/<sha>/          the tree, as cloned
    <root>/lib/<name>          -> packages/<name>/<sha>/src

`upgrade` clones the new pin beside the old one and repoints the links. The two
trees coexist under stable paths, so nothing has to be renamed to change which
is live.

**The manifest is the only thing that says which commit is live**, and it is
written atomically — to a temporary file, then renamed over the old one. A
rename either happens or does not, so the manifest is always one whole version
or the other, never half of each.

    > rollback dark-star
    dark-star   9e21b70c -> 4f1c9a2b   (from the kept clone)

That makes rollback a manifest rewrite followed by repointing links. **Links
are derived state**: whatever the manifest says is live, the links can be
rebuilt from it at any time, and replacing a symlink is itself a rename and so
atomic. An interruption therefore leaves the manifest definitely old or
definitely new, with links possibly stale — and stale links are reconciled by
recomputing them, not by guessing what step was in flight.

This is why the earlier design was wrong, and it is worth recording. It renamed
`<name>` and `<name>.prev` around a `<name>.tmp`, so liveness was a property of
directory *names* — and a set of names cannot be changed atomically. Interrupted
between two of the three renames, a retry from the top would rename the live
tree onto an existing `.tmp` and destroy the version being rolled back from.
Storing by commit removes the class of problem rather than sequencing around it.

Rollback is reversible: the version rolled back from is still on disk, so a
second `rollback` returns to it. One step of history, held as a pair — an
`upgrade` past that point drops the older clone.

Two consequences worth stating, because both are easy to design out and then
rediscover as bugs:

- **`packages/<name>/` is owned wholly by that package**, and that is what
  makes cleanup recoverable. The manifest authorises the *directory*; anything
  inside it is ours by construction, so individual clones need no separate
  authorisation. A leftover `<sha>/` from an interrupted cleanup is collectable
  garbage, and a `<sha>/` the manifest names but which is missing is simply
  gone. Both are reconciled in passing, not treated as corruption.

  Without that, dropping the older clone has no safe ordering: manifest-first
  and an interruption orphans a clone `remove` may not delete; delete-first and
  an interruption leaves the manifest naming a missing tree, which — under a
  rule that aborts on any mismatch — makes the package unremovable. The
  strictness belongs to the entries *outside* `packages/<name>/`: the links and
  the command, where something that is not ours could be standing.
- **The manifest records each link's target**, not just its path. A package may
  relocate its files between versions, so the link for one commit is not
  necessarily the link for another.

Further back than one step is `install <name>@<sha>`, with the warning above.

**`install` writes one thing outside `~/.basicforth`**: the command in
`~/.local/bin`. That is why it shows its plan and asks. If the name is already
taken there, it refuses and says what holds it.

---

## What `remove` is allowed to delete

A path must satisfy **both** checks:

1. **The `installed` manifest authorises it** — `install` recorded creating it,
   and it still matches what was recorded.
2. **Its shape permits it** — one of the five forms `install` can produce:

        <root>/packages/<name>
        <root>/lib/<name>
        <root>/docs/Packages/<name>::*.md
        <root>/docs/Tutorials/<name>::*.md
        <bin>/<name>

Neither is sufficient alone: the manifest is a text file anything can edit, and
a shape rule on its own is a path heuristic that would claim hand-made links.
Anything failing either check aborts the whole operation, naming the entry —
for the links and the command, where a path could belong to something else.
Inside `packages/<name>/`, which the manifest authorises as a whole, a
disagreement between manifest and disk is reconciled rather than fatal.

A package name is a **validated identifier** — lowercase, digits, internal `-`,
bounded, no `/` `.` `..` `::` or whitespace — checked when read from a manifest
as strictly as when typed, because a manifest is remote data. Same for the
`<page>` half of `<name>::<page>.md`. The shape test compares **canonical**
paths: resolve the parent, require it to equal the expected directory, require
the last component to be exactly the name.

**Deletion never follows a link.** Every path but the clone is a symlink into
the user's own source tree. The clone is the one recursive delete, and its
parent components must be real directories.

A package absent from the manifest cannot be removed — `remove` says it did not
install it. Hand-made layouts predate `install`, and adopting them is an open
question.

---

## Incompatible majors: two packages, not two versions

A source can carry an old major beside a new one, under **different names**:

    sprites    2.0  https://github.com/.../sprites   9e21b70c
    sprites1   1.1  https://github.com/.../sprites   4f1c9a2b

They install independently, into separate directories and pages. Rare and
opt-in: most v2s just replace v1.

**Installed together is fine; `require`d together is not.** A program uses one
or the other. Nothing enforces that — `require` cannot tell they are related,
so both loaded means the flat dictionary silently takes whichever came second.
The queued redefinition warning in `TODO.md` would at least make it audible.

---

## Updating BasicForth

Not a package, and `chip` does not update it: a package is plain source a
curator can read, while BasicForth is assembly needing binutils, gcc and make.

    cd BasicForth && git pull && make && make install PREFIX=...

Your packages survive — `make install` writes under `PREFIX`, packages live in
`~/.basicforth`. Note `make install` is additive and never removes, so a
library deleted upstream lingers in an install tree (measured 2026-08-22).

`chip` may *report* that a newer BasicForth exists, without touching it.

---

## Open questions

1. **Where does a package's one-line description come from?** The manifest
   sketch has no column for it, and cloning every package to read its
   `package.info` is far too eager for a listing.
2. **Is `needs` checked at install time?** It fails at load today, which is
   honest but late. A check at install is friendlier but can go stale.
3. **How stale before a refetch?** A day is the obvious default; it wants
   trying before it is fixed.
4. **Does the default source carry a non-installable `basicforth` entry**, so
   `chip` can notice the interpreter is behind?
5. **Adopting hand-made installs** into the `installed` manifest, or telling
   the user to unlink once.

---

## Not covered here

`publish` (settled only that it never pushes), namespaces
(`Package_Registry.md` §Shared Global Namespaces), and system-wide or
per-project scopes (see "Package scopes" in `TODO.md`).
