# Dev Notes

Notes about the **development environment** — the machines, boards and links
we build and test BasicForth on. This is not user documentation: nothing here
describes the language, and none of it is needed to use BasicForth.

These pages are deliberately outside the help system. `BASICFORTH_DOCS` names
the sections that reach `help` — `docs/Language-Reference`, `docs/Tutorial` and
`docs/Guides` (see `setup.sh` for the current list) — and `docs/dev-notes` is
not among them, so files here never appear in `help`, `apropos` or `tutorials`,
and can be as long and as specific-to-our-hardware as they need to be.

Where a page records addresses, hostnames or MAC addresses, they are **our**
values, written down as a worked example. Each page also says how to derive the
equivalent for a different machine, because a value measured on one host is the
usual way these notes go stale.

- [ARM64-Hardware-Testing.md](ARM64-Hardware-Testing.md) — running the test
  suites on real ARM64 hardware instead of qemu
- [Direct-Ethernet-Link.md](Direct-Ethernet-Link.md) — a private wired link to
  a test board, without disturbing wifi or other setups
