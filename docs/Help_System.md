# Help System — Docs Browser (`man` / `topics` / `apropos`)

BasicForth can browse its own Markdown documentation from the REPL. The docs
browser reads the `*.md` files in the directories named by the `BASICFORTH_DOCS`
environment variable and lets you list, page, and search them.

This is the first slice of the planned interactive help system. A later "Part A"
will add per-word help (`help <word>`); for now the browser works on whole
topic files.

## Words

| Word | Stack effect | Meaning |
|------|--------------|---------|
| `topics` | ( -- ) | list the available topics, grouped under their section (directory) and sorted alphabetically |
| `man` | ( "topic" -- ) | find `<topic>.md` (case-insensitive) and page it a screenful at a time |
| `apropos` | ( "keyword" -- ) | list the topics whose file contains `<keyword>` (case-insensitive), each labelled with its section |

## Sections

Each directory in `BASICFORTH_DOCS` is a **section**, named by the directory's
last path component — much like the numbered sections of the Unix `man` system,
but named rather than numbered. `topics` groups its listing under one header per
section, and `apropos` tags each hit with the section it came from. `man` and
`apropos` search *across* all sections (first match wins for `man`).

A typical setup keeps user-facing material in its own sections, separate from
the project's internal design docs:

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
> topics
Language-Reference
  Arithmetic  Comparison  Memory  Stack
Tutorial
  Snake
> man stack
# Stack Manipulation
...
-- more (space=page, q=quit) --      \ press space for the next page, q to stop
> apropos dup
Stack (Language-Reference)
Snake (Tutorial)
```

`man` matches case-insensitively and appends `.md`, so `man stack`,
`man Stack`, and `man STACK` all open `Stack.md`. When no topic matches, it
prints `no help for <topic> (try TOPICS)`.

`apropos` scans each topic file line by line for the keyword as a
case-insensitive substring and prints each matching topic with its section.

## How It Works

- **Directory enumeration** uses the `(getdents)` primitive, a thin wrapper over
  the Linux `getdents64` syscall, to read directory entries into a buffer and
  walk the `linux_dirent64` records (16-bit `d_reclen` at offset 16, the
  null-terminated `d_name` at offset 19). Only entries ending in `.md` are
  treated as topics.
- **The docs path** comes from the `(docs-path)` primitive, which returns the
  value of `BASICFORTH_DOCS` (address and length); `(each-dir)` splits it on `:`
  and runs a handler per directory.
- **Section grouping** uses `(basename)` to take each directory's last path
  component as the section name. `topics` collects a directory's topic names into
  a heap buffer (the getdents buffer is reused across reads, so name pointers into
  it aren't stable), sorts them alphabetically, then prints the section header
  followed by the sorted names — so a directory with no topics adds no header and
  each section reads in order.
- **Paging** reads the file with `read-line` and prints `screen-height - 1`
  lines before pausing for a key. The getdents buffer and the line buffer are
  allocated on the heap (`allocate`) on first use, so the feature adds very
  little to the dictionary footprint.

All of the helper words are internal (parenthesized names like `(getdents)`,
`(each-dir)`, `(ci-has?)`); only `man`, `topics`, and `apropos` are meant to be
called directly.

## See Also

- `docs/Tutorial_System.md` — `tutorial` / `next` / `back`, an interactive walk
  through a docs file one `## ` step at a time, built on this same machinery.
- `docs/BasicForth_Manual.md` — the "Built-in Help" section and the
  `BASICFORTH_DOCS` environment variable.
- `docs/Outer_Interpreter.md` — `INCLUDED` and file loading, which share the
  `BASICFORTH_PATH` directory-search convention that `BASICFORTH_DOCS` mirrors.
