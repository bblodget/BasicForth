# Defining Words

How you add to BasicForth's vocabulary: new commands with `:`, named values with
`constant`/`value`, storage with `variable`/`create`, and your own defining words
with `create … does>`.

## : ( "name" -- )  and  ; ( -- )
`:` begins a new definition, reads its name, and switches to compile mode; `;`
finishes it and returns to interpreting. Between them, words are compiled rather
than run.

    : square  dup * ;
    5 square .        \ 25

## variable ( "name" -- )   →   name: ( -- a-addr )
Create a named one-cell variable. Running the name pushes its address; use `@`
and `!` (see `man memory`).

    variable v   7 v !   v @ .    \ 7

## constant ( x "name" -- )   →   name: ( -- x )
Create a named constant. Running the name pushes the value.

    42 constant answer   answer .     \ 42

## value ( x "name" -- )   →   name: ( -- x )
Like a constant, but reassignable with `to`. Running the name pushes the current
value.

    5 value count   count .       \ 5

## to ( x "name" -- )
Store a new value into a `value`.

    5 value count   9 to count   count .   \ 9

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
words; pairs with `postpone`/`literal` (see `man interpreter`).

## See Also

- `man memory` — `@` / `!` / `allot` for the storage these words create.
- `man interpreter` — `execute`, `postpone`, `literal`, and how compilation works.
- docs/Defining_Words.md and docs/Marker.md — deeper dives.
