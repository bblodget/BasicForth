# Session Persistence (SAVE)

BasicForth can remember the words you define across sessions, in the spirit of
1980s BASIC: define some words, `save`, quit, come back later and they're
already there. Persistence is **source-replay** — it records the *source text*
of your definitions and re-runs it at startup. There is no binary image and no
dictionary serialization; `session.fs` is just an ordinary Forth source file
that happens to be written by the machine.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `save` | ( -- ) | write the captured definitions to `session.fs` in the current directory |

There is no separate "load" word: an interactive session **auto-loads**
`session.fs` from the current directory at startup (if present), right after
`core.fs`.

## What gets captured

While you type at the interactive prompt, BasicForth watches each line. A line
(or group of lines) is captured **only if it adds to the dictionary** — i.e. it
defines a word. Transient actions are *not* captured:

```
> : double dup + ;      \ captured
> variable count        \ captured
> 5 double .            \ NOT captured (just prints 10)
> page                  \ NOT captured (just clears the screen)
```

Multi-line definitions are captured as a unit:

```
> : factorial ( n -- n! )
>   dup 2 < if drop 1 exit then
>   dup 1- recurse * ;
```

A definition that **errors** partway through is rolled back and not captured.

`save` then writes everything captured (plus anything previously in
`session.fs`) back out. Saving is **idempotent** — saving twice in a row leaves
the file unchanged — and **cumulative** — each session's new definitions are
appended to what was already there.

```
> : greet ." hello" cr ;
> save
saved to session.fs
```

`save` is a no-op (prints `nothing to save`) when nothing has been captured, so
it never leaves an empty `session.fs` lying around.

## Scope: interactive sessions only

Capture and auto-load are active **only in an interactive terminal session** —
when standard input is a TTY and no script file was given on the command line.
Running a Forth script (`basicforth tool.fs`) or piping input never auto-loads
your session or captures anything, so utilities and automation stay clean.

You can override the default with the `BASICFORTH_SESSION` environment variable:

| Value | Effect |
|-------|--------|
| unset | default — on when stdin is a terminal |
| `1`   | force the session on (e.g. to drive capture through a pipe) |
| `0`   | force the session off, even at an interactive terminal |

## Limitations

Persistence saves **definitions, not runtime state**. A `variable` reloads
*uninitialized*; a `value` reloads at its original literal, not its current
contents:

```
> variable hits   10 hits !
> save             \ captures `variable hits`, NOT the `10 hits !`
\ ...next session: `hits @` is 0, not 10
```

Initialize such state inside a defining word (e.g. `10 value hits`) so the value
is part of the definition.

Other notes:

- **Redefinitions accumulate.** Redefining a word across sessions appends each
  version to `session.fs`; on reload they run in order, so the last one wins,
  but the file grows. A compacting `save` is possible future work.
- **Reload is bounded by dictionary space.** A very large accumulated session
  can exceed the fixed dictionary arena on reload — the same limit you'd hit
  typing it all in. This is one of the motivations for a future growable
  dictionary.

## How it works

The capture machinery is built on the dynamic-memory heap (see
[Core_Primitives.md] / the MEMORY wordset): the session log lives in a
heap-backed buffer that grows with `RESIZE` as you define more.

The interactive REPL (in `main.s`) drives three hook words defined in `core.fs`
and registered with the internal `(hook!)` primitive:

- `(session-seed)` — at startup, copies an existing `session.fs` into the log so
  `save` rewrites it cumulatively. (The actual *loading* of `session.fs` is done
  in assembly by `main.s`, exactly like `core.fs`, because calling `INCLUDED`
  from inside a colon word re-enters the interpreter unsafely.)
- `(capture-line)` — called after each interpreted line; accumulates it and
  flushes a completed definition to the log (detected by `LATEST` advancing — a
  new named header was linked — while `STATE` is back to interpret, so bare
  `ALLOT`/`,`/`C,` that move only `HERE` are not captured).
- `(capture-reset)` — called at the top of the REPL loop; discards a pending
  partial definition left by a line error or fault.

`save` writes the log to `session.fs` with the ordinary file-access words.
