# Interpreter

The words behind BasicForth's outer interpreter: looking words up, parsing input,
running execution tokens, evaluating strings, and resetting on error. (The
compile-time half — `[`, `]`, `literal`, `postpone` — is in `help compiler`.)

At a glance:

    words        ( -- )                 list the whole vocabulary
    find         ( c-addr u -- xt n | c-addr u 0 )  look a word up
    execute      ( xt -- )              run an execution token
    evaluate     ( i*x c u -- j*x )     interpret a string
    \            ( -- )                 comment to end of line
    (            ( "text)" -- )         inline comment, to the closing )
    parse-word   ( -- c-addr u )        next whitespace-delimited token
    parse-name   ( -- c-addr u )        standard alias of parse-word
    parse        ( char -- c-addr u )   parse up to a delimiter
    word         ( char -- c-addr )     parse to a counted string
    source       ( -- c-addr u )        the current input line
    source-id    ( -- 0|-1|fileid )     where input is coming from
    >in          ( -- a-addr )          variable: parse position in source
    >body        ( xt -- a-addr )       a created word's data address
    unused       ( -- u )               dictionary space remaining
    environment? ( c-addr u -- ... )    standard environment query
    catch        ( xt -- 0 | n )        run xt, trapping any throw
    throw        ( n -- )               jump back to the nearest catch
    quit         ( -- )                 restart the interpreter loop
    abort        ( -- )                 clear the stacks, restart
    abort"       ( flag -- )            abort with a message when flag set
    bye          ( -- )                 leave BasicForth

## words ( -- )
List every word currently in the dictionary, newest first.

    \ words            \ prints the whole vocabulary

## find ( c-addr u -- xt n | c-addr u 0 )
Look up a name. On success it **replaces** the name with `xt n`, where `n` is
non-zero: `-1` for a normal word, `1` for an immediate one, `2` for immediate
*and* compile-only (`if`, `[char]`). On failure it **leaves the name alone**
and pushes `0` — so the two cases leave different stack depths, and a caller
that may miss must drop two cells, not one:

    : run  ( c-addr u -- )  find 0= if  2drop  ." missing" cr  else  execute  then ;
    s" cr" run

Testing the flag with `nip` reads well but only balances on the success path:

    : found?  s" dup" find nip . ;  found?            \ -1
    : missing?  s" nope" find nip . drop ;  missing?   \ 0, and drop the name

## execute ( xt -- )
Run the word identified by an execution token (from `'` or `find`).

    2 3 ' + execute .     \ 5

## evaluate ( i*x c-addr u -- j*x )
Interpret the text in a string as if it were typed — compiling or executing it.

    : run  s" 2 3 +" evaluate . ;   run      \ 5

## \ ( -- )
Comment: ignore everything to the end of the line. In a file, that's the end
of the source line.

    1 2 + . \ this text is ignored     \ 3

## ( ( "text)" -- )
Inline comment: ignore everything up to the closing `)`. The convention is
stack-effect comments in definitions — `( n1 n2 -- n3 )`.

    : add5  ( n -- n+5 )  5 + ;
    1 ( ignored ) 2 + .    \ 3

## parse-word ( -- c-addr u )
Skip leading spaces and parse the next space-delimited word from the input,
returning it as a string. The basis of words that read their own arguments.

    \ : tick  parse-word find drop ;   \ (a simplified ')

## parse-name ( -- c-addr u )
The Forth-2012 standard name for `parse-word` — an alias; the two are
interchangeable.

## parse ( char -- c-addr u )
Parse from the input up to the next occurrence of `char` (no leading-space skip),
returning the text between.

    \ : rest-of-line  10 parse type ;

## word ( char -- c-addr )
Like `parse`, but skips leading delimiters and returns a *counted* string (use
`count` to get an address/length pair — see `help strings`).

## source ( -- c-addr u )
The current input buffer (the line or string being interpreted).

## source-id ( -- 0 | -1 | fileid )
Where input is coming from: `0` for the terminal, `-1` for an `evaluate`d string,
or a file id when loading a file.

    source-id .       \ 0   (at the terminal)

## >in ( -- a-addr )
A variable holding the parse position — the offset into `source` where the
interpreter will read next. Parsing words advance it; storing into it makes
the interpreter re-read (or skip) part of the line. Sharp tool.

    : parse2  >in @  parse-word type space  >in !  parse-word type ;
    parse2 hello      \ hello hello   (same token parsed twice)

## >body ( xt -- a-addr )
Given the xt of a `create`d (or `variable`/`constant`) word, return the address
of its data field.

    create cx 5 ,   ' cx >body @ .    \ 5

## unused ( -- u )
The number of free bytes left in the dictionary — handy for keeping an eye on
space (the whole dictionary is 256 KB; prefer `allocate` for big buffers).

    unused .          \ e.g. 230000-ish

## environment? ( c-addr u -- false | i*x true )
Query a system attribute by name (e.g. `/COUNTED-STRING`, `MAX-N`). Returns
`false` if the name is unknown, otherwise the value(s) and `true`.

## catch ( i*x xt -- j*x 0 | i*x n )
Run the execution token like `execute`, but trap any `throw` (or `abort`)
that happens inside it. Returns 0 on top if the word completed normally;
otherwise the thrown code n, with the stack depth restored to what it was
before `catch` ran (the cells the word consumed are unspecified — usually
you drop them). This is how a word cleans up after a failure instead of
losing control to the REPL:

    : risky  true abort" went boom" ;
    ' risky catch .        \ went boom-2   (we kept control)
    : game  ['] play catch  snd-close sdl-close  throw ;

The final `throw` re-raises a non-zero code after the cleanup — and is a
no-op for the normal 0.

## throw ( n -- )
If n is non-zero, jump back to the nearest enclosing `catch`, which returns
n; the stacks and input source are restored to their state at that `catch`.
`0 throw` does nothing (so an error code of 0 means "fine"). With no
enclosing `catch`, non-zero n resets to the REPL like `abort`, reporting
`uncaught exception: n` first — except for the standard codes -1 (`abort`)
and -2 (`abort"`), which stay silent because their message, if any, was
already printed.

    : must-fit ( n -- )  10 > if 1 throw then ;
    : try  ['] must-fit catch if ." too big" cr then ;

Codes are yours to define, but keep to positive numbers or the two standard
negatives above — the standard reserves the rest of the negative range.
`catch` restores the *stacks*, not the world: files, devices, and allocated
memory opened by the aborted word are still open (clean up like `game`
above).

## quit ( -- )
Reset the return stack and re-enter the interpreter loop, without clearing the
data stack — the normal "stop what you're doing and listen" reset.

## abort ( -- )
Clear the data stack and `quit`. The blunt-instrument error recovery.
Equivalent to `-1 throw`, so a `catch` traps it.

## abort" ( flag -- )  (compile-only; text follows)
Inside a definition, compile a guard: at run time, if the flag is true, print
the message and `-2 throw` (the standard `abort"` code) — a `catch` traps it
as -2, message already printed.

    : checked  1 abort" went boom" ;
    checked           \ went boom  (and aborts)

## bye ( -- )
Leave BasicForth, restoring the terminal. If the session has unsaved work,
the dirty-guard asks first. (Scripts that need an exit *status* use
`bye-code` — `help scripting`.)

    bye               \ Goodbye!

## See Also

- `help compiler` — `[`, `]`, `literal`, `postpone`, `compile,`.
- `help defining-words` — `'`, `[']`, and the words `>body` inspects.
- docs/Outer_Interpreter.md — how the REPL ties these together.
- docs/Exceptions.md — how `catch`/`throw` are built and their limits.
