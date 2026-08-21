# BasicForth — Wild Ideas

Ideas that are exciting but not yet planned. Some may be impractical,
some may become features. The point is to capture them before they're
forgotten.

---

## Standalone Executables from Forth Source

Compile a Forth application into a self-contained binary that boots
and runs without the interactive REPL.

**Option A: Run-only main** — A stripped-down `main_run.s` that loads
core.fs + app.fs, executes a single word (e.g., `snake`), and exits.
No REPL, no prompt. Usage: `./basicforth-run snake.fs snake`

**Option B: Baked-in source** — Embed .fs files into the binary via
`.incbin` so no external files are needed at runtime. The result is a
single self-contained executable: `./snake`

**Option C: AOT compilation** — Compile Forth words to native code at
build time, emitting a binary with no interpreter overhead. Essentially
a Forth cross-compiler. Much more ambitious but Option B gets 90% of
the benefit with 10% of the effort.

**Makefile integration** — A target like `make app SRC=snake.fs ENTRY=snake`
that produces a standalone binary.

## Growing the dictionary at runtime

The mmap-backed data heap (ANS MEMORY wordset: `ALLOCATE`/`FREE`/`RESIZE`) is
now implemented — see Phase 4 in TODO.md. That covers dynamic *data*: session
buffers for `SAVE`/persistence, help text, and text-processing scratch.

What's still a wild idea is the harder, separate piece: *growing the dictionary
itself* when it runs out of space (today it's one fixed `DICT_SPACE_SIZE` arena,
512 KB total / ~384 KB free after core.fs). Unlike the data heap, dictionary
space must be
**executable** (compiled words run from it), so this needs a `PROT_EXEC`
mapping — or `mprotect` to add exec, see Future/Hardening in TODO.md — plus a
movable or chained `HERE` and guard-page handling. Could be a second mmap region
that `HERE` spills into, or a relocation of the whole arena. Needs more
discussion before it's firmed up.

## Perl-style Text-Processing Library

A Forth vocabulary that makes BasicForth pleasant for the kind of quick text
munging people reach for Perl or awk for. Candidate words: line and field
splitting / joining, `fields`, `substr`, simple match / replace, and maybe a
tiny glob or regex engine. The Phase 4 file words (`read-line`, `write-line`,
`open-file`, …) are the foundation; this layers ergonomic string/text helpers
on top so a `.fs` script can slice columns, filter lines, and reformat data in
a few words.

## Interactive Help System (man / perldoc style)

**Done — docs browser:** `help` (topic listing / topic summary / per-word
entry), `tutorials`, and `apropos <keyword>` read the markdown files in
`$BASICFORTH_DOCS` from the REPL. See `docs/Help_System.md`.

**Done — per-word help (Part A):** `help <word>` prints one word's stack
effect, description, and example straight from its Language-Reference entry
(the `## word ( effect )` block). The open question resolved itself: the help
text lives in the reference pages, read on demand — no doc blocks in the `.fs`
sources, no parse-at-load store.

## Interactive Line Editor + EDIT (recall and re-edit definitions)

Today `ACCEPT` only handles backspace and echo. The dream is a mini-readline:
type a line, move the cursor with the arrow keys, insert/delete in the middle,
and recall previous input with up/down — the way you edit in a modern shell.
Built on top of that, an `EDIT <word>` that recalls a word's *last definition*
back into the editable input line so you can tweak it and resubmit, instead of
retyping it from scratch.

This pairs naturally with SAVE/persistence and `SEE`: the session log already
holds the source text of every definition (indexed by name at capture time), so
`SEE <word>` (read-only display) is the cheap first step, and `EDIT <word>` is
the same lookup piped into the line editor.

Staging:

- **Stage A — `SEE <word>`**: print the last captured source for a word.
  Read-only; lands with / just after SAVE since it reuses the log. **Done** (and
  since generalised to any word via dictionary source metadata — see above).
- **Stage B — line editor + history**: **Done.** The REPL prompt is now an
  in-line editor (left/right arrows, Ctrl-A/Ctrl-E, mid-line insert/delete) with
  an up/down command-history ring. Implemented in Forth in `core.fs` behind a
  REPL input hook, arrow keys decoded by `platform_key`. See docs/Line_Editor.md.
- **Stage C — `EDIT <word>`**: **Done, then re-done.** The first cut fed `see`'s
  source lookup into the Stage-B line editor as starting text, flattening a
  multi-line `: … ;` onto one (long) horizontally-scrolled line with `\` comments
  rewritten to `( … )`. That solved recall but lost formatting. `edit` now instead
  **spawns an external editor** (`$VISUAL`/`$EDITOR`/`vi`) on a temp file via a new
  `fork`/`exec`/`wait` platform primitive (`(system)`), then splices the fix into
  the module file and reloads on save — so the full source, multi-line layout and
  all, survives the round-trip.
  See docs/Line_Editor.md.

The **free-cursor multi-line editor** (see all the lines of a definition at once,
move the cursor freely between rows, soft-enter to split) is no longer needed for
`edit` — the external editor covers it — but remains the obvious path for an
*in-window* editor once BasicForth grows its own graphics surface (see below).
The `(system)` spawn primitive is also the foundation for reusing other Unix
tools: `sh`/`!` to run a command, `history | grep`/fzf, and friends.

## SEE for any word — source-location metadata in the dictionary

**Done (v0.6.0).** Each compiled word's header now carries an 8-byte
`[SrcId:2][Len:2][Off:4]` record stamped at compile time, plus a `.bss` source
table mapping SrcId → absolute file path. `SEE` dispatches on SrcId: file-loaded
words (`core.fs` and any `include`d file) read their byte span straight from the
source file; **primitives** report *primitive (assembly)*; a word typed at the
REPL with no file falls back to the session capture log. See docs/See_Metadata.md
and docs/See.md.

**Still far-future — decompilation.** Reconstructing source from compiled STC
when no source file exists at all (and no capture-log entry). Only worth it if we
ever want `SEE` to work with no source on disk.

## Shell-Like Words (pwd / cd / ls / cat / more)

Navigate and inspect the filesystem from the REPL, so you can hop to another
directory and list or read a file without leaving BasicForth — handy for pulling
up a source file or data file mid-session.

Most of the infrastructure already exists: `pwd` ← `platform_getcwd` (added for
SEE metadata); `ls` ← `(getdents)` / `(each-dir)` (the help browser already
walks directories); `cat` / `more` ← the file words (`open-file`, `read-file`)
plus the man/tutorial pager (`(pg-line)`, `screen-height`). The only new syscall
needed is `chdir` (80 on x86-64, 49 on ARM64) to back `cd`.

**cwd model:** `cd` does a real `chdir`, so `ls`, `cat`, and relative `include`
all agree on "where am I." `session.fs` is **pinned to the startup directory**
(captured as an absolute path at boot, the way SEE already does), so persistence
never wanders no matter where you `cd` to.

**Jumping back:**
- `cd <dir>` — change to `<dir>`.
- `cd` (no argument) — return to the **startup directory** (the session home
  base where `session.fs` lives). Note this differs from a Unix shell, where
  bare `cd` goes to `$HOME`; here the meaningful anchor is where you launched,
  not the OS home.
- `cd ~` — go to `$HOME` (optional `~` expansion, for shell muscle memory).
- `pushd` / `popd` / `dirs` — a small fixed-depth directory stack for deeper hops.

**First cut:** read-only + navigation (`pwd cd ls cat more pushd popd dirs`).
Defer filesystem *mutators* (`mkdir rm cp touch`) as a separate, riskier class —
a later decision, not part of this. Limitation: path tokens come from
`parse-word`, so paths containing spaces won't work in v1.

## Raw ALSA Audio for Appliance Mode

Sound today is SDL3 audio (`sound.fs`, docs/Sound.md) — the right call on a
desktop, where PipeWire holds the hardware PCM device open and a direct
`open("/dev/snd/pcm*")` fails with EBUSY, the same fight-the-compositor
problem that killed the DRM/KMS display backend.

But in a future **appliance / PID-1 mode** (BasicForth as the whole system, no
sound server running) the calculus flips: `/dev/snd/pcmC*D*p` is free, and a
raw ALSA-ioctl backend — `open` + `SNDRV_PCM_IOCTL_*` through the existing
`(ioctl)` gateway, mirroring how drm.fs drove the display — would give sound
with zero dependencies. The fiddly part is `snd_pcm_hw_params` (a ~600-byte
struct of masks/intervals); a `tools/sndoff.c` offset dumper would pin it
down, like drmoff.c/sdl3off.c did. Same words (`snd-open drop  tone beep snd-wait
snd-close`) backed by a different file, so programs wouldn't care.

## Programming Adventures Youtube Channel

This is not really a wild idea, but instead of having the Youtube channel
be call BlodgetProject...  I like the name "Programming Adventures" better
(at the moment). It's more descriptive of the content and less tied to my
name, which is good if I want to eventually bring in other hosts or rebrand.

It also ties in to my initial experiences of programming as a child.
I remember sitting with with Dad watching him program in BASIC on his
APPLE II, and feeling as if we where moving through computer space,
exploring.  I remember my Mom calling us for dinner, and thinking
she has no idea the adventure we are on.


## A Heap Library — tracking allocations, and finding leaks

`allocate`, `free` and `resize` are standard and belong in core. Everything
*around* them — knowing what is currently allocated, how much, and what
leaked — is not standard, and would be a library you `require` only when
hunting something: `heap-count`, `heap-bytes`, a `.heap` listing, and a
snapshot/run/compare idiom for "did that leak?".

**Asking the kernel does not work, and it is worth knowing why**, because the
idea looks sound: every `allocate` really is its own `mmap` (see the MEMORY
section of core.fs), so `/proc/self/maps` ought to list them. It does not.
The kernel **coalesces adjacent anonymous mappings with the same
permissions**, and measured here, 20 separate 4096-byte allocations added
exactly **one** entry to `/proc/self/maps`. Freeing a block in the middle of a
coalesced run *splits* it and pushes the count back **up**. So the map tells
you how much is mapped, never which blocks — and the count moves the wrong way
at the moment you would most want to trust it.

So the bookkeeping has to live with the allocator, and that is the one real
design decision:

- **A library that redefines `allocate`/`free`.** Purely additive, costs
  nothing when it is not loaded. But Forth binds at compile time, so
  `core.fs`, `wavcore.fs` and `sound.fs` keep calling the originals and their
  allocations stay invisible — backwards, since the leaks worth finding are
  the ones inside libraries.
- **Two `defer` hooks in core, given bodies by the library.** `allocate` and
  `free` call a note-taker that is a no-op until `require heap.fs` fills it
  in; then *everything* is tracked, including code compiled long before. The
  cost is one indirect call per allocate/free, which is noise beside the
  `mmap`/`munmap` syscall already in the path.

The second is the one that could find a leak in `wav-load`. It costs core two
`defer`s and a promise to keep calling them.

Either way the per-block header does the work: there is already one cell at the
mmap base holding the length, so a link field and a size are a natural
extension of something that exists.

**They are nearly free, but not free**, and the difference is worth stating
because the obvious hand-wave ("allocations are page-granular, so the extra
cells are lost in the rounding") is only true most of the time. The header
records the **unrounded** request — `1 allocate` stores 9, `4096 allocate`
stores 4104 — and it is the *kernel* that rounds the mapping up to a page. So
a block costs `ceil((u + header) / 4096)` pages, and growing the header pushes
a narrow band of sizes over the edge: today `4088 allocate` fits one page,
and with two more cells of metadata it would take two. That is a 16-byte-wide
window out of every 4096, where the cost is +100%.

The reason it does not matter much in practice is less flattering: **every
allocation already occupies at least a whole page**, so `1 allocate` costs
4 KB today. Against that, metadata is noise — and the same fact is why
core.fs already warns this heap "suits a few large buffers rather than many
tiny ones". If the heap ever grows a real allocator that packs small blocks,
the metadata question becomes a genuine one and should be re-measured rather
than assumed.

**Deliberately not done (2026-08-06/07):** `allocate!` and `free!` — words
taking a *variable's address*, so `free!` could zero the pointer it just
released and stop it dangling. Attractive, and there are three hand-written
free-then-zero sites in the tree today (`wavcore.fs`, and twice in `core.fs`).
Left out because **gforth has neither** — nor `buffer:`, nor any `alloc-to` /
`free-to` — and moving away from the Forth way to make something nicer is
usually the mistake. Also weighed and rejected: a convention of "if you
allocate, use a `variable` so `free!` applies". It trades a mistake you can
make **once**, at cleanup, for one you can make on **every use** — a forgotten
`@` writes through the variable's own cell, silently destroying the pointer
and leaking the block. The current advice stands: keep the pointer in a
`value`, and pair `free` with `0 to name` in the same breath.

## A Forth word as a C callback — and what it unlocks

`(c-callback) ( xt -- fnptr )`: hand back an address a C library can *call*,
which enters Forth and runs the xt. We can already call outward through the
FFI; this is the missing direction.

**It is not blocked on anything conceptual.** `forth_thread_tramp`
(`core.s`, and its ARM64 twin) is already exactly this: pthread invokes it as
a plain C function, and it installs a DSP, its own data and return stacks from
a context block, runs an xt through `CATCH`, and restores every callee-saved
register glibc expects. Threads shipped 2026-08-01 on that mechanism. What is
missing is a second trampoline with a *different signature*, stacks that live
across many calls rather than one per thread, and an FFI that can hand an
address out as well as take one.

**The reason to want it is a synthesiser, not fades.** Today every sound must
have a length known before it starts: `tone` renders the whole thing up front
(176 KB allocated, filled, queued, freed for two seconds at 44100). That is
fine for a beep and useless for an instrument. SDL's
`SDL_SetAudioStreamGetCallback` inverts it — SDL says roughly how many bytes
it wants, and you supply them from one small buffer reused forever. That makes
expressible:

- sound with **no end** — a held note, a drone, an engine
- **live control**: change frequency or cutoff and it lands at the next
  callback (~10 ms), not when a pre-rendered buffer runs out
- **voices**: N oscillators summed per callback instead of N pre-rendered
  streams

**Forth is fast enough by a wide margin.** Measured 2026-08-07: 441,000 frames
of square wave (ten seconds of 44.1 kHz audio) generated in 12 ms — about
**1.2 ms of CPU per second of sound, roughly 833x real time**. A 10 ms
callback needs 441 frames. Envelopes, filters and a dozen voices all fit
inside three orders of magnitude of headroom.

**SDL facts worth not rediscovering** (SDL 3.4.12 headers, read 2026-08-07):

- The Get callback fires *before* data is taken, and SDL explicitly sanctions
  calling `SDL_PutAudioStreamData` from inside it.
- It is "not required to supply exact amounts... too much or too little or
  none at all". A generator that runs late degrades to a gap, not a fault.
- `additional_amount` may be **zero**, and differs per call.
- The stream's lock **is already held** when the callback runs.
- Clearing or flushing a stream does not call it.

**For fades, prefer `SDL_AddTimer` over the audio callback** — but not for the
reason first written here. (The claim that a silent channel gets no callbacks
was wrong: the callback fires whenever data is *requested* from the stream,
and the device requests from every bound stream while it is running, which is
why the docs note it "may be asked for zero bytes".) The real objections are:

- The stream's lock **is held** during the callback, and `snd-pump` sets gains
  via `SDL_SetAudioStreamGain`. Whether that is safe on the very stream whose
  callback you are inside is **unverified** — it may be fine, it may deadlock;
  nobody has tested it.
- It is per-stream. Driving all 64 channels' fades from one arbitrarily chosen
  stream's callback is odd, and stops if that stream is closed or unbound.
- It stops entirely when the device is paused.

`SDL_AddTimer` has none of these: its own thread, no audio lock, independent of
device state, self-rearming (the callback returns the next interval, 0 to
stop), and SDL subtracts the callback's own runtime from the next wait.

**It has a shutdown race of its own, though, and it is the sharp edge of the
whole idea.** `snd-close` destroys all 64 streams and closes the device. A pump
callback already running is inside `snd-pump`, walking channels and calling
`SDL_SetAudioStreamGain` on those very streams — a use-after-free on SDL's
timer thread. And `SDL_RemoveTimer`'s documentation says only that it is safe
to call from any thread; **it does not say whether a callback already in flight
finishes first**, so that cannot be assumed. Removing the timer as the first
line of `snd-close` is necessary and not obviously sufficient.

That is a point in the plain pump thread's favour, though a smaller one than
it first looks. With `thread` and `join` the ordering is at least *ours*: clear
a stop flag, `join` the pump, then destroy the streams. But `join` is
`( t -- result status )` and **it can fail** — a bad handle, or a pthread error
— so the guarantee holds only when that status is 0. Drop it and "the pump
stopped" and "the join failed" look identical, which is the exact mistake
`tutorial Concurrency` is built around warning about.

A failed join means the pump may still be live, so `snd-close` must **not**
destroy the streams: that would be a use-after-free on a thread still walking
them. `threads.fs` already faces this and answers it, and the same answer
applies here — *"A leak is recoverable; a use-after-free is not."* So the
honest shutdown is: stop flag, join, and on a non-zero status leave the device
and its streams alone and say so, rather than tear down blind.

So neither route makes shutdown free. The difference is that with a thread the
failure is **visible and decidable**, where `SDL_RemoveTimer` gives you nothing
to test.

**But for fades alone, a callback buys nothing over a plain thread.** Both put
`snd-pump` on another thread with identical races against `ch-fade` / `ch-put`
/ `ch-stop` on the main thread. A Forth pump thread needs no new assembly at
all, since `thread` already ships. So: do fades that way if fades are the
goal, and build `(c-callback)` when the synthesiser is.

**The discipline a callback word must keep:** no `allocate`, no blocking, no
dictionary writes, and no overstaying — it runs on someone else's real-time
thread. Narrow and checkable, and the measurement above says time is not the
hard part.
