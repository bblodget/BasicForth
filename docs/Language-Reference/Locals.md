# Locals

Names for the values a word was given, so you can stop juggling them on the
stack. Three arguments is roughly where `rot swap over` stops being readable,
and graphics and game code is full of `x y w h colour`.

At a glance:

    {: a b c :}              ( x1 x2 x3 -- )   name the top 3 items
    a                        ( -- x )          read one, by name

## {: … :} ( x1 … xn -- )
**Compile-only.** Takes the top n items off the stack and gives them names for
the rest of the definition. Names are listed **in stack order**, so the deepest
item named comes first — the same order you write a stack comment in:

    : blit ( src x y w h -- )  {: s x y w h :}
        s x y w h ... ;

    : mid ( a b -- n )  {: a b :}  a b + 2/ ;
    10 20 mid .            \ 15

The list ends at `:}`. Everything between is a name.

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

### Limits
At most **16** locals per definition, each name **31 characters** or fewer —
Forth 2012 requires a system to accept 8. Exceeding either is a compile error
that abandons the definition, as is a `{:` with no closing `:}`.

Recursion is what consumes the locals stack: each level in flight holds its own
copy of every local. Going deeper than the stack allows reports
`locals stack overflow` and returns you to the prompt, like any other stack
overflow.

### What is not here yet
Assigning to a local (`to`) is not wired up, and a `does>` body cannot refer to
the defining word's locals — its frame is gone by the time the created word
runs. Both are being built; until then a local is read-only within its
definition.
