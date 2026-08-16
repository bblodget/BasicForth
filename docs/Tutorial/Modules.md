# Modules — Keep Your Work as a Program

Everything you define at the prompt is a **module**: your program, sitting on
top of BasicForth's core. This lesson turns one into a file you can leave and
come back to, then shows how to change it in place — the BASIC `SAVE`/`LOAD`
loop, with a Forth twist. About ten minutes, typing as you go.

This is a *lesson*: short steps, one idea each. After each step you're back
at the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## What you've built so far

Define a word — anything at all:

    : hello  ." Hello!" cr ;

Now ask what you own:

    .module

`.module` lists **your** words, newest first — the ones you added on top of
core. That list is your module. Type `next`.

## Save it

Give the module a name and it becomes a file:

    save score.fs

BasicForth prints the full path it wrote. That file is plain Forth source:
the definitions you typed, in the order you typed them. Nothing is hidden in
it, and nothing else is needed to bring your program back.

## Look at the whole program

    list

That's BASIC's `LIST` — your program, top to bottom. It shows the file's text
*plus anything you've typed since*, so what you see is always what you have.
(`q` stops a long listing.)

## Keep going — definitions append

Add some state and two words that use it:

    variable score
    : bump   1 score +! ;
    : show   ." score: " score @ . cr ;

    bump bump show
    list

`show` prints 2, and `list` shows all four definitions — including the three
you haven't saved yet. Type `save` on its own (no name) whenever you want the
file caught up.

## Changing a word: `:e`

Suppose "score:" should read "points:". Retyping `: show ... ;` would *layer a
new definition* over the old one — Forth keeps both, and words that already
call `show` keep calling the old one. That's rarely what you meant, so
BasicForth prints `redefined show` when it happens.

Instead, edit it:

    :e show   ." points: " score @ . cr ;
    show

`:e` replaces the definition **where it stands in the file** and reloads, so
every caller is rebuilt against the new version. (Unsaved work is saved first,
so the file is never behind.)

## What a reload costs

Did you notice `show` printed 0, not 2?

Rebuilding means reading the file again, and a fresh `variable` starts at
zero. Your *program* survives an edit; whatever it was holding at the time
does not. That's the trade for never having stale code around, and it's worth
knowing before it surprises you mid-game.

A step near the end shows how to keep a value that matters.

## Taking one back out: `delete`

`delete` is `:e` with nothing as the replacement — it removes the word from
the file and reloads:

    delete hello
    hello

`hello` is gone, and the `?` tells you so. Nothing else was disturbed.

## `delete` is also undo

Because `delete` removes the *newest* definition of a name, it undoes a
redefinition — the one `redefined` warned you about:

    : bump   5 score +! ;
    delete bump
    bump show

The 5-point version is gone and the original `1 score +!` is back — `show`
prints 1, not 5 — because the reload replayed the file, which still holds
the original. (And the score started from 0 again, as it does after every
reload.) Type `next`.

## Reload — the edit-and-run loop

    reload

`reload` forgets your module and reads the file again. That's the whole loop:
change something, reload, try it. It's also what `:e` and `delete` do for you
after they rewrite the file, which is why callers are never left pointing at
code that no longer exists.

Note what that means: the file is the program. Anything you typed but haven't
saved is *not* in it, so a reload drops it — at the terminal you'll be asked
"save first? (y/n)" before that happens.

## Your editor, for bigger changes

`:e` is for one-liners. For a real edit, two words open `$EDITOR` on the word
and reload when you quit — worth trying *after* the lesson, since they take
over the screen:

    \ edit show          \ open show's source in your editor
    \ define total       \ open a skeleton for a NEW word
    \ edit               \ no name: open the whole module file

Same rule as `:e`: on save the file is spliced and reloaded, so the change
lands in one place and everything rebuilds.

## Who calls this word?

Before changing something, ask who depends on it:

    uses score

It searches your own definitions and reports the words that mention `score`.
Ordinary grep, but over the module you're holding — the check you want before
a rename or a `delete`.

## Lines that only *do* something

You just saw a reload reset `score` to 0. `save` records lines that *define*
a word; a line that only makes something happen leaves no trace, so the value
a variable was holding is gone. `keep` says "write this line down too":

    100 score !  keep
    save
    reload
    show

The line went into your program, so the reload replayed it and `show` prints
100 instead of 0. Use `keep` for setup your module needs when it loads, and
for state a `variable` holds.

## Starting and stopping

Name a word `on-start` and BasicForth runs it after your module loads;
`on-stop` runs before the module is torn down. `booting?` tells the two
kinds of load apart:

    : on-start   booting? if  ." ready!" cr  then ;
    save
    reload
    load score.fs

Save first — a hook that isn't in the file can't run when the file is
replayed. Then: nothing after `reload`, because that's a restart; `load` is a
real start, so it prints `ready!`. That's how a game launches itself on `basicforth game.fs` without
relaunching every time you edit a word.

## Switching programs

    new

`new` clears the module — a blank slate, core only. `load <file>` swaps in a
different program the same way. Both ask "save first? (y/n)" if you have
unsaved work, so a typo can't cost you anything.

Your `score.fs` is still on disk. `load score.fs` brings it all back.

## When your program needs a library

Everything so far has been your own words. Most programs lean on a library too,
and `require` is how you say so:

    require fontcore.fs
    require fontcore.fs

The first pulls in `fontcore.fs` — and `graphics.fs`, which *it* requires in
turn. The second does nothing at all: `require` remembers what it has already
loaded, so every file can name what it needs without anyone tracking who gets
there first.

That line is captured like a definition, so `save` writes it into your file and
the program loads its own dependencies next time.

## Ask before you load: `deps`

A file declares its needs at the top, in a **dep block**: the `require` lines,
plus `needs-lib` for a shared library it cannot run without, or `wants-lib` for
one it can manage without. `deps` reads that block and checks it against this
machine — without loading a line of the file:

    deps fontcore
    deps sdl3

`fontcore` is pure Forth, so it is always fine. `sdl3` needs a real library, so
what you see there depends on your machine. A `require` reads `loaded`, `found`
or `MISSING`; a `needs-` reads `ok` or `MISSING`, which stops the load; a
`wants-` reads `ok` or `missing (optional)`, which does not — the file loads
with less of it working. A missing line carries the hint its author wrote, like
which package to install, and the last line is the verdict for the whole file.

## Where to go next

That's the loop: **save**, `list`, `:e`, `delete`, `reload`, and `require` for
what you did not write. The reference page `help modules` covers every word here
plus `redo` and `-session`; `help files` covers `require`, `deps` and the
`needs-`/`wants-` declarations; `see <word>` shows any word's source, from the
file or from your session. `docs/Persistence.md` tells the deeper story — why
editing mutates the file in place while a plain `:` appends.

    tutorials          \ pick another lesson

Type `end-tutorial` to wrap up. Your words stay defined.
