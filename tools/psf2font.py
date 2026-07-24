#!/usr/bin/env python3
# psf2font.py - Convert a PSF bitmap console font to src/forth/font-terminus-8x16.fs
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Reads an 8-wide PSF font (PSF1 or PSF2) and emits the font
# source: a 256-entry
# CP437 glyph table, 8x16, one byte per row -- exactly the format `stamp`
# reads, so `text` is a thin loop over `stamp`. The default input is
# Terminus Font (Uni2-Terminus16.psf.gz), SIL OFL 1.1; see fonts/OFL.txt.
#
# The font-terminus-8x16.fs it writes is the shipped artifact -- BasicForth needs no
# Python to build or run. Re-run this only to regenerate from a new PSF.
#
# Usage:  python3 psf2font.py [font.psf.gz] [output.fs]

import sys
import os
import gzip
import struct

CELL_WIDTH = 8               # PSF1 is always 8 wide; we require 8 for PSF2 too
CELL_HEIGHT = 16
NUM_CHARS = 256
BYTES_PER_GLYPH = CELL_HEIGHT  # 1 byte/row at width 8

PSF1_MAGIC = (0x36, 0x04)
PSF1_MODE_512 = 0x01
PSF1_MODE_HASTAB = 0x02
PSF2_MAGIC = 0x864AB572
PSF2_HAS_UNICODE = 0x01

# CP437 (codes 128-255) -> Unicode. Codes 0-127 map to themselves.
CP437_MAP = [
    0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,  # 128-135
    0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,  # 136-143
    0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,  # 144-151
    0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,  # 152-159
    0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,  # 160-167
    0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,  # 168-175
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,  # 176-183
    0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,  # 184-191
    0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,  # 192-199
    0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,  # 200-207
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,  # 208-215
    0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,  # 216-223
    0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4,  # 224-231
    0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,  # 232-239
    0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248,  # 240-247
    0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,  # 248-255
]


def char_to_unicode(code):
    return code if code < 128 else CP437_MAP[code - 128]


def generate_block_glyph(cp):
    """Synthesize a block-element glyph the PSF may lack. 16 bytes, or None."""
    g = bytearray(BYTES_PER_GLYPH)
    half = CELL_HEIGHT // 2
    if cp == 0x2580:                       # upper half
        for r in range(CELL_HEIGHT):
            g[r] = 0xFF if r < half else 0x00
    elif cp == 0x2584:                     # lower half
        for r in range(CELL_HEIGHT):
            g[r] = 0xFF if r >= half else 0x00
    elif cp == 0x258C:                     # left half
        for r in range(CELL_HEIGHT):
            g[r] = 0xF0
    elif cp == 0x2590:                     # right half
        for r in range(CELL_HEIGHT):
            g[r] = 0x0F
    elif cp == 0x2588:                     # full block
        for r in range(CELL_HEIGHT):
            g[r] = 0xFF
    elif cp == 0x2591:                     # light shade (25%)
        for r in range(CELL_HEIGHT):
            g[r] = 0x88 if r % 2 == 0 else 0x22
    elif cp == 0x2592:                     # medium shade (50% checker)
        for r in range(CELL_HEIGHT):
            g[r] = 0xAA if r % 2 == 0 else 0x55
    elif cp == 0x2593:                     # dark shade (75%)
        for r in range(CELL_HEIGHT):
            g[r] = 0x77 if r % 2 == 0 else 0xDD
    else:
        return None
    return bytes(g)


def parse_psf1(data):
    mode, charsize = data[2], data[3]
    nglyph = 512 if (mode & PSF1_MODE_512) else 256
    if charsize != BYTES_PER_GLYPH:
        raise ValueError(f"PSF1 charsize {charsize}, expected {BYTES_PER_GLYPH} (8x16)")
    glyphs = [data[4 + i * charsize: 4 + (i + 1) * charsize] for i in range(nglyph)]
    uni = {}
    if mode & PSF1_MODE_HASTAB:            # UCS-2 table: 2-byte LE entries
        pos = 4 + nglyph * charsize
        for gi in range(nglyph):
            while pos + 1 < len(data):
                val = data[pos] | (data[pos + 1] << 8)
                pos += 2
                if val == 0xFFFF:          # end of this glyph's list
                    break
                if val == 0xFFFE:          # sequence follows; skip to terminator
                    while pos + 1 < len(data):
                        v = data[pos] | (data[pos + 1] << 8)
                        pos += 2
                        if v in (0xFFFF, 0xFFFE):
                            pos -= 2
                            break
                    continue
                uni.setdefault(val, gi)
    return glyphs, uni


def parse_psf2(data):
    (hsz, flags, nglyph, bpg, h, w) = struct.unpack_from('<IIIIIIII', data, 0)[2:]
    if w != CELL_WIDTH or h != CELL_HEIGHT:
        raise ValueError(f"PSF2 is {w}x{h}, expected {CELL_WIDTH}x{CELL_HEIGHT}")
    stride = (w + 7) // 8
    glyphs = []
    for i in range(nglyph):
        raw = data[hsz + i * bpg: hsz + i * bpg + bpg]
        # take the first byte of each row (width 8 -> stride 1)
        glyphs.append(bytes(raw[r * stride] for r in range(h)))
    uni = {}
    if flags & PSF2_HAS_UNICODE:           # UTF-8 table
        pos = hsz + nglyph * bpg
        for gi in range(nglyph):
            while pos < len(data):
                b = data[pos]
                if b == 0xFF:
                    pos += 1
                    break
                if b == 0xFE:
                    pos += 1
                    while pos < len(data) and data[pos] not in (0xFF, 0xFE):
                        pos += 1 + (0 if data[pos] < 0x80 else
                                    1 if data[pos] < 0xE0 else
                                    2 if data[pos] < 0xF0 else 3)
                    continue
                if b < 0x80:
                    cp, pos = b, pos + 1
                elif b < 0xE0:
                    cp = ((b & 0x1F) << 6) | (data[pos + 1] & 0x3F); pos += 2
                elif b < 0xF0:
                    cp = ((b & 0x0F) << 12) | ((data[pos + 1] & 0x3F) << 6) | (data[pos + 2] & 0x3F); pos += 3
                else:
                    cp = ((b & 0x07) << 18) | ((data[pos + 1] & 0x3F) << 12) | ((data[pos + 2] & 0x3F) << 6) | (data[pos + 3] & 0x3F); pos += 4
                uni.setdefault(cp, gi)
    return glyphs, uni


def load(psf_path):
    raw = open(psf_path, 'rb').read()
    data = gzip.decompress(raw) if psf_path.endswith('.gz') else raw
    if data[0] == PSF1_MAGIC[0] and data[1] == PSF1_MAGIC[1]:
        return parse_psf1(data)
    if struct.unpack_from('<I', data, 0)[0] == PSF2_MAGIC:
        return parse_psf2(data)
    raise ValueError("not a PSF1 or PSF2 file")


def build_table(glyphs, uni):
    table, found, gen, blank = [], 0, 0, 0
    empty = bytes(BYTES_PER_GLYPH)
    for code in range(NUM_CHARS):
        cp = char_to_unicode(code)
        if cp in uni:
            table.append(glyphs[uni[cp]]); found += 1
        elif (g := generate_block_glyph(cp)) is not None:
            table.append(g); gen += 1
        else:
            table.append(empty); blank += 1
    return table, found, gen, blank


def ascii_art(glyph):
    return ["".join("#" if (b & (0x80 >> x)) else "." for x in range(8)) for b in glyph]


def emit_fs(table, out_path, src_name):
    lines = []
    w = lines.append
    w("\\ font-terminus-8x16.fs -- 8x16 bitmap text on the framebuffer.")
    w("\\ require it for `text`.  GENERATED by tools/psf2font.py -- do not edit.")
    w("\\")
    w("\\ This file is dual-licensed by content:")
    w("\\")
    w("\\   The Forth code (the glyph/text words below the table) is")
    w("\\     Copyright (C) 2026 Brandon Blodget")
    w("\\     SPDX-License-Identifier: GPL-2.0-only")
    w("\\")
    w("\\   The (glyphs) bitmap table is derived from Terminus Font, and is")
    w("\\   NOT under the GPL -- the SIL Open Font License forbids relicensing")
    w("\\   font data:")
    w("\\     Copyright (C) 2010 Dimitar Toshkov Zhekov")
    w("\\     SPDX-License-Identifier: OFL-1.1")
    w("\\   This is a MODIFIED version per the OFL (format changed to a Forth")
    w("\\   array; a few block-shading glyphs synthesized where the PSF lacked")
    w("\\   them), so it is not the official \"Terminus Font\" -- that is a")
    w("\\   Reserved Font Name.  Full license and reserved-name note in")
    w("\\   fonts/OFL.txt.")
    w(f"\\   Generated from {src_name}.")
    w("")
    w("require graphics.fs                         \\ text draws each glyph with `stamp`")
    w("")
    w("8  constant font-w                          \\ every glyph is 8 wide,")
    w("16 constant font-h                          \\ 16 tall, one byte per row")
    w("")
    w("\\ 256 glyphs in CP437 order, font-h bytes each (MSB = leftmost pixel) --")
    w("\\ laid out exactly as `stamp ( color src x y w h -- )` reads them.")
    w("create (glyphs)")
    for code in range(NUM_CHARS):
        g = table[code]
        ch = chr(code) if 33 <= code <= 126 else ("SPC" if code == 32 else ".")
        body = " ".join(f"${b:02x} c," for b in g)
        w(f"  {body}   \\ {code:3d} {ch}")
    w("")
    w("\\ Address of a glyph's bitmap in the table (its byte offset is ch*font-h).")
    w(": >glyph ( ch -- addr )  255 and  font-h *  (glyphs) + ;")
    w("")
    w("\\ Draw one glyph in `color` with its top-left at pixel x,y.  0-bits are")
    w("\\ transparent (it is a `stamp`), so glyphs compose over anything drawn.")
    w("\\ Not named `char`: that is the standard word ( \"name\" -- c ).")
    w(": glyph ( color ch x y -- )")
    w("    >r >r                                   \\ R: x y  ( x on top )")
    w("    >glyph                                  ( color src )")
    w("    r> r>                                   ( color src x y )")
    w("    font-w font-h stamp ;")
    w("")
    w("variable (t-col)  variable (t-adr)          \\ text pen state: color, string,")
    w("variable (t-x)    variable (t-y)  variable (t-x0)   \\ pen x/y, and line start x")
    w("")
    w("\\ Draw a string with its top-left at x,y, one glyph every font-w pixels.")
    w("\\ A newline (10) returns to the start column and drops down font-h; a")
    w("\\ carriage return (13) is ignored.  Off-screen glyphs clip, via `stamp`.")
    w(": text ( color c-addr u x y -- )")
    w("    (t-y) !  dup (t-x0) !  (t-x) !          ( color c-addr u )")
    w("    >r  (t-adr) !  (t-col) !                \\ empty; R: u")
    w("    r> 0 ?do")
    w("        (t-adr) @ i + c@                    ( ch )")
    w("        dup 10 = if   drop")
    w("            (t-x0) @ (t-x) !  font-h (t-y) +!")
    w("        else dup 13 = if  drop")
    w("        else")
    w("            (t-col) @ swap (t-x) @ (t-y) @ glyph")
    w("            font-w (t-x) +!")
    w("        then then")
    w("    loop ;")
    w("")
    with open(out_path, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    default_font = "/usr/share/consolefonts/Uni2-Terminus16.psf.gz"
    default_out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "..", "src", "forth", "font-terminus-8x16.fs")
    psf_path = sys.argv[1] if len(sys.argv) > 1 else default_font
    out_path = sys.argv[2] if len(sys.argv) > 2 else default_out
    if not os.path.exists(psf_path):
        print(f"Error: font not found: {psf_path}")
        sys.exit(1)

    glyphs, uni = load(psf_path)
    print(f"{len(glyphs)} glyphs, {len(uni)} unicode mappings")
    table, found, gen, blank = build_table(glyphs, uni)
    print(f"Found: {found}, Generated: {gen}, Blank: {blank}")
    emit_fs(table, out_path, os.path.basename(psf_path))
    print(f"Wrote {out_path}")

    print("\nSample glyphs:")
    for s in (ord('A'), ord('g'), ord('|'), 0xC4, 0xB0, 0xDB):
        print(f"\n  {s} (U+{char_to_unicode(s):04X}):")
        for row in ascii_art(table[s]):
            print("    " + row)
