# Line Editor — Interactive Input and History

At an interactive terminal the BasicForth prompt is a small line editor, like
the one a modern shell gives you: move around the line, fix a typo in the
middle, and recall and re-run previous commands. It is the everyday way you type
at the REPL — no words to call, it is just how the prompt behaves.

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
- Lines longer than the terminal width are not specially handled (no horizontal
  scroll); this is a known cosmetic limit.
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
`ALLOCATE`.
