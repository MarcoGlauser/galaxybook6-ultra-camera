"""Stamp a Windows IPU75XA graph settings file with the hashes of
ipu7-camera-hal e5172cc (PTL release 2025-12-10), whose layout it matches.

Usage: patch-hashes.py <windows graph_settings .bin> <output .bin>
"""
import struct
import sys

COMMON = 1110027246
GRAPHS = {100032: 611075083, 100035: 1527132867}
HEADERS_AT = 580      # after header, pin ranges, graph hash table, zoom keys
HEADER_SIZE = 116

d = bytearray(open(sys.argv[1], 'rb').read())
struct.pack_into('<I', d, 4, COMMON)
_, _, nres, _ = struct.unpack_from('<4I', d, 0)
pins = struct.unpack_from('<5I', d, 16)
table = 16 + 20 + 16 * sum(pins)
count, = struct.unpack_from('<I', d, table)
for i in range(count):
    graph, = struct.unpack_from('<I', d, table + 4 + 8 * i)
    struct.pack_into('<I', d, table + 8 + 8 * i, GRAPHS[graph])
for i in range(nres):
    b = HEADERS_AT + HEADER_SIZE * i
    graph, = struct.unpack_from('<i', d, b + 100)
    struct.pack_into('<I', d, b + 112, GRAPHS[graph])
open(sys.argv[2], 'wb').write(d)
