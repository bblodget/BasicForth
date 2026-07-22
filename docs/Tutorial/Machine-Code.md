# Machine-Code — What Your Words Compile To

You've been told BasicForth compiles your definitions to real machine code —
no interpreter in the middle. In this lesson you stop taking that on faith:
you'll disassemble your own words and read the instructions the compiler
laid down, watch a literal hide its bytes in the code stream, and peek at
the assembly behind the built-ins.

The listings below appear on an x86-64 machine; on ARM64 the instructions
differ but every idea is the same — that's the point of using the system
disassembler. Addresses in *your* session will differ from any shown here;
that's normal, they depend on what you've defined.

This is a *lesson*: short steps, one idea each. Type `next` to continue,
`back` to re-read, and `end-tutorial` to stop.

Type `next` to begin.

## Load the tool

The disassembler is a library, loaded on demand:

    require disasm.fs

It drives the system's `objdump` (from binutils — the same tool that built
BasicForth), so it needs that on PATH; if it's missing, `dis` says so
politely instead of guessing. Type the line, then `next`.

## Your first disassembly

Define a word, then ask to see its machine code:

    : sq  dup * ;
    dis sq

The banner tells you where the code lives (an address in the
*dictionary*) and how big it is — a couple dozen bytes at most. Then the
listing: a `call` per word and a `ret` (on ARM64 the calls are `bl`, with
an `stp`/`ldp` pair bracketing them — the frame link its ABI wants).
That's the whole word. `next`.

## Subroutine Threaded Code

Look at what the compiler did with `: sq dup * ;` — it compiled one `call`
per word in the definition, and `;` became `ret`. This scheme is called
**Subroutine Threaded Code**, and it's the heart of BasicForth: your
definition *is* a machine-code subroutine, run by the CPU directly.

The `\ dup` and `\ *` at the ends of the lines are `dis` helping you: a
raw listing only shows target addresses, so `dis` looks each one up in the
dictionary and writes the word's name in the margin. `next`.

## Inside a building block

Those `call`s land in real code too. Look inside `dup`:

    dis dup

This time the banner says *primitive*: `dup` isn't compiled Forth, it's
hand-written assembly living in the BasicForth binary itself, under the
symbol `forth_dup`. Three instructions on x86-64: fetch the top of stack,
grow the stack, store the copy. The register there (`%r15` on x86-64,
`x19` on ARM64) is the **data stack pointer** — the stack your numbers
live on is just memory it points at. `next`.

## Calls all the way down

Your words and the built-ins are the same kind of thing. Prove it:

    : cube  dup sq * ;
    dis cube

Three calls and a `ret` — and the middle call's target is your own `sq`,
annotated just like the primitives around it. When you define a word, you
extend the machine's vocabulary on equal footing with `dup` and `*`.
`next`.

## A literal hides in the code

Numbers need different treatment — there's no `call 5`. Look:

    : five  5 ;
    dis five

The line after the banner calls `lit`, the runtime that pushes an inline
value — and the next 8 bytes *are the number 5*, data sitting in the
middle of the instruction stream. Find the `05` at the start of that
line's hex column. A plain disassembler would chew those bytes into
garbage instructions (on x86-64 it even loses step and swallows the
following `ret`) — but `dis` knows the compiler's idiom, so it prints
the span as what it is: `\ literal: 5`, hex intact, and the `ret` after
it stays honest. Strings work the same way: try `: hi ." hello" ;` then
`dis hi` and read your text back out of the code. `next`.

## Control flow becomes jumps

`if` doesn't call anything — it compiles a test and a conditional jump:

    : odd?  1 and if 1 else 0 then ;
    dis odd?

After the `call` to `and` comes a short test-and-branch sequence, and the
jump's target is an address *inside this same listing* — skip ahead and
you'll find the instruction it lands on. `if`/`else`/`then` vanish at
compile time; only jumps remain. (The three literals show up as
`\ literal:` lines, as you now expect.) `next`.

## A variable is code too

    variable hits
    dis hits

Even a variable compiles code: a call to `lit` with the *address* of its
cell inline — shown as a `\ literal:` whose hex value is exactly where
your data lives — then `ret`. That's how `hits` pushes its address when
you run it. The stub also leaves `does>` (see `help defining-words`) room
to graft new behavior onto a created word later: on x86-64 that's the
trailing `nop`s you see after the `ret`; on ARM64 `does>` instead
overwrites the `ret` itself with a branch. `next`.

## Reading a big one

Now you can read real machinery. If you did the Exceptions lesson:

    dis catch

There's the whole exception frame from that lesson, laid out in
instructions: a run of pushes saving the interpreter's state (objdump
labels the globals by name — `<handler>`, `<source_addr>`), the indirect
`call` that runs your word, and the success path that pushes 0. Machine
code with the lights on. `next`.

## When dis can't help

`dis` needs a word it can find and locate:

    dis nosuchword          \ ? nosuchword

A typo gets the usual complaint. Words with no dictionary entry
(`:noname` definitions) and hidden internals can't be looked up by name —
though `dis` still *annotates* hidden ones like `lit` when they show up as
call targets in other listings. `next`.

## Where to go next

- `see sq` shows the *source* of a word; `dis sq` shows the *code*. Two
  sides of the same coin — `help tools` lists both.
- docs/Disassembler.md explains how `dis` works — including how it finds
  the running binary and why the same lesson works on ARM64.
- The instruction cheat-sheets: docs/x86_Quick_Reference.md and
  docs/ARM64_Quick_Reference.md.
- Try `dis` on anything you define from here on. When a definition
  surprises you, the machine code never lies.

Type `end-tutorial` to leave — everything you defined is still here.
