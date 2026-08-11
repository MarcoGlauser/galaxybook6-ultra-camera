#!/bin/bash
# Install the SC200PC camera stack for the Samsung Galaxy Book6 Ultra.
#
# Run with sudo, after a Machine Owner Key is enrolled (see README).
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")

if [[ $EUID -ne 0 ]]; then
    echo "Run this with sudo." >&2
    exit 1
fi

if [[ ! -f /var/lib/shim-signed/mok/MOK.priv ]]; then
    echo "No MOK signing key found. With Secure Boot enabled the modules will" >&2
    echo "be refused. See the Secure Boot section of the README." >&2
    exit 1
fi

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

install -Dm 644 "$HERE/tuning/sc200pc.yaml" \
    /usr/share/libcamera/ipa/simple/sc200pc.yaml
install -Dm 644 "$HERE/wireplumber/50-ipu7-hide-v4l2.conf" \
    /etc/wireplumber/wireplumber.conf.d/50-ipu7-hide-v4l2.conf

depmod -a

echo
echo "Installed. Reboot, then check with:  cam -l"
