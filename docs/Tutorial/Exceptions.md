# Exceptions — Errors You Can Catch

Sooner or later a word fails: a bad argument, a full disk, a missing file.
So far a failure has meant the nuclear option — stacks cleared, back to the
prompt. `catch` and `throw` let your program handle the failure itself and
keep going. Two words, one pattern, about ten minutes.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## A word that can fail

`abort"` is the guard you've seen in the libraries: if the flag is true, it
prints its message and gives up. Define a word that only likes even numbers:

    : half ( n -- n/2 )  dup 1 and abort" odd number! "  2/ ;
    8 half .           \ 4
    7 half             \ odd number!

Failing was the right call — half of 7 isn't an integer. The question this
lesson answers: who gets to decide what happens next?

## The cost of an abort

By default, the answer is: nobody. An abort throws away *everything* —
including work that had nothing to do with the failure:

    10 20 30 depth .   \ 3
    7 half
    depth .            \ 0

Your 10, 20, 30 are gone. Harmless at the prompt; fatal halfway through a
game loop or a long calculation. Type `next` for the safety net.

## catch: run it with a safety net

`catch` runs a word the way `execute` does — you hand it an execution token
(`'` gets one) — but it *traps* any failure inside. First the happy path:

    8 ' half catch . .   \ 0 4

Read the results top-down: `catch` pushed **0** for "completed normally",
and underneath is `half`'s answer, 4. No failure, nothing unusual — just an
extra 0 to say so.

## Catching the failure

Now the odd number, with the net in place:

    7 ' half catch .   \ odd number! -2
    depth . drop       \ 1

The message still printed, but you got **-2** — `abort"`'s code — instead
of losing everything. The stack depth is back to what it was before `catch`
ran; the cell `half` was chewing on is still *there* but its value is
unspecified, so `drop` it. The important part: it's still your turn.

## The handler shape

Non-zero is true in Forth, so the code `catch` returns drops straight into
an `if`. This is the everyday pattern (inside a definition, `[']` replaces
`'`):

    : try-half ( n -- )  ['] half catch if drop ." skipped " else . then ;
    8 try-half         \ 4
    7 try-half         \ odd number! skipped

Failure path: drop the unspecified cell, handle it. Success path: the
result is right there. Nothing aborted; a loop calling `try-half` would
just keep going.

## throw: raise your own

`abort"` always means "print and code -2". `throw` is the general form:
pick a code, raise it, and the nearest `catch` gets it:

    : guard ( n -- n )  dup 100 > if 7 throw then ;
    50 guard .         \ 50
    200 guard          \ uncaught exception: 7

With no `catch` anywhere, a throw falls back to abort behavior — reset to
the prompt, reporting the code. Pick positive numbers for your own codes:
-1 and -2 are taken, and the standard reserves the rest of the negatives.

## 0 throw does nothing

The zero case is the quiet star of the wordset:

    0 throw  depth .   \ 0

Why that matters: lots of words return an *ior* — 0 for success, an error
code otherwise. `throw` consumes it either way:

    : grab ( -- addr )  1024 allocate throw ;
    grab free drop

`allocate throw` reads as "allocate, and fail loudly if that didn't work" —
one word replacing a whole `if drop abort" ..." then` dance. Success costs
nothing; failure throws the errno.

## Clean up, then rethrow

The pattern that motivated this whole wordset — run a task, *always* clean
up, then pass any failure along:

    : task ( -- )  ." working... "  5 throw ;
    : tidy ( -- )  ['] task catch  ." (cleaned up) "  throw ;
    tidy               \ working... (cleaned up) uncaught exception: 5

The final `throw` re-raises the 5 *after* the cleanup ran. And when `task`
someday succeeds, `catch` returns 0 and `0 throw` does nothing — cleanup
runs on both paths, failures still surface. A game does exactly this:
`['] play catch  snd-close sdl-close  throw` — no more windows left open
by a crash.

## abort is a throw too

The old bluntness and the new wordset are one mechanism: `abort` *is*
`-1 throw`, and `abort"` prints, then throws -2. So `catch` traps both:

    : risky ( -- )  true abort" went boom " ;
    ' risky catch .    \ went boom -2
    ' abort catch .    \ -1

That's why an uncaught -1 or -2 prints no "uncaught exception" line —
their story was already told (or, for plain `abort`, deliberately silent).

## What catch does not undo

`catch` restores the *stacks* — it does not rewind the world. Stores,
files, devices, allocated memory: whatever happened before the throw,
happened:

    variable hits  0 hits !
    : bump-fail ( -- )  1 hits +!  13 throw ;
    ' bump-fail catch drop  hits @ .   \ 1

The store to `hits` survived the throw. That's not a flaw — it's why the
clean-up-then-rethrow pattern exists: undoing side effects is the
catcher's job, and only the catcher knows what needs undoing.

## Where to go next

You have the whole wordset: `catch` to keep control, `throw` to raise and
relay, codes to say what went wrong, and cleanup on every path. In the
reference, `help catch` and `help throw` have the fine print;
`docs/Exceptions.md` covers how it works underneath. Spot it in the wild:
every `abort"` in the libraries is now something your program may choose
to survive.

    tutorials          \ pick your next lesson

Type `end-tutorial` to wrap up. Happy catching!
