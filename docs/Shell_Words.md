# Shell-Like Words (`pwd` / `cd` / `ls` / `cat` / `more` / `pushd` / `popd` / `dirs`)

A small set of shell-style words for moving around the filesystem and reading
files from the REPL — so you can hop to another directory and list or read a
file without leaving BasicForth. They reuse the platform layer and the help
system's machinery; the only new syscall is `chdir`.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `pwd` | ( -- ) | print the current working directory |
| `cd` | ( "dir" -- ) | change directory to `<dir>`; **bare `cd`** returns to the startup directory |
| `ls` | ( "[dir]" -- ) | list a directory (the current one by default), one entry per line, skipping `.` and `..` |
| `cat` | ( "file" -- ) | write a file to stdout |
| `more` | ( "file" -- ) | page a file a screenful at a time (space = next page, `q` = quit) |
| `pushd` | ( "dir" -- ) | save the current directory, then `cd` to `<dir>` |
| `popd` | ( -- ) | return to the most recently `pushd`-ed directory |
| `dirs` | ( -- ) | list the directory stack: current first, then saved entries (top first) |

The path/file argument is taken with `parse-word` — the next whitespace-delimited
token — so **paths cannot contain spaces** yet.

`page` is *not* one of these words: it already means "clear the screen", so the
paged file viewer is named `more`.

## The working directory and `session.fs`

`cd` changes the **real process working directory** (via the `chdir` syscall), so
relative `include`, `open-file`, and `BASICFORTH_PATH` lookups all agree with
wherever you are.

`session.fs`, however, is **pinned to the startup directory** — the directory
BasicForth was launched in, captured once at boot. `save`, `reload`, and the
session seed always read and write `<startup>/session.fs`, so your session is
never scattered across the tree no matter where you `cd`. (If the boot-time
`getcwd` fails, the session file falls back to the plain relative `session.fs`,
matching how `see`'s path handling degrades.)

Bare `cd` (no argument) returns to that startup directory — note this differs
from a Unix shell, where a bare `cd` goes to `$HOME`; here the meaningful anchor
is where you launched. (`$HOME` expansion via `cd ~` is not implemented yet.)

## The directory stack

`pushd` / `popd` / `dirs` are a fixed-depth (16) directory stack:

```
> pwd
/home/you/project
> pushd src                      \ save /home/you/project, cd to src
> pushd /tmp                     \ save .../src, cd to /tmp
> dirs                           \ current first, then saved (top first)
/tmp /home/you/project/src /home/you/project
> popd                           \ back to .../src
> popd                           \ back to /home/you/project
```

Saved paths are **absolute**, so `popd` returns to the right place even after
intervening `cd`s. `pushd` saves the current directory *before* the `cd` and only
commits the entry if the `cd` succeeds, so a failed `pushd` leaves the stack
untouched. `popd` likewise tries the restore `chdir` *before* removing the entry,
so if the saved directory has since vanished it reports the error and keeps the
entry rather than losing it.

## Errors

Every failure path reports a message and then **aborts**, so the REPL shows the
error and no `ok` — a failed command never looks like success:

```
> cd /no/such/dir
cd: cannot access /no/such/dir
> cat missing.txt
cat: cannot open file
> popd
popd: directory stack empty
```

`cat` surfaces both read errors (e.g. trying to `cat` a directory) and write
errors: it writes to stdout with `write-file` rather than `type` so a broken
pipe or a full disk is reported instead of silently ignored. `ls` reports a
directory-read (`getdents`) failure the same way.

## How It Works

- **`cd`** is the Forth word; the primitive `chdir ( c-addr u -- ior )` copies
  the path to a NUL-terminated buffer and calls the new `platform_chdir` syscall
  wrapper (`chdir` = 80 on x86-64, 49 on ARM64). Over-long paths return
  `-ENAMETOOLONG`.
- **`pwd`** is `(cwd) type cr`, where `(cwd) ( -- c-addr u )` reads the live
  directory with `getcwd`. The startup directory is exposed by
  `(startup-dir) ( -- c-addr u )`, captured once at boot and used for bare `cd`
  and the `session.fs` pin.
- **`ls`** walks the directory with the `(getdents)` primitive (the same one the
  help browser uses), parsing `linux_dirent64` records.
- **`cat`** reads in chunks through the pager's line buffer; **`more`** is built
  on `page-file`, the shared pager that also backs `man` and `tutorial`.
- **The directory stack** keeps absolute paths in a heap buffer allocated lazily
  on first `pushd` (so it adds nothing to the dictionary arena until used).

## See Also

- `docs/BasicForth_Manual.md` — the "Shell-Like Words" section.
- `docs/Help_System.md` — `man` / `topics` / `apropos`, which share the
  `(getdents)` directory-walk and `page-file` pager.
- `docs/Persistence.md` — `save` / `reload` and `session.fs`, now pinned to the
  startup directory.
- `docs/Platform_Layer.md` — the syscall wrappers (`platform_chdir`,
  `platform_getcwd`).
