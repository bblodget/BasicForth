# Interactive Tutorial (`tutorial` / `next` / `back`)

BasicForth can walk you through a lesson **one step at a time**, right at the
REPL. Unlike `man` (which pages a whole file), the tutorial shows a single step
and then **returns to the prompt**, so you can type the examples yourself before
moving on with `next`.

A tutorial is just one of the Markdown files in a `BASICFORTH_DOCS` section — the
same files `man` and `topics` use. No special file format: each lesson is split
into steps by its `## ` headings.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `tutorial` | ( "name" -- ) | start tutorial `<name>` (resolved case-insensitively across the docs dirs, like `man`) and show step 1; with no name, prints a hint and the `topics` list |
| `next` | ( -- ) | show the next step |
| `back` | ( -- ) | show the previous step |

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
file still reads fine under `man Lesson` — the headings are ordinary Markdown.

## Using it

```
> tutorial Snake
# Snake — Build Your First Game
...

[ next = continue   back = previous   step 1 ]
 ok
> next
## The stack — Forth's workspace
...

[ next = continue   back = previous   step 2 ]
 ok
> : square dup * ;        \ try things between steps — the REPL is live
 ok
> 5 square .
25  ok
> back                    \ review the previous step
```

The name is the file's base name without `.md` (what `topics` shows), matched
case-insensitively — `tutorial Snake`, `tutorial snake`.

`back` stops at step 1 (it won't go below it). Stepping past the last step prints
`-- end of '<name>' --` and leaves you on the last step, so `back` still works.
If you type `next`/`back` before starting, or name a tutorial that doesn't
exist, BasicForth says so rather than failing silently.

## Notes for lesson authors

- **Keep each step to about one screen.** A step is printed through the same
  pager as `man`, so an over-long step pauses (`space` to continue, `q` to stop)
  — but the point of a tutorial step is to fit above the prompt so the reader can
  see it *while* typing the examples. Split a long idea across two `## ` steps.
- **Make examples runnable and short**, with the expected result in a trailing
  `\ comment`, exactly as in the Language Reference pages.
- **Number lesson files** (`01-…`, `02-…`) so `topics` lists them in order
  (`topics` sorts names within each section).
- A lesson file lives in a `BASICFORTH_DOCS` section just like a reference page;
  a common layout is a `Tutorial` section alongside `Language-Reference`:

  ```
  $ BASICFORTH_DOCS=docs/Language-Reference:docs/Tutorial ./basicforth
  ```

## How It Works

The engine reuses the docs-browser machinery: `(each-dir)` to walk the
`BASICFORTH_DOCS` sections, the `(getdents)` directory scan to find `<name>.md`
(case-insensitively, like `man`), `(build-path)` to form the path, and
`read-line` to read it. `(print-step)` walks the lines counting `## ` headings,
printing only the requested step through the pager line-printer (`(pg-line)`), so
long steps page automatically. State is a stable copy of the current tutorial
name plus the current step index, so `next`/`back` just re-open the file and
re-scan to the new step — no file is held open between commands.

All helper words are internal (`(tut-go)`, `(print-step)`, `(tut-head?)`, …);
only `tutorial`, `next`, and `back` are meant to be called directly.

## See Also

- `docs/Help_System.md` — `man` / `topics` / `apropos`, which share the
  `BASICFORTH_DOCS` sections and file-resolution that tutorials use.
- `docs/BasicForth_Manual.md` — the "Built-in Help" section.
