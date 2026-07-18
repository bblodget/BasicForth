# Compiler

The compile-time half of the interpreter — words that control what happens
*while* a definition is being compiled. Most are **compile-only** and only make
sense inside a `:` definition. The interpreter state itself lives in the `state`
variable (see `help variables-constants`).

At a glance:

    [         ( -- )       switch to interpreting, mid-definition
    ]         ( -- )       switch back to compiling
    literal   ( x -- )     compile a computed value as a literal
    postpone  ( "name" -- ) compile a word's compilation behavior
    compile,  ( xt -- )    compile a call to an xt

## [ ( -- )  (compile-only)
Leave compile mode and start interpreting — temporarily, in the middle of a
definition. Pairs with `]`.

## ] ( -- )
Resume compiling. Together, `[ … ]` runs code at compile time and is the usual
way to precompute a value to embed with `literal`.

## literal ( x -- )  (compile-only)
Compile the value `x` so it is pushed when the word runs. Combined with `[ … ]`,
it bakes a computed constant into a definition.

    : circle-ish  [ 22 7 ] literal literal ;   \ (illustrative)
    : answer  [ 6 7 * ] literal ;
    answer .          \ 42  (computed once, at compile time)

## postpone ( "name" -- )  (compile-only)
Defer a word: compile it so it acts later. For an immediate word, `postpone`
compiles *it* into the new word instead of running it now — the standard way to
build words that build words.

    : endif  postpone then ; immediate    \ "endif" as a synonym for "then"
    : test   5 0> if 111 else 222 endif . ;
    test              \ 111

## compile, ( xt -- )
Append a call to the word with execution token `xt` into the definition currently
being compiled — the low-level "compile a call" used by defining words.

    \ ' + compile,     \ compile a call to +  (inside a compiling word)

## See Also

- `help variables-constants` — the `state` variable this all hinges on.
- `help defining-words` — `'`, `[']`, `immediate`, and `does>`.
- `help interpreter` — the run-time/interpret side (`evaluate`, `execute`, …).
- docs/Conditionals.md and docs/Compiler.md — deeper background.
