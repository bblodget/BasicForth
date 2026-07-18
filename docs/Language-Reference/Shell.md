# Shell Words

Move around the filesystem and read files without leaving BasicForth. Paths
are taken as the next whitespace-delimited token (so no spaces in paths); a
leading `~` expands to `$HOME` (`cd ~/src`). For arbitrary shell commands,
use `sh` (`help tools`).

At a glance:

    pwd          ( -- )        print the working directory
    cd <dir>     ( "dir" -- )  change directory (bare cd: startup dir)
    ls [dir]     ( "[dir]" -- ) list a directory
    cat <file>   ( "file" -- ) write a file to the screen
    more <file>  ( "file" -- ) page a file (space = next, q = quit)
    pushd <dir>  ( "dir" -- )  save the current dir, cd to <dir>
    popd         ( -- )        return to the last pushd-ed dir
    dirs         ( -- )        show the directory stack

## pwd ( -- )
Print the current working directory.

    pwd               \ /home/you/project

## cd ( "dir" -- )
Change the process working directory — relative `include`/`open-file` paths
follow. **Bare `cd` returns to the startup directory** (where BasicForth was
launched — not `$HOME` as in a Unix shell; use `cd ~` for home). The session
file stays pinned to the startup directory regardless of `cd`.

    cd src            \ into ./src
    cd                \ back to where you launched

## ls ( "[dir]" -- )
List a directory (the current one by default), one entry per line.

    ls                \ the current directory
    ls ~/Dev          \ another one

## cat ( "file" -- )
Write a file to the screen, unpaged.

    cat notes.txt

## more ( "file" -- )
Page a file a screenful at a time — space for the next page, `q` to quit.
(The name `page` was taken: it clears the screen.)

    more core.fs

## pushd ( "dir" -- )
Save the current directory on a stack (16 deep), then `cd` to `<dir>`.

    pushd /tmp        \ over there...
    popd              \ ...and back

## popd ( -- )
Return to the most recently `pushd`-ed directory.

## dirs ( -- )
Show the directory stack: current directory first, then the saved entries,
most recent first.

## See Also

- `help tools` — `sh`, arbitrary shell commands.
- `help files` — `open-file` / `include`, which follow `cd`.
- docs/Shell_Words.md — `~` expansion rules, the session-file anchor, details.
