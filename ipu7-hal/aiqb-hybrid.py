"""Build a hybrid tuning file: one file's sections with some of another's.

The SC200PC file comes from the Windows tuning tools (IQStudio 25.46). Its
LCMC and LAIQ sections (sensor calibration, AE/AWB) load fine in the Linux
AIC, but its LISP section (ISP kernel tuning: noise reduction, TNR, sharpening)
uses parameter sets the Dec 2025 Linux AIC may not recognise. This keeps
every section of the base file except the named ones (default LISP), which
are taken whole from a donor file, and fixes the CPFF size and file checksum.

Usage: aiqb-hybrid.py <base.aiqb> <donor.aiqb> <out.aiqb> [SECTION...]
"""
import struct
import sys


def sections(d):
    off = 0x18
    while off + 16 <= len(d) and d[off:off + 4].isalpha():
        size = struct.unpack_from('<I', d, off + 4)[0]
        yield d[off:off + 4].decode(), d[off:off + size]
        off += size


def main():
    base = open(sys.argv[1], 'rb').read()
    donor = dict(sections(open(sys.argv[2], 'rb').read()))
    swap = set(sys.argv[4:]) or {'LISP'}
    out = bytearray(base[:0x18])
    for tag, blob in sections(base):
        out += donor[tag] if tag in swap else blob
    struct.pack_into('<I', out, 4, len(out))
    # The file checksum is a word sum over the file zero-padded to whole
    # words; the file itself is not padded (Intel's own files have odd sizes).
    out[0x14:0x18] = b'\0' * 4
    padded = bytes(out) + b'\0' * (-len(out) % 4)
    struct.pack_into('<I', out, 0x14,
                     sum(struct.unpack_from(f'<{len(padded) // 4}I', padded)) & 0xffffffff)
    open(sys.argv[3], 'wb').write(out)
    print(f'wrote {len(out)} bytes')


if __name__ == '__main__':
    main()
