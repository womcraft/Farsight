#!/usr/bin/env python3
"""Joins single-frame GIFs (frame-000.gif ...) into one looping animated GIF.
Usage: gifmerge.py <frames dir> <out.gif> [delay in 1/100 s]"""
import glob, os, struct, sys

def parse(path):
    d = open(path, "rb").read()
    assert d[:3] == b"GIF", path
    w, h, flags = struct.unpack("<HHB", d[6:11])
    pos = 13
    gct = b""
    if flags & 0x80:
        n = 3 * (2 << (flags & 7))
        gct = d[pos:pos + n]; pos += n
    while d[pos] != 0x2C:                      # skip extensions
        assert d[pos] == 0x21, hex(d[pos])
        pos += 2
        while d[pos]:
            pos += d[pos] + 1
        pos += 1
    x, y, iw, ih, iflags = struct.unpack("<HHHHB", d[pos + 1:pos + 10])
    pos += 10
    table = gct
    if iflags & 0x80:
        n = 3 * (2 << (iflags & 7))
        table = d[pos:pos + n]; pos += n
    start = pos
    pos += 1                                   # LZW minimum code size
    while d[pos]:
        pos += d[pos] + 1
    pos += 1
    return w, h, (x, y, iw, ih), table, d[start:pos]

def main(src, out, delay=25):
    files = sorted(glob.glob(os.path.join(src, "frame-*.gif")))
    assert files, "no frames in " + src
    w, h = parse(files[0])[:2]
    o = bytearray(b"GIF89a" + struct.pack("<HHBBB", w, h, 0x70, 0, 0))
    o += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"          # loop forever
    for f in files:
        _, _, (x, y, iw, ih), table, data = parse(f)
        bits = max(1, (len(table) // 3 - 1).bit_length()) - 1
        o += b"\x21\xF9\x04\x04" + struct.pack("<H", delay) + b"\x00\x00"
        o += b"\x2C" + struct.pack("<HHHHB", x, y, iw, ih, 0x80 | bits) + table + data
    o += b"\x3B"
    open(out, "wb").write(o)
    print("%s: %d frames, %dx%d, %.1f MB" % (out, len(files), w, h, len(o) / 1e6))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 25)
