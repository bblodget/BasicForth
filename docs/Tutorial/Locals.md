# Locals — Stop Juggling the Stack

Forth hands a word its arguments on the stack, and for one or two that is a
pleasure. At three it starts to cost you: `rot swap over` is a puzzle you
re-solve every time you read it. Locals give those values names for the rest of
the definition. This lesson builds up to a collision test with six arguments —
a word you would not want to write any other way. About ten minutes, typing as
you go.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## Three arguments and a knot

`tween` finds a point part-way between two numbers — the arithmetic behind a
fade, an animation, a health bar draining:

    : tween-juggle ( a b pct -- n )  >r over - r> 100 */ + ;
    0 100 50 tween-juggle .
    20 60 25 tween-juggle .

`50`, then `30`. Both right. But the formula is `a + (b-a) × pct/100`, and
almost none of that survives in the code. The `>r` only parks `pct` so that
`b - a` can happen underneath it; the `over` keeps a copy of `a` that gets used
four words later. Neither is part of the calculation. Of the three words that
are, `*/` is the one worth knowing: `100 */` scales by `pct` and divides by 100
in a single step, keeping the product in double precision so it cannot overflow
midway (`help */`).

## Name them instead

`{: … :}` takes items off the stack and gives them names:

    : tween ( a b pct -- n )  {: a b pct :}
        b a -  pct 100 */  a + ;
    0 100 50 tween .
    20 60 25 tween .

Same answers, and now the line *is* the formula. No `>r`, no `over` — there is
nothing to park or copy, because a name stays available whether or not you have
used it already.

Names are listed in **stack order**, deepest first — the same order you write a
stack comment in. `a b pct` on the stack becomes `{: a b pct :}`.

## A name is just a name

That difference is bigger than tidiness. On the stack a value is *consumed* when
you use it: reading it twice costs a `dup`, and reading out of order costs a
`swap` or `rot`. A local has no such rule:

    : describe ( lo hi -- )  {: lo hi :}
        ." from " lo .  ." to " hi .  ." spans " hi lo - . cr ;
    3 10 describe

`lo` and `hi` are each mentioned twice, in whatever order suited the line.
Nothing was duplicated and nothing was rearranged.

## The declaration can carry the stack comment

Anything after `--` inside the declaration is ignored, so it can document
itself and you can drop the separate comment:

    \ : mid ( lo hi -- n )  {: lo hi :}  lo hi + 2/ ;
    : mid {: lo hi -- n :}  lo hi + 2/ ;
    3 11 mid .

Both spellings compile to the same thing. Prefer the second for one reason: the
input names are no longer a comment, they are the code, and code cannot drift
out of date. Be precise about the limit, though — only the left side is live.
`-- n` is still ignored text, and nothing checks what you leave behind.

## `|` — a local of your own

Names after `|` take nothing from the stack. They are yours, and start at zero:

    : demo ( n -- )  {: n | t :}  ." n=" n .  ." t=" t . cr ;
    7 demo

`demo` still takes one argument. `t` came from nowhere and arrived as `0` — a
counter, a total, a scratch value belonging to the word rather than its caller.
Without `|` you would fake it by pushing a `0` before the call, which reads like
idiom but quietly makes the word take an argument it does not want.

## `to` writes one

Reading a local is its name; writing one is `to` — here, summing 1 to n:

    : sum-to ( n -- sum )  {: n | acc :}
        n 1+ 1 ?do  acc i +  to acc  loop  acc ;
    5 sum-to .
    100 sum-to .

`15`, then `5050`. `acc` sits after the `|`, so it is not an argument — it is
the accumulator, zeroed for free, and `to acc` writes it back each time round.
`5050` is what the young Gauss is said to have produced in seconds, by seeing
the answer is `n(n+1)/2` — which wants `n` twice and no loop at all:

    : gauss ( n -- sum )  {: n :}  n n 1+ *  2/ ;
    100 gauss .

## A bar chart

Both halves together. `bar` scales a value to a width and draws it:

    : bar ( value max width -- )  {: v mx w | n :}
        v w mx */ to n
        n 0 ?do [char] # emit loop
        w n - 0 ?do space loop
        ." |" v . cr ;
    100 100 40 bar
    72 100 40 bar
    15 100 40 bar

`v` is read twice — to scale, then to label. `w` twice — to scale, then to pad.
`n` is computed once with `to` and used twice. On the stack that is four `dup`s
and a `rot` you no longer have to think about.

## Locals shadow — including verbs

While a definition compiles, a local name beats **anything** of that name in the
dictionary. Every language does that for variables; Forth lets you shadow verbs
too, which bites harder:

    : oops ( n -- )  {: i :}  3 0 do i . loop ;
    7 oops

That prints `7 7 7`, not `0 1 2` — inside `oops`, `i` is the local, and the `DO`
index of that name is out of reach. You will have seen the compiler say so:

    \ note: local i shadows an existing word

A note, not an error — shadowing is what locals are *for*. `i` and `j` are the
two to watch.

## Where `{:` may appear

Once per definition, and only where nothing is left open:

    : ok1  1 if ." closed " then {: a :}  ." a=" a . cr ;
    3 ok1

Fine — the `if` has already closed. This one is refused:

    : nope  1 if {: a :} then ;

The frame is built where `{:` appears but released once, when the definition
returns. Inside an `if`, calls skipping the branch would release a frame they
never built; inside a loop it would build one per iteration and release one.
Either way the locals stack drifts on every call, silently.

## Each call gets its own frame

Locals are not a fixed set of slots per word. Every call in flight has its own
copy, which is what makes recursion work:

    : fact ( n -- n! )  {: n :}
        n 1 > if  n 1- recurse  n *  else  1  then ;
    5 fact .
    20 fact .

`120`, then `2432902008176640000`. At the deepest point twenty `n`s are alive at
once, each belonging to one call, and each `n *` on the way out finds its own.

## …and its own stack

Those frames live on a stack of their own — 2048 cells — so recursion is what
consumes them, and a runaway is caught rather than let loose:

    \ : runaway ( n -- )  {: n :}  n 1+ recurse ;
    \ 1 runaway          →  locals stack overflow

Type those two lines without the `\` if you want to see it. It reports and
returns you to the prompt, like any other stack overflow: the stack is fenced by
a guard page, so overflowing it is a message rather than corruption.

## Is it faster?

You can measure it. These compute the same thing, one with locals and one by
juggling:

    : f-locals ( a b c -- n )  {: a b c :}  a b + b c + * ;
    : f-juggle ( a b c -- n )  over + >r + r> * ;
    2 3 4 f-locals .  2 3 4 f-juggle .

Both give `35`. `time` runs a word and says how long it took, so put each in a
loop — identical loops, so only the *difference* means anything:

    : t-locals  10000000 0 ?do 2 3 4 f-locals drop loop ;
    : t-juggle  10000000 0 ?do 2 3 4 f-juggle drop loop ;
    time t-locals
    time t-juggle

## What that number means

**It depends on the machine, and both answers are correct.** A reference is a
memory load written straight into your word, never a call — four instructions
on x86-64 and six on ARM64, where most of the extra goes on locating the locals
pointer. That gap is why locals win comfortably on x86-64 and lose by a similar
margin on ARM64. Not a bug; it is what the implementation costs on each chip.

Under emulation the result belongs to neither machine: an emulator turns each
instruction into some number of host instructions, and that does not preserve
what they cost relative to one another. Run it on the machine you care about.

Size is the trade that does not vary. Those inline instructions are bulkier
than the single call a stack operation compiles to, so a small word written
with locals comes out several times larger. See for yourself —
`require disasm.fs`, then `dis f-locals` and `dis f-juggle`.

## Two circles

The word that makes the case on its own. Two circles collide when the distance
between their centres is no more than the sum of their radii — six arguments,
and no stack comment needed:

    : hit? {: x1 y1 r1 x2 y2 r2 -- flag :}
        x2 x1 - dup *  y2 y1 - dup * +
        r1 r2 + dup *  <= ;
    0 0 5   8 0 5  hit? .
    0 0 5  11 0 5  hit? .
    0 0 3   0 4 1  hit? .

`-1`, `0`, `-1` — overlapping, clear, exactly touching. Both sides are squared,
so there is no square root and nothing is approximated. Try writing that one by
juggling and you will see why locals exist.

## Where to go next

You have the whole of it: `{: a b c :}` to name arguments, `|` for locals of
your own, `to` to write one, and `--` to document the lot in place.

`help locals` is the reference, including the corners this lesson skipped — the
16-local limit, why `does>` cannot see them, why `is` refuses one. Two things
worth knowing now: locals never touch the return stack, so `>r` and `r>` remain
yours; and every thread gets its own locals stack, which makes a `|` local the
scratch space a shared `variable` cannot safely be inside a worker. See
`tutorial Concurrency`.

    tutorials          \ pick another lesson

Type `end-tutorial` to wrap up. `tween`, `bar` and `hit?` stay defined.
