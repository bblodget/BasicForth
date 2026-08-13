# Files

Reading and writing files on disk. The pattern is always: open (or create) to get
a **fileid**, do some reads/writes, then close. Every operation returns an
**ior** — `0` on success, non-zero on error — so check it (`abort"` is handy).

A full round trip — write a line, then read it back:

    : wr  s" demo.txt" w/o create-file abort" create"
          >r  s" Hello, file!" r@ write-line  r> close-file drop ;
    : rd  s" demo.txt" r/o open-file abort" open"
          >r  pad 80 r@ read-line drop drop  pad swap type  r> close-file drop ;
    wr  rd            \ Hello, file!

At a glance:

    r/o  w/o  r/w   ( -- fam )                access methods (read/write/both)
    bin             ( fam -- fam )            binary-mode modifier
    open-file       ( c u fam -- fileid ior ) open an existing file
    create-file     ( c u fam -- fileid ior ) create (truncate) and open
    close-file      ( fileid -- ior )         close
    read-file       ( c u1 fid -- u2 ior )    read up to u1 bytes
    read-line       ( c u1 fid -- u2 f ior )  read one line
    write-file      ( c u fid -- ior )        write u bytes
    write-line      ( c u fid -- ior )        write u bytes + newline
    file-size       ( fid -- ud ior )         size as a double
    rename-file     ( c1 u1 c2 u2 -- ior )    rename
    include <name>  ( "name" -- )             load a Forth source file
    included        ( c u -- )                include, name on the stack
    require <name>  ( "name" -- )             include, only if not yet loaded
    required        ( c u -- )                require, name on the stack
    needs-cmd <cmd> ( "name" ccc -- )         this file needs a system command
    needs-lib <so>  ( "name" ccc -- )         this file needs a shared library
    open-pipe       ( c u fam -- fid ior )    pipe over a shell command
    close-pipe      ( fid -- wret wior )      finish a pipe, reap the child
    stdin stdout stderr  ( -- fileid )        the standard streams

## r/o ( -- fam )
The read-only file-access method, for `open-file`.

## w/o ( -- fam )
The write-only file-access method.

## r/w ( -- fam )
The read-write file-access method. (Refused by `open-pipe`, which is
one-directional.)

    \ s" state.dat" r/w open-file ...

## bin ( fam -- fam )
Modify an access method to binary mode (no text translation).

    \ s" data.bin" r/o bin open-file ...

## open-file ( c-addr u fam -- fileid ior )
Open an existing file named by the string, with access method `fam`.

    \ s" demo.txt" r/o open-file abort" not found"

## create-file ( c-addr u fam -- fileid ior )
Create a new file (truncating any existing one) and open it.

    \ s" out.txt" w/o create-file abort" cannot create"

## close-file ( fileid -- ior )
Close an open file.

    \ fileid close-file drop

## read-file ( c-addr u1 fileid -- u2 ior )
Read up to `u1` bytes into the buffer at `c-addr`; `u2` is the number actually
read (`0` at end of file).

## read-line ( c-addr u1 fileid -- u2 flag ior )
Read one line (up to `u1` bytes, newline stripped) into `c-addr`. `u2` is its
length and `flag` is true while a line was read, false at end of file.

    \ pad 80 fileid read-line   ( -- u2 flag ior )

## write-file ( c-addr u fileid -- ior )
Write `u` bytes from `c-addr` to the file.

## write-line ( c-addr u fileid -- ior )
Write `u` bytes followed by a newline.

    \ s" a line" fileid write-line drop

## file-size ( fileid -- ud ior )
Return the file's size as a double (`ud`).

    \ fileid file-size drop drop .    \ size in bytes (low cell)

## rename-file ( c-addr1 u1 c-addr2 u2 -- ior )
Rename the file named by the first string to the second.

    \ s" old.txt" s" new.txt" rename-file drop

## include ( "name" -- )
Load and interpret the Forth source file named by the next word — the usual way
to load a program. Always loads, even if the file was loaded before — that's
the edit-and-reload workflow (`require` is the load-only-once variant). A
missing file is an error (`cannot open <name>`).

**Where it looks:** the current directory first, then each directory in
`BASICFORTH_PATH` in order, loading the first match — so a file of your own
shadows a library of the same name. That path is where the shipped libraries
(`sdl3.fs`, `graphics.fs`, …) are found, and it's colon-separated, so adding
the examples directory makes the demos loadable by bare name:

    \ BASICFORTH_PATH=src/forth:examples basicforth

Every loading word below searches the same way.

    \ include game.fs

## included ( c-addr u -- )
Like `include`, but takes the filename as a string on the stack (so it can be
computed). Use it inside definitions.

    \ : load  s" game.fs" included ;

## require ( "name" -- )
Like `include`, but a no-op if the file has already been loaded this session —
for dependencies. Libraries `require` what they need at the top, so requiring
the top of a stack loads the whole stack once: `require sdl3.fs` pulls in
`ffi.fs` and `graphics.fs` by itself, and repeats are harmless. After editing
a file mid-session, use `include` to force the reload (`require` will see it
as already loaded). Loaded-ness follows the dictionary: if a `marker` forgets
a library, `require` will happily load it again.

A file that is already part-way through loading is skipped as well, so a ring
of libraries that require each other settles instead of looping forever. The
same guard stops a file that requires *itself* — which is easier to do than it
sounds, since the search starts in the current directory: name your own module
`font.fs` and `require font.fs` finds your file, not the library's. The skip
prints a line, because the library's words are then missing and you would
otherwise meet that as an unexplained `? name` further down:

    require: font.fs is already loading — skipped

    \ require sdl3.fs

## required ( c-addr u -- )
Like `require`, with the filename as a string on the stack.

    \ s" sdl3.fs" required

## needs-cmd ( "name" ccc -- )
State that this file needs an external command, and stop the load if it is not
on `PATH`. Goes at the top of a file with the `require` lines — together they
are its **dep block**, everything it needs before its first definition.

    needs-cmd objdump         install binutils

The name is one word. Everything after it on the line is a hint for whoever
has to fix it — the part the name itself cannot tell them, since `objdump`
does not say "binutils". The hint is optional, and stops at a `\` so an
ordinary trailing comment still works.

    disasm.fs: needs the command objdump -- install binutils

The load stops **there**, before any of the file's definitions exist, so a
package never half-loads: you either have the words or you have the reason you
do not. It is a `-2 throw`, the same as `abort"`, so `catch` sees it.

A name containing `/` is taken as a path and used as-is, with no search. What
counts as found is what a shell would accept: a regular file this user can
execute. A directory does not count, however searchable it is.

The `PATH` walk follows the shell's rules exactly, including the two that
surprise people. An **empty element means the current directory** — and `PATH`
holds one more element than it has colons, so `:/usr/bin`, `/usr/bin:`,
`/bin::/usr/bin` and the empty string all contain one. An **unset** `PATH` is
different from an empty one: it falls back to `/bin:/usr/bin` and does not
search the current directory at all.

## needs-lib ( "name" ccc -- )
The same, for a shared library — the ones the FFI opens by soname.

    needs-lib libSDL3.so.0    see help install

    sdl3.fs: needs the library libSDL3.so.0 -- see help install

The probe is a real `dlopen`, so it answers the question that matters (will
this library load, here, now) rather than guessing from a filename. The handle
is kept and handed to the next `dlopen` of the same name, so declaring a
library costs nothing over binding it — and guarantees the library that was
checked is the library that gets bound.

Declaring is worth it even though `dlopen` fails perfectly well on its own,
because the two failures say different things. `dlopen` can only report what
it tried; `needs-lib` reports what you should do about it.

## open-pipe ( c-addr u fam -- fileid ior )
Run a shell command with a pipe over its stdout (`r/o`: read what it prints)
or stdin (`w/o`: write what it reads). The fileid works with `read-file`,
`read-line`, `write-file`, `write-line`. `r/w` is refused (ior 22). Finish
with `close-pipe`, not `close-file`.

    \ s" ls" r/o open-pipe drop   ( -- fileid )

## close-pipe ( fileid -- wretval wior )
Close an `open-pipe` fileid and reap the command; `wretval` is its exit
status. The only correct way to finish a pipe (`close-file` would leak a
zombie process).

    \ fileid close-pipe 2drop

## stdin stdout stderr ( -- fileid )
The standard streams (file descriptors 0, 1, 2) as constants, usable wherever
a `fileid` is — read piped input with `stdin read-line`, or send diagnostics
to `stderr` without disturbing redirected output.

    : warn  s" watch out" stderr write-line drop ;
    \ pad 80 stdin read-line   ( in a filter script )

## See Also

- `help strings` — building the filename and buffer strings these words take.
- `help memory` — `pad`/`allocate` for read buffers.
- `help scripting` — `arg`/`argv` and `#!` scripts that read `stdin`.
- docs/Platform_Layer.md — the underlying syscalls; BASICFORTH_PATH file search.
