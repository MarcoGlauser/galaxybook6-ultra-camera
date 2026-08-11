"""Map the top-level sections of an Intel CPFF tuning file.

Each section starts with three nested 16-byte headers -- an outer tag, then
DFLT, then AIQB -- whose sizes step down by 16. A section spans
`offset + size`, which is where the next section's outer tag begins.
"""

import struct
import sys


def sections(data, start=0x18):
    offset = start
    while offset + 16 <= len(data):
        tag = data[offset:offset + 4]
        if not tag.isalpha():
            break
        size = struct.unpack_from("<I", data, offset + 4)[0]
        if size < 16 or offset + size > len(data):
            break

        inner = []
        probe = offset + 16
        while probe + 16 <= len(data):
            inner_tag = data[probe:probe + 4]
            if not inner_tag.isalpha():
                break
            inner_size = struct.unpack_from("<I", data, probe + 4)[0]
            inner.append((inner_tag.decode(), inner_size))
            probe += 16

        yield tag.decode(), offset, size, inner, probe
        offset += size


def main(path):
    data = open(path, "rb").read()
    print(f"file: {len(data)} bytes = 0x{len(data):x}\n")

    for tag, offset, size, inner, payload in sections(data):
        chain = " -> ".join(f"{t}({s})" for t, s in inner)
        print(f"{tag:6s} off=0x{offset:06x} size={size:>7} "
              f"end=0x{offset + size:06x}")
        print(f"       nested: {chain}")
        print(f"       payload at 0x{payload:06x}: "
              f"{data[payload:payload + 16].hex(' ')}")

        text = data[payload:payload + 200]
        printable = bytes(c if 32 <= c < 127 else 46 for c in text)
        print(f"       ascii: {printable.decode()[:90]}\n")


if __name__ == "__main__":
    main(sys.argv[1])
