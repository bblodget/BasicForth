# Speech

Two ways to make BasicForth talk, aimed at two different moments.

**Rendering** (`voice.fs`) drives an external text-to-speech program to write
a WAV file, which you then load and play like any other sample. It is what a
game wants: render the phrases once, ship the WAVs, load them at startup.

**Speaking** (`speech.fs`) synthesizes into memory and plays immediately, so
`say` works from the prompt on text you have only just typed.

The split is not arbitrary — it falls out of how long synthesis takes.

## Why a game renders ahead of time

Synthesis is fast in the sense that matters for a REPL and slow in the sense
that matters for a frame. Measured on the development laptop with flite's
`slt` voice:

    "go"                  8.7 ms of work for   0.72 s of audio
    "hurry hurry hurry"  16.8 ms          for  1.42 s
    "the quick brown..." 35.8 ms          for  2.97 s

That is roughly eighty times faster than real time, and still one to two
dropped frames at 60 Hz. A neural engine is heavier again: it loads a model
before it says anything.

So a game that speaks mid-play should not be synthesizing mid-play. It
renders its vocabulary offline, exactly as the TI-99/4A's speech synthesizer
had a fixed vocabulary in ROM, and plays samples at run time. That costs
nothing a sound effect does not already cost.

## Rendering with voice.fs

    require voice.fs
    s" you win" s" voice/you-win.wav" voice-render abort" render failed"

The engine is named by a command template, not baked in:

    s" piper -m en_US-lessac-medium -f %o -- %t" voice-cmd!

`%t` expands to the text and `%o` to the output path, both **quoted**, so a
phrase containing an apostrophe or a `$` is data rather than shell syntax.
Everything else in the template passes through verbatim, which is what lets
one word drive engines whose flags disagree. See `help voice`.

Because nothing in BasicForth binds to a particular engine, switching is one
line and costs no code. `voice.fs` requires only `shellutil.fs` — no FFI, no
SDL, no WAV decoder — so rendering works on a machine with no audio hardware
at all, including the board and the QEMU aarch64 test run.

## Installing an engine

Nothing here ships an engine; the machine provides one. Piper is a good
default: neural, offline, small, and permissively licensed.

    sudo apt install pipx                 # or your distribution's package
    pipx ensurepath                       # once: puts ~/.local/bin on PATH
    pipx install piper-tts
    command -v piper                      # check before going further

    mkdir -p ~/.local/share/piper-voices
    "$(dirname "$(readlink -f "$(command -v piper)")")/python" \
        -m piper.download_voices \
        --data-dir ~/.local/share/piper-voices en_US-lessac-medium

**`pipx ensurepath` matters, and it needs a fresh shell.** It edits a shell
profile (`~/.bashrc` or similar), so the change reaches the shell you are
already in only after you start a new one or re-source that file. Skip it, or
carry on in the same shell, and everything above still *succeeds* while
`piper` is not on `PATH` — which is why the check is there. `setup.sh` finds
its engine on `PATH` and nothing else, so an unreachable piper leaves
`VOICE_ENGINE_CMD` unset, and the only sign is the suite's real-engine test
reporting `SKIP … VOICE_ENGINE_CMD not set`.

`pipx` is the tool for installing Python **applications** rather than
libraries: piper gets its own isolated environment, and the `piper` command is
linked into `~/.local/bin` — the directory `ensurepath` adds. A plain
`python3 -m venv` works too, but then the command exists only inside that
venv — fine until you have several checkouts, none of which can see a venv
belonging to another.

Downloading voices is the one thing that needs the environment's own
interpreter: pipx links the `piper` **app** onto `PATH`, and `download_voices`
is a module rather than an app. Hence the incantation above — it follows the
`piper` symlink back to the environment it lives in and uses the `python`
beside it, rather than naming a pipx directory. That matters because pipx has
moved its venvs (older versions used `~/.local/pipx/venvs`, newer ones
`~/.local/share/pipx/venvs`), and a written-down path is right only for the
version you happened to test. The voice is about 60 MB; `--data-dir` is what
both commands call it.

`setup.sh` builds the template from whatever `piper` is on `PATH` and exports
it as `VOICE_ENGINE_CMD`, so there is no install path written down anywhere to
drift. `PIPER_VOICES` and `PIPER_VOICE` override the voice store and the voice.

**`voice.fs` reads that variable when it loads**, so the whole setup is:

    . ./setup.sh
    ...
    require voice.fs
    s" you win" s" you-win.wav" voice-render abort" render failed"

with no template to paste. An explicit `voice-cmd!` still overrides it, and
`voice-from-env` goes back.

It **clears** the variable when no engine is on `PATH`, rather than leaving
whatever an earlier shell set — an inherited value would quietly keep pointing
at an engine this shell cannot see.

The integration suite reads that variable and runs one end-to-end check that
a real engine's WAV renders *and decodes*, which no stand-in engine can
answer; unset, the check skips and says so. To use a different engine, set
the template by hand **after** sourcing, and in single quotes — a template
reaches `voice-cmd!` through `s"`, which ends at the first double quote.

Other engines work the same way. Two that are packaged on most Linux
distributions:

    s" espeak-ng -w %o -- %t" voice-cmd!
    s" flite -voice slt -o %o -t %t" voice-cmd!

Both are robotic next to a neural voice, and both are useful precisely
because they are tiny and always available — good for a smoke test that a
template is wired up correctly before downloading a 60 MB model.

## Checking a render worked

`voice-render` returns an `ior` and `voice-why` explains it. The failure
worth knowing about is an engine that **exits 0 having written nothing** —
piper does this when its voice model is missing. `voice-render` checks the
output file itself rather than trusting the exit status, so that case comes
back as an error instead of an empty WAV reaching `wav-load`.

For that check to mean anything it has to be about *this* render, so the
output file is removed before the engine runs. Otherwise the nastiest version
of the same failure gets through: re-render a vocabulary after the voice
model goes missing and every phrase reports success while keeping its old
audio — nothing looks wrong until you listen. A render that cannot run at all
removes nothing, so a refusal never costs you the previous take.

Removing can fail too — a read-only directory will not give the file up — so
the clearance is verified rather than assumed. If the path could not be
cleared the render stops there and says so, instead of judging the engine by
a file it was never able to replace.

## Speaking with speech.fs

`speech.fs` puts `say` at the prompt, synthesizing into memory through the FFI
and playing on a `sound.fs` channel — no file, no shell, and `talking?`
answered by the channel itself. flite suits that job: `flite_text_to_wave`
takes two arguments and hands back a `cst_wave` (`sample_rate@8`,
`num_samples@12`, `num_channels@16`, `samples*@24`, verified by calling it),
which fits the FFI as it stands and needs no callback. The samples go straight
to `ch-put` and the wave is freed on the next line, because SDL copies.

Speech takes **its own channel**, with `next-ch` at open time, and keeps it. A
channel is a sequential queue, so that single decision buys both properties
worth having: successive `say`s wait for each other instead of talking over
themselves, and a phrase never queues up behind a sound effect.

Binding is lazy — `require speech.fs` never touches flite, and `speech-open`
returns an `ior`. A machine without the library gets a reason it can print
rather than an abort while loading a file, which is the same shape `snd-open`
uses for a machine without audio.

The cost that shapes everything else: **`say` blocks while it synthesizes**.
Measured with `cmu_us_slt`, "Go!" is 7 ms, a full sentence 38 ms, against a
16.7 ms frame at 60 Hz. Fast enough to feel instant at a prompt, too slow to
sit in a frame loop — which is the whole reason `voice.fs` exists beside it
rather than being replaced by it.

## Where speech goes next

Longer term, an engine that streams while it speaks would let BasicForth
start talking before a sentence is finished. That wants a C callback into
Forth, which is the same machinery a live synthesiser needs — see
`docs/WildIdeas.md`.

## See also

- `help voice` — the rendering words
- `help samples` / `help playing` — loading and playing the WAV afterwards
- [Sound.md](Sound.md) — how the audio backend works
