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

    python3 -m venv ~/.venv/piper
    ~/.venv/piper/bin/pip install piper-tts
    mkdir -p ~/.local/share/piper-voices
    ~/.venv/piper/bin/python -m piper.download_voices \
        --data-dir ~/.local/share/piper-voices en_US-lessac-medium

Then point the template at that copy, using absolute paths since the venv is
not on `PATH`:

    s" /home/you/.venv/piper/bin/piper --data-dir /home/you/.local/share/piper-voices
       -m en_US-lessac-medium -f %o -- %t" voice-cmd!

(one line, split here only to fit the page).

`setup.sh` builds that template for you. It looks for piper in `venv/` beside
the checkout, then `~/.venv/piper`, then `PATH`, and exports the result as
`VOICE_ENGINE_CMD` — so either install location above works. `PIPER_VOICES`
and `PIPER_VOICE` override the directory and the voice.

It **clears** the variable when the checkout it is sourced from has no
engine, rather than leaving whatever a previous checkout set. Sourcing
`setup.sh` from a second worktree is routine, and an inherited value would
quietly keep pointing at the first one's venv.

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

## Where speech goes next

`speech.fs` puts `say` at the prompt, synthesizing into memory through the
FFI and playing on a `sound.fs` channel — no file, no shell, and `talking?`
answered by the channel itself. flite suits that job: its
`flite_text_to_wave` takes two arguments and hands back a buffer, which fits
the FFI as it stands and needs no callback.

Longer term, an engine that streams while it speaks would let BasicForth
start talking before a sentence is finished. That wants a C callback into
Forth, which is the same machinery a live synthesiser needs — see
`docs/WildIdeas.md`.

## See also

- `help voice` — the rendering words
- `help samples` / `help playing` — loading and playing the WAV afterwards
- [Sound.md](Sound.md) — how the audio backend works
