"""Graft ISP tuning sub-records from one aiqb into another (experiment).

Record 201 in each LISP block carries a stream's ISP tuning as a list of
sub-records {u32 size, u32 id, ...}. The SC200PC file (IQStudio 25.46,
Windows) uses some ids the Dec 2025 Linux AIC does not have, and lacks some it
does; those kernels then run untuned. This appends the given ids' sub-records
from a donor file's record to the target's record for the same stream in the
DFLT block, fixing up the record, AIQB, DFLT, LISP and file sizes and the
block and file checksums.

Usage: aiqb-graft.py <target.aiqb> <donor.aiqb> <out.aiqb> <stream> <id>...
"""
import struct
import sys


def word_sum(buf):
    buf = bytes(buf) + b'\0' * (-len(buf) % 4)
    return sum(struct.unpack_from(f'<{len(buf) // 4}I', buf)) & 0xffffffff


def lisp(d):
    off = 0x18
    while off + 16 <= len(d) and d[off:off + 4].isalpha():
        size = struct.unpack_from('<I', d, off + 4)[0]
        if d[off:off + 4] == b'LISP':
            return off
        off += size
    sys.exit('no LISP section')


def dflt_record(d, stream):
    """Return (lisp, block, record offset, record size) of record 201/stream in DFLT."""
    sec = lisp(d)
    b = sec + 16
    bsize = struct.unpack_from('<I', d, b + 4)[0]
    pay = b + 40
    while pay + 8 <= b + bsize:
        size, rid, flags = struct.unpack_from('<IHH', d, pay)
        if rid == 201 and flags == stream:
            return sec, b, pay, size
        pay += size
    sys.exit(f'no record 201 for stream {stream}')


def subrecords(d, pay, size):
    o, out = pay + 8, []
    while o + 8 <= pay + size:
        sz, uid = struct.unpack_from('<II', d, o)
        out.append((uid, d[o:o + sz]))
        o += sz
    return out


def main():
    target = bytearray(open(sys.argv[1], 'rb').read())
    donor = open(sys.argv[2], 'rb').read()
    stream = int(sys.argv[4], 0)
    ids = {int(x) for x in sys.argv[5:]}

    _, _, dpay, dsize = dflt_record(donor, stream)
    extra = b''.join(raw for uid, raw in subrecords(donor, dpay, dsize)
                     if (uid & 0xffff if uid > 0xffff else uid) in ids)
    if not extra:
        sys.exit('donor has none of those ids')

    sec, b, pay, size = dflt_record(target, stream)
    target[pay + size:pay + size] = extra
    grow = len(extra)
    struct.pack_into('<I', target, pay, size + grow)                     # record
    for off in (b + 4, b + 16 + 4, sec + 4):                              # DFLT, AIQB, LISP
        struct.pack_into('<I', target, off, struct.unpack_from('<I', target, off)[0] + grow)
    struct.pack_into('<I', target, 4, len(target))                        # CPFF file size

    bsize = struct.unpack_from('<I', target, b + 4)[0]
    target[b + 36:b + 40] = b'\0' * 4
    struct.pack_into('<I', target, b + 36, word_sum(target[b + 16:b + bsize]))
    target[0x14:0x18] = b'\0' * 4
    struct.pack_into('<I', target, 0x14, word_sum(target))
    open(sys.argv[3], 'wb').write(target)
    print(f'grafted {grow} bytes of sub-records into stream {stream:#x}')


if __name__ == '__main__':
    main()
