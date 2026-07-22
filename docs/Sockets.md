# Sockets — Design Notes

Status: **design only, nothing implemented** (2026-07-22). TCP socket words
for BasicForth: the plumbing under the chat client and BBS
(docs/Community.md), and eventually anything else that talks to a network.

## Shape

Sockets are just file descriptors, and socket calls are just syscalls —
this is platform-layer work in the established pattern (`platform_linux.s`,
both arches, raw syscalls, no libc). Two happy consequences:

- **`read-file` / `write-file` / `close-file` already work on a connected
  socket fd.** The new words are only the ones files don't have: creating,
  connecting, listening, and polling. (`recv`/`send` with flags can wait
  until a real need appears.)
- The syscall list is short: `socket`, `connect`, `bind`, `listen`,
  `accept`, `poll`, `fcntl` (for O_NONBLOCK), and optionally `setsockopt`
  (SO_REUSEADDR for the BBS restart case).

## Design rule: non-blocking + poll from day one

The chat client's REPL integration (prompt peek — see docs/Community.md)
works with **zero concurrency** if nothing ever blocks: poll the fd, drain
what's ready, return to the prompt. So the library should make the
non-blocking path the paved road, not an option bolted on later. A
blocking convenience layer can sit on top for scripts.

Network games are the second client of the same design (see Community.md):
a game loop adds one `fd-poll` with a 0 ms timeout per frame — drain
remote input, simulate, draw — no threads, same pattern as chat v1.

Candidate word set (names unsettled):

    tcp-connect  ( ip-addr port -- fd ior )     socket+connect, IPv4
    tcp-listen   ( port backlog -- fd ior )     socket+bind+listen, REUSEADDR
    tcp-accept   ( fd -- fd' ior )              accept one connection
    fd-nonblock  ( fd -- )                      fcntl O_NONBLOCK
    fd-poll      ( fd events ms -- revents )    poll one fd with timeout
    ip           ( "a.b.c.d" -- ip-addr )       parse a dotted quad

plus the byte-order and sockaddr plumbing as internal `(words)` — a
`sockaddr_in` is 16 bytes built in a scratch buffer; `htons` is a swap.

## The sneaky hard part: DNS

Raw syscalls give no name resolution — `getaddrinfo` is a libc service,
not a syscall. Options, in order of appearing effort:

1. **v1: numeric IPs only.** `ip` parses a dotted quad. Fine for a hobby
   BBS and for testing; annoying for IRC.
2. **Shell out**: `getent hosts irc.libera.chat` via the existing
   shellutil.fs `(cmd-line1)` plumbing — one line of Forth, uses the
   system resolver correctly, and fits the `sh`-escape-hatch model.
   Probably the right v1.5.
3. **FFI `getaddrinfo`**: correct and self-contained, but the result is a
   linked list of C structs to walk — real FFI struct work. Later, if ever.

## REPL integration point

The prompt-peek experience needs one small core hook: a deferred word the
REPL calls before printing ` ok` (name open — `prompt-hook`?), no-op by
default; chat.fs `is`-es it to a poll-and-report word. Deliberately
generic — other libraries get the same hook for free. Needs the usual
care: the hook must be fast, must not error (wrap in `catch`), and must
not recurse into the interpreter.

## Testing

- **`socketpair`/UNIX-domain sockets** give a connected fd pair with no
  network at all — ideal for deterministic integration tests of the
  read/write/poll words.
- Loopback TCP (`tcp-listen` + `tcp-connect` on 127.0.0.1) tests the full
  stack inside one test process — the BBS accept loop and the client words
  cover each other.
- The suite must never touch the real network (CI, qemu).

## Open questions

- IPv6: punt in v1 (AF_INET only), keep the word set shape neutral so an
  `ip6` variant can arrive without renames.
- TLS: **never build it.** Plaintext to our own server; an FFI shim to a
  TLS library later if a public IRC network demands it (docs/Community.md).
- Partial writes on non-blocking sockets: v1 can expose `write-file`'s ior
  and let the caller retry; a buffered `net-type` convenience can come with
  the chat client.
- Word names above are placeholders — settle them against the existing
  file-word vocabulary before implementing.
