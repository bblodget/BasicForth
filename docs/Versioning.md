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

1. Do the work, commit as usual
2. Update `CHANGELOG.md` with the new version entry
3. Commit the changelog update
4. Tag: `git tag vX.Y.Z`
5. Push: `git push && git push origin vX.Y.Z`
