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
    wants-cmd <cmd> ( "name" ccc -- )         ...and works without it
    wants-lib <so>  ( "name" ccc -- )         ...and works without it
    deps <name>     ( "name" -- )             check a file's requirements
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

**Where it looks:** the directory of the file *doing the loading* first, then
the current directory, then each directory in `BASICFORTH_PATH` in order,
loading the first match. Typed at the prompt there is no loading file, so it
starts at the current directory — and a file of your own shadows a library of
the same name. That path is where the shipped libraries
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
same guard stops a file that requires *itself*, which used to be easy to do by
accident: name your own module `font.fs`, and a library requiring `font.fs`
found yours instead of its own. Looking beside the loading file first prevents
that now — a library gets its own neighbours — but the guard still matters for
`require font.fs` typed at the prompt, where there is no loading file and the
current directory really is first. The skip prints a line, because the
library's words are then missing and you would otherwise meet that as an
unexplained `? name` further down:

    require: font.fs is already loading — skipped

    \ require sdl3.fs

## my-dir ( -- c-addr u )
The directory of the file currently being loaded, without a trailing slash —
so a package can find its own parts wherever it was installed. Empty (`0 0`)
when nothing is loading, which includes everything you type at the prompt.

    \ inside mypackage.fs
    \ my-dir type cr        \ /home/you/.basicforth/lib/mypackage

`require` already looks beside the loading file, so a package's own `.fs`
files need nothing special. `my-dir` is for everything else a package carries —
artwork, sounds, data — which is opened by name and gets no search path.

**Capture it while the file loads.** Once loading finishes there is no current
file, so `my-dir` inside a word that runs *later* answers nothing. A package
that opens its own files at run time records the directory as it loads:

    my-dir 2constant my-home
    : my-file ( c-addr u -- c-addr' u' )  my-home 2swap path-join ;

    : load-art  s" art/tiles.wav" my-file wav-load ... ;

`path-join` does the length check for you — see below.

## path-join ( dir-a dir-u name-a name-u -- path-a path-u )
Join a directory and a name into `dir/name`. An empty directory returns the
name unchanged, so a path built from `my-dir` at the prompt is still usable.

    s" /a/b" s" c/d.wav" path-join type      \ /a/b/c/d.wav

**The result is valid until the next call** — it lives in one reusable buffer,
shared by every caller. Use it straight away; that is what it is for.

**`2constant` will not keep it.** A `2constant` records the address and the
length, not the text, and the address is that shared buffer — so the name goes
on answering with whatever the *next* join wrote, at the *old* length:

    s" a/one.wav" my-file 2constant bad
    bad type                              \ /tmp/a/one.wav
    s" c/three.wav" my-file 2drop
    bad type                              \ /tmp/c/three.w   <- wrong, and cut short

That is safe for `my-dir`, whose string lives in the source table and does not
move, and unsafe here. To keep a joined path, copy the bytes somewhere you own:

    : keep-path ( c-addr u -- c-addr' u )     \ an allotted copy that survives
        here >r  dup allot
        2dup r@ swap cmove
        nip r> swap ;

    s" a/one.wav" my-file keep-path 2constant good

**A path too long to build aborts**, naming the problem, rather than
truncating: a silently shortened path opens the wrong file, or none, on a
machine you never see. That check is the whole reason this word exists in core
rather than in each package — it is one line, and it is the line everybody
forgets.
the session down with no message at all.

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

## wants-cmd ( "name" ccc -- )
State that this file *uses* an external command but works without it. Same
syntax as `needs-cmd`, opposite behaviour: it does not probe, does not print,
and never stops the load.

    wants-cmd objdump         install binutils

A soft requirement is a **declaration, not a check**. It exists to be read by
`deps`, and it stays silent at load time because a file that declares one is a
file designed to run without it — saying anything would nag every user who is
perfectly happy.

Use it wherever aborting would break a promise the file makes. `disasm.fs`
re-probes for `objdump` on every `dis`, so installing binutils mid-session
works without a reload; `voice.fs` names `piper` only as a default that
`voice-cmd!` replaces; `speech.fs` answers `speech-open ( -- ior )` rather
than aborting. `needs-cmd` in any of those would take that away.

## wants-lib ( "name" ccc -- )
The same, for a shared library.

    wants-lib libflite.so.1   install flite

## deps ( "name" -- )
Report what a file requires, and whether this machine has it — without loading
a line of the file.

    deps sdl3

    sdl3.fs
      require ffi.fs            loaded
      require graphics.fs       found
      needs-lib libSDL3.so.0    MISSING -- see help install
    sdl3.fs will not load: 1 requirement missing.

`.fs` is added if you leave it off, and the file is looked for in the current
directory first and then on `BASICFORTH_PATH` — the same order `require` uses,
so `deps` answers for the same file the load would pick.

Going the other way — you have a *word* and want the file it came from — is
`help where`; and `help word-deps` does this whole report for a word's file in
one step.

It reads only the **dep block**: the file's leading run of blank lines,
whole-line comments and requirements, stopping at the first line that is none
of those. Each requirement is then re-run in a reporting mode, by the same word
that would run it at load time, so what you are shown is what would happen.

A `require` gets one of three answers — `loaded` (already in memory), `found`
(on disk, not yet loaded) or `MISSING`. The verdict has three forms too: all
met, will-load-but-degraded, and will-not-load.

`deps` follows `require` into the files named there, because the flat answer
can lie — `require sound.fs  found` is no comfort on a machine where sound.fs
itself cannot load. Those nested files print **only if something in them is
missing**, so a healthy machine sees one short list and a broken one sees
exactly the section that explains itself:

    mygame.fs
      require sdl3.fs           found
      require sound.fs          found
      sdl3.fs
        needs-lib libSDL3.so.0    MISSING -- see help install
    mygame.fs will not load: 1 requirement missing.

A file already loaded is not followed: it is in memory, so its own
requirements were met when it got there.

The traversal is bounded at 64 files. If a dep graph outruns that, `deps` says
so rather than reporting on what it managed to read — a bound that truncated
quietly would produce exactly the false "all requirements met" this word exists
to prevent. A requirement that is definitely missing still outranks the notice,
since that verdict stays true however much went unread.

## deps-path ( c-addr u -- )
`deps` over a path you already hold: the same report and verdict, without
parsing a name or searching for it. `deps` itself ends here once it has
resolved a filename.

It exists so that composing with `deps` does not mean reaching for internals.
`where-path` returns a path, `deps-path` takes one, and `word-deps` is the two
joined:

    s" disasm.fs" deps-path

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
