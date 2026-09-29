"""Temporal vs spatial noise on a static patch of an NV12 capture.

For independent frame-to-frame noise the mean absolute step between
consecutive frames is 1.128 times the temporal standard deviation; recursive
temporal noise reduction correlates consecutive frames and pushes the ratio
below 1. Each frame's patch mean is subtracted first, so slow AE/AWB drift
does not count as noise.

Frames are taken from the middle of the capture, after AE has settled. The
default patch is a flat piece of ceiling in the test scene.

Usage: noise-measure.py <capture.nv12> [x0 y0 x1 y1]
"""
import statistics as st
import sys

W, H, FRAME = 1280, 720, 1384320   # icamerasrc NV12 buffers carry 1920 bytes of padding


def main():
    path = sys.argv[1]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6]) if len(sys.argv) == 6 else (760, 200, 960, 300)
    frames = []
    with open(path, 'rb') as f:
        while (b := f.read(FRAME)) and len(b) == FRAME:
            frames.append(b)
    use = frames[len(frames) // 3:len(frames) // 3 + 60]

    def patch(b):
        return [[b[y * W + x] for x in range(x0, x1)] for y in range(y0, y1)]

    pf = [patch(b) for b in use]
    h, w = y1 - y0, x1 - x0
    for f in pf:                                    # remove per-frame drift
        m = sum(map(sum, f)) / (h * w)
        for row in f:
            row[:] = [v - m for v in row]
    temporal = st.mean(st.pstdev([f[y][x] for f in pf]) for y in range(0, h, 4) for x in range(0, w, 4))
    step = st.mean(abs(pf[i][y][x] - pf[i - 1][y][x])
                   for i in range(1, len(pf)) for y in range(0, h, 8) for x in range(0, w, 8))

    def highpass(f):
        return st.pstdev(f[y][x] - sum(f[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9
                         for y in range(1, h - 1, 3) for x in range(1, w - 1, 3))

    spatial = st.mean(highpass(f) for f in pf[::10])
    luma = st.mean(use[0][y * W + x] for y in range(y0, y1) for x in range(x0, x1))
    print(f'{path}: {len(frames)} frames, patch luma {luma:.0f}, temporal std {temporal:.2f}, '
          f'step {step:.2f}, step ratio {step / (1.128 * temporal):.2f}, '
          f'spatial high-pass std {spatial:.2f}')


if __name__ == '__main__':
    main()
