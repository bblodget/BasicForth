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

## r/o ( -- fam )
The read-only file-access method, for `open-file`.

## w/o ( -- fam )
The write-only file-access method.

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
to load a program.

    \ include game.fs

## included ( c-addr u -- )
Like `include`, but takes the filename as a string on the stack (so it can be
computed). Use it inside definitions.

    \ : load  s" game.fs" included ;

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

## See Also

- `man strings` — building the filename and buffer strings these words take.
- `man memory` — `pad`/`allocate` for read buffers.
- docs/Platform_Layer.md — the underlying syscalls; BASICFORTH_PATH file search.
