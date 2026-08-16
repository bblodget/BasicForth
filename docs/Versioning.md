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

Create a tag:

    git tag v0.1.0
    git push origin v0.1.0

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

7. Push: `git push && git push origin vX.Y.Z`

Step 4 is the part that is easy to get wrong. Tagging on `staging` would put
the release on a commit `main` does not contain, so `git describe` on `main`
would still name the *previous* release — and `main` can be a hundred commits
behind by the time a minor version is ready. `v0.14.0` and `v0.15.0` are
lightweight tags and `v0.15.1` onward are annotated; annotated is preferred,
so a release carries its own message and date.
