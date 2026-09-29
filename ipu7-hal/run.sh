#!/bin/bash
# Short test capture through icamerasrc. Killed after 20 s regardless.
# Usage: [PREFIX=work/prefix] [NUM=frames] [ICAM_OPTS="prop=value ..."] run.sh [output.nv12] [cameraDebug level]
W=$(dirname "$(readlink -f "$0")")/work
P=$(readlink -f "${PREFIX:-$W/prefix}")
LD_LIBRARY_PATH=$P/lib GST_PLUGIN_PATH=$P/lib/gstreamer-1.0 \
GST_REGISTRY=$P/gst-registry.bin cameraDebug=${2:-0x1} \
timeout -s KILL 20 gst-launch-1.0 icamerasrc device-name=sc200pc-uf num-buffers=${NUM:-30} ${ICAM_OPTS:-} \
    ! video/x-raw,format=NV12,width=1280,height=720 ! filesink location="${1:-$W/test.nv12}"
