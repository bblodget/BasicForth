# Speech — Saying Text Out Loud

Speaks arbitrary text through flite, synthesized into memory and played on a
channel — no file anywhere. Load the backend first: `require speech.fs` (it
pulls in `sound.fs`, and so the FFI). With nothing open the speech words are
silent no-ops, so a machine without flite runs rather than failing.

    require speech.fs
    snd-open drop  speech-open drop
    s" hello, commander" say
    speech-ch ch-wait

At a glance:

    speech-open  ( -- ior )        bind flite and take a channel; 0 = success
    speech-ready? ( -- flag )      is speech bound right now?
    speech-why   ( -- c-addr u )   why the last speech-open or say failed
    say          ( c-addr u -- )   speak a phrase
    talking?     ( -- flag )       is speech still playing?
    speech-ch    ( -- ch )         the channel speech plays on (-1 if closed)
    speech-voice! ( lib u sym u -- )  choose a different flite voice
    say-max      ( -- n )          longest phrase say will take, 240

For recorded speech that sounds far better, see `help voice` — it renders a
phrase to a WAV with any engine on the machine, which is what a game wants.

## speech-open ( -- ior )
Bind flite, register the voice and take a channel. Returns **0 on success**,
non-zero otherwise — an `ior`, like `snd-open` and `allocate`. Ask `speech-why`
for the reason.

    speech-open drop                     \ don't care; silence is fine
    speech-open abort" no speech"        \ speech is a requirement
    speech-open if speech-why type cr then

`snd-open` must have succeeded first — speech plays on a channel, and with no
device there is none to take. Opening an **already-open** binding succeeds and
changes nothing, so a redundant call in an `on-start` hook is free.

Binding happens here rather than at `require` time deliberately: a machine with
no flite gets an `ior` it can handle, instead of an abort while loading a file.

## speech-ready? ( -- flag )
True if speech can actually speak right now: the voice is bound **and** the
channel it holds still belongs to the open device. `speech-open` is the verb;
this is the question, the same pair `snd-open` and `snd-ready?` make.

    speech-ready? if  s" ready" say  then

It goes false after `snd-close`, and stays false after a later `snd-open`
until `speech-open` is called again — closing the device destroys every
channel, and reopening builds new ones. Call `speech-open` after any
`snd-open`; it is free when nothing has changed.

## say ( c-addr u -- )
Speak a phrase. Queues the audio and returns; the sound plays in the
background, and `talking?` says whether it still is.

    s" three, two, one" say
    s" go" say                  \ queues behind the first, never over it

**`say` blocks while it synthesizes**, and that is the one thing to know about
it. Measured with `cmu_us_slt`: "Go!" 7 ms, "Dark Star, ready." 16 ms, a full
sentence 38 ms. A frame at 60 Hz is 16.7 ms. So `say` belongs at the prompt, in
a menu, or in the pause between levels — in a frame loop it drops frames, and
what a game wants there is `help voice`, whose phrases are rendered ahead of
time and cost nothing to play.

A phrase longer than `say-max` is refused, with the reason in `speech-why`. A
no-op if speech isn't open, exactly as `tone` is with no device.

## talking? ( -- flag )
True while speech is still playing. False when the channel has drained, and
false when speech was never opened.

    begin talking? while  snd-pump  16 ms  repeat     \ let a phrase finish

To block instead of poll, `speech-ch ch-wait` — see `help channels`.

## speech-ch ( -- ch )
The channel speech plays on, or `-1` before `speech-open` succeeds. It is taken
with `next-ch` at open time and kept for the session, which buys two things: a
channel is a sequential queue, so successive `say`s wait for each other rather
than talking over themselves, and because it is speech's own channel, a phrase
never queues up behind a sound effect.

It is never channel 0 — that belongs to `tone`.

A `snd-close` destroys it, so `speech-open` takes a fresh one after the device
comes back. That re-take is not cosmetic: reopening starts handing the same
channel numbers out again, so a kept number would collide with whatever
`next-ch` gives the next caller, and speech would share a queue with it.

## speech-voice! ( lib u sym u -- )
Choose the flite voice: its library and the symbol that registers it. Call
before `speech-open`.

    s" libflite_cmu_us_rms.so.1" s" register_cmu_us_rms" speech-voice!

Two strings rather than a short name because the two do not follow one pattern
— the `indic` and `grapheme` voices are not named `cmu_us_<something>`, so
deriving the symbol would break for exactly the voices someone would go looking
for. Both are copied, so a caller's `s"` buffer can be reused straight after.

The `.so.1` matters. A machine with the runtime package has `libflite.so.1` and
no `libflite.so`; the bare name belongs to the `-dev` package, so naming the
soname is what makes this work on a plain install.

The default is `libflite_cmu_us_slt.so.1` / `register_cmu_us_slt`.

## say-max ( -- n )
The longest phrase `say` will take, 240 characters. The FFI copies a string
into one shared scratch buffer to NUL-terminate it, and that buffer is 256
bytes; `say` checks first so an over-long phrase reports about the phrase
rather than about a buffer the caller never mentioned. Say it in sentences —
which is better delivery anyway.

## speech-why ( -- c-addr u )
Why the last `speech-open` or `say` failed; empty after a successful one.

    speech-open if  ." no speech: " speech-why type cr  then

## See Also

- `help voice` — rendering a phrase to a WAV, for anything inside a game loop.
- `help channels` — `ch-wait`, `ch-vol!` and the channel `speech-ch` names.
- `help sound` — `snd-open`, which must succeed first.
- `help ffi` — the calling mechanism underneath.
