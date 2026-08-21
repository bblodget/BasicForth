# Environment

Every variable BasicForth reads, what it does, and what happens when it is
unset. **Nothing here is required.** An installed binary works with an
empty environment — it derives where its files live from the path of the
running binary — and a checkout works once `setup.sh` is sourced. These are
the overrides for when the defaults are wrong.

At a glance:

    BASICFORTH_PATH       where include / require look for .fs files
    BASICFORTH_DOCS       where help / apropos / tutorial look for .md pages
    BASICFORTH_PACKAGES   your own package directory (default ~/.basicforth)
    BASICFORTH_SESSION    force the interactive session on or off
    BASICFORTH_EDITOR     force the line editor on or off
    VOICE_ENGINE_CMD      the command `voice` shells out to
    VISUAL / EDITOR       which editor `edit` opens
    HOME                  `cd ~`, and the default package directory
    PATH                  searched by `needs-cmd`

The sections — each of these is `help <topic>`:

    search          where include, require, help and apropos look
    packagedir      your own package directory
    session         forcing the interactive session on or off
    editing         which editor `edit` opens, and the line editor
    speaking        the command `voice` shells out to
    display         SDL: running with no window, and the ibus hang
    system          HOME and PATH
    setup           what `. ./setup.sh` exports, and why
    precedence      why the environment beats an installed binary

## search

**`BASICFORTH_PATH`** — colon-separated directories that `include` and
`require` search. The current directory is always tried first, and is not part
of this variable.

**`BASICFORTH_DOCS`** — colon-separated directories that `help`, `apropos`,
`tutorials` and `tutorial` search. A directory's *role* comes from its last
path component: one named `Tutorial` holds lessons and is left out of `help`'s
topic listing, one named `Guides` may use single-word headings, and anything
else is a reference section listed under that name.

**Unset?** An installed binary derives both from its own location —
`<prefix>/bin/basicforth` implies `<prefix>/share/basicforth/{forth,docs}` — so
`help` and `require` work under `env -i`. A checkout has no such structure, so
without `setup.sh` you get built-in primitives and no documentation.

## packagedir

**`BASICFORTH_PACKAGES`** — the root of your own package directory, default
`$HOME/.basicforth`. It names the directory itself, not its parent, so
`BASICFORTH_PACKAGES=/opt/bf` means `/opt/bf/lib`.

Three directories under it are appended to the searches above, if they exist:

    lib/                a .fs file here is `require`-able from anywhere
    docs/Packages/      a .md page here answers `help`
    docs/Tutorial/      a lesson here is listed by `tutorials`

**Appended, never prepended** — nothing you install can shadow a library, help
topic or lesson that ships with BasicForth, and a copy in the directory you are
working in still beats both.

Point it at a directory that does not exist and the whole mechanism sits out.
That is not a workaround; it is how the test suites stay independent of
whatever the person running them has installed. Set neither it nor `HOME` and
the same applies. See `help packages`.

## session

**`BASICFORTH_SESSION`** — overrides the terminal check that decides whether
you get an interactive session. `0` forces it off; **any other value, including
an empty one, forces it on**; unset keeps the default, which is "on when stdin
is a terminal".

Useful when driving BasicForth from a script or a test harness that wants REPL
behaviour without a terminal attached.

## editing

**`BASICFORTH_EDITOR`** — the same shape of override for the line editor
(history, arrow keys, the continuation prompt). `0` forces it off, any other
value forces it on, unset means "on when stdin is a terminal". Turning it off is
what keeps piped input and script loading behaving like plain reads.

**`VISUAL`, then `EDITOR`, then `vi`** — which external editor `edit` and `:e`
open, in that order. Set `VISUAL` if you have both and they disagree.

## speaking

**`VOICE_ENGINE_CMD`** — the command template `voice.fs` runs to turn text into
a WAV. Nothing binds BasicForth to a particular speech engine; the template
takes `%o` for the output file and `%t` for the text. `setup.sh` builds one for
piper when piper is on your `PATH`, and clears it when it is not. See
`help engines`.

## display

Not read by BasicForth, but they change what it does through SDL, and both are
worth knowing about:

**`XMODIFIERS=@im=none`** — skips the X input-method handshake, which can hang
`SDL_Init` on a desktop with a wedged ibus. `setup.sh` sets it.

**`SDL_VIDEODRIVER=dummy`** — runs the graphics words with no window at all.
This is how the lesson suite exercises the drawing lessons on a machine with no
display, and it is a good way to smoke-test a game without one.

## system

**`HOME`** — expanded by `cd ~`, and the default root of the package directory
above. Unset, `cd ~` leaves the token alone and fails rather than guessing.

**`PATH`** — walked by `needs-cmd` when a library declares it needs an external
program. BasicForth reads it the way a shell does, so a `needs-cmd objdump`
finds the same `objdump` your shell would.

## setup

`setup.sh` sets these, from the checkout it lives in:

    BASICFORTH_HOME     its OWN record of the checkout root -- see below
    PATH                PREPENDS the build directory for this machine, so
                        `basicforth` runs from anywhere
    BASICFORTH_PATH     src/forth, then examples
    BASICFORTH_DOCS     Language-Reference, Tutorial and Guides

And these two, which deliberately do *not* come from the checkout:

    XMODIFIERS          the constant @im=none -- see `display` above
    VOICE_ENGINE_CMD    only when `command -v piper` finds one, and UNSET
                        otherwise, so a value inherited from another checkout
                        cannot outlive the shell that set it. Never a path
                        inside a checkout: several worktrees source this file,
                        and one checkout's venv would then serve all of them

If it cannot find `src/forth/core.fs` it sets **nothing** and returns 1.
Sourcing it from outside a checkout is not a partial setup; it is no setup.

**It does not set `BASICFORTH_PACKAGES`,** deliberately. A checkout is not a
package directory, so a development shell uses `~/.basicforth` like any other.

**`BASICFORTH_HOME` is not read by BasicForth at all.** It is `setup.sh`'s own
record of the checkout root, and what it builds is `PATH`, `BASICFORTH_PATH` and
`BASICFORTH_DOCS` — nothing else. Do not confuse it with `BASICFORTH_PACKAGES`;
they are unrelated, and one names a source checkout while the other names your
package directory.

## precedence

The environment always wins over what an installed binary derives from its own
path. That is what lets a checkout with `setup.sh` sourced keep using the
checkout even with a copy installed system-wide, and it is why every test suite
sets these variables itself rather than trusting the machine it runs on.
