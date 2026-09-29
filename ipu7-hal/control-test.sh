#!/bin/bash
# Control test for the PSYS path: Intel's own OV08X40 graph and tuning (built
# by build.sh, dev variant), fed a synthetic raw frame from a file instead
# of the sensor. If this produces frames, the Linux PSYS stack works on this
# machine and a stall is specific to the SC200PC/Windows graph.
# Killed after 20 s regardless.
W=$(dirname "$(readlink -f "$0")")/work
RAW=$W/ov08x40-gradient.raw
OUT=${1:-$W/control.nv12}

if [[ ! -f $RAW ]]; then
    # 3856x2176 SGRBG10 in 16-bit words, 7744-byte lines (ALIGN_64 of 7712).
    python3 - "$RAW" <<'EOF'
import struct, sys
w, h, bpl = 3856, 2176, 7744
line = bytearray(bpl)
with open(sys.argv[1], 'wb') as f:
    for y in range(h):
        for x in range(w):
            struct.pack_into('<H', line, 2 * x, 64 + (x * 800) // w)
        f.write(line)
EOF
fi

LD_LIBRARY_PATH=$W/prefix/lib GST_PLUGIN_PATH=$W/prefix/lib/gstreamer-1.0 \
GST_REGISTRY=$W/prefix/gst-registry.bin cameraInjectFile=$RAW cameraDebug=${2:-0x1} \
timeout -s KILL 20 gst-launch-1.0 icamerasrc device-name=sc200pc-wf num-buffers=10 \
    ! video/x-raw,format=NV12,width=1920,height=1080 ! filesink location="$OUT"
