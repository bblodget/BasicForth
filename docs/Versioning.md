# Versioning

BasicForth uses [Semantic Versioning](https://semver.org/) with git tags
as the single source of truth.

## Version Format

    MAJOR.MINOR.PATCH

- **MAJOR** — incompatible changes (dictionary layout, register conventions)
- **MINOR** — new features (new words, new targets)
- **PATCH** — bug fixes and minor improvements

## Git Tags

Every release is a git tag: `v0.1.0`, `v0.2.0`, etc.

Tags are annotated, and a release tags the `staging`-into-`main` merge — see
**Workflow** below for the whole sequence. Do not follow a `git tag` / `git
push origin <tag>` pair from memory: pushing the tag without its branches
publishes a release naming a commit the remote's `main` does not contain.

## Startup Banner

The build system generates a startup banner from `git describe --tags --dirty`:

    *** BasicForth v0.1.0 (Linux/x86-64) ***

The version string reflects the exact build state:

| State                        | Example                          |
|------------------------------|----------------------------------|
| Clean tagged release         | `v0.1.0`                         |
| Commits past a tag           | `v0.1.0-3-g638bb18`             |
| Uncommitted local changes    | `v0.1.0-dirty`                   |
| Commits past tag + dirty     | `v0.1.0-3-g638bb18-dirty`       |

This is generated at build time into `version.inc` (gitignored) by each
arch Makefile. Rebuilding after a commit or tag updates the banner
automatically.

## Changelog

Release notes are documented in `CHANGELOG.md` at the project root.
Each tagged version gets an entry describing features, fixes, and
breaking changes.

## Workflow

Work happens on `staging` (feature branch → `--no-ff` merge → delete branch).
A release is `staging` arriving on `main`, and **the tag is what makes it a
release**, since the banner comes from `git describe`.

1. Do the work, commit as usual — feature branches merged into `staging`
2. Curate `CHANGELOG.md`: date the `## Unreleased` heading as
   `## vX.Y.Z — YYYY-MM-DD`, and update the `## Status` block in `README.md`
3. Commit that on `staging` and merge it there
4. Merge into main, naming the version in the merge message:

       git checkout main
       git merge --no-ff staging -m 'Merge branch "staging" into main: vX.Y.Z — <tagline>'

5. Tag **that merge commit**, annotated:

       git tag -a vX.Y.Z -m "Release vX.Y.Z"

6. Fast-forward `staging` so the two agree and the next commit is not a fork:

       git checkout staging && git merge --ff-only main

7. Push **both branches and the tag, named explicitly, in one atomic push**:

       git push --atomic origin main staging vX.Y.Z

   Not `git push`. Step 6 leaves you on `staging`, which has no upstream, so a
   bare push fails outright — and if it were configured, `push.default=simple`
   would publish only the current branch, leaving `main` on the remote at the
   *previous* release. The tag needs naming too: tags are not pushed by
   default.

   `--atomic` because the three refs are one release. Without it the push is
   three independent updates, so a rejection on any one of them — someone
   else's commit landing on `staging` between your last fetch and the push is
   enough — leaves the other two published: a tag on the remote naming a commit
   that remote's `main` does not contain. All-or-nothing turns that into a
   clean failure you retry.

   **Why not `git push origin main --tags`?** It is the obvious shorter form,
   and it fails three ways. It does not push `staging`, so the remote branch the
   Pi and the other worktrees pull sits a release behind. It publishes *every*
   local tag rather than this release's, so a scratch tag escapes with it. And
   the one that matters: naming the version makes the push **self-checking**. If
   you arrive here having skipped step 5, or you mistype the number, git refuses:

       error: src refspec v0.17.0 does not match any

   With `--atomic` nothing goes out and you fix it. `--tags` in that same
   situation *succeeds*, publishing both branches with no release tag on them —
   and `git describe` in a fresh clone then reports the previous version, which
   is the failure this whole procedure exists to prevent.

8. Verify against the remote, **including the tag**, naming each ref exactly:

       git ls-remote origin refs/heads/main refs/heads/staging \
                            'refs/tags/vX.Y.Z' 'refs/tags/vX.Y.Z^{}'

   Expect four lines, and expect three of them to carry the same sha:
   `main`, `staging`, and `refs/tags/vX.Y.Z^{}`.

   Check the remote, not the local `origin/*` refs — those only report what the
   last fetch saw.

   An annotated tag has **two** refs, and the difference matters:
   `refs/tags/vX.Y.Z` is the sha of the tag *object* and matches nothing else,
   while `refs/tags/vX.Y.Z^{}` is the commit it names. For v0.16.0 the tag
   object was `62c5097` and the commit `15eed45` — compare the wrong line and a
   correct release looks broken.

   Name both refs rather than reaching for `refs/tags/vX.Y.Z*`. The wildcard
   exists only to pick up that `^{}` line, and it also matches any sibling that
   happens to share the prefix — a `vX.Y.Z-rc1`, say — so the check can print
   extra refs while still looking like it passed. A verification is worth
   nothing if it cannot be read at a glance.

Step 4 is the part that is easy to get wrong. Tagging on `staging` would put
the release on a commit `main` does not contain, so `git describe` on `main`
would still name the *previous* release — and `main` can be a hundred commits
behind by the time a minor version is ready. `v0.14.0` and `v0.15.0` are
lightweight tags and `v0.15.1` onward are annotated; annotated is preferred,
so a release carries its own message and date.
