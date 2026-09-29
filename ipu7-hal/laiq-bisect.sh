#!/bin/bash
# Swap LAIQ record groups from the OV08X40 file into the SC200PC file and
# measure output noise on the synthetic mild-noise sequence at fixed gain.
# Usage: laiq-bisect.sh <algorithm ids...>
H=$(dirname "$(readlink -f "$0")")
W=$H/work
P=$W/prefix
C=$P/etc/camera/ipu75xa
python3 "$H/aiqb-laiq-swap.py" "$W/a1.tmp" "$C/OV08X40_KAFE799_PTL.aiqb" "$C/SC200PC_KAFC917_PTL.aiqb" "$@" > /dev/null
LD_LIBRARY_PATH=$P/lib GST_PLUGIN_PATH=$P/lib/gstreamer-1.0 GST_REGISTRY=$P/gst-registry.bin \
cameraInjectFile=$W/noise-sc cameraDebug=0x1 timeout -s KILL 28 gst-launch-1.0 icamerasrc device-name=sc200pc-uf \
    num-buffers=48 ae-mode=manual exposure-time=30000 gain=23.8 \
    ! video/x-raw,format=NV12,width=1280,height=720 ! filesink location="$W/bisect.nv12" > "$W/run-bisect.log" 2>&1
echo -n "swap [$*] exit $? segv $(grep -c SIGSEGV "$W/run-bisect.log"): "
python3 "$H/noise-measure.py" "$W/bisect.nv12" 500 300 700 400 | sed 's/.*frames, //'
