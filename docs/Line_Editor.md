# Line Editor — Interactive Input and History

At an interactive terminal the BasicForth prompt is a small line editor, like
the one a modern shell gives you: move around the line, fix a typo in the
middle, and recall and re-run previous commands. Long lines scroll sideways, a
`:` definition that spans lines gets a continuation prompt, and `edit <word>`
recalls an existing definition for tweaking. Most of it is just how the prompt
behaves — only `edit` is a word you type.

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

`edit <name>` recalls a word's source onto the **next** prompt, pre-filled and
ready to tweak:

```
> : triple 3 * ;
 ok
> edit triple
> : triple 3 * ;        # pre-filled; arrow to the 3, change it, press Enter
```

It works for words you defined this session (from the capture log) and for
file-loaded words — `core.fs`, `include`d files — read straight from their source
file via the dictionary's source metadata, the same way `see` finds them. An
assembly primitive or an unknown name reports a short message instead.

The source is **flattened to a single line** so the existing single-line editor
can hold it (newlines are whitespace to Forth). One wrinkle is handled
automatically: a `\` comment runs to end-of-line, which on one line would swallow
the rest of the definition, so a `\ comment` is rewritten as a self-terminating
`( comment )`. A definition whose flattened form exceeds one input line (256
chars) is declined rather than truncated — edit it in the file and `reload`.

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
- `edit`'s `\`-comment conversion does not recognise a literal backslash, paren,
  or quote introduced via `[char]` / `char` in code (e.g. `[char] \`); such a
  definition would flatten incorrectly. This is rare; edit it in the file
  instead.

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
`BASICFORTH_EDITOR=1`) covers editing, history, and `edit`; scrolling and the
continuation prompt need a real terminal, so `tests/test_line_editor_pty.py`
(run via `make run-pty`) drives the REPL under a narrow pseudo-terminal.
