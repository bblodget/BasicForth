# BasicForth — Outer Interpreter

The outer interpreter is the main REPL loop that makes BasicForth
interactive. It reads lines of input, breaks them into words, and for
each word either executes it from the dictionary or parses it as a number.

## REPL Loop

```
_start
  ├── Initialize engine registers (DSP, HERE, LATEST, sp0)
  ├── Enter raw terminal mode
  │
  └── repl_loop:
        ├── Print "> " prompt
        ├── ACCEPT a line into input buffer
        ├── Empty line? → print "Goodbye!", exit
        ├── Set source_addr, source_len, to_in
        ├── DROP the count
        │
        └── interpret_loop:
              ├── PARSE-WORD → ( c-addr u )
              ├── u == 0? → end of line, print " ok", goto repl_loop
              │
              ├── FIND → ( xt flag | c-addr u 0 )
              │   ├── flag != 0? → DROP flag, EXECUTE xt, loop
              │   └── flag == 0? → fall through
              │
              ├── DROP 0 flag
              ├── NUMBER → ( n true | c-addr u false )
              │   ├── true? → DROP flag, n is on stack, loop
              │   └── false? → fall through
              │
              └── Error: DROP false
                  Print "? " + token + newline
                  DROP c-addr and u
                  goto repl_loop (abort rest of line)
```

## Data Flow

The key design is that FIND and NUMBER both preserve the original
`c-addr u` on failure, so they chain naturally:

1. **PARSE-WORD** returns `( c-addr u )` pointing into the input buffer
2. **FIND** tries to look it up. On failure returns `( c-addr u 0 )` —
   the original string is preserved
3. After dropping the 0, **NUMBER** gets `( c-addr u )` — the same string
4. If NUMBER also fails, `( c-addr u )` is still available for the error
   message

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

## Words Used by the Interpreter

| Word         | Stack Effect                              | Role                          |
|--------------|-------------------------------------------|-------------------------------|
| `ACCEPT`     | `( c-addr max -- count )`                 | Read a line with editing      |
| `PARSE-WORD` | `( -- c-addr u )`                         | Extract next token            |
| `FIND`       | `( c-addr u -- xt 1 \| xt -1 \| c-addr u 0 )` | Dictionary lookup       |
| `NUMBER`     | `( c-addr u -- n true \| c-addr u false )` | Parse as number              |
| `EXECUTE`    | `( xt -- )`                               | Call execution token          |
| `DROP`       | `( a -- )`                                | Clean up flags                |
| `.`          | `( n -- )`                                | Print number (user-facing)    |
| `.S`         | `( -- )`                                  | Show stack (user-facing)      |
| `BYE`        | `( -- )`                                  | Exit                          |

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

## Interpret vs Compile Mode (Future)

The current interpreter is interpret-only — every word is executed
immediately. A future STATE variable will control compile mode, where
non-IMMEDIATE words are compiled into new definitions instead of
executed. The FIND return flag (`1` for IMMEDIATE, `-1` for normal)
already supports this distinction.
