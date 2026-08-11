"""List the records inside one CPFF section.

Section payload starts with a zero word and a checksum, after which records
run back to back as {u32 size, u16 id, u16 flags} followed by size-8 bytes of
data. The walk is only trusted if it lands exactly on the section end.

Usage: records.py <file> [section-tag]
"""

import struct
import sys

sys.path.insert(0, sys.path[0])
from sections import sections  # noqa: E402


def walk(data, payload, end):
    offset = payload + 8
    records = []
    while offset + 8 <= end:
        size, record_id, flags = struct.unpack_from("<IHH", data, offset)
        if size < 8 or offset + size > end:
            return records, False
        records.append((record_id, flags, offset, size))
        offset += size
    return records, offset == end


def main():
    path = sys.argv[1]
    want = sys.argv[2] if len(sys.argv) > 2 else "LCMC"
    data = open(path, "rb").read()

    for tag, offset, size, _inner, payload in sections(data):
        if tag != want:
            continue

        end = offset + size
        records, exact = walk(data, payload, end)
        print(f"{tag}: {len(records)} records, "
              f"walk {'lands exactly on' if exact else 'DID NOT reach'} "
              f"section end 0x{end:x}\n")

        for record_id, flags, roff, rsize in records:
            body = data[roff + 8:roff + 8 + min(24, rsize - 8)]
            print(f"  id={record_id:>5} flags=0x{flags:04x} "
                  f"off=0x{roff:06x} size={rsize:>7}  {body.hex(' ')}")


if __name__ == "__main__":
    main()
