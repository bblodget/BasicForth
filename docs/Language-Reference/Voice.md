# Voice — Rendering Speech to WAV Files

Turns text into a WAV file by driving an external text-to-speech program.
Load it with `require voice.fs`. The result is an ordinary sample: `wav-load`
it and play it like any other sound.

    require voice.fs
    s" you win" s" voice/you-win.wav" voice-render abort" render failed"

At a glance:

    voice-render   ( text u path u -- ior )  speak text into a WAV file; 0 = ok
    voice-why      ( -- c-addr u )           why the last render failed
    voice-cmd!     ( c-addr u -- )           set the engine command template
    voice-cmd      ( -- c-addr u )           the template in force
    voice-from-env ( -- )                    re-read $VOICE_ENGINE_CMD

This is an **offline** step. A neural engine spends hundreds of milliseconds
loading its model before it says anything, and a 60 Hz frame is 16 — so a
game renders its phrases once, ships the WAVs beside itself, and loads them
at startup. See [Speech.md](../Speech.md) for the other way round — speaking
text straight from the prompt, with no file in between.

`voice.fs` needs only a shell, not an audio device: rendering works on a
machine with no libSDL3 and no sound hardware at all.

## voice-render ( text u path u -- ior )
Speak `text` into a WAV file at `path`, using the engine named by
`voice-cmd`. Returns **0 on success**, non-zero on failure — an `ior`, like
`allocate` and `open-file`. Ask `voice-why` for the reason.

    s" hurry hurry hurry" s" voice/hurry.wav" voice-render
    if voice-why type cr then

The engine's own output is left on the terminal, and when a render fails its
complaint is usually more specific than `voice-why`.

Both strings can come from `s"` on one line, as above — but only just.
Interpreted `s"` alternates between **two** transient buffers, so a third
`s"` in the same phrase would overwrite the first.

The directory must already exist; this word writes a file, it does not make
a path.

**Any existing file at `path` is removed before the engine runs.** That is
what makes the check below meaningful: "did this render produce audio" has to
be about *this* render, not about whatever happened to be there already. A
render that cannot run at all (ior 2) removes nothing, so a refusal never
costs you the previous take.

## voice-why ( -- c-addr u )
The reason the last `voice-render` failed, as text. Empty after a successful
render. The six outcomes:

    0  rendered
    1  no engine command set (voice-cmd!)
    2  engine command too long to run
    3  engine exited with an error
    4  engine wrote no audio
    5  could not clear the previous output

The last one is worth its own code: an engine that exits **0 having written
nothing** is a real failure mode — piper does exactly that when its voice
model is missing — and a caller trusting the exit status alone would go on to
`wav-load` an empty file.

It is also why the output is cleared first. Re-rendering a vocabulary whose
voice model has gone missing would otherwise report success for every phrase
while leaving the previous take on disk — a failure nothing reveals until you
listen to it.

Clearing can fail in its own right, which is ior 5: a read-only directory, or
a `path` naming a directory rather than a file. Either way the render stops
there rather than going on to judge the engine by a file it was never able to
replace.

## voice-cmd! ( c-addr u -- )
Set the command template used to run the engine, overriding whatever loading
`voice.fs` worked out. The template in force is decided in this order:

    voice-cmd!            an explicit call, at any time — always wins
    $VOICE_ENGINE_CMD     read once, when voice.fs loads
    a built-in default    piper, with no --data-dir

so `. ./setup.sh` then `require voice.fs` needs no template pasted in. The
default is a guess and says so: it finds a voice only where piper happens to
look by default, and a machine that keeps its voices elsewhere gets the
engine's own *"unable to find voice"* — which says nothing about *which*
template asked for it.

Two placeholders expand:

    %t   the text to speak        %o   the output WAV path

Everything else is shell syntax, passed through verbatim. The two
substitutions are **quoted**, so a phrase containing an apostrophe, a `$`, a
backtick or a semicolon is data and never syntax.

    s" piper -m en_US-lessac-medium -f %o -- %t" voice-cmd!   \ the default
    s" espeak-ng -w %o -- %t" voice-cmd!
    s" printf '%s' %t | some-engine --out %o" voice-cmd!      \ stdin engines

Only `%o` and `%t` expand, so a literal `printf %s` survives untouched.

Because a template is written with `s"`, it cannot contain a double quote —
use single quotes, which is what every shell wants here anyway.

A template too long to hold (512 characters) is stored as **nothing** rather
than truncated: half a command could have lost the flag naming its output
file, and `voice-render` answering "no engine command set" is better than
running that.

## voice-cmd ( -- c-addr u )
The template currently in force.

    ." engine: " voice-cmd type cr

The string lives **in the template buffer itself**, so the next `voice-cmd!`
overwrites it. To switch engines and switch back, keep your own copy of the
old template — holding what `voice-cmd` returned restores nothing.

## voice-from-env ( -- )
Set the template from `$VOICE_ENGINE_CMD`, as loading `voice.fs` already did.
Use it to get back to the configured engine after experimenting:

    s" espeak-ng -w %o -- %t" voice-cmd!    \ try the robotic one
    voice-from-env                          \ back to the real one

An **unusable** variable — unset, empty, or longer than a template can be —
leaves the current template alone rather than clearing it. `voice-cmd!` refuses
both of the latter by storing *nothing*, which is right when you asked for one
specific template and must not silently get another, but wrong for a variable
that was only ever meant to improve on a working default: the result would be
"no engine command set" for a session that had a perfectly good one.

See `help samples` for loading the WAV afterwards, `help playing` for playing
it, and `docs/Speech.md` for how speech fits together as a whole.
