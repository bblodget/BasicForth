# Shelling Out — Running Linux Programs from BasicForth

BasicForth runs on Linux, so the whole catalog of Unix tools is already
installed next to it — `ls`, `grep`, `git`, `vi`, `fzf`, your compiler. Rather
than reimplement those in Forth, BasicForth **runs them as programs**: it asks
the OS to start a command, waits for it, and gets back an exit status. This is
how `edit` opens your editor, and it is the seed of using BasicForth as an
interactive shell.

## Spawn, not link

There are two ways to reach the outside world:

- **Spawn** a program — `fork` a child, `exec` the command, `wait` for it. The
  child is a separate process; you talk to it the way a shell does.
- **Link** a library — call its functions in-process (an FFI / dynamic linker).

BasicForth uses **spawn**. It costs nothing architecturally: `fork`/`execve`/
`wait` are ordinary Linux syscalls, so BasicForth stays a pure-assembly,
no-libc, statically linked binary — running a program is not the same as linking
it. (Linking libraries — for Vulkan, audio, an in-window editor — is a separate,
later decision that would end the no-libc design; see WildIdeas.md.)

## `sh` — run a command at the prompt

```
> sh ls -la
> sh git status
> sh grep -n drift chase.fs
```

`sh` takes **the rest of the input line** and runs it as a shell command, the way
you would type it at a terminal. Output goes straight to your terminal. The
interpreter resumes after the command, so a line like `sh date` then carries on
normally. `sh` is transient — it defines nothing, so it is never captured into
your module. Bare `sh` with no command prints a usage hint.

Because it runs through `/bin/sh -c`, the full shell is available — pipes,
globs, redirection, `$VARS`:

```
> sh ls *.fs | sort
> sh echo "$HOME"
```

BasicForth also has a few **built-in** shell-like words — `pwd`, `cd`, `ls`,
`cat`, `more`, `pushd`/`popd`/`dirs` (see the Manual's *Shell-Like Words*). Those
are tiny native conveniences with no flags; `sh` is the escape hatch to the real
programs and everything else (`sh ls -la`, `sh git diff`). One important
difference: `cd` changes BasicForth's own working directory, but a directory
change *inside* a `sh` command affects only that child — `sh cd /tmp` does
nothing lasting. Use the built-in `cd` to move BasicForth itself.

## `(system)` — the primitive underneath

```
(system) ( c-addr u -- status )
```

`(system)` runs the command string `c-addr u` via `/bin/sh -c` and returns the
child's **exit status** (0–255), or `-1` if the spawn itself failed. `sh` is a
thin wrapper over it. Use `(system)` directly when you want the status or are
building the command in code:

```
: backup ( -- )
    s" cp game.fs game.bak"  (system)
    if  ." backup failed" cr  then ;
```

(`s"` also works at the prompt — `s" ls -l" (system) drop` is fine — but
`sh` remains the convenient way to run commands interactively.)

## How it works

`(system)` is the Forth name for the `platform_system` call (see
Platform_Layer.md):

1. The terminal is restored to **cooked** mode (BasicForth's prompt runs raw),
   so a full-screen child like `vi` starts from a clean state. The next
   interactive read re-enters raw mode lazily.
2. `fork` (x86-64) or `clone(SIGCHLD, …)` (ARM64, which has no `fork`) makes a
   child.
3. The child `execve`s `/bin/sh -c <cmd>`, inheriting BasicForth's standard
   input/output/error and its **environment** — `$PATH` finds the program,
   `$EDITOR`/`$TERM` reach it. (BasicForth saves `environ` at startup for this.)
4. The parent `wait4`s for the child and returns its exit status.

Everything is **synchronous**: the command runs to completion, sharing your
terminal, before the prompt returns.

## What you can and can't do (yet)

Available now:

- Run any command and see its output on the terminal (`sh`, `(system)`).
- Branch on whether it succeeded (the exit status).
- Open files in your `$EDITOR` — `edit <word>` is built on this (see
  Line_Editor.md).

Not yet — these need pipes (`pipe`/`dup2`), a planned next step:

- **Capturing a command's output into Forth** (e.g. read `git rev-parse` into a
  string). Today output goes to the terminal, not back onto the stack.
- **Feeding Forth data into a command's stdin** (`… | grep`, `… | fzf`).

## Limitations and gotchas

- **Synchronous only.** `sh sleep 10` blocks the REPL for ten seconds. There is
  no backgrounding.
- **It is a shell.** The command goes to `/bin/sh -c`, so shell metacharacters
  are interpreted. When you build a command string from data, mind quoting (and,
  for untrusted data, injection) — the same caution as any `system()`.
- **No output capture yet** (see above).
- **`sh` reads to end of line**, so it consumes the rest of the input line —
  put other Forth words on their own line.

## Roadmap

The spawn primitive is the foundation; the shell-like experience grows from it:

- `pipe`/`dup2` → capture command output into Forth, and pipe Forth data out
  (`history | grep`, picking with `fzf`).
- A `!` alias for `sh`, and quality-of-life around recall.
- Tab-completion presented through `fzf` (candidates are the dictionary, so
  generation stays native).

See also: **Line_Editor.md** (`edit` via `$EDITOR`), **Platform_Layer.md**
(`platform_system`, syscalls), **WildIdeas.md** (the Forth-as-shell direction).
