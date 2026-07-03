# BasicForth Manual

A modern Forth environment for Linux, inspired by 1980s BASIC. Boot up and
start coding — games, robots, whatever you want.

## Prerequisites

### x86-64 (native build)

```
sudo apt install binutils gcc make
```

### ARM64 (cross-compile from x86-64)

```
sudo apt install binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu make qemu-user-static
```

- `binutils-aarch64-linux-gnu` — cross-assembler and linker (`as`, `ld`)
- `gcc-aarch64-linux-gnu` — cross-compiler (needed for unit tests)
- `qemu-user-static` — user-mode emulation to run ARM64 binaries on x86

### ARM64 (native build on ARM64 board)

```
sudo apt install binutils gcc make
```

## Building and Running

Run `make help` for a full list of targets.

### Native build

```
make
cd src/arch/x86        # or arm64
./basicforth
```

This auto-detects your architecture — builds x86-64 on x86 hosts, ARM64 on ARM64 hosts.

### x86-64 (explicit)

```
make x86
./src/arch/x86/basicforth
```

### ARM64 (cross-compile and run via QEMU)

```
make arm64
make run-arm64
```

### ARM64 (deploy to a remote board)

See `src/arch/arm64/deploy_template.sh` — copy it to `deploy.sh` and
customize with your board's SSH hostname.

### How QEMU User-Mode Works

When you run `make run-arm64` on an x86-64 host, the Makefile invokes
`qemu-aarch64-static` to run the ARM64 binary. This is QEMU **user-mode
emulation** — it translates ARM64 instructions to x86-64 on the fly
(dynamic binary translation), while Linux syscalls pass straight through
to the host kernel.

No virtual machine, no emulated OS — just CPU translation. That's why it's
fast and why our syscall-based programs work perfectly.

The `qemu-user-static` package also registers with the kernel via
**binfmt_misc**, which teaches Linux to recognize ARM64 ELF binaries and
run them through QEMU automatically. So `./basicforth` just works, even
though it's an ARM64 binary on an x86 machine.

**Limitation:** user-mode QEMU only emulates the CPU, not hardware. Programs
that access framebuffers, GPIO, or device-specific ioctls need real hardware.

### Unit Tests

```
make run-test-x86
make run-test-arm64
```

## Usage

```
./basicforth                        # interactive REPL
./basicforth file.fs                # load file, then enter REPL
```

Run from the build directory (`src/arch/x86/` or `src/arch/arm64/`)
where `core.fs` is located, or set `BASICFORTH_PATH` to find library
files from any directory:

```
BASICFORTH_PATH=src/forth src/arch/x86/basicforth
```

`BASICFORTH_PATH` accepts a colon-separated list of directories, like
`PATH`. For example, to find both `core.fs` and the bundled examples:

```
BASICFORTH_PATH=src/forth:examples src/arch/x86/basicforth snake.fs
```

The `basicforth` binary contains only the assembly primitives; everything else
(`cr`, `.`, `if`, `marker`, `save`, the help words, …) lives in `core.fs`, loaded
at startup. If `core.fs` is found neither in the current directory nor via
`BASICFORTH_PATH`, BasicForth prints a warning to **stderr** and comes up with
only the primitives:

```
basicforth: core.fs not found - only built-in primitives are available.
  Set BASICFORTH_PATH to the directory containing core.fs.
```

If you see that, point `BASICFORTH_PATH` at the directory holding `core.fs`
(typically `…/src/forth`).

### Environment Variables

| Variable          | Description                                              |
|-------------------|---------------------------------------------------------|
| `BASICFORTH_PATH` | Colon-separated directories searched when a file is not found in CWD |
| `BASICFORTH_SESSION` | `1` forces the interactive session (SAVE) on, `0` forces it off; unset = on at a terminal |
| `BASICFORTH_EDITOR` | `1` forces the line editor on, `0` forces it off; unset = on when stdin is a terminal |
| `BASICFORTH_DOCS` | Colon-separated directories of `*.md` topics for the `man` / `topics` / `apropos` help words |

When `INCLUDE`, `INCLUDED`, or the startup `core.fs` load fails to find
a file in the current directory, BasicForth searches each directory in
`$BASICFORTH_PATH` in order and loads the first match
(`$DIR/filename`). The current directory is always tried first; empty
segments (e.g. from a leading, trailing, or doubled `:`) are skipped.
If the variable is not set, only CWD is searched.

### Startup Sequence

At startup, BasicForth:
1. Loads `core.fs` from CWD, falling back to `$BASICFORTH_PATH/core.fs`
2. If a filename argument was given, loads it via INCLUDED
3. Enters the interactive REPL

### Loading Files from the REPL

```
> include ../../../examples/snake.fs
 ok
> snake
```

`INCLUDE` parses the next word as a filename and loads it. Paths are
relative to the current working directory (the build directory).

For the compile-only `S"` form (e.g., inside a colon definition):

```
> : load-snake s" ../../../examples/snake.fs" included ; load-snake
```

### Executable Scripts (`#!`)

A Forth file can be run directly as a Unix executable script. Give it a
`#!` first line pointing at the interpreter, make it executable, and run
it:

```
#!/usr/bin/env basicforth
.( Hello from BasicForth) cr
bye
```

```
$ chmod +x hello.fs
$ ./hello.fs
Hello from BasicForth
```

BasicForth ignores a leading `#!` line (only the first line, and only an
exact `#!` — a leading `#` decimal literal such as `#10` is unaffected).
Error line numbers still count the shebang as line 1, so they match the
file's physical lines.

Notes:
- End the script with `bye` (or `0 bye-code`); otherwise BasicForth enters
  the interactive REPL after the script runs.
- If the script hits an error (an undefined word, a failed parse, a stack
  underflow, `ABORT`, …), BasicForth prints the diagnostic and exits with a
  non-zero status instead of dropping into the REPL — so a Forth utility fails
  like any other Unix program. (Errors while loading `core.fs` still drop to
  the REPL, since a broken bootstrap is a development problem, not a script
  failure.)
- `core.fs` is still loaded from the current directory or `BASICFORTH_PATH`,
  so set `BASICFORTH_PATH` if the script is run from an arbitrary directory.
- With `#!/usr/bin/env basicforth`, `basicforth` must be on your `PATH`;
  alternatively use an absolute path to the binary.
- The startup banner is printed only when BasicForth enters the interactive
  REPL (a script ending in `bye`/`bye-code` exits first) and only when stdout
  is a terminal, so a script run as a utility produces clean output whether its
  output goes to a terminal, a pipe, or a file.
- `basicforth -v` (or `--version`) prints the version/banner string and exits
  immediately. Unlike the startup banner it is not gated on a terminal, so it
  works through a pipe. At the REPL, the `version` word prints the same string.

### Command-Line Arguments

Scripts can read their arguments, mirroring gforth:

| Word | Stack | Description |
|------|-------|-------------|
| `argc` | ( -- a-addr ) | variable: number of arguments (`argc @`) |
| `argv` | ( -- a-addr ) | variable: pointer to the argument vector |
| `arg` | ( u -- c-addr u ) | the uth argument as a string; `0 0` if out of range |
| `next-arg` | ( -- c-addr u ) | return the next argument and consume it; `0 0` when none remain |
| `shift-args` | ( -- ) | drop the first argument, decrementing `argc` |

The auto-loaded script itself is removed from the vector at startup, so a
script's own first argument is `arg[1]` and the first `next-arg`. `arg[0]`
is the interpreter name. Both of these pass `level1.txt` as the first
argument:

```
basicforth game.fs level1.txt        # game.fs is the script
./game.fs level1.txt                 # shebang launcher, same result
```

### Exiting With a Status

`bye-code ( n -- )` exits with status `n` (visible to the shell as `$?`)
and prints nothing, so a utility's output is not corrupted. Plain `bye`
prints `Goodbye!` and exits 0, for interactive use.

```forth
matched? if  0 bye-code  else  1 bye-code  then
```

A script that errors before reaching `bye`/`bye-code` exits with status `1`
automatically (see the Notes above), so you only need an explicit `bye-code`
to return a *specific* status on success or on a handled condition.

See `examples/echo.fs` for a small Unix utility (a Forth `echo`) that uses
`next-arg` and `bye-code`.

### Writing to stdout, stderr, and files

`TYPE` and `EMIT` always write to standard output. To target a specific
stream — in particular standard error, so error text stays out of a utility's
real output — use the file-output words. A *fileid* is a raw OS file
descriptor; the three standard streams are predefined:

| Word | Stack | Description |
|------|-------|-------------|
| `stdin` | ( -- 0 ) | the standard-input fileid (0) |
| `stdout` | ( -- 1 ) | the standard-output fileid (1) |
| `stderr` | ( -- 2 ) | the standard-error fileid (2) |
| `write-file` | ( c-addr u fileid -- ior ) | write `u` bytes to `fileid` |
| `write-line` | ( c-addr u fileid -- ior ) | write `u` bytes plus a newline |

Both return an `ior` (I/O result): `0` on success, otherwise the positive
`errno` (e.g. `9` = `EBADF` for a bad descriptor). For example, a utility that
reports a problem without corrupting its stdout:

```forth
: warn ( c-addr u -- ) stderr write-line drop ;
: main ... ok? 0= if  s" input out of range" warn  1 bye-code  then ... ;
```

(`S"` is compile-only, so build strings inside a definition as shown.)

Note: `write-file`/`write-line` loop over `write(2)` until **all** the bytes are
written, so a short write never silently truncates output; the `ior` is non-zero
only on a real error.

See `examples/lines.fs` for a small utility that writes its data to stdout and
its diagnostics to stderr, so `./lines.fs a b > out` leaves clean data in `out`
while the log stays on the terminal.

### Reading and Writing Files

Files are opened by name and accessed through a *fileid* (a raw OS file
descriptor, the same kind of value as `stdin`/`stdout`/`stderr`). These follow
the ANS File-Access wordset:

| Word | Stack | Description |
|------|-------|-------------|
| `r/o` `w/o` `r/w` | ( -- fam ) | access method: read-only / write-only / read-write |
| `bin` | ( fam1 -- fam2 ) | binary mode — a no-op on Linux |
| `open-file` | ( c-addr u fam -- fileid ior ) | open an existing file |
| `create-file` | ( c-addr u fam -- fileid ior ) | create or truncate, then open (mode 0666) |
| `close-file` | ( fileid -- ior ) | close |
| `read-file` | ( c-addr u1 fileid -- u2 ior ) | read up to u1 bytes; u2 = actual, 0 at end of file |
| `read-line` | ( c-addr u1 fileid -- u2 flag ior ) | read one line (≤ u1 chars); newline not stored; flag false only at end of file |
| `file-size` | ( fileid -- ud ior ) | size in bytes, as a double |
| `rename-file` | ( c-addr1 u1 c-addr2 u2 -- ior ) | rename/replace file1 → file2 (atomic) |

Every operation returns an `ior` (`0` success, else the positive `errno`).
A typical read-a-whole-file-in-chunks loop (`S"` is compile-only, so build the
name inside a definition):

```forth
create buf 4096 allot
: dump ( c-addr u -- )
    r/o open-file if drop exit then        ( fileid )       \ bail on open error
    >r
    begin  buf 4096 r@ read-file drop  dup 0>  while         ( u2 )
        buf swap stdout write-file drop
    repeat drop
    r> close-file drop ;
```

`read-line` returns one line per call into a buffer — the newline (and a CR
immediately before it) are not stored, and `flag` is false only once end of
file is reached with nothing left to read, which is the loop's stop signal. At
most `u1` characters are stored, so size the buffer for your longest line; a
line longer than `u1` fills the buffer and the rest of that line is discarded,
so the next call starts at the following line.

```forth
create line 256 allot
: cat-lines ( c-addr u -- )
    r/o open-file if drop exit then        ( fileid )       \ bail on open error
    >r
    begin  line 256 r@ read-line drop  while                 ( u2 )
        line swap stdout write-line drop   \ write-line re-adds the newline
    repeat drop
    r> close-file drop ;
```

`create-file` pairs with `write-file` (above) to produce files. See
`examples/cat.fs` for a complete Forth `cat` — args → `open-file` → `read-file`
loop → `write-file` to stdout → `close-file`, with errors on stderr and a
non-zero exit on failure. `examples/cat-lines.fs` is the same program written
with `read-line`/`write-line` instead, so you can compare the byte-exact and
line-oriented styles side by side (the line version normalizes CRLF to LF).
`examples/sort.fs` goes further: it slurps a file with `file-size`/`read-file`,
sorts the lines with `compare`, and writes `<name>_sorted.<ext>` with
`create-file`/`write-line`.

### Dynamic memory

The dictionary is a fixed arena, so for large or variable-size buffers there is
a heap — memory obtained from the kernel on demand (via anonymous `mmap`) and
kept separate from the dictionary. It is the standard ANS MEMORY wordset:

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `allocate` | ( u -- a-addr ior ) | reserve `u` bytes; `ior` 0 on success, else the `errno` (and `a-addr` 0) |
| `free` | ( a-addr -- ior ) | release a block from `allocate`/`resize` |
| `resize` | ( a-addr1 u -- a-addr2 ior ) | change a block's size, preserving contents up to the smaller of old/new; may move it |

`allocate` of `0` bytes is rejected with a non-zero `ior` (nothing is
allocated). On a `resize` failure the original block is unchanged and
`a-addr2 = a-addr1`. Allocations are page-granular (rounded up to 4 KB), so the
heap suits a handful of large buffers rather than many tiny ones.

```forth
1024 allocate  ( a-addr ior )
if   drop                  \ failed: discard the (zero) a-addr
     ." out of memory" cr
else ( a-addr )
    dup 42 swap !          \ use the block...
    free drop              \ ...then return it
then
```

`examples/tac.fs` (the Unix `tac` — print stdin's lines in reverse) is the
worked example: a pipe's size is unknown, so it slurps stdin into an
`allocate`d buffer that doubles with `resize` whenever it fills, then emits the
lines back-to-front and `free`s it. It has no fixed input limit, in contrast to
`sort.fs`, which relies on `file-size` and a fixed buffer.

### Saving your work — modules

The words you define are a **module** you can save to a named file and load
back, like 1980s BASIC's `SAVE "GAME"` / `LOAD "GAME"`:

```
> : greet ." hello!" cr ;
> : double dup + ;
> save mygame.fs
saved to mygame.fs
> bye
$ basicforth mygame.fs     # later — open the module
> greet
hello!
```

`basicforth <file>` opens a module (defines its words, makes it the current
file); mid-session, `load <file>` does the same; `new` clears to a blank slate.
A bare `save` re-writes the **current file** wherever it lives (it's remembered
as an absolute path, so `cd` can't move it); `save <name>` is "save as" in the
current directory.

`save` records the *source* of your definitions (not a memory image), so a module
file is a readable, editable Forth file. Only definitions are captured —
transient actions like `5 double .` are not — and saving is idempotent and
cumulative (it rewrites the whole file plus your edits, so redefinitions pile
up). `compact <name>` writes a **deduped** sibling (`game.fs` → `game.compact.fs`)
— each word's latest source once — so you can `diff` it and adopt the clean one.
Capture is interactive-only: a piped script captures nothing.

For an edit/compile/run loop, edit the file in another terminal and type `reload`
to pull the changes in (it forgets the module and re-reads the current file).
Files stay pure definitions (the `-session`/`reload`/`load`/`save` lines are never
written into them). When you have unsaved changes, `new`/`load`/`bye` ask
"save first? (y/n)" at the terminal before discarding (`reload` doesn't — it
always pulls from disk; pipes and scripts never prompt). See `docs/Persistence.md`
for the full module model and limitations (notably: variable/value *contents* are
not persisted, only the definitions).

### Looking at a definition (`see`)

`see <name>` prints the source of a word's most recent definition — exactly what
you typed, comments and all:

```
> : square dup * ;   \ a number times itself
> see square
: square dup * ;   \ a number times itself
```

It covers words you define interactively this session (it reads the same capture
log as `save`). A redefinition shadows the earlier one, and `see` works for any
defining word, not just `:`. See `docs/See.md`.

### Listing your words (`.module`)

`words` lists the entire dictionary — every built-in plus your own, hundreds of
names. Usually you only want to see *your* words, so `.module` lists just the
ones you've defined on top of `core.fs` — your module — newest first, with a
count:

```
> 22 constant W   variable score   : tick  score @ 1+ score ! ;
> .module
3 words in this module (newest first):
tick score W
```

It's the BASIC `LIST` — *"what have I built so far?"* — and it counts every kind
of definition (`:`, `variable`, `constant`, `defer`, …). Anything you `load` or
`include` counts as part of your module too.

### Finding references (`uses`)

Where `.module` lists your words and `see` shows one definition, `uses
<word>` greps across them — it lists the module words whose source mentions
`<word>` as a whole word (case-insensitive), so you can answer *"if I rename
this, what do I touch?"*:

```
> uses score
score is used by: tick
```

Like `see`, it finds each word's source either way — from the interactive
capture log for words you typed, or from the file for words loaded as a startup
argument, via `load`, or via `include` — so it covers everything
`.module` lists. It skips `<word>`'s own defining line.

### Forgetting definitions (`marker`)

`marker <name>` sets a restore point in the dictionary. Running `<name>` later
forgets `<name>` and everything defined after it, reclaiming the space — the
standard way to undo a batch of definitions and the basis of an
edit/compile/run loop.

```
> marker -work
> : double  dup + ;
> 5 double .
10
> -work          \ forget double and -work itself
> double
? double         \ gone
```

By convention marker names start with `-`. See `docs/Marker.md` for details
(nesting, what is and isn't reclaimed, and the planned tie-in with sessions).

### Deferred words (`defer` / `is`)

`defer <name>` creates a word whose behavior you set — and can change — later
with `is`. It lets you write the high-level structure first and fill in (or swap)
the parts without recompiling the callers:

```
> defer play
> : game  ." [" play ." ]" cr ;   \ compiles now; play is deferred
> :noname ." stub" ; is play
> game
[stub]
> : real  ." REAL" ;
> ' real is play                  \ swap the action; game is NOT recompiled
> game
[REAL]
```

`is` is state-aware like `to`, so it works inside definitions too. An
uninitialized deferred word aborts with a message if run. See
`docs/Deferred_Words.md`, and `docs/Redo.md` for recompiling ordinary words.

### Recompiling a word (`redo`)

Because compiled calls are baked in, redefining a leaf word does not change words
already compiled to call it. `redo <name>` recompiles `<name>` from the source
you typed, so it picks up the redefined leaf:

```
> : setup ." OLD" cr ;
> : snake setup ;
> : setup ." NEW" cr ;   \ improved leaf
> snake
OLD                       \ still the old setup
> redo snake
> snake
NEW                       \ recompiled against the new setup
```

`redo` works on words defined at the REPL this session; for file-loaded words it
points you to edit-and-`reload`, and primitives have no source. See
`docs/Redo.md`.

## Built-in Help

BasicForth can browse its own documentation. Point `BASICFORTH_DOCS` at one or
more directories of `*.md` files (colon-separated, like `BASICFORTH_PATH`):

```
$ BASICFORTH_DOCS=docs/Language-Reference:docs/Tutorial ./basicforth
> topics                         \ list topics, grouped by section
Language-Reference
  Arithmetic  Comparison  Memory  Stack
Tutorial
  Snake
> man stack                      \ page a topic (case-insensitive, .md added)
# Stack Manipulation
...
-- more (space=page, q=quit) --
> apropos dup                    \ which topics mention "dup"?
Stack (Language-Reference)
Snake (Tutorial)
```

- Each directory in `BASICFORTH_DOCS` is a **section**, named by the directory's
  last path component (like the sections of the Unix `man` system, but named
  rather than numbered).
- `topics` lists every `*.md` file (without the extension), grouped under its
  section.
- `man <topic>` finds `<topic>.md` (case-insensitive) across all sections and
  pages it one screenful at a time — press space for the next page or `q` to stop.
- `apropos <keyword>` lists the topics whose file contains `<keyword>`
  (case-insensitive substring match), each labelled with its section.

If `BASICFORTH_DOCS` is unset, each word prints `(BASICFORTH_DOCS not set)`.
See `docs/Help_System.md` for details.

### Interactive tutorials

Where `man` pages a whole file, `tutorial` walks one **one step at a time** and
returns to the prompt after each step, so you can try the examples before moving
on:

```
> tutorial Snake                \ start a lesson (name like man, case-insensitive)
...
[ next = continue   back = previous   step 1 ]
> next                          \ next step    (back = previous step)
```

Steps are split on the file's `## ` headings, so any docs file can be walked this
way. See `docs/Tutorial_System.md`.

Two tutorials ship today, each building a complete terminal game:

- `tutorial Snake` — learn the language *bottom-up*, one small word at a time,
  until the last word is the whole game. Finished program: `examples/snake-mini.fs`.
- `tutorial Chase` — learn to *design* a game *top-down*: sketch the whole shape
  first with `defer`, run the empty skeleton, then fill in the parts and give each
  monster its own swappable brain. Finished program: `examples/chase.fs`.

## Shell-Like Words

Navigate and inspect the filesystem from the REPL without leaving BasicForth:

```
> pwd                            \ print the current directory
/home/you/project
> ls                             \ list the current directory (or: ls <dir>)
core.fs   notes.txt   src
> cat notes.txt                  \ dump a file to stdout (more <file> to page it)
remember to feed the snake
> cd src                         \ change directory; bare `cd` returns to startup
> pushd /tmp                     \ save the current dir and cd to another
> popd                           \ return to the saved dir (dirs lists the stack)
```

| Word | Stack | Meaning |
|------|-------|---------|
| `pwd` | ( -- ) | print the current working directory |
| `cd` | ( "dir" -- ) | change directory; **bare `cd`** returns to the startup directory; `cd ~` expands `~` to `$HOME` |
| `ls` | ( "[dir]" -- ) | list a directory (current by default), one entry per line |
| `cat` | ( "file" -- ) | write a file to stdout |
| `more` | ( "file" -- ) | page a file a screenful at a time (`page` already means clear-screen) |
| `pushd` | ( "dir" -- ) | save the current directory, then `cd` to `<dir>` |
| `popd` | ( -- ) | return to the most recently `pushd`-ed directory |
| `dirs` | ( -- ) | list the directory stack: current first, then saved (top first) |

- `cd` changes the **real process directory**, so relative `include`,
  `open-file`, and `save <name>` agree with it. Bare `cd` (no argument) returns
  to the startup directory. (A bare `save` still rewrites the current module
  wherever it lives — its path is remembered absolute — so `cd` can't move it.)
- A failed command (missing file/directory, bad path) prints an error and
  signals failure — the REPL shows the message and **no `ok`** — rather than
  silently succeeding.
- Paths come from the next word, so they cannot contain spaces yet.

See `docs/Shell_Words.md` for details.

### Running real Linux programs (`sh`)

The words above are small built-ins. For everything else — flags, pipes, `git`,
`grep`, any installed program — **`sh`** runs the rest of the line as a real
shell command:

```
> sh ls -la                      \ GNU ls with flags (the built-in ls takes none)
> sh grep -n drift chase.fs
> sh git status
```

`sh` goes through `/bin/sh -c`, so pipes, globs, and `$VARS` all work, and the
whole line is the command (no single-word path limit). Output goes to the
terminal and nothing is captured to your module. The underlying primitive,
`(system) ( c-addr u -- status )`, returns the command's exit status for use in
code. BasicForth runs these as separate programs (spawn, not link), so it stays a
small static binary. See `docs/Shelling_Out.md`.

## The Prompt

BasicForth presents an interactive prompt:

```
> 
```

Type Forth expressions and press Enter. Type `bye` to exit.

### Line Editing

At a terminal the prompt is a small line editor: move the cursor with the
**left/right arrows**, jump to the start/end with **Ctrl-A/Ctrl-E**, and
insert or delete (Backspace) anywhere in the line. The **up/down arrows** recall
previous lines from the command history, which you can edit before pressing
Enter. A line wider than the terminal **scrolls sideways** instead of wrapping.

A `:` definition can span several lines; while one is open the prompt becomes
`... ` until `;` closes it. **`edit <word>`** opens an existing definition in your
editor (`$VISUAL`/`$EDITOR`/`vi`); when you save and quit, BasicForth recompiles
it — preserving your multi-line formatting — and updates every word that calls it.
See `docs/Line_Editor.md` for the full key list and details.

## Numbers

BasicForth parses number literals in several bases. The default base is
decimal (10), controlled by the `BASE` variable.

### Decimal

Plain digits are parsed in the current base (decimal by default):

```
> 42
= 42
> 0
= 0
```

The `#` prefix forces decimal regardless of the current base:

```
> #99
= 99
```

### Hexadecimal

The `$` prefix selects base 16. Hex digits A–F are case-insensitive:

```
> $FF
= 255
> $ff
= 255
> $1A3
= 419
```

### Binary

The `%` prefix selects base 2:

```
> %1010
= 10
> %11111111
= 255
```

### Negative Numbers

A `-` sign can appear before or after the base prefix:

```
> -7
= -7
> -$10
= -16
> $-10
= -16
```

Both forms are equivalent.

### Invalid Input

If the input cannot be parsed as a number, BasicForth reports an error:

```
> hello
  Not a number
> $GG
  Not a number
> %2
  Not a number
```

Digits are validated against the current base — `G` is not a valid hex digit,
and `2` is not a valid binary digit.

## Stack

BasicForth uses a data stack to pass values between words. Numbers are pushed
onto the stack as they are entered. Stack manipulation words will be
documented here as they become available in the interactive environment.

### Stack Words (planned)

| Word     | Effect             | Description                   |
|----------|--------------------|-------------------------------|
| `DUP`    | `( a -- a a )`     | Duplicate top of stack        |
| `DROP`   | `( a -- )`         | Remove top of stack           |
| `SWAP`   | `( a b -- b a )`   | Exchange top two items        |
| `OVER`   | `( a b -- a b a )` | Copy second item to top       |
| `.S`     | `( -- )`           | Display the stack (non-destructive) |
