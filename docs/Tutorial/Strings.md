# Strings — Text on the Stack

Forth has no string type. What it has is two stack items — an address and
a length — plus a handful of words that make, print, slice, and compare
them. This short lesson shows you the pair and the idioms around it.
About ten minutes, typing as you go.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## Two numbers make a string

`s"` makes a string; look at what it actually leaves behind:

    s" hello" .s

Two items: an **address** (yours will differ) and a **5** — where the text
starts, and how many characters. `type` consumes exactly that pair:

    type               \ hello

That's the whole design. A string *is* an addr/len pair, and every string
word deals in them.

## Printing without the ceremony

When you only want to say something, `."` prints text directly:

    ." score: " 100 . cr

Use `."` for messages; use `s"` when you want the string as a *value* to
pass around. (There's also `.(` which prints even mid-compile — handy for
progress messages in files. `help printing` compares all three.)

## It's just bytes

The address points at plain memory, one character per byte:

    s" hello" drop c@ emit     \ h

`drop` discards the length, `c@` fetches the first byte, `emit` prints it.
If you took the Arrays lesson: a string is a byte array you didn't have to
build — `c@`, `c!`, and friends all apply.

## Slicing

Because a string is just addr+len, slicing is arithmetic — no copying.
`/string` drops characters from the front; `-trailing` trims spaces off
the back:

    s" hello" 2 /string type      \ llo
    s" hi   " -trailing type      \ hi (the three spaces are gone)

The first moved the address forward 2 and shrank the count; the second
only shrank the count.

## Characters are numbers

A character is just a small number — its code. `char` reads one from the
input; `emit` goes the other way:

    char A .           \ 65
    65 emit            \ A

Inside a definition, use `[char]` instead (it compiles the code as a
literal — `char` would try to read at the wrong time).

## Comparing

`compare` takes two strings and returns 0 when they're equal, so the
"same?" idiom is `compare 0=`:

    : yes? ( c-addr u -- flag )  s" yes" compare 0= ;
    s" yes" yes? .     \ -1  (true)
    s" nope" yes? .    \ 0   (false)

This is how you'll test user input, command names, file extensions — any
text decision.

## Borrowed memory

Now the catch. At the prompt, `s"` parks its text in a small **transient
buffer** — there are only two, reused round-robin. Watch the oldest one
get clobbered:

    s" AAAA" s" BBBB" s" CCCC"
    type space type space type    \ CCCC BBBB CCCC

The third `s"` overwrote the first string's memory: that last `type`
printed `CCCC`, not `AAAA`. So a prompt-level `s"` string is fine to use
*now*, but not to keep. (Inside a `:` definition, `s"` compiles the text
into the word — that copy is permanent.)

## Keeping a string

To keep text, copy it into memory you own — `create`/`allot` for the
bytes, a `variable` for the length, `cmove` to copy:

    create name 16 allot   variable name-len
    : name! ( c-addr u -- )  dup name-len !  name swap cmove ;
    : name@ ( -- c-addr u )  name name-len @ ;
    s" Ada" name!
    name@ type         \ Ada

`name!` stores any string; `name@` hands back a fresh addr/len pair. Try
a few more `s"`s and then `name@ type` again — your copy is safe.

## The payoff

Glue the pieces into something friendly:

    : greet  ." Hello, " name@ type ." !" cr ;
    greet                       \ Hello, Ada!
    s" Grace Hopper" name!  greet

Stored text, `type`, and `."` working together — that's most of the
string handling a real program ever needs.

## Where to go next

You've met the pair behind all Forth text: **an address and a length**.
The reference has the full toolbox — `help strings` for `count`,
`compare`, `cmove` and friends, `help printing` for output. (One heads-up
for later: C libraries want NUL-terminated strings instead — when you get
to the FFI, `help ffi` shows `>z`, the one-word converter.) The Snake
tutorial uses `."` and `type` to draw a whole game.

    tutorials          \ pick your next lesson

Type `end-tutorial` to wrap up. Happy typing!
