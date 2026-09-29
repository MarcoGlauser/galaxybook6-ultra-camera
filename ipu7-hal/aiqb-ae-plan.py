"""Stretch the video AE exposure plan in the SC200PC tuning file.

The factory plan in the LAIQ section raises exposure to 7.9 ms at 1x, then
reaches 16.7 ms and 15.5x analogue gain together, then 25 ms / 25x and
32 ms / 37x. In ordinary indoor light the AE therefore settles at 1/60 s with
the analogue gain at its ceiling, which is where the grain comes from.

This moves the second and third breakpoints to 33.3 ms and 41.7 ms, so the
AE settles near a full 30 fps frame instead of 1/60 s (measured: 31.6 ms
instead of 16.7 ms at the same gain in ordinary indoor light). Moving the
second breakpoint to 41.7 ms as well made the AE settle at 25 ms instead:
the plan interpolates exposure and gain together and the AE rounds to the
flicker grid, so it is not a plain "exposure first, then gain" table. Gains
are left alone.

The plan is stored several times (16.16 fixed-point and float gain
variants); every copy starts with the same exposure-time row and all are
patched together. The
LAIQ section checksum (32-bit word sum from its AIQB header to the section
end, checksum word zeroed) and the file checksum at 0x14 (word sum of the
whole file, that word zeroed) are recomputed.

Usage: aiqb-ae-plan.py <in.aiqb> <out.aiqb>
"""
import struct
import sys

FACTORY = (1, 7896, 16666, 25000, 32000, 100000)
STRETCHED = (1, 7896, 33333, 41666, 41666, 100000)


def word_sum(buf, start, end):
    return sum(struct.unpack_from(f'<{(end - start) // 4}I', buf, start)) & 0xffffffff


def sections(d):
    off = 0x18
    while off + 16 <= len(d) and d[off:off + 4].isalpha():
        size = struct.unpack_from('<I', d, off + 4)[0]
        yield d[off:off + 4].decode(), off, size
        off += size


def main():
    d = bytearray(open(sys.argv[1], 'rb').read())
    laiq = next((off, size) for tag, off, size in sections(d) if tag == 'LAIQ')
    start, end = laiq[0], laiq[0] + laiq[1]

    old = struct.pack('<6I', *FACTORY)
    new = struct.pack('<6I', *STRETCHED)
    hits = []
    pos = d.find(old, start, end)
    while pos >= 0:
        hits.append(pos)
        pos = d.find(old, pos + 4, end)
    if not hits:
        sys.exit('factory exposure plan not found in LAIQ')
    for pos in hits:
        d[pos:pos + len(new)] = new

    checksum = start + 48 + 4
    d[checksum:checksum + 4] = b'\0' * 4
    struct.pack_into('<I', d, checksum, word_sum(d, start + 32, end))
    d[0x14:0x18] = b'\0' * 4
    struct.pack_into('<I', d, 0x14, word_sum(d, 0, len(d)))

    open(sys.argv[2], 'wb').write(d)
    print('patched plan at', ', '.join(hex(p) for p in hits))


if __name__ == '__main__':
    main()
