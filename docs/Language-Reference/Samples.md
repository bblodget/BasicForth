# Samples — Loading WAV Files

`wavcore.fs` reads a `.wav` file into memory and tells you what is in it. It
is pure Forth — no FFI, no audio device — so it works anywhere BasicForth
runs, and a program can inspect a sound without opening the speakers.

    require wavcore.fs
    s" blip.wav" wav-load        ( -- sample | 0 )
    dup wav-frames .             \ 8820
    dup wav-rate .               \ 44100
    wav-free

A **sample** is a handle. Ask it questions; free it when done. On failure
`wav-load` returns `0` and `wav-why` says what was wrong, so a program can
carry on without its sound effect instead of aborting.

At a glance:

    wav-load        ( c-addr u -- sample|0 )  read a .wav file
    wav-why         ( -- c-addr u )           why the last load failed
    wav-free        ( sample -- )             release it
    wav-frames      ( sample -- n )           length in sample frames
    wav-rate        ( sample -- n )           frames per second
    wav-chans       ( sample -- n )           1 mono, 2 stereo
    wav-bytes       ( sample -- u )           size of the audio in bytes
    wav-data        ( sample -- c-addr )      the raw 16-bit samples
    wav-loop?       ( sample -- flag )        does it carry loop points?
    wav-loop-start  ( sample -- n )           loop start in frames, or -1
    wav-loop-end    ( sample -- n )           loop end (inclusive), or -1

## wav-load ( c-addr u -- sample|0 )
Read a `.wav` file and return a sample handle, or `0` if it could not be used.

Accepts **uncompressed 16-bit PCM, mono or stereo** — what every tool writes
by default, and the format that needs no conversion before playing. Anything
else is refused rather than mis-decoded into noise; ask `wav-why` which it
was.

Chunks are walked properly, so a file with `LIST` or `fact` metadata before
its audio loads fine. (Audio does *not* reliably begin at byte 44 — that is
only true of the simplest files.)

    s" step.wav" wav-load ?dup 0= if  wav-why type cr  then

## wav-why ( -- c-addr u )
The reason the last `wav-load` returned 0, as a string. Each refusal names
itself:

    wav: cannot read the file
    wav: not a RIFF file
    wav: not uncompressed PCM
    wav: need 16-bit samples
    wav: need mono or stereo
    wav: no fmt chunk
    wav: no data chunk
    wav: a chunk runs past the end of the file

## wav-free ( sample -- )
Release a sample. Safe on `0`, so an unchecked failed load can be freed
without a guard. A sample holds the whole file image, so free the ones you
stop using.

## wav-frames ( sample -- n )
Length in **frames**. One frame is one instant of sound: one sample for mono,
a left/right pair for stereo. Divide by `wav-rate` for seconds.

    dup wav-frames  over wav-rate  /  . ." seconds"

## wav-rate ( sample -- n )
Frames per second as recorded in the file — commonly 44100, 22050, or 16000.
This is what the file *says*; it does not resample anything.

## wav-chans ( sample -- n )
`1` for mono, `2` for stereo.

## wav-bytes ( sample -- u )
Size of the audio in bytes: `wav-frames * wav-chans * 2`. A partial trailing
frame is trimmed at load, so this is always a whole number of frames.

## wav-data ( sample -- c-addr )
Address of the raw audio: signed 16-bit little-endian samples, stereo
interleaved left-then-right. The bytes live inside the loaded file image, so
they stay valid until `wav-free`.

Read them like any memory — `w@` fetches one, zero-extended, so sign-extend
by hand if you care about the value:

    dup wav-data w@  dup 32767 > if 65536 - then  .

## wav-loop? ( sample -- flag )
True if the file carries usable loop points, from its `smpl` chunk. Most
sound effects have none; sustained sounds meant to be held often do.

A loop whose start is not before its end, or whose end is not inside the
audio, is **discarded** rather than trusted, and both endpoints then read back
as `-1`. So a true answer means the range is real and safe to play, and a
false one never leaves the refused numbers lying around.

## wav-loop-start ( sample -- n )
## wav-loop-end ( sample -- n )
The loop range in frames. **Both are `-1` when there is no usable loop** —
whether the file had no `smpl` chunk at all, or had one that was refused. A
rejected end point is never reported back, so you cannot accidentally use the
out-of-range value that got the loop discarded in the first place.

**The end point is inclusive** — the `smpl` chunk defines it as the last frame
that will be played, so a loop repeats `wav-loop-start` through
`wav-loop-end` and back. On an n-frame sample the largest legal end is
`n-1`; a file claiming `n` is refused, because playing it would read one
frame past the audio.

    dup wav-loop-end over wav-loop-start - 1+  . ." frames in the loop"

## Notes

The file is read in one piece and kept, with the sample pointing into that
image rather than copying the audio out of it — so a load costs one read and
the memory of the file, and `wav-free` releases both.

## See Also

- `help channels` — playing sounds, and playing several at once.
- `help sound` — opening the audio device, and tones.
- `help files` — the file words underneath.
