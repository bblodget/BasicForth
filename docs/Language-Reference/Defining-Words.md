# Defining Words

How you add to BasicForth's vocabulary: new commands with `:`, named values with
`constant`/`value`, storage with `variable`/`create`, and your own defining words
with `create … does>`.

At a glance:

    : name ... ;    ( "name" -- )      define a new word
    cancel;         ( -- )             abandon the definition being typed
    :noname ... ;   ( -- xt )          unnamed definition, leaves its xt
    variable        ( "name" -- )      one cell of storage; name pushes addr
    constant        ( x "name" -- )    name pushes x, fixed
    value           ( x "name" -- )    name pushes x, changeable with to
    to              ( x "name" -- )    store into a value (or deferred word)
    defer           ( "name" -- )      a word whose action comes later
    is              ( xt "name" -- )   install a deferred word's action
    defer@          ( xt1 -- xt2 )     fetch a deferred action (raw)
    action-of       ( "name" -- xt )   fetch a deferred action, checked
    create          ( "name" -- )      name pushes the address after it
    does>           ( -- )             run-time action for created words
    marker          ( "name" -- )      restore point; run name to forget
    '               ( "name" -- xt )   "tick": a word's execution token
    [']             ( "name" -- )      tick, compile-time version
    immediate       ( -- )             last word runs during compilation

## : ; ( "name" -- )
`:` begins a new definition, reads its name, and switches to compile mode; `;`
finishes it and returns to interpreting. Between them, words are compiled rather
than run.

    : square  dup * ;
    5 square .        \ 25

## cancel; ( -- )
Abandon the definition being typed (a `:`, `:noname`, or `:e`): nothing is
defined, the rest of the input line is discarded, and a pending `:e` splice
is disarmed. Immediate — it acts the moment it's read, even mid-line or on
a continuation line. At the prompt (nothing compiling) it's a no-op.

    : foo 1 2 cancel;     \ "canceled" — foo never existed

## :noname ( -- xt )
Like `:` but with no name: compile a definition and leave its *execution token*
(xt) on the stack instead. Run it with `execute`, or install it as a deferred
word's behavior with `is` — the seam-filling idiom from the Chase tutorial.
The definition's source is recorded like any word's, so `see` on a deferred
word shows its `:noname` action in full, and `save` replays it.

    :noname  dup * ;      \ compiles, leaves the xt on the stack
    5 swap execute .      \ 25

## variable ( "name" -- )   →   name: ( -- a-addr )
Create a named one-cell variable. Running the name pushes its address; use `@`
and `!` (see `help memory`).

    variable v   7 v !   v @ .    \ 7

## constant ( x "name" -- )   →   name: ( -- x )
Create a named constant. Running the name pushes the value.

    42 constant answer   answer .     \ 42

## value ( x "name" -- )   →   name: ( -- x )
Like a constant, but reassignable with `to`. Running the name pushes the current
value.

    5 value count   count .       \ 5

Unlike a `variable` (whose `!` contents aren't saved), a `value` set with a
direct `to` at the prompt **persists across `save`/`reload`** — see `help modules`.

## to ( x "name" -- )
Store a new value into a `value` (or a deferred word). Any other target is
refused — `x: not a value or deferred word` — since the store would corrupt an
ordinary word's compiled code.

    5 value count   9 to count   count .   \ 9

## defer ( "name" -- )
Create a word whose behavior is filled in *later* — a named seam. Running it
before a behavior is installed aborts with `greet: uninitialized deferred
word`. The
tool behind top-down design (`tutorial Chase`).

    defer greet
    :noname  ." Hello!" cr ;  is greet
    greet                 \ Hello!

## is ( xt "name" -- )
Install an execution token as a deferred word's behavior. Swappable **live**, any
time, without recompiling the word's callers — that's the point. A non-deferred
target is refused: `x: not a deferred word`.

    defer brain
    ' negate is brain   5 brain .    \ -5
    ' abs    is brain  -5 brain .    \ 5

A direct `is` typed at the prompt persists across `save`/`reload`, like `to` —
see `help modules`. Deeper dive: docs/Deferred_Words.md.

## defer@ ( xt1 -- xt2 )
Fetch a deferred word's current action from its xt — the raw form of
`action-of`. Applying it to a non-deferred xt reads garbage; prefer `action-of`,
which checks.

## action-of ( "name" -- xt )
A deferred word's current action, by name — checked (`x: not a deferred word`
for anything else). With `see`, the way to ask "what does this seam do right
now?":

    defer greet   :noname ." hi" ; is greet
    action-of greet execute        \ hi
    see greet                      \ defer greet
                                   \ \ currently set by: :noname ." hi" ; is greet

## create ( "name" -- )   →   name: ( -- addr )
Create a named entry whose run-time behaviour is to push the address of the space
that follows it — the basis for arrays and buffers. Reserve space after it with
`allot` (and fill with `,` / `c,`).

    create grades  3 cells allot
    90 grades !   85 grades cell+ !
    grades @ .        \ 90

## does> ( -- )
Used inside a defining word to give the words it creates a custom run-time
action. Everything after `does>` runs when a created word is *used*, with that
word's data address on the stack.

    : constant2  create , does> @ ;   \ a home-grown CONSTANT
    99 constant2 x
    x .               \ 99

## marker ( "name" -- )
Define a dictionary restore point. Running the name later forgets it and
everything defined after it, reclaiming the space — the basis of an
edit/compile/run loop. See docs/Marker.md.

    marker -work
    : temp  1 ;
    -work             \ forget temp and -work itself

## ' ( "name" -- xt )
"Tick": parse the next word and push its *execution token* (xt) — a handle you
can run with `execute` or store.

    2 3 ' + execute .     \ 5

## ['] ( "name" -- )   compile-time; at run time: ( -- xt )
The compile-time form of `'`: inside a definition it compiles the next word's xt
as a literal.

    : apply-add  ['] + execute ;
    2 3 apply-add .       \ 5

## immediate ( -- )
Mark the most recently defined word as *immediate*, so it runs during
compilation rather than being compiled. The building block for custom compiling
words; pairs with `postpone`/`literal` (see `help interpreter`).

## See Also

- `help memory` — `@` / `!` / `allot` for the storage these words create.
- `help interpreter` — `execute`, `postpone`, `literal`, and how compilation works.
- docs/Defining_Words.md, docs/Deferred_Words.md, and docs/Marker.md — deeper dives.
