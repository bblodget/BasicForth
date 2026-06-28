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
| `save` | ( -- ) | write the captured definitions to `session.fs` in the startup directory |
| `-session` | ( -- ) | forget everything defined since startup (session words + interactive definitions) |
| `reload` | ( -- ) | `-session`, then re-`include` the (possibly edited) `session.fs` |

There is no separate "load" word: an interactive session **auto-loads**
`session.fs` at startup (if present), right after `core.fs`.

`session.fs` lives in the **startup directory** — the directory BasicForth was
launched in, captured once at boot. `save` and `reload` always use
`<startup>/session.fs`, so the `cd` shell word can move the working directory
without scattering your session across the tree (see `docs/Shell_Words.md`). If
the boot-time `getcwd` fails, it falls back to a plain relative `session.fs`.

## The edit / compile / run loop

`session.fs` is a plain, hand-editable Forth file. Edit it in another terminal
(vi, your editor of choice), then in the running BasicForth pull the changes in:

```
> reload
```

`reload` forgets all the current session definitions (`-session`) and re-loads
`session.fs`, so you get a clean redefinition every time — no duplicate buildup,
and definitions you deleted from the file actually disappear. You can also do the
two steps by hand (`-session` then `include session.fs`).

This works because at startup BasicForth records a **restore point** just past
`core.fs`; `-session` rewinds the dictionary to it (keeping `core.fs` and the
session words themselves, including `-session`/`reload`). Markers underpin this —
see [Marker.md](Marker.md).

`session.fs` stays **pure definitions** — `-session` and `reload` are never
written into it (capture logs only lines that *define* a word; forgetting moves
`LATEST` backward and is ignored, and `reload` suppresses its own line). So the
file is always clean to hand-edit.

If the edited `session.fs` has an error, `reload` shows the file's own
`session.fs:line: ? token` diagnostic, then reports `reload: session.fs had
errors — session may be incomplete`. Loading stops at the bad line, the in-memory
log is left untouched (so a later `save` won't persist a broken file), and the
REPL keeps running — fix the file and `reload` again.

If `session.fs` is missing or unreadable, `reload` reports `reload: cannot read
session.fs` and does nothing — it does **not** forget the current session or
clear the log, so nothing is lost.

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
your session or captures anything, so utilities and automation stay clean. The
session words respect this too: outside an interactive session `reload` is a
no-op (it reports `reload: no active session` rather than auto-loading
`session.fs`), `-session` forgets nothing, and `save` has an empty log to write.

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

`save` writes the log to a temporary `session.fs.new` and then `rename-file`s
it over `session.fs` — an atomic replace, so a write failure (e.g. a full disk)
leaves the existing `session.fs` untouched rather than truncating it.
