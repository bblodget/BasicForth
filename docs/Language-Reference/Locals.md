# Locals

Names for the values a word was given, so you can stop juggling them on the
stack. Three arguments is roughly where `rot swap over` stops being readable,
and graphics and game code is full of `x y w h colour`.

At a glance:

    {: a b c :}              ( x1 x2 x3 -- )   name the top 3 items
    a                        ( -- x )          read one, by name

## {: … :} ( x1 … xn -- )
**Compile-only.** Names the top stack items for the rest of the definition:

    {: <arg>… [| <val>…] [-- <comment>…] :}

Names before `|` are taken from the stack. Names after it are **locals of your
own**, taking nothing from the stack and starting at zero. Everything after
`--` is ignored, so a declaration can carry its own stack comment.

Arguments are listed **in stack order**, so the deepest item named comes
first — the same order you write a stack comment in:

    : blit ( src x y w h -- )  {: s x y w h :}
        s x y w h ... ;

    : mid ( a b -- n )  {: a b :}  a b + 2/ ;
    10 20 mid .            \ 15

The list ends at `:}`. A declaration can also document itself, which is what
`--` is for — the names after it are a comment, not locals:

    : hyp ( a b -- c )  {: a b -- c :}  a a *  b b *  + ;

Naming pays off most where a value is used more than once, or out of order —
the case that otherwise costs a `dup` and a `rot` to set up:

    : clamp ( n lo hi -- n )  {: n lo hi :}
        n lo < if lo exit then
        n hi > if hi exit then
        n ;
    5 0 10 clamp .         \ 5
    99 0 10 clamp .        \ 10

A local is read just by writing it. Reading one costs a memory load, not a
call — the compiler resolves the name while compiling and emits the load
directly, so locals are not slower than the stack shuffling they replace.

Locals live on their own stack, so they do not interact with `>r` / `r>`, and
they are per-thread: a worker running a word with locals cannot disturb the
frames of anything else.

### Locals shadow — including verbs
While a definition is being compiled, a local name wins over **anything** of the
same name in the dictionary. That is what every language does for variables, but
Forth lets you shadow verbs too, which is sharper:

    : oops  {: i :}  3 0 do i . loop ;
    7 oops             \ 7 7 7  -- `i` is the local, NOT the loop index

Nothing is broken there; `i` simply means the local now. Avoid naming a local
after a word you still need in that definition — `i` and `j` are the ones to
watch, since they are the natural names for a counter *and* the loop indices.

So the compiler says when it happens:

    : oops  {: i :}  3 0 do i . loop ;
    note: local i shadows an existing word

A note, not an error — shadowing is what locals are for. It appears only when
you type, like the `redefined` warning, so neither a `require`d library nor a
script run from the command line nags about its own locals.

### Where `{:` may appear
**Once per definition, and only where the compile-time stack is empty.** Both
are compile errors, and both exist for the same reason: the frame is built where
`{:` appears but released once when the definition returns. A `{:` inside a
branch would be released by calls that never took the branch; inside a loop it
would build a frame per iteration and release one. Either way the locals stack
drifts a little on every call, in silence, until it walks into its guard page.

In practice that means: not inside an unclosed `if`, `begin`, `do` or `case`. A
structure that has already *closed* is fine — the rule is about what is still
open, not about coming first:

    : blit ( src x y w h -- )  {: s x y w h :}   \ the usual place
    : t  1 if 2 . then {: a :} a . ;             \ fine: the IF is closed
    : oops  1 if {: a :} then ;                  \ refused: inside the IF

"Compile-time stack is empty" is blunter than "no control structure is open",
and deliberately so: that stack holds plain cells, so a marker left by `if` and
a value left behind by `[ 5 ]` look identical. Both are refused. If you get the
error with no control structure in sight, look for a `[ … ]` that left something
on the stack.

In practice the top of the definition is where locals read best anyway, right
where a stack comment goes.

### Limits
At most **16** locals per definition, each name **31 characters** or fewer —
Forth 2012 requires a system to accept 8. Exceeding either is a compile error
that abandons the definition, as is a `{:` with no closing `:}`.

Recursion is what consumes the locals stack: each level in flight holds its own
copy of every local. Going deeper than the stack allows reports
`locals stack overflow` and returns you to the prompt, like any other stack
overflow.

### `does>` cannot see them
A `does>` body runs when the *created* word is executed — long after the
defining word returned and its frame was released. Referring to a local there
is a compile error:

    : mk {: v :} create v , does> @ v + ;
    \ does> cannot see the defining word's locals: does>

This is refused rather than merely discouraged because it did not fail loudly:
it compiled, ran, and returned a wrong number read from a dead slot.

### Assigning: `to`
`to` writes a local, and follows the same resolution order as reading one — a
local in scope wins over a `value` of the same name, so `to` can never write
through a shadow to the global by mistake:

    : running ( n -- sum )  {: n | acc :}
        n 0 do  acc i +  to acc  loop  acc ;
    5 running .            \ 10

`acc` is after the `|`, so it is not an argument — `running` still takes one
value. That is what `|` is for: a counter, an accumulator or a scratch value
that belongs to the word rather than to its caller.

Writing is open-coded like reading — a store, not a call — because `to x` in a
loop is as hot as reading `x`.

`is` is the exception: it targets *deferred* words, and a local is not one, so
`is` on a local name is a compile error rather than a silent write to whatever
global it was shadowing.
