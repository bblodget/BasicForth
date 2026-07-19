# Interactive Tutorial (`tutorial` / `next` / `back`)

BasicForth can walk you through a lesson **one step at a time**, right at the
REPL. Unlike `man` (which pages a whole file), the tutorial shows a single step
and then **returns to the prompt**, so you can type the examples yourself before
moving on with `next`.

A tutorial is just one of the Markdown files in a `BASICFORTH_DOCS` section — the
same files `help` browses. No special file format: each lesson is split
into steps by its `## ` headings.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `tutorial` | ( "name" ["step"] -- ) | start tutorial `<name>` (resolved case-insensitively across the docs dirs, like a `help` topic) at step 1 — or at an optional step: a number, or the name of a `value` holding one. With no name, prints a hint and the `tutorials` list |
| `next` | ( -- ) | show the next step |
| `back` | ( -- ) | show the previous step |
| `step` | ( ["step"] -- ) | replay the current step (handy after running something that drew all over the screen); with a number or a `value` name, jump straight there — `step 7`, `step tstep` |
| `end-tutorial` | ( -- ) | leave the tutorial: forgets which step `next` would show, nothing else — **your definitions remain** |

## How a file becomes steps

Each **`## ` (level-2) heading** starts a new step. Everything before the first
`## ` — the `# Title` and any intro — is **step 1**. So a file like:

```
# Lesson One
A short intro.

## Adding
    1 2 + .          \ prints 3

## Defining a word
    : square dup * ;
    5 square .       \ prints 25
```

walks as three steps: the intro, then *Adding*, then *Defining a word*. The same
file still reads fine under `help` — the headings are ordinary Markdown.

## Using it

```
> tutorial Snake
# Snake — Build Your First Game
...

[ step 1/25:  next   back   step [n] = replay/jump   end-tutorial ]
 ok
> next
## The stack — Forth's workspace
...

[ step 2/25:  next   back   step [n] = replay/jump   end-tutorial ]
 ok
> : square dup * ;        \ try things between steps — the REPL is live
 ok
> 5 square .
25  ok
> back                    \ review the previous step
```

The name is the file's base name without `.md`, matched case-insensitively —
`tutorial Snake`, `tutorial snake`. `Tutorial` directories on
`BASICFORTH_DOCS` are searched first (the same set this listing shows), so a
reference page with the same name — `Strings.md` exists in both
Language-Reference and Tutorial — never shadows a lesson. Other docs
directories are searched second: any docs page can still be walked step by
step (`tutorial Printing`). The `tutorials` listing shows each file's
**title line** (our convention is `# <Name> — <what you'll learn>`, so the
title names the tutorial *and* describes it):

```
> tutorials
Tutorials (start one with:  tutorial <name>):
  Arrays — Your First Data Structure
  Chase — Design a Game from the Top Down
  Snake — Build Your First Game
  Strings — Text on the Stack
```

A file with no `# ` title line is listed by its file name.

Each step is shown on a **cleared screen** (interactive sessions only — piped
input gets plain text with no escape codes). Your experiments between steps
scroll away when you type `next`, but their *effects* persist: the words you
defined are still there. The clear also keeps the display clean after a step
has you run something that draws with `at-xy` (like the Chase game itself).

`back` stops at step 1 (it won't go below it). Stepping past the last step prints
`-- end of '<name>' --` and leaves you on the last step, so `back` still works.
If you type `next`/`back` before starting, or name a tutorial that doesn't
exist, BasicForth says so rather than failing silently.

## Notes for lesson authors

- **Keep each step to half–two-thirds of a screen.** A step is printed through
  the same pager as `help`, so an over-long step pauses (`space` to continue,
  `q` to stop) — but the point of a tutorial step is to leave room *below* it,
  so the reader can type the examples while the instructions stay visible.
  Split a long idea across two `## ` steps.
- **Make examples runnable and short**, with the expected result in a trailing
  `\ comment`, exactly as in the Language Reference pages.
- **Give the file a descriptive, prefix-free name** (`Arrays`, `Snake` — not
  `01-arrays`) and open it with a `# <Name> — <what you'll learn>` title:
  that line *is* the description shown by `tutorials` (which sorts names
  alphabetically within each section).
- Two styles have emerged: **project tutorials** (Snake, Chase) build one
  program across many steps; **topic lessons** (Arrays) teach one concept in
  ~10 minutes with extra-short steps — one idea, one thing to type — and end
  by pointing into the reference (`help memory`). Same engine either way.
- A lesson file lives in a `BASICFORTH_DOCS` section just like a reference page;
  a common layout is a `Tutorial` section alongside `Language-Reference`:

  ```
  $ BASICFORTH_DOCS=docs/Language-Reference:docs/Tutorial ./basicforth
  ```

## How It Works

The engine reuses the docs-browser machinery: `(each-dir)` to walk the
`BASICFORTH_DOCS` sections, the `(getdents)` directory scan to find `<name>.md`
(case-insensitively, like `help`), `(build-path)` to form the path, and
`read-line` to read it. `(print-step)` walks the lines counting `## ` headings,
printing only the requested step through the pager line-printer (`(pg-line)`), so
long steps page automatically and steps get the same markdown rendering as
help pages on a terminal (see docs/Help_System.md). State is a stable copy of the current tutorial
name plus the current step index, so `next`/`back` just re-open the file and
re-scan to the new step — no file is held open between commands.

All helper words are internal (`(tut-go)`, `(print-step)`, `(head?)`, …);
only `tutorial`, `next`, `back`, `step`, and `end-tutorial` are meant to be
called directly. The optional step argument on `tutorial`/`step` is parsed
from the line (not the stack). A number is used as-is; the name of a
**`value`** is looked up by its word-type tag and its contents used — which
enables the bookmark pattern:

```
> 11 value tstep          \ in your module; save persists it
> to tstep ( later: 14 to tstep as you advance )
...next session:
> tutorial chase tstep    \ resume exactly where you left off
```

A `variable` is deliberately refused (its name would mean an address, and
`save` doesn't persist a variable's *contents* anyway — a `value` is the
bookmark that survives your save file). Anything that isn't a number or a
value is left for the interpreter, so `step` followed by another word still
just replays.

## See Also

- `docs/Help_System.md` — `help` / `tutorials` / `apropos`, which share the
  `BASICFORTH_DOCS` sections and file-resolution that tutorials use.
- `docs/BasicForth_Manual.md` — the "Built-in Help" section.
