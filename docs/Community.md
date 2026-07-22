# Community — Design Notes

Status: **ideas and direction, nothing built** (2026-07-22). How BasicForth
grows a community, and what we build to make that happen. Companion pieces:
docs/Package_Registry.md (sharing), docs/Sockets.md and docs/Threading.md
(the plumbing under the fun parts).

The model is the one that worked in the 1980s: the community lives *inside*
the tool. You dialed the BBS from the same machine you coded on; you typed
in programs from the magazine and mailed yours back. BasicForth can tell
that story in modern form.

## Three Pillars

1. **A place to share** — the package registry (docs/Package_Registry.md).
   `save invaders` → `publish invaders` → someone else `install invaders`.
   Your saved program *is* the thing you share, one file, like a magazine
   listing.
2. **A place to talk** — a chat client that runs inside the REPL (below).
3. **A reason to return** — the lesson arc. Interactive tutorials that take
   someone from `2 2 + .` to publishing their own game are genuinely rare
   in hobby languages; "learn Forth by building Snake, then post your game
   to the board" is a complete loop no other Forth offers.

The "introducing BasicForth" video seeds all three; the loop keeps people.
(Deliberately pre-1.0 — "it's young, it's moving fast, come play" is the
right story for the audience we want. 1.0 is a lock-in promise for later.)

## The Chat Client

A messaging client written in BasicForth, usable from the REPL — check the
channel between compiles. Two candidate shapes, not mutually exclusive:

### Near term: IRC

IRC is a line-based plaintext protocol from 1988 — `PRIVMSG #basicforth
:hello` — implementable with `s"`, `compare`, and `/string`. Parsing it is
roughly Strings-lesson difficulty, and a minimal client is maybe 150 lines:
connect, answer `PING` with `PONG`, print `PRIVMSG`s, send lines. Live
networks (e.g. Libera.Chat) mean `#basicforth` has real people in it the
week the client works.

The REPL experience, in escalating versions (see docs/Threading.md for why
v1 needs no threads at all):

- **v1, pull**: a `msgs` word drains the socket (non-blocking) when you
  ask. Very BBS — you check your mail.
- **v2, prompt peek**: the REPL polls the socket each time it prints
  ` ok`, so `*** 2 new messages in #basicforth` appears between commands
  without ever interrupting typing.
- **v3, live**: messages interleave while you type — needs poll in the key
  loop or a reader thread. Defer until threading lands.

Caveat: big IRC networks increasingly require TLS. Don't build TLS. Either
target a plaintext-friendly server (or our own — below), or add a small
FFI shim to a TLS library later if a public network demands it.

### Destination: a BasicForth BBS

The most BasicForth answer: the community server is *itself written in
BasicForth*, speaking plain TCP — message boards, who's-online, maybe door
games (we have Snake). It owns the whole retro story, and it can **merge
with the registry**: browse packages, post a message, `publish` your game
to the board — one community home, all in Forth. The server side is an
accept loop plus the same string words the client uses (sockets design
covers `bind`/`listen`/`accept`).

Not exclusive with IRC: IRC first for real humans fast, the BBS later as
the destination.

## Network Games

Sockets unlock multiplayer, and the retro lineage is exact: two-player
games over a null-modem cable were peak 1980s, and TCP is a very long
null-modem cable. The game loop already has the right shape — the
`sdl-fps` timer loop gains one `fd-poll` with a 0 ms timeout per frame:
drain remote input, simulate, draw. No threads, same as chat v1.

The model that keeps it Forth-simple is **lockstep**: don't send world
state, send *inputs*. Both sides run the same deterministic simulation and
exchange only keystrokes — a byte per frame or per turn (the Doom LAN
model). BasicForth games are already deterministic little state machines.

The escalation ladder, each step fun on its own:

1. **Shared high-score server** — one `tcp-connect`, send a line; could be
   the BBS's first real service.
2. **Turn-based over TCP** — checkers, battleship; latency stops mattering.
3. **Real-time lockstep on a LAN** — two-player tron is the classic first
   network game for a reason: two inputs, one byte per turn.
4. **BBS-hosted lobbies** — door games that are actually networked.

And it feeds the loop: a Network-Games lesson ("build two-player tron,
then play it with someone from #basicforth") plus network games shipping
as ordinary packages. Caveat, so we stay grounded: real-time over the
*internet* means latency hiding, prediction, and drop handling — a
genuinely deep field. LAN + turn-based covers the joy without climbing
that cliff.

## Principles

- **Everything demo-able from the prompt.** `install chat`, `run chat`,
  `/join #basicforth` — each community feature should be a video moment.
- **The community lives inside the tool.** Prefer in-REPL experiences over
  "go to this website".
- **Single-file sharing.** The magazine-listing model: one `.fs` you can
  read top to bottom (see Package_Registry.md).
- **Curation over gatekeeping.** PRs into the main registry, promotion from
  personal registries — review as the trust layer, not accounts and locks.

## Sequencing

1. **sockets.fs** (docs/Sockets.md) — unblocks everything; no concurrency
   needed thanks to non-blocking + `poll`.
2. **Chat v1** — pull/prompt-peek, single-threaded, proves the fun.
3. **Registry stages** (docs/Package_Registry.md) — `needs-cmd`/`needs-lib`
   and `deps` are already unblocked by shellutil.fs.
4. **Threading** (docs/Threading.md) — its own arc; chat v3, audio feeders,
   robot control loops.
5. **BBS** — when the pieces above make it a weekend of composition rather
   than a month of plumbing.
