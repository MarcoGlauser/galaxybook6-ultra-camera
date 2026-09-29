/*
 * Write N raw Bayer frames for the HAL file source (cameraInjectFile=<dir>):
 * a static horizontal gradient plus independent, roughly Gaussian noise in
 * every frame. Fed through the ISP, a working temporal noise reduction makes
 * consecutive output frames correlated; without it they stay independent.
 *
 * Usage: noise-frames <dir> <width> <height> <frames> [sigma]
 * Lines are 16-bit words, 64-byte aligned, as the HAL expects for 10-bit raw.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc < 5) {
        fprintf(stderr, "usage: %s <dir> <width> <height> <frames> [sigma]\n", argv[0]);
        return 1;
    }
    const int w = atoi(argv[2]), h = atoi(argv[3]), n = atoi(argv[4]);
    const double sigma = argc > 5 ? atof(argv[5]) : 12.0;
    const int bpl = (w * 2 + 63) / 64 * 64;
    uint16_t *line = calloc(bpl / 2, 2);
    srand(1);
    for (int f = 0; f < n; f++) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/frame%03d.raw", argv[1], f);
        FILE *out = fopen(path, "wb");
        if (!out) {
            perror(path);
            return 1;
        }
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                /* sum of 4 uniforms ~ Gaussian, stddev 1 after scaling */
                double g = 0;
                for (int k = 0; k < 4; k++)
                    g += rand() / (double)RAND_MAX;
                g = (g - 2.0) * 1.7320508;
                int v = 64 + 100 + x * 500 / w + (int)(g * sigma);
                line[x] = v < 0 ? 0 : v > 1023 ? 1023 : v;
            }
            fwrite(line, 1, bpl, out);
        }
        fclose(out);
    }
    return 0;
}
