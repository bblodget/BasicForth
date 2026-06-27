# Getting Started

Welcome to BasicForth — a Forth environment in the spirit of 1980s BASIC: turn
it on and start coding. This first lesson gets you from a blank prompt to
writing your own commands.

## The prompt

When BasicForth starts, it prints a prompt and waits for you:

    >

Type something and press Enter. After it runs, BasicForth prints ` ok` to show
it finished without error. Type `bye` and press Enter to leave at any time.

## Your first calculation

Forth does arithmetic, but not the way you may expect — you write the numbers
*first*, then the operator:

    1 2 + .

This prints `3`. Read it left to right: push `1`, push `2`, add them, then print
the result with `.` (pronounced "dot"). This back-to-front style is called
*Reverse Polish Notation* (RPN), and once it clicks it is wonderfully simple.

Try a subtraction:

    10 2 - .          \ prints 8

## The stack

The numbers you type don't go to a variable — they go onto **the stack**, a pile
of values. `1 2` pushes two numbers; `+` removes the top two and pushes their
sum; `.` removes the top value and prints it.

You can look at the stack without disturbing it using `.s`:

    7 3 .s            \ prints <2> 7 3

The `<2>` is how many items are on the stack; then it lists them from bottom to
top. `.s` is your best friend while learning — it never changes the stack, so
use it freely to see what's going on.

The stack is the subject of its own reference page; from the prompt type:

    man stack

## Printing things

`.` prints a number. To print text, use `emit` for a single character (by its
character code) —

    42 emit           \ prints *  (42 is the code for '*')

— and you'll print whole strings once you start defining your own words, next.

## Defining your own words

This is where Forth shines: you teach it new commands, called *words*. A
definition starts with `:` (colon), then the name, then what it does, then `;`
(semicolon) to finish:

    : square  dup * ;

`square` takes a number, `dup`licates it (so there are two copies), and
multiplies them. Now `square` is a permanent command, just like `+`:

    5 square .        \ prints 25

Words can print text, too. Inside a definition, `." ..."` prints the text and
`cr` starts a new line:

    : hello  ." Hello, BasicForth!" cr ;
    hello             \ prints: Hello, BasicForth!

Your new words can use words you defined earlier, building up from small pieces —
the whole language grows out of this.

## Leaving

When you're done:

    bye

## Where to go next

- `topics` — list every help topic available.
- `man <topic>` — read a topic (e.g. `man stack`).
- `apropos <word>` — find which topics mention a word (e.g. `apropos dup`).

Next lesson: more about the stack and the words that rearrange it.
