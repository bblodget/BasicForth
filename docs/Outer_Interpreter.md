# BasicForth — Outer Interpreter

The outer interpreter is the main REPL loop that makes BasicForth
interactive. It reads lines of input, breaks them into words, and for
each word either executes it, compiles it, or parses it as a number —
depending on the current STATE.

## REPL Loop

```
_start
  ├── Save argc/argv[1] from initial stack pointer
  ├── Initialize engine registers (DSP, HERE, LATEST, sp0)
  ├── Set up guard pages and raw terminal mode
  ├── Print startup banner
  ├── Load core.fs via INCLUDED (silent skip if not found)
  ├── If argv[1] given, load it via INCLUDED (silent skip if not found)
  │
  └── repl_loop:
        ├── Save rp0, saved_latest, saved_here (for error recovery)
        ├── Print "> " prompt
        ├── ACCEPT a line into input buffer
        ├── Empty line? → re-prompt
        ├── Set source_addr, source_len, to_in
        ├── DROP the count
        │
        ├── call forth_interpret_line
        │   ├── returns 0? → print " ok\n", goto repl_loop
        │   └── returns 1? → print "? " + err_token + "\n", goto repl_loop
```

## forth_interpret_line

The interpret loop is a callable subroutine in core.s (not main.s), so
EVALUATE and INCLUDED can reuse it. It assumes the caller has set
`source_addr`, `source_len`, and `to_in`.

```
forth_interpret_line:
  loop:
    ├── PARSE-WORD → ( c-addr u )
    ├── u == 0? → drop 0 0, return 0 (success)
    │
    ├── FIND → ( xt flag | c-addr u 0 )
    │   ├── flag == 0?  → not found, fall through to NUMBER
    │   ├── STATE == 0? → check compile-only, EXECUTE xt, loop
    │   ├── flag == 1?  → IMMEDIATE: EXECUTE xt, loop
    │   └── flag == -1? → normal: compile_call xt, loop
    │
    ├── DROP 0 flag
    ├── NUMBER → ( n true | c-addr u false )
    │   ├── false?     → not a number, fall through to error
    │   ├── STATE == 0? → DROP flag, leave n on stack, loop
    │   └── STATE != 0? → DROP flag, compile_literal n, loop
    │
    └── Error:
        Save token in err_token_addr/err_token_len
        If STATE != 0: reset STATE, restore LATEST, restore HERE
        return 1 (error)
```

Returns: 0 = success, 1 = error. On error, the offending token is stored
in `err_token_addr` and `err_token_len` for the caller to format its own
error message.

## Data Flow

The key design is that FIND and NUMBER both preserve the original
`c-addr u` on failure, so they chain naturally:

1. **PARSE-WORD** returns `( c-addr u )` pointing into the input buffer
2. **FIND** tries to look it up. On failure returns `( c-addr u 0 )` —
   the original string is preserved
3. After dropping the 0, **NUMBER** gets `( c-addr u )` — the same string
4. If NUMBER also fails, `( c-addr u )` is still available for the error
   message

## Interpret vs Compile Mode

The STATE variable controls whether the interpreter executes or compiles:

| STATE    | Words                    | Numbers                   |
|----------|--------------------------|---------------------------|
| 0        | EXECUTE immediately      | Push to data stack        |
| non-zero | compile_call (emit code) | compile_literal (emit code) |

**IMMEDIATE words always execute**, even in compile mode. This is how `;`
can end a definition and `'` can parse the next word at compile time.

The FIND return flag distinguishes the two cases:
- `flag == 1` — word is IMMEDIATE (always execute)
- `flag == -1` — word is normal (compile in compile mode)

## Input Buffer Variables

Three global variables in `core.s` manage the input source:

| Variable      | Purpose                                          |
|---------------|--------------------------------------------------|
| `source_addr` | Pointer to the current input buffer              |
| `source_len`  | Total length of the input line                   |
| `to_in`       | Current parse offset (advanced by PARSE-WORD)    |

These are set by the REPL after each ACCEPT and read by PARSE-WORD.
Multiple calls to PARSE-WORD within one line advance `to_in` to extract
successive tokens.

EVALUATE and INCLUDED save and restore these variables so nested input
sources work correctly. EVALUATE saves them in callee-saved registers;
INCLUDED sets them per-line as it processes the file.

## Words Used by the Interpreter

| Word             | Stack Effect                                       | Role                     |
|------------------|----------------------------------------------------|--------------------------|
| `ACCEPT`         | `( c-addr max -- count )`                          | Read a line with editing |
| `PARSE-WORD`     | `( -- c-addr u )`                                  | Extract next token       |
| `FIND`           | `( c-addr u -- xt 1 \| xt -1 \| c-addr u 0 )`    | Dictionary lookup        |
| `NUMBER`         | `( c-addr u -- n true \| c-addr u false )`         | Parse as number          |
| `EXECUTE`        | `( xt -- )`                                        | Call execution token     |
| `compile_call`   | consumes xt from RAX/X0                            | Emit CALL/BL at HERE     |
| `compile_literal`| consumes value from RAX/X0                         | Emit LIT + value at HERE |
| `DROP`           | `( a -- )`                                         | Clean up flags           |

## Stack Persistence

The data stack persists across lines. Items pushed on one line are
available on the next:

```
> 3 4
 ok
> + .
7  ok
```

## Error Handling

When a token is neither a dictionary word nor a valid number, the
interpreter prints `? <token>` and aborts the rest of the line. Items
already pushed or executed on that line remain on the stack.

```
> 1 2 hello 3
? hello
> .s
<2> 1 2
```

In this example, `1` and `2` were pushed before the error. `3` was never
reached because `hello` caused an abort.

### Error During Compilation

If an error occurs while compiling a definition, the interpreter also:

1. Resets STATE to 0 (back to interpreting)
2. Restores LATEST to the value saved by `:` before it started
3. Restores HERE to the value saved by `:` before it started

This discards the partial definition completely. Earlier definitions on the
same line are not affected — the save point is per-definition (set by `:`),
not per-line.

```
> : FOO 42 ; : BAR typo
? typo
> FOO .
42  ok
```

FOO completed before the error and survives. BAR is rolled back.
