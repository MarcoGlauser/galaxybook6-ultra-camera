"""List the tuning-mode blocks and records of an aiqb LISP section.

LISP holds several DFLT/AIQB blocks back to back (one per tuning mode).
Each AIQB payload starts with a zero word and a checksum word, followed by
records of {u32 size, u16 id, u16 flags} + data.

Usage: aiqb-lisp.py <file.aiqb>
"""
import struct
import sys


def blocks(d):
    off = 0x18
    while off + 16 <= len(d) and d[off:off + 4].isalpha():
        tag, size = d[off:off + 4].decode(), struct.unpack_from('<I', d, off + 4)[0]
        if tag == 'LISP':
            b = off + 16
            while b + 32 <= off + size and d[b:b + 4].isalpha():
                bsize = struct.unpack_from('<I', d, b + 4)[0]
                mode = struct.unpack_from('<I', d, b + 8)[0]
                yield d[b:b + 4].decode(), b, bsize, mode
                b += bsize
        off += size


def records(d, b, bsize):
    pay = b + 32 + 8
    end = b + bsize
    out = []
    while pay + 8 <= end:
        size, rid, flags = struct.unpack_from('<IHH', d, pay)
        if size < 8 or pay + size > end:
            break
        out.append((rid, flags, pay, size))
        pay += size
    return out, pay


if __name__ == '__main__':
    d = open(sys.argv[1], 'rb').read()
    for tag, b, bsize, mode in blocks(d):
        recs, stop = records(d, b, bsize)
        print(f'{tag} @{b:#x} size {bsize} mode-word {mode:#x} records {len(recs)} '
              f'walk {"exact" if stop == b + bsize else "stopped at %#x" % stop}')
        for rid, flags, pay, size in recs:
            print(f'   id {rid:>5} flags {flags:#06x} size {size}')
