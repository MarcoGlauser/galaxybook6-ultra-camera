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

# --- Windows driver files ----------------------------------------

# The two files the IPU7 build converts, from sc200pc.inf 71.26100.0.11. The
# conversion depends on their exact layout, hence the checksums.
declare -A WINDOWS_FILES=(
    [graph_settings_SC200PC_KAFC917_PTL.bin]=acd119628426009170a12ee86ed7fa7e1bd7650e259339b43551b4685f8c9bd0
    [SC200PC_KAFC917_PTL.aiqb]=65b75702f33e880f9976cf51a3afa41e577dd33c1f1995e9a9fdfd1e29e5c99e
)
WIN=$HERE/win
# Samsung's download of that driver (Intel camera driver 71.26100.23.20550).
SAMSUNG_DRIVER='https://org.downloadcenter.samsung.com/downloadfile/ContentsFile.aspx?CttFileID=11639971&CDCttType=DR&ModelType=C&ModelName=&VPath=DR/202608/20260811081131834/BASW-A4296A0R_1063.ZIP'

have_windows_files() {
    local f
    for f in "${!WINDOWS_FILES[@]}"; do
        [[ -f $WIN/$f ]] || return 1
        echo "${WINDOWS_FILES[$f]}  $WIN/$f" | sha256sum --quiet -c - > /dev/null 2>&1 || return 1
    done
}

copy_windows_files() {  # directory
    local f
    for f in "${!WINDOWS_FILES[@]}"; do
        [[ -f $1/$f ]] || return 1
    done
    install -d "$WIN"
    for f in "${!WINDOWS_FILES[@]}"; do
        install -m 644 "$1/$f" "$WIN/$f"
    done
}

# Search a directory tree for the two files; copy the first matching set.
copy_windows_files_from_tree() {  # directory
    local bin
    while read -r bin; do
        copy_windows_files "$(dirname "$bin")" && have_windows_files && return 0
    done < <(find "$1" -iname 'graph_settings_SC200PC_KAFC917_PTL.bin' 2>/dev/null)
    return 1
}

unpack() {  # archive directory
    case $(head -c 4 "$1" | od -An -tx1 | tr -d ' ') in
        504b0304)  # zip
            python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2" ;;
        4d534346)  # cab
            command -v cabextract > /dev/null || apt-get install -y cabextract
            mkdir -p "$2"
            cabextract -q -d "$2" "$1" ;;
    esac || true
}

find_windows_files() {
    local dir mnt tmp
    have_windows_files && return 0
    if [[ -n $windows_driver ]]; then
        if [[ -d $windows_driver ]]; then
            copy_windows_files_from_tree "$windows_driver" || true
        else
            # Samsung's download (a zip) or the Microsoft Update Catalog .cab,
            # as a file or a URL. Unpack archives nested inside, too.
            tmp=$(mktemp -d)
            if [[ $windows_driver == http*://* ]]; then
                command -v curl > /dev/null || apt-get install -y curl
                curl -fsSL --retry 3 -o "$tmp/download" "$windows_driver" || true
            else
                cp "$windows_driver" "$tmp/download"
            fi
            unpack "$tmp/download" "$tmp/0"
            for level in 1 2 3; do
                copy_windows_files_from_tree "$tmp" && break
                find "$tmp/$((level - 1))" -type f \( -iname '*.cab' -o -iname '*.zip' \) -print0 2>/dev/null |
                    while IFS= read -r -d '' f; do
                        unpack "$f" "$tmp/$level/$(basename "$f").d"
                    done
            done
            rm -rf "$tmp"
        fi
    else
        while read -r mnt; do
            for dir in "$mnt"/Windows/System32/DriverStore/FileRepository/sc200pc.inf_amd64_*; do
                [[ -d $dir ]] && copy_windows_files "$dir" && have_windows_files && break 2
            done
        done < <(findmnt -rn -o TARGET -t ntfs3,ntfs,fuseblk)
        if ! have_windows_files; then
            echo "Downloading the camera driver from Samsung..."
            windows_driver=$SAMSUNG_DRIVER
            find_windows_files
        fi
    fi
    have_windows_files
}

if ! find_windows_files; then
    cat >&2 <<'EOF'
The IPU7 install needs two files from Samsung's Windows camera driver
(sc200pc.inf 71.26100.0.11):

    graph_settings_SC200PC_KAFC917_PTL.bin
    SC200PC_KAFC917_PTL.aiqb

Downloading them from Samsung failed. Either mount the Windows partition
(unlock BitLocker first) and run this again, or download the camera driver
for this model from Samsung
(https://www.samsung.com/global/galaxybooks-downloadcenter/) and pass it with
--windows-driver: the downloaded .zip (or its URL), or a directory it was
unpacked to.

Files that are present but fail the checksum come from a different driver
version, which the conversion has not been checked against.
EOF
    exit 1
fi

# --- Packages ------------------------------------------------------------------

# Build dependencies of the Intel camera HAL (expat, jsoncpp, libdrm) and
# icamerasrc (GStreamer, libdrm_intel); Ubuntu's signed IPU7 PSYS module and
# the IPU7 firmware; the relay, whose v4l2sink is in plugins-good.
# v4l2loopback-dkms is built and signed by DKMS with the same MOK.
apt-get install -y build-essential dkms "linux-headers-$(uname -r)" \
    git cmake automake autoconf libtool pkg-config python3 g++ \
    libexpat1-dev libjsoncpp-dev libdrm-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    linux-modules-ipu7-generic linux-firmware-intel-graphics \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    v4l2-relayd v4l2loopback-dkms v4l-utils gstreamer1.0-tools

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
