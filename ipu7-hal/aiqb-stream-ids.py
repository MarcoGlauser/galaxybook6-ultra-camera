"""Key the SC200PC ISP tuning to the Linux HAL's stream ids.

The LISP section holds one DFLT block and per-mode LMOD blocks, each with
record 201 entries whose flags field is the stream id the tuning applies to.
The Windows file keys them to 60014 (video) and 60015 (still), the ids of the
Windows DOL graph. The Linux HAL built without DOL_FEATURE, and the converted
graph 100002, use 60001 (video) and 60000 (still), so AIC found no ISP tuning
at all and ran every kernel on defaults: no effective TNR, flat, noisy output.

This relabels the records and recomputes each touched block's checksum (32-bit
word sum from the block's AIQB header to its end, zero-padded to a multiple of
4, checksum word zeroed) and the file checksum at 0x14 (word sum of the whole
file, that word zeroed).

Usage: aiqb-stream-ids.py <in.aiqb> <out.aiqb>
"""
import struct
import sys

REMAP = {60014: 60001, 60015: 60000}
RECORD_ISP = 201


def word_sum(buf):
    buf = bytes(buf) + b'\0' * (-len(buf) % 4)
    return sum(struct.unpack_from(f'<{len(buf) // 4}I', buf)) & 0xffffffff


def lisp_blocks(d):
    off = 0x18
    while off + 16 <= len(d) and d[off:off + 4].isalpha():
        size = struct.unpack_from('<I', d, off + 4)[0]
        if d[off:off + 4] == b'LISP':
            b = off + 16
            while b + 32 <= off + size and d[b:b + 4].isalpha():
                bsize = struct.unpack_from('<I', d, b + 4)[0]
                yield b, bsize
                b += bsize
        off += size


def main():
    d = bytearray(open(sys.argv[1], 'rb').read())
    changed = 0
    for b, bsize in lisp_blocks(d):
        pay, end = b + 40, b + bsize
        touched = False
        while pay + 8 <= end:
            size, rid, stream = struct.unpack_from('<IHH', d, pay)
            if size < 8 or pay + size > end:
                break
            if rid == RECORD_ISP and stream in REMAP:
                struct.pack_into('<H', d, pay + 6, REMAP[stream])
                touched = True
                changed += 1
            pay += size
        if touched:
            d[b + 36:b + 40] = b'\0' * 4
            struct.pack_into('<I', d, b + 36, word_sum(d[b + 16:end]))

    d[0x14:0x18] = b'\0' * 4
    struct.pack_into('<I', d, 0x14, word_sum(d))
    open(sys.argv[2], 'wb').write(d)
    print(f'relabelled {changed} ISP tuning records')


if __name__ == '__main__':
    main()
