#!/bin/bash
# Build Intel's IPU7 camera HAL and icamerasrc for the SC200PC, using the
# Windows driver's graph settings and tuning. Everything is built in work/
# (git-ignored).
#
#   VARIANT=dev (default)  installs into work/prefix, for run.sh and
#                          control-test.sh
#   VARIANT=system         builds for /opt/ipu7-camera and stages it under
#                          work/stage; `sudo ./install.sh` runs this and
#                          copies it
#
# Needs win/ at the repo root; install.sh fills it from the Windows driver.
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")
REPO=$(dirname "$HERE")
W=$HERE/work
VARIANT=${VARIANT:-dev}
case $VARIANT in
    dev)    PREFIX=$W/prefix;       DESTDIR= ;;
    system) PREFIX=/opt/ipu7-camera; DESTDIR=$W/stage ;;
    *)      echo "VARIANT must be dev or system" >&2; exit 1 ;;
esac
ROOT=$DESTDIR$PREFIX
BUILD=$W/build-$VARIANT
mkdir -p "$W"
rm -rf "$ROOT" ${DESTDIR:+"$DESTDIR"}

HAL_REV=e5172cc          # PTL release for iot on 2025-12-10
BINS_REV=ed16ac7         # matching ipu7-camera-bins
ICAMERASRC_REV=4fb31db   # last icamerasrc before that

fetch() {  # repo dir rev [branch]
    [[ -d $W/$2 ]] || git clone -q ${4:+-b $4} "https://github.com/intel/$1.git" "$W/$2"
    git -C "$W/$2" checkout -q "$3"
}
fetch ipu7-camera-hal hal "$HAL_REV"
fetch ipu7-camera-bins bins "$BINS_REV"
fetch icamerasrc icamerasrc "$ICAMERASRC_REV" icamerasrc_slim_api

# Build-time pkg-config files point at the staged copy; the installed ones
# keep the final prefix.
PC=$W/pkgconfig-$VARIANT
rm -rf "$PC"
mkdir -p "$PC"
export PKG_CONFIG_PATH=$PC

# Closed-source libraries.
mkdir -p "$ROOT/lib/pkgconfig" "$ROOT/include"
cp -a "$W"/bins/lib/*ipu75xa* "$ROOT/lib/"
cp -a "$W/bins/include/ipu75xa" "$ROOT/include/"
sed "s#^prefix=.*#prefix=$PREFIX#" "$W/bins/lib/pkgconfig/ia_imaging-ipu75xa.pc" \
    > "$ROOT/lib/pkgconfig/ia_imaging-ipu75xa.pc"
sed "s#^prefix=.*#prefix=$ROOT#" "$W/bins/lib/pkgconfig/ia_imaging-ipu75xa.pc" \
    > "$PC/ia_imaging-ipu75xa.pc"

# HAL with our patches (hal-e5172cc.patch), without DOL_FEATURE.
git -C "$W/hal" checkout -q -- .
git -C "$W/hal" apply "$HERE/hal-e5172cc.patch"
cmake -S "$W/hal" -B "$BUILD/hal" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_SYSCONFDIR="$PREFIX/etc" \
    -DBUILD_CAMHAL_ADAPTOR=ON -DBUILD_CAMHAL_PLUGIN=ON -DIPU_VERSIONS=ipu75xa \
    -DUSE_STATIC_GRAPH=ON -DUSE_STATIC_GRAPH_AUTOGEN=ON > "$W/hal-cmake-$VARIANT.log"
make -C "$BUILD/hal" -j"$(nproc)" > "$W/hal-make-$VARIANT.log"
make -C "$BUILD/hal" install DESTDIR="$DESTDIR" > /dev/null
sed "s#$PREFIX#$ROOT#g" "$ROOT/lib/pkgconfig/libcamhal.pc" > "$PC/libcamhal.pc"

# icamerasrc with an fps-range property (icamerasrc-4fb31db.patch), built out
# of tree so the two variants do not share objects.
git -C "$W/icamerasrc" checkout -q -- .
git -C "$W/icamerasrc" clean -qfdx
git -C "$W/icamerasrc" apply "$HERE/icamerasrc-4fb31db.patch"
(cd "$W/icamerasrc" && autoreconf --force --install --make > /dev/null 2>&1)
rm -rf "$BUILD/icamerasrc"
mkdir -p "$BUILD/icamerasrc"
(cd "$BUILD/icamerasrc" && export CHROME_SLIM_CAMHAL=ON &&
    "$W/icamerasrc/configure" --prefix="$PREFIX" > /dev/null &&
    make -j"$(nproc)" > /dev/null && make install DESTDIR="$DESTDIR" > /dev/null)

C=$ROOT/etc/camera/ipu75xa

# The SC200PC, with the Windows graph rebuilt as Linux graph 100002.
# Tuning: the AE exposure plan stretched to use the whole frame before gain,
# and the LAIQ records the Dec 2025 AIC cannot use from the Windows file
# (0x108 is a newer version it ignores; with 0x104 and 0x10c the colour noise
# roughly halves) taken from Intel's Linux OV08X40 tuning.
cp "$HERE/sc200pc-uf.json" "$C/sensors/"
python3 "$HERE/aiqb-ae-plan.py" "$REPO/win/SC200PC_KAFC917_PTL.aiqb" "$W/sc200pc-plan.aiqb"
python3 "$HERE/aiqb-laiq-swap.py" "$W/sc200pc-plan.aiqb" "$C/OV08X40_KAFE799_PTL.aiqb" \
    "$C/SC200PC_KAFC917_PTL.aiqb" 0x108 0x104 0x10c
python3 "$HERE/patch-hashes.py" "$REPO/win/graph_settings_SC200PC_KAFC917_PTL.bin" "$W/sc200pc_patched.bin"
H=$W/hal/modules/ipu_desc/ipu75xa
python3 "$HERE/gen-kernel-meta.py" "$H/Ipu75xaStaticGraphAutogen.cpp" "$W/kernel_meta.h" \
    LbffDol2Inputs LbffBayer BbpsWithTnr
g++ -std=c++17 -w -I"$H" -I"$W" -o "$W/convert-100002" "$HERE/convert-100002.cpp"
"$W/convert-100002" "$W/sc200pc_patched.bin" "$C/gcss/SC200PC_KAFC917.IPU75XA.bin"

sensors=(sc200pc-uf-0)
if [[ $VARIANT == dev ]]; then
    # Control test (control-test.sh): Intel's own OV08X40 graph and tuning,
    # detected through the sc200pc media entity and fed from a file.
    sed -e 's/ov08x40-uf/sc200pc-wf/' -e 's/ov08x40 \$I2CBUS/sc200pc $I2CBUS/' \
        "$C/sensors/ov08x40-uf.json" > "$C/sensors/sc200pc-wf.json"
    sensors+=(sc200pc-wf-0)
fi
for s in "${sensors[@]}"; do
    sed -i "s/\"availableSensors\": \\[/\"availableSensors\": [\\n            \"$s\",/" \
        "$C/libcamhal_configs.json"
done

echo "Built $VARIANT into $ROOT"
