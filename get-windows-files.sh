#!/bin/bash
# Put the two Windows driver files the IPU7 build needs into win/, checked
# against known checksums. Used by install.sh and CI.
#
#   get-windows-files.sh [path]
#
# path is Samsung's camera driver download (a .zip, as a path or URL), the
# Microsoft Update Catalog .cab, or a directory holding the unpacked files.
# Without it, win/ and mounted Windows partitions are searched, then the
# driver is downloaded from Samsung. Needs root only to install curl or
# cabextract when they are missing.
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")
windows_driver=${1:-}

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
