"""Extract colour matrices from an Intel CPFF tuning file as libcamera YAML.

Record 25 of the LCMC section holds Intel's hue-segmented advanced colour
matrix: six illuminants, each with a chromaticity pair, a colour temperature,
and one 3x3 matrix per hue sector. libcamera's simple IPA takes a single
matrix per colour temperature, so the hue sectors are averaged. Averaging is
safe for neutrals because every sector's rows sum to 1.0, so the mean's rows
do too -- which the output asserts.

Usage: extract_ccm.py <aiqb> [--yaml]
"""

import struct
import sys

sys.path.insert(0, sys.path[0])
from records import walk  # noqa: E402
from sections import sections  # noqa: E402

HEADER = 104
BLOCK = 924
MATRIX_COUNT = 24


def illuminants(body):
    """Yield (cct, chromaticity, base matrix, per-hue-sector matrices).

    Each 924-byte block is [16 B chromaticity][4 B CCT][36 B base matrix]
    [24 x 36 B hue sectors][4 B pad], which accounts for every byte and
    matches the 24-entry hue axis in the record header. The base matrix is the
    global correction; the sector matrices each apply to one hue range only,
    so they must not be averaged into a single matrix.
    """
    count = struct.unpack_from("<H", body, 0)[0]
    for index in range(count):
        base = HEADER + index * BLOCK
        chroma = struct.unpack_from("<4f", body, base)
        cct = struct.unpack_from("<I", body, base + 16)[0]
        global_matrix = struct.unpack_from("<9f", body, base + 20)
        sectors = [
            struct.unpack_from("<9f", body, base + 56 + n * 36)
            for n in range(MATRIX_COUNT)
        ]
        yield cct, chroma, global_matrix, sectors


def mean_matrix(matrices):
    return [sum(m[i] for m in matrices) / len(matrices) for i in range(9)]


def median_matrix(matrices):
    """Element-wise median, then renormalise each row to sum to 1.0.

    A handful of hue sectors carry a much stronger green diagonal than the
    rest and drag the mean towards green. The median tracks the cluster the
    majority of sectors sit in. Unlike the mean it does not preserve row sums
    on its own, so rows are rescaled -- neutrals must stay neutral.
    """
    values = []
    for i in range(9):
        column = sorted(m[i] for m in matrices)
        middle = len(column) // 2
        values.append(column[middle] if len(column) % 2
                      else (column[middle - 1] + column[middle]) / 2)

    for row in range(3):
        total = sum(values[row * 3:row * 3 + 3])
        for column in range(3):
            values[row * 3 + column] /= total
    return values


def spread(matrices):
    """Largest single-coefficient deviation across hue sectors."""
    worst = 0.0
    for i in range(9):
        values = [m[i] for m in matrices]
        worst = max(worst, max(values) - min(values))
    return worst


def main():
    path = sys.argv[1]
    as_yaml = "--yaml" in sys.argv
    # Default to the per-illuminant base matrix. The hue-sector reductions are
    # kept only for comparison; they are not a valid global matrix.
    reduce = None
    if "--median" in sys.argv:
        reduce = median_matrix
    elif "--mean" in sys.argv:
        reduce = mean_matrix
    blend = 1.0
    for arg in sys.argv:
        if arg.startswith("--blend="):
            blend = float(arg.split("=", 1)[1])
    data = open(path, "rb").read()

    entries = []
    for tag, offset, size, _inner, payload in sections(data):
        if tag != "LCMC":
            continue
        for _fmt, name, roff, rsize in walk(data, payload, offset + size)[0]:
            if name != 25:
                continue
            body = data[roff + 8:roff + rsize]
            for cct, chroma, global_matrix, sectors in illuminants(body):
                matrix = reduce(sectors) if reduce else list(global_matrix)

                if "--keep-green-row" not in sys.argv:
                    # Clipped highlights arrive as raw (1,1,1), which the
                    # folded-in AWB gains turn into (gainR, 1, gainB). Green
                    # cross-terms then pull G below the clipped R and B and
                    # blown whites render magenta. An identity green row keeps
                    # G at 1.0 there, at the cost of the green correction.
                    matrix[3:6] = [0.0, 1.0, 0.0]
                if blend != 1.0:
                    # Interpolate towards identity. The factory matrices are
                    # strong, and a grey-world AWB leaves enough residual for
                    # their large negative green terms to amplify into a cast.
                    identity = [1, 0, 0, 0, 1, 0, 0, 0, 1]
                    matrix = [blend * m + (1 - blend) * i
                              for m, i in zip(matrix, identity)]
                entries.append((cct, chroma, matrix, spread(sectors)))

    entries.sort(key=lambda e: e[0])

    if not as_yaml:
        for cct, chroma, matrix, worst in entries:
            sums = [sum(matrix[r * 3:r * 3 + 3]) for r in range(3)]
            print(f"{cct:5d} K  chroma={tuple(f'{c:.4f}' for c in chroma)}")
            for r in range(3):
                print("           " + " ".join(
                    f"{v:8.4f}" for v in matrix[r * 3:r * 3 + 3])
                    + f"   sum={sums[r]:.4f}")
            print(f"           hue spread (max coefficient range): {worst:.3f}\n")
        return

    print("""# SPDX-License-Identifier: CC0-1.0
#
# Tuning file for the Samsung/SmartSens SC200PC (ACPI SSLC2000).
#
# Colour matrices and black level are extracted from the factory tuning
# binary SC200PC_KAFC917_PTL.aiqb shipped with the Windows driver, module
# KAFC917. Each entry is that illuminant's base matrix; the 24 hue-sector
# matrices alongside it in the file are not usable here, because libcamera
# applies one matrix to every hue.
#
# The green row is forced to identity. Clipped highlights reach the matrix as
# (gainR, 1, gainB) once the AWB gains are folded in, and green cross-terms
# then drag G below the clipped R and B, turning blown whites magenta.
%YAML 1.1
---
version: 1
algorithms:
  # Factory pedestal is 64 at 10 bits; the IPA takes this on a 16-bit scale
  # and applies value >> 8.
  - BlackLevel:
      blackLevel: 4096
  - Awb:
  - Ccm:
      ccms:""")
    for cct, _chroma, matrix, _worst in entries:
        rows = [", ".join(f"{v: .4f}" for v in matrix[r * 3:r * 3 + 3])
                for r in range(3)]
        print(f"        - ct: {cct}")
        print(f"          ccm: [ {rows[0]},")
        print(f"                 {rows[1]},")
        print(f"                 {rows[2]} ]")
    print("  - Adjust:\n  - Agc:\n...")


if __name__ == "__main__":
    main()
