# Line Editor — Interactive Input and History

At an interactive terminal the BasicForth prompt is a small line editor, like
the one a modern shell gives you: move around the line, fix a typo in the
middle, and recall and re-run previous commands. Long lines scroll sideways, a
`:` definition that spans lines gets a continuation prompt, `edit <word>`
opens an existing definition in your editor, `define <word>` opens the
editor on a template for a new one, and `:e <word>` lets you retype a
definition inline. Most of it is just how the prompt behaves — only `edit`,
`define`, and `:e` are words you type.

## Keys

| Key | Action |
|-----|--------|
| Printable characters | Insert at the cursor (the rest of the line shifts right) |
| Left / Right arrow | Move the cursor one character |
| Ctrl-A | Jump to the start of the line |
| Ctrl-E | Jump to the end of the line |
| Backspace / Delete | Delete the character before the cursor |
| Up arrow | Recall the previous line from history |
| Down arrow | Move toward more recent lines; past the newest, restore what you were typing |
| Enter | Submit the line |

## History

Every non-empty line you submit is added to a command history (the most recent
**64** lines). A line identical to the one before it is not stored twice. Up and
Down walk through the history into the input line, where you can edit the
recalled text before submitting it. Down past the newest entry brings back the
line you were in the middle of typing (it is stashed the moment you first press
Up). History lives in memory for the session only; it is not written to disk.

## Long lines

A line wider than the terminal **scrolls sideways** rather than wrapping: the
editor shows a one-row window onto the line and slides it as the cursor moves, so
the cursor is always visible. Editing, Home/End, and history recall all work the
same on a scrolled line. A line is still limited to one input buffer (256
characters) in total; scrolling just lets you see and edit a long line on any
width.

## Editing a definition: `edit`

`edit <name>` opens a word's source in your editor; when you save and quit,
BasicForth **splices the new text into the module file** over the definition
you edited and **reloads the module**, so the change is on disk and live
everywhere in one step:

```
> edit triple              # opens $EDITOR on triple's source — edit, save, quit
saved to /home/you/game.fs
 ok
> triple                   # the new definition is live, and so is every caller
```

It writes the word's current source to a temp file next to the module
(`<module>.edit.fs`, removed afterwards — the `.fs` suffix so your editor
filetype-detects Forth and highlights it) and launches your editor — `$VISUAL`,
then `$EDITOR`, then `vi` if neither is set. The terminal returns to its
normal (cooked) mode for the editor and the prompt re-engages raw mode when
you come back, so a full-screen editor (vim, nano, …) behaves normally. If
you leave without changing the file (vi's `:q!`), or the editor exits
non-zero (vim's `:cq`), nothing happens — no splice, no reload, the session
untouched.

Because the source is a real multi-line file, your **formatting is
preserved** — indentation, line breaks, and `\` comments all survive the
round-trip.

An edit is a **mutation** ("that text was wrong"), so it operates on the
module file: the binding you edit is the word's newest definition *in the
file*. Unsaved session work is **auto-saved** (and the module reloaded)
before the edit proceeds — an edit implies the file is current, so there is
no prompt; if you want checkpoints to return to, that's what
`sh git commit` is for. If the new text calls a word defined *later* in
the file (say, a helper you typed moments ago that the auto-save appended),
a **warning names it** — the splice still happens in place, the reload's
line error shows where, and the fix is bare `edit`: move the helper above
its user. An assembly primitive or an unknown name
reports a short message instead of opening the editor; a scratch session
(no module file) is told to `save <name>` first.

### The edit goes live everywhere (reload)

BasicForth is subroutine-threaded: redefining a word does **not** update the
words that already call it (their call targets are compiled in). `edit`
solves this by **reloading the module** after the splice: in a Forth file
every word is defined before its callers, so the reload rebuilds every
caller of the edited word *by construction* — transitive chains,
`:noname … ; is x` bindings (the group replays and the last `is` wins), all
of it, with no bookkeeping.

The trade-off: a reload resets **runtime state** — variables reload
uninitialized, values return to their file-time contents. Growth stays hot
(`define`, `:`, and `' word is defer` swaps never reload); it is *revising*
a definition that restarts the module. See docs/Module_Architecture.md for
the full model.

### The whole file at once: bare `edit`

`edit` with no word name opens the **current module file** itself in your
editor, straight on disk (no temp copy), and `reload`s it when you save and
quit — the edit-on-disk loop (edit in another terminal + `reload`) in one
word. An untouched file skips the reload, so the session is kept exactly
as-is. Unsaved session work is **auto-saved** before the editor opens, so
it sees your module's real state and the reload replays it. (`new`/`load`/
`bye` still prompt "save first? (y/n)" — those *discard* by intent; an edit
converges.)

## Retyping a definition inline: `:e`

`:e <name>` is `edit <name>` with the prompt as the editor: type the new
definition right there — multi-line works, with the same `... ` continuation
prompt as `:` — and when `;` closes it, the text is spliced into the module
file over the word's newest definition and the module reloads:

```
> :e triple 3 * 1+ ;       # retype it; on ; the file is updated and reloaded
 ok
> see triple               # the file (and every caller) has the new text
```

Same mutation semantics and guards as `edit`: the word must already exist
(unsaved session work is auto-saved and reloaded first), a deferred word
redirects you to its action, and a refusal discards the rest of the input
line — it was the definition body. A new dependency on a later-defined word
warns and splices in place, like `edit`. If the file
changed on disk mid-definition, the splice is refused and your new
definition stays live as an unsaved binding.

Changed your mind mid-definition? Type **`cancel;`** — it abandons the
definition being typed (works for a plain `:` too): nothing is defined,
the rest of the line is discarded, and the pending `:e` is disarmed, so
nothing is spliced.

```
> :e triple 3 * cancel;    # oops, never mind
canceled
> triple                   # unchanged
```

The full verb grid: `:` **binds** a new definition (earlier words keep the
old one — hyper-static), `define` creates one in the editor, `:e` **fixes**
one inline, `edit` fixes one in the editor.

## Defining a new word: `define`

`define <name>` is `edit` for a word that doesn't exist yet. It opens your
editor on a fresh template:

```
: name
    ;
```

Fill in the body (and add more lines — multi-line formatting and comments
survive, exactly as with `edit`), save, and quit; the definition is compiled
and logged like one typed at the prompt, so `see`, `uses`, and `save` all
cover it. Leaving the template untouched defines nothing (`define:
unchanged`). The pair stays symmetric — `define` creates, `edit` revises: an
existing word is refused with `is already defined — use edit`, and `edit` on
a missing word tells you it's not found.

## Multi-line definitions

A `:` definition can span several lines. While one is open (the compiler is
still in `STATE` compiling), the prompt changes to `... ` so you can see at a
glance that you are mid-definition; it returns to `> ` once `;` closes it:

```
> : square
... dup *
... ;
 ok
```

Every line is a normal input line with the full editor available (including
scrolling on a long continuation line).

## When it is active

The editor engages only when standard input is an interactive terminal. When
input is piped or redirected (scripts, the test suite, `cat file | basicforth`),
the prompt falls back to the plain `ACCEPT` line reader, so non-interactive
behavior is unchanged.

You can override the terminal check with the `BASICFORTH_EDITOR` environment
variable: `BASICFORTH_EDITOR=1` forces the editor on (used by the integration
tests to drive it over a pipe), and `BASICFORTH_EDITOR=0` forces it off.

```
> 1 2 + .            # type this, then press Up on the next prompt
3  ok
> 1 2 + .            # recalled with Up arrow; edit it or press Enter to re-run
```

## Notes and limits

- `ACCEPT` itself is unchanged: programs that call `ACCEPT` get the plain line
  reader with no editing or history. The rich editing is the REPL's input path
  only.
- The arrow keys are decoded from ANSI escape sequences (`ESC [ A/B/C/D`) by the
  platform layer, so a terminal in standard ("application cursor keys" off) mode
  is assumed.

## Implementation

The editor is written in Forth in `core.fs` (`(edit-line)` and its helpers), so
both the x86-64 and ARM64 builds share one implementation. The REPL reaches it
through a hook: `main.s` resolves once at startup whether the editor should
engage and, if so, calls the registered `(edit-line)` for each input line
instead of the assembly `forth_accept`. Key reading and arrow-key decoding live
in the platform layer (`platform_key`); the history ring is a heap buffer from
`ALLOCATE`. Each edit just mutates the buffer and calls `(el-redraw)`, which
paints the horizontally-scrolled window using only backspace/space/printables (no
escape sequences). The `... ` continuation prompt is printed by `main.s` based on
`STATE`, and the editor's scroll margin tracks `STATE` to stay aligned with it.

Automated coverage: the pipe-based suite (`tests/test_integration.sh`, with
`BASICFORTH_EDITOR=1`) covers editing and history; `edit` is covered in its own
section (driving `$EDITOR` with a non-interactive `sed`/`true`/`false`). Scrolling
and the continuation prompt need a real terminal, so `tests/test_line_editor_pty.py`
(run via `make run-pty`) drives the REPL under a narrow pseudo-terminal.
