# Sound — One at a Time, or All at Once

Making a noise is easy. Making two noises *at the same time* is the whole
subject, and it is the one thing a single stream of Forth words cannot express
on its own. This lesson builds up to playing several sounds together, then
builds a sound from nothing and plays that. About twenty minutes, typing as
you go.

This is a *lesson*: short steps, one idea each. After each step you're back at
the prompt to try it. Type `next` to continue, `back` to re-read, and
`end-tutorial` to stop (your definitions stay).

Type `next` to begin.

## A device to play through

    require wav.fs
    snd-open abort" no audio device"

`require` loads the sound words — they are not in the startup image. `snd-open`
takes the audio device and holds it until you give it back.

It hands back an **ior**: 0 if it worked, non-zero if this machine has no
usable audio. `abort"` stops on a non-zero one, which is how you say *sound is
a requirement*. A program that would rather play on in silence writes
`snd-open drop` instead — every sound word then does nothing, and nothing
fails.

    beep snd-wait

An 880 Hz blip, 60 milliseconds long. `snd-wait` waits until every channel has
fallen silent; we will need it constantly, and the next step shows why.

## One after another

`tone` takes a frequency and a duration in milliseconds:

    : two-tones  440 300 tone  660 300 tone  snd-wait ;
    time two-tones

About **0.65 s** — the two tones, one after the other, plus a moment for the
last of it to leave the speaker. Note what did the waiting: `snd-wait`. `tone`
itself does not, which is the surprise in the next step.

## What tone actually does

Keep this on **one line**, so you can see exactly when the message appears:

    440 2000 tone  ." prompt is already back" cr

Straight back, with two seconds of tone still to come. `tone` **queues** audio
and leaves; it never waits for anything.

Now the same line with `snd-wait` dropped into the middle of it:

    snd-wait  440 2000 tone  snd-wait  ." ...that took two seconds" cr

Same tone, same words, and this time you wait for it. `snd-wait` is the only
difference, and `snd-wait` is the only part that ever waits.

So two `tone`s in a row do not overlap — they queue up behind each other and
play in turn. That is what the 0.65 s was.

## How loud is a tone?

`tone` builds a square wave, and `tone-amp` is how **tall** it is:

    tone-amp .                          \ 8000
    tone-amp  2000 to tone-amp  440 400 tone  snd-wait  to tone-amp

Quieter. That line borrows `tone-amp`, plays with the borrowed value, and hands
your original back — the leading `tone-amp` pushes it, the closing `to tone-amp`
stores it again.

A 16-bit sample holds up to 32767, so the default 8000 is about a quarter of
full swing. That is deliberate: a square wave at full scale is punishing,
because unlike a sine — which passes through every value on its way — a square
spends *all* its time at the two extremes.

It is named for `tone` the way `tone-ch` is, and it is **not** a volume. A
volume turns up later, once channels exist — a different number with a
different range, applied at a different moment. The difference to hold on to:
`tone-amp` is what gets *written into* the samples.

## The same two tones, together

    : two-at-once  440 300 0 tone-on  660 300 1 tone-on  snd-wait ;
    time two-at-once

About **0.35 s** — one tone's worth. Both played, and they played *together*.

The only difference is the extra number: `tone-on` takes a **channel**. Sounds
queued on the same channel wait their turn; sounds on different channels mix.

## What a channel is

A channel is one queue of audio. You get sixty-four:

    snd-channels .     \ 64

Queue a tone and ask about it **on the same line** — a third of a second is
gone long before you finish typing the next one:

    440 300 7 tone-on  7 ch-queued .  7 ch-playing? .    \ a big number, and -1
    snd-wait  7 ch-playing? .                             \ 0

Three tenths of a second of 16-bit samples at 44100 a second is 26460 bytes, so
that is roughly what you will see — **a little less, and a different little
less each time**. The device starts draining the channel the moment the audio
is queued, and how fast depends on the machine and on what it is doing.

Do not read an exact figure there. What matters is that it is greater than zero
— sound is still waiting — and that `ch-playing?` says so too. Type `next`.

## What is special about channel zero

    tone-ch .          \ 0

`tone` and `beep` are `tone-on` with the channel filled in, and the channel
they fill in is 0. That is the whole reason two `tone`s queue instead of
mixing.

Channel 0 is an ordinary channel in everything it can *do* — queue it, set its
volume, stop it, like any other:

    440 200 tone-ch tone-on  snd-wait

What is special is who owns it. `tone-ch` is a **constant**, not a `value`, so
`tone` cannot be pointed elsewhere:

    \ 9 to tone-ch     \ tone-ch: not a value or deferred word

Channel 0 is reserved for your tones, and the next step shows what that buys.

## Letting the system choose

Naming channels yourself gets old once sounds come and go. `next-ch` hands
you one:

    next-ch .        \ 1
    next-ch .        \ 2

It works round-robin through the channels, skipping any that are still
playing, and when every channel is busy it takes the one that has been going
longest — a new sound cuts off the oldest rather than being dropped. Which
numbers you get depends on what has been playing, so don't lean on them; keep
the channel it returns.

Nothing is *allocated* here, despite what asking for a channel might suggest —
the channels are a fixed set, and there is nothing to give back. A channel
returns to the rotation on its own once it falls silent.

And it never hands you channel 0 — that is what reserving it was for. However
many effects come and go, none can land on your tones and cut them short. Ask
a hundred times and keep the smallest answer:

    : lowest ( -- ch )  snd-channels  99 0 do  next-ch min  loop ;
    lowest .           \ 1 — never 0, however hard you push

## Volume

Here is the other one. `tone-amp` was how tall the wave is; this is how loud
the **channel** plays whatever it is handed — anyone's audio, not just `tone`'s.
Each channel has its own, and `snd-unity` is full:

    snd-unity .        \ 256    (against tone-amp's ceiling of 32767)

Two words, so you can hear this rather than read about it:

    : loud  snd-unity 3 ch-vol!  440 400 3 tone-on ;
    : soft  64 3 ch-vol!         440 400 3 tone-on ;
    loud snd-wait soft snd-wait

The same tone twice, at a quarter of the volume the second time. Type `next`.

## Volume catches what is already queued

Now run them back to back with no wait in between — one line, because
together they are less than a second:

    loud soft  3 ch-queued 0> .  3 ch-vol@ .  snd-wait    \ -1 64

**Both come out quiet**, including the one queued at full volume. There is
still audio waiting, and the gain about to be applied to it is 64.

The question is "is anything still queued?" rather than "how many bytes?"
because the audio thread is draining the channel while you type — the count
falls as you look at it, and how fast depends on the machine.

`ch-vol!` does not scale samples on the way in. SDL applies the channel's gain
as it pulls audio *out*, so changing it catches everything still waiting — no
copying, no recalculating, and nothing to undo. That same property is what
lets a fade work on sound that was queued before the fade was asked for.

## Stopping

Timing only means something if the machine does it. Typed line by line, a
`200 ms` between two lines is lost in how long you take to read the second —
so from here on, anything with a clock in it goes inside a word:

    : cut  440 3000 5 tone-on  200 ms  5 ch-stop ;
    cut
    5 ch-playing? .    \ 0

Three seconds queued, silenced after a fifth of one. `ch-stop` cuts the
waveform wherever it happens to be, which can click. Type `next`.

## Fading

`ch-fade` says *be silent 800 ms from now, gently*. Queue a two-second tone,
ask for the fade, and look half a second later:

    : fading  6 ch-stop  440 2000 6 tone-on  800 6 ch-fade  500 ms
              6 ch-playing? . ;
    fading             \ -1 — still going, and still at full volume

Five eighths of the way through the fade, nothing has faded. The next step
says why. (Leave it running; `snd-stop` at the end tidies up.)

It opens with `6 ch-stop` so it starts from silence however often you run it —
a channel is a queue, and a word that queues without clearing first measures
whatever the last one left behind.

## Fades need a pump

SDL pulls audio on a thread of its own, and a Forth word cannot be handed to it
as a callback. So the only clock a fade has is **your loop**:

    : fade-out  6 ch-stop  440 2000 6 tone-on  800 6 ch-fade  500 ms
            ms@  begin snd-pump 6 ch-playing? while 20 ms repeat  ms@ swap - ;
    fade-out .         \ about 300

`snd-pump` moves every running fade along. Call it once a frame — in a game,
next to the redraw. Nothing else moves a fade.

About 300, not 800: `ch-fade` set a **deadline**, and 500 ms of it went by
before the first `snd-pump`. The fade did not pause waiting to be noticed; it
simply was not being applied. Stop pumping mid-fade and the sound holds its
volume until you resume, then jumps to where the clock says it should be.

## Building a sound from nothing

Enough of tones. A channel will take any samples you give it, so let's make
some — a fifth of a second at 22050 samples a second:

    22050 constant HZ
    HZ 5 / constant FRAMES               \ a fifth of a second
    FRAMES . FRAMES 2* .                 \ 4410 frames, 8820 bytes
    FRAMES 2* allocate abort" out of memory" value wave

A **frame** is one instant of sound; mono, so one 16-bit sample each, which is
why the byte count is `FRAMES 2*`. `allocate` returns an address **and** an
error code, and `abort"` takes the code so the address reaches `value`.

22050 is half the 44100 the device runs at, so SDL still has to resample what
we build.

## A square wave

Sixteen-bit samples are signed — anywhere from −32768 to 32767. Swing between
two values and you have the crudest possible tone.

    : square ( freq -- )
        wave 0= if drop exit then          \ nothing to write into
        HZ swap 2* /                       \ samples per half cycle
        FRAMES 0 do
            dup i swap / 1 and if tone-amp negate else tone-amp then
            wave i 2* + w!
        loop drop ;

    440 square
    tone-amp .  wave w@ .   \ 8000 8000
    HZ 440 2* / .           \ 25 samples per half cycle

Why *half* a cycle, rather than a whole one? Because a half cycle is how long
the level stays put. At 22050 a 440 Hz cycle is about 50 samples — 25 of them
at one value, 25 at the other — so the flat stretch, which is what the loop
actually needs to know, is half the cycle. That is all the `2*` is doing.

`i swap /` then counts how many flat stretches in, and `1 and` asks whether
that count is odd, so the value changes every 25 samples.

Those 25 samples are where the pitch really comes from, and 25 is a rounded
number: 22050 / 880 is 25.06. So you get 22050 / 50 = **441 Hz**, not 440 —
four hundredths of a semitone sharp, which nobody can hear. Pick the rate
badly and it matters: at 11025 the same word gives 459 Hz, three quarters of a
semitone out and plainly wrong to an ear. A square wave can only change sign
*between* samples, so its pitch comes in steps, and the steps get coarser as
the rate drops.

A word that writes through a pointer should check it first. That first line
looks like nothing now; it earns its keep when the buffer is freed, at the end
of the lesson.

## You have just rewritten tone

That `if tone-amp negate else tone-amp then` is not merely *similar* to what
`tone` does — it is the same line, out of `sound.fs`. Turn the amplitude down
and both follow, because there is only one of them:

    tone-amp  2000 to tone-amp  440 square  440 400 tone  snd-wait
    to tone-amp  440 square

Your hand-built wave and the built-in tone got quieter together. The trailing
`to tone-amp` hands your original back, and the last `440 square` refills the
buffer at it, so the rest of the lesson sounds the way it would have.

`tone` is this word plus a buffer and a `ch-put`, and nothing in it was hidden
from you — type `see tone-on` and read it. Allocate a buffer, fill it with
`±tone-amp`, hand it to the channel, free it: the same four moves you are
making by hand.

Look at the last two lines of it. It frees the buffer immediately *after* the
`ch-put`, which it can only do because **`ch-put` copies**. The samples belong
to the channel from that moment; yours were just the stencil.

## Handing it to a channel

A channel has to be told what is coming: the format, how many channels of
audio in the samples themselves, and the rate.

    AUDIO_S16LE 1 HZ 4 ch-format!
    wave FRAMES 2* 4 ch-put  snd-wait

Signed 16-bit, mono, 22050 a second. `ch-put` queues the bytes as they are —
no scaling, no conversion — which is the machinery `tone` and `beep` have been
using all along. It copies them into the channel, so `wave` is yours again as
soon as the line finishes; we keep it only because `square` refills it.

## A .wav file is those samples, labelled

A WAV file is 44 bytes saying what the samples are, then the samples. We have
the samples; let's put a label on them.

    FRAMES 2* constant BYTES
    BYTES 44 + allocate abort" out of memory" value image
    image 44 + value audio

`image` holds the whole file, `audio` points past the header to where the
samples go. Type `next`.

## Filling in the header

    : riff ( -- )
        image 0= wave 0= or if exit then
        s" RIFF" image      swap move   BYTES 36 + image  4 + l!
        s" WAVE" image  8 + swap move
        s" fmt " image 12 + swap move   16 image 16 + l!
        1  image 20 + w!    1 image 22 + w!       \ PCM, one channel
        HZ image 24 + l!    HZ 2* image 28 + l!   \ rate, bytes per second
        2  image 32 + w!    16 image 34 + w!      \ bytes per frame, bits
        s" data" image 36 + swap move   BYTES image 40 + l!
        wave audio BYTES move ;                   \ samples after the header

Four-character tags, then numbers little-endian. Every field is either a name
or a size.

**RIFF** is Resource Interchange File Format — a container, not an audio
format, and nothing to do with guitars. A WAV file is "a RIFF whose contents
are WAVE"; the same container carries AVI and WebP. Everything inside it is a
chunk: a four-byte tag, a four-byte length, then that many bytes. That is why
`fmt ` has a trailing space — a tag is *exactly* four characters.

It is also why WAV is little-endian. RIFF is Microsoft's little-endian rework
of Electronic Arts' big-endian IFF; Apple took the other branch, which is what
AIFF is. Type `next`.

## The order move wants

`move` takes ( source destination count ), and `s" RIFF"` leaves an address
*and* a length — so `image swap` puts them in that order, and the length
doubles as the count. Get those two backwards and you copy *from* address 4,
which ends the session rather than the line.

Run it, and ask the header what it thinks it holds:

    riff
    image 4 + l@ .     \ 8856  — the size RIFF claims

That is 8820 bytes of samples plus 36, which is everything after that field.

## Reading it back

    image BYTES 44 + wav-from value blip
    blip wav-frames .  \ 4410
    blip wav-rate .    \ 22050
    blip wav-ms .      \ 200

`wav-from` decodes a WAV **already in memory** — it never saw a file. `wav-load`
is the same decoder pointed at one:

    \ s" blip.wav" wav-load value blip

Either way you get a sample: an opaque thing that knows its own format.

## Playing a sample

    blip wav-play .  snd-wait    \ a channel number

`wav-play` picks a channel with `next-ch`, tells it the sample's format, and
queues it. To choose the channel yourself, `wav-play-on`:

    blip 10 wav-play-on  blip 11 wav-play-on  snd-wait

One sample, two channels, playing together — and `blip` itself was not
duplicated to manage it; SDL took a copy of the bytes into each channel. Both
plays go on one line for the same reason as before: the sample is a fifth of a
second, so on two lines the first would be over before you started the second.

## Four names, three allocations

Before handing anything back, count what we are holding. `blip`, `wave` and
`image` each came from an allocation. `audio` did not:

    audio image - .    \ 44

`see audio` says where it came from: `image 44 +`, a pointer *into* that block,
past the header. So it must **not** be freed — no block starts there, and
handing `free` an interior address is a different question from handing it a
null one. `free` reads a block's length from the cell just before the address
it is given; 44 bytes into a WAV that is header bytes, and it would unmap
whatever number they happen to spell.

It does still have to be **zeroed**. Type `next`.

## Giving it all back

Three things were allocated along the way — `blip`, `wave` and `image` — and
all three are ours to release:

    blip wav-free   0 to blip
    snd-stop
    snd-close
    wave  free drop   0 to wave
    image free drop   0 to image   0 to audio

`wav-free` releases the sample, `snd-stop` clears every channel, and
`snd-close` hands back the device — after which the sound words go quiet
rather than complaining, so a program that closes early still runs.

`wave` and `image` came from `allocate`, so they go back with `free`, which
hands back a status — 0 for success — that we drop. Freeing `image` cannot hurt
`blip`: `wav-from` **copied** the bytes it decoded, precisely so the sample owns
its own memory and does not hold you to a buffer you might reuse.

## Why zero them

    audio .            \ 0 — and it was never freed, only forgotten

Freeing memory does not remove the word that names it. `square` and `riff` are
still here — this lesson leaves your definitions behind — and `wave` would
still hold the address of memory that now belongs to somebody else.

That is a **dangling pointer**, and writing through one is the worst kind of
bug: it works, nothing complains, and something unrelated breaks later.
`0 to wave` is the other half of `free` — and `audio`, which was never freed at
all, still needed it, because it pointed into a block that was. Type `next`.

## Which is what square was checking for

    440 square         \ does nothing at all now
    riff               \ likewise

That guard on `square`'s first line looked like decoration when you typed it.
It is the reason those two lines are harmless instead of writing 4410 samples
through a null pointer and taking the session with them.

The same zeroing makes the whole cleanup safe to repeat. Run it again:

    blip wav-free   wave free drop   image free drop
    wave free .        \ 0  — freeing nothing is not an error

Nothing breaks, because there is nothing left to release. Both words take a 0
and do nothing with it, which is deliberate: freeing a *live* block twice hands
memory back that something else may already own, and the habit that prevents
that is exactly this one — free, then zero. A contract that complained here
would be punishing the thing you want people to do.

## When your sounds become a program

Everything so far opened the device by hand. A program you `save` and come back
to should do it for you:

    : on-start  snd-open abort" no audio device" ;
    : on-stop   snd-close ;
    snd-ready? .       \ 0 — defining them runs nothing yet

The module lifecycle calls them: `on-start` once the file has been read,
`on-stop` **before** a reload rolls the dictionary back. That second one is the
half `keep` cannot cover — an open device is a resource your module is
*holding*, and a rollback zeroes the handle while the device stays open with
nothing left to reach it.

`on-start` may run twice (editing a dirty module reloads it twice), which is
safe: opening an already-open device does nothing. Type `next`.

## Where to go next

Try the hooks for real, outside the tutorial: `save blip.fs`, leave with `bye`,
then start a session **on** that file — `basicforth blip.fs` — and the device
is open before you type anything. (Plain `require` does not run `on-start`;
starting a session on the file does, and so does `load`.)

Load a real file with `wav-load` — the decoder takes 8, 16, 24 and 32-bit
samples, and 32-bit float, mono or stereo, at any rate. A sound recorded at
48000 and one made at 8000 can play at the same moment; SDL converts each.

- `help channels` — `tone-on`, `next-ch`, volume, stopping, fading
- `help samples` — loading and asking a sample what it holds
- `help playing` — `wav-play` and friends
- `tutorial Modules` — `save`, `reload`, and the lifecycle hooks in full
- `docs/Sound.md` — how the device, the channels and the samples fit together

Type `end-tutorial` to finish. Your definitions stay.
