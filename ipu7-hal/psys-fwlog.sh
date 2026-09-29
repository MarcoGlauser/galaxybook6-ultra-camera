#!/bin/bash
# Swap Ubuntu's intel-ipu7-psys for one built with the PSYS firmware logger
# (ipu7-drivers + psys-fwlog.patch, -DENABLE_FW_OFFLINE_LOGGER), read the
# firmware log, or go back to Ubuntu's module. Run with sudo.
#
#   sudo ipu7-hal/psys-fwlog.sh load      sign and load the logging module
#   sudo ipu7-hal/psys-fwlog.sh dump      copy the firmware log to work/fwlog.bin
#   sudo ipu7-hal/psys-fwlog.sh restore   reload Ubuntu's module
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")
KO=$HERE/work/drv/drivers/media/pci/intel/ipu7/psys/intel-ipu7-psys.ko
SIGNED=$HERE/work/intel-ipu7-psys-fwlog.ko
USER_NAME=${SUDO_USER:-$(logname)}

[[ $EUID -eq 0 ]] || { echo "Run this with sudo." >&2; exit 1; }

grant() {
    for _ in $(seq 20); do
        [[ -e /dev/ipu7-psys0 ]] && break
        sleep 0.1
    done
    setfacl -m "u:$USER_NAME:rw" /dev/ipu7-psys0
}

case ${1:-} in
load)
    cp "$KO" "$SIGNED"
    "/usr/src/linux-headers-$(uname -r)/scripts/sign-file" sha256 \
        /var/lib/shim-signed/mok/MOK.priv /var/lib/shim-signed/mok/MOK.der "$SIGNED"
    modprobe -r intel-ipu7-psys 2>/dev/null || true
    insmod "$SIGNED" dyndbg=+p
    grant
    echo "Loaded logging PSYS module."
    ;;
dump)
    mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
    cat /sys/kernel/debug/ipu7-psys/fwlog > "$HERE/work/fwlog.bin"
    chown "$USER_NAME:" "$HERE/work/fwlog.bin"
    echo "Wrote $(stat -c %s "$HERE/work/fwlog.bin") bytes to work/fwlog.bin"
    ;;
restore)
    rmmod intel_ipu7_psys 2>/dev/null || true
    modprobe intel-ipu7-psys
    grant
    echo "Ubuntu's PSYS module is back."
    ;;
*)
    echo "Usage: $0 load|dump|restore" >&2
    exit 1
    ;;
esac
