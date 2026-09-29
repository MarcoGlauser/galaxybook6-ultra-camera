"""Replace chosen LAIQ records of one tuning file with another file's.

LAIQ (AIQ algorithm tuning) holds one DFLT block of records
{u32 size, u16 version, u16 algorithm} + data, one record per algorithm. The
SC200PC file (Windows tuning tools) carries newer versions of several records
than the Dec 2025 Linux AIC knows. This swaps the records for the given
algorithm ids with the donor's (keeping the base's order, appending donor
records the base lacks) and fixes the DFLT, AIQB, LAIQ and CPFF sizes, the
LAIQ checksum (word sum from its AIQB header, zero-padded) and the file
checksum at 0x14 (word sum of the zero-padded file).

Usage: aiqb-laiq-swap.py <base.aiqb> <donor.aiqb> <out.aiqb> <algorithm>...
       algorithm ids as in the record flags, e.g. 0x108
"""
import struct
import sys


def word_sum(buf):
    buf = bytes(buf) + b'\0' * (-len(buf) % 4)
    return sum(struct.unpack_from(f'<{len(buf) // 4}I', buf)) & 0xffffffff


def laiq(d):
    off = 0x18
    while off + 16 <= len(d) and d[off:off + 4].isalpha():
        size = struct.unpack_from('<I', d, off + 4)[0]
        if d[off:off + 4] == b'LAIQ':
            return off, size
        off += size
    sys.exit('no LAIQ section')


def records(d):
    sec, size = laiq(d)
    b = sec + 16
    bsize = struct.unpack_from('<I', d, b + 4)[0]
    pay, end, out = b + 40, b + bsize, []
    while pay + 8 <= end:
        rsize, _, alg = struct.unpack_from('<IHH', d, pay)
        out.append((alg, d[pay:pay + rsize]))
        pay += rsize
    return sec, size, b, bsize, out


def main():
    base = open(sys.argv[1], 'rb').read()
    donor = open(sys.argv[2], 'rb').read()
    algs = {int(a, 0) for a in sys.argv[4:]}
    sec, size, b, bsize, recs = records(base)
    donor_recs = dict(records(donor)[4])

    body = b''.join(donor_recs[a] if a in algs and a in donor_recs else r for a, r in recs)
    have = {a for a, _ in recs}
    body += b''.join(donor_recs[a] for a in sorted(algs - have) if a in donor_recs)

    header = bytearray(base[b:b + 40])            # DFLT + AIQB headers, zero word, checksum
    new_bsize = 40 + len(body)
    grow = new_bsize - bsize
    struct.pack_into('<I', header, 4, new_bsize)
    struct.pack_into('<I', header, 16 + 4, new_bsize - 16)
    block = header + body
    out = bytearray(base[:b]) + block + base[b + bsize:]
    struct.pack_into('<I', out, sec + 4, size + grow)
    struct.pack_into('<I', out, 4, len(out))

    out[b + 36:b + 40] = b'\0' * 4
    struct.pack_into('<I', out, b + 36, word_sum(out[b + 16:sec + size + grow]))
    out[0x14:0x18] = b'\0' * 4
    struct.pack_into('<I', out, 0x14, word_sum(out))
    open(sys.argv[3], 'wb').write(out)
    print(f'swapped {sorted(hex(a) for a in algs)}, LAIQ grew by {grow} bytes')


if __name__ == '__main__':
    main()
