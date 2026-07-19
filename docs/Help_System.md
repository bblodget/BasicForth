# Help System — Docs Browser (`help` / `tutorials` / `apropos`)

BasicForth can browse its own Markdown documentation from the REPL. The docs
browser reads the `*.md` files in the directories named by the `BASICFORTH_DOCS`
environment variable; `help` is the front door.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `help` | ( -- ) | list every topic, three to a row, grouped by section (the Tutorial section is left to `tutorials`) |
| `help <topic>` | ( "topic" -- ) | print the topic's **summary**: the page's preamble — title, short intro, and "At a glance" table |
| `help <word>` | ( "word" -- ) | print that word's reference entries — every `## ` block naming it, on whatever pages document it |
| `tutorials` | ( -- ) | list the interactive tutorials (start one with `tutorial <name>`) |
| `apropos` | ( "keyword" -- ) | list the topics whose file contains `<keyword>` (case-insensitive), each labelled with its section |

## Resolution

`help <name>` tries a **topic first, then a word**:

1. **Topic**: `<name>` matches a `<topic>.md` file case-insensitively, folding
   `-` and `_` — `help help-system`, `help Help_System`, and `help HELP-SYSTEM`
   all find `Help_System.md`. On a match, the page's preamble is printed: top
   of the file to the first `## ` heading.
2. **Word**: otherwise the reference pages are scanned for `## ` headings that
   name `<name>` (case-insensitive), and **every** matching entry block —
   heading to the next `## ` — is printed. A word like `begin` heads three
   entries (`begin…until`, `begin…again`, `begin…while…repeat`); all three
   appear, in page order. Tutorial sections are skipped in this pass; their
   `## ` headings are lesson steps, not word entries.

When neither matches: `no help for <name>  (try:  help  or  apropos <keyword>)`.

## The Page Convention

The browser does no Markdown parsing; it leans on the layout every
`docs/Language-Reference/*.md` page follows:

- The **preamble** — title, a short intro paragraph, and an indented
  "At a glance" table — runs from the top of the file to the first `## `
  heading. That is exactly what `help <topic>` prints.
- Each **entry** starts with `## <word(s)> ( stack-effect )` and runs to the
  next `## ` heading. A heading may name several words that share one entry
  (`## stdin stdout stderr ( -- fileid )`); the token scan stops at the `(`
  that opens the stack effect, so effect names like `n` or `flag` are not
  matchable words.

Keep new pages to this shape and they are automatically browsable.

## Sections

Each directory in `BASICFORTH_DOCS` is a **section**, named by the directory's
last path component. `help` groups its listing under one header per section,
and `apropos` tags each hit with the section it came from. A section named
`Tutorial` is the one exception: bare `help` points at `tutorials` instead of
listing it, so lessons don't crowd the reference topics.

A typical setup:

```
$ BASICFORTH_DOCS=docs/Language-Reference:docs/Tutorial ./basicforth
```

## Configuration

Set `BASICFORTH_DOCS` to one or more directories of `*.md` files, colon-separated
(the same convention as `BASICFORTH_PATH`):

```
$ BASICFORTH_DOCS=docs ./basicforth
$ BASICFORTH_DOCS=docs:/usr/share/basicforth/docs ./basicforth
```

Empty segments (from a leading, trailing, or doubled `:`) are skipped. If the
variable is unset, every help word prints `(BASICFORTH_DOCS not set)`.

## Example

```
> help
Language-Reference
  Arithmetic           Comparison           Compiler
  Conditionals         Defining-Words       FFI
  ...
Tutorial:  type  tutorials  to list the interactive tutorials.

help <topic>  - that topic's summary       (help stack)
help <word>   - one word's entry           (help allot)
> help stack
# Stack Manipulation
...the page preamble, ending at its "At a glance" table...
> help allot
## allot ( n -- )
Reserve `n` bytes of dictionary space (advance `here`). ...
> apropos dup
Stack (Language-Reference)
Snake (Tutorial)
```

Long output still pages a screenful at a time at a terminal
(space = next page, q = quit); piped output never pauses.

## How It Works

- **Directory enumeration** uses the `(getdents)` primitive, a thin wrapper over
  the Linux `getdents64` syscall, to read directory entries into a buffer and
  walk the `linux_dirent64` records (16-bit `d_reclen` at offset 16, the
  null-terminated `d_name` at offset 19). Only entries ending in `.md` are
  treated as topics.
- **The docs path** comes from the `(docs-path)` primitive, which returns the
  value of `BASICFORTH_DOCS` (address and length); `(each-dir)` splits it on `:`
  and runs a handler per directory.
- **Section listing** uses `(basename)` for the section name. `help` collects a
  directory's topic names into a heap buffer (the getdents buffer is reused
  across reads, so name pointers into it aren't stable), sorts them
  alphabetically, then prints them three to a row padded to the longest name.
- **Topic lookup** compares names with `(fd=)`, a case-insensitive equality that
  also folds `-`/`_`; the preamble pager `(page-preamble)` stops at the first
  `## ` line. **Word lookup** tokenizes each `## ` heading — `(head-word?)` —
  and `(page-entry)` prints every matching entry (each heading re-decides
  whether the lines after it print), scanning all pages even after a hit.
- **Paging** reads the file with `read-line` and prints `screen-height - 1`
  lines before pausing for a key. The getdents buffer and the line buffer are
  allocated on the heap (`allocate`) on first use, so the feature adds very
  little to the dictionary footprint.

All of the helper words are internal (parenthesized names like `(getdents)`,
`(each-dir)`, `(page-entry)`); only `help`, `tutorials`, and `apropos` are
meant to be called directly.

## History

`help` replaced the original `man` / `topics` pair in v0.11.0: `topics`'s
listing became bare `help`, and `man`'s whole-file paging was split into the
topic-summary and per-word forms. `apropos` is unchanged.

## See Also

- `docs/Tutorial_System.md` — `tutorial` / `next` / `back`, an interactive walk
  through a docs file one `## ` step at a time, built on this same machinery.
- `docs/BasicForth_Manual.md` — the "Built-in Help" section and the
  `BASICFORTH_DOCS` environment variable.
- `docs/Outer_Interpreter.md` — `INCLUDED` and file loading, which share the
  `BASICFORTH_PATH` directory-search convention that `BASICFORTH_DOCS` mirrors.
