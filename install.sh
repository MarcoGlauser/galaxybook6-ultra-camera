#!/bin/bash
# Install the SC200PC camera stack for the Samsung Galaxy Book6 Ultra.
#
# Run with sudo, after a Machine Owner Key is enrolled (see README).
#
# The camera runs through the IPU7 hardware ISP (Intel camera HAL +
# icamerasrc), relayed into a v4l2loopback device that browsers (through
# PipeWire) and Zoom use. It is built from source during the install and
# needs two files from Samsung's Windows camera driver, which cannot be
# shipped here; see --windows-driver.
#
#   --windows-driver <path>  Samsung's camera driver download (a .zip, as a
#                            path or URL), the Microsoft Update Catalog .cab,
#                            or a directory holding the unpacked files.
#                            Without it, win/ and mounted Windows partitions
#                            are searched, then the driver is downloaded from
#                            Samsung.
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")

windows_driver=
while [[ $# -gt 0 ]]; do
    case $1 in
        --windows-driver) windows_driver=${2:?--windows-driver needs a path}; shift ;;
        *) echo "Usage: $0 [--windows-driver <zip|cab|dir|url>]" >&2; exit 1 ;;
    esac
    shift
done

if [[ $EUID -ne 0 ]]; then
    echo "Run this with sudo." >&2
    exit 1
fi

# With Secure Boot on, the kernel only loads modules signed with an enrolled
# key, and DKMS signs with this one.
if mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled' &&
        [[ ! -f /var/lib/shim-signed/mok/MOK.priv ]]; then
    echo "Secure Boot is on, but there is no MOK signing key, so the kernel" >&2
    echo "would refuse the camera modules. Enroll one first (README, step 1)." >&2
    exit 1
fi

# --- Windows driver files ------------------------------------------------------

"$HERE/get-windows-files.sh" ${windows_driver:+"$windows_driver"}

# --- Packages ------------------------------------------------------------------

mapfile -t packages < <(grep -v -e '^#' -e '^$' "$HERE/packages.txt")
apt-get install -y "linux-headers-$(uname -r)" "${packages[@]}"

# --- Sensor driver and ipu_bridge ------------------------------------------------

kernel=$(uname -r)
bridge_version=${kernel%%-*}

for pkg in "sc200pc/0.9.0" "ipu-bridge-sslc2000/$bridge_version"; do
    name=${pkg%/*}
    version=${pkg#*/}
    source_dir="$HERE/dkms/$name-$version"

    if [[ ! -d $source_dir ]]; then
        echo "No DKMS sources for $name at $version." >&2
        echo "The bundled ipu-bridge.c matches one kernel series; see README." >&2
        exit 1
    fi

    dkms remove "$name/$version" --all 2>/dev/null || true
    rm -rf "/usr/src/$name-$version"
    cp -r "$source_dir" "/usr/src/$name-$version"
    dkms add "$name/$version"
    dkms build "$name/$version"
    dkms install "$name/$version" --force
done

# --- IPU7 hardware ISP -------------------------------------------------------------

# Build as the invoking user, so the checkout and build tree in ipu7-hal/work
# stay theirs; only the result is installed as root.
builder=${SUDO_USER:-root}
sudo -u "$builder" env VARIANT=system "$HERE/ipu7-hal/build.sh"
rm -rf /opt/ipu7-camera
cp -a "$HERE/ipu7-hal/work/stage/opt/ipu7-camera" /opt/ipu7-camera
chown -R root:root /opt/ipu7-camera
install -Dm 644 "$HERE/ipu7-hal/70-ipu7-psys.rules" /etc/udev/rules.d/70-ipu7-psys.rules
udevadm control --reload
udevadm trigger --subsystem-match=intel-ipu7-psys

# --- WirePlumber and the relay ------------------------------------------------------

WP=/etc/wireplumber/wireplumber.conf.d
DROPIN=/etc/systemd/system/v4l2-relayd@sc200pc.service.d

# Files earlier versions of this installer put in place.
rm -f "$WP/51-libcamera-relay.conf" "$DROPIN/override.conf" \
    /etc/modprobe.d/zz-v4l2loopback-sc200pc.conf \
    /usr/share/libcamera/ipa/simple/sc200pc.yaml

install -Dm 644 "$HERE/wireplumber/50-ipu7-hide-v4l2.conf" "$WP/50-ipu7-hide-v4l2.conf"
install -Dm 644 "$HERE/wireplumber/51-ipu7-isp.conf" "$WP/51-ipu7-isp.conf"
install -Dm 644 "$HERE/relayd/sc200pc.conf" /etc/v4l2-relayd.d/sc200pc.conf
install -Dm 644 "$HERE/relayd/v4l2-relayd@sc200pc.service.d/ipu7.conf" "$DROPIN/ipu7.conf"
systemctl daemon-reload
systemctl enable v4l2-relayd.service

depmod -a

echo
echo "Installed. Reboot; the camera then appears as \"Virtual Camera\"."
