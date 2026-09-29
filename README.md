# Galaxy Book6 Ultra webcam driver for Linux

Makes the built-in front camera of the **Samsung Galaxy Book6 Ultra** work on
Linux. After installing, the camera shows up as an ordinary webcam called
**Virtual Camera** in Google Meet, Zoom, Teams in the browser, and other video
apps.

Tested on Ubuntu 26.04 LTS with kernel 7.0 (`7.0.0-34-generic`), on the
Galaxy Book6 Ultra (model PAMC, `PAMC-960UJH-PTLH-0`).

## What it does

- Installs a Linux driver for the camera sensor (an SC200PC), which Linux
  does not support on its own.
- Processes the picture on the laptop's built-in image processor (the Intel
  IPU7), using Intel's camera software and the picture tuning from Samsung's
  Windows driver. This gives automatic exposure, white balance and noise
  reduction, and uses little CPU.
- Delivers 1280×720 video at 30 fps, slowing to 24 fps in dim light to get a
  brighter picture.
- Keeps the camera off until an app uses it, and turns it off again when the
  last app stops.

## What is missing

- **Other laptops.** It is only tested on the Galaxy Book6 Ultra. Other
  laptops with the same camera may need changes.
- **Full HD.** Video is 1280×720 only.
- **Match Windows in low light.** The picture is grainier than on Windows,
  especially in a dim room.
- **Windows Hello face login, background blur, or other Windows camera
  effects.**
- **Use its own camera name.** The camera is listed as "Virtual Camera".
  Apps see a stand-in device that carries the picture; the real capture
  devices only deliver raw sensor data.
- **Survive every kernel update.** It is built for Linux 7.0. A newer kernel
  may need an updated version of this repository (see
  [Kernel updates](#kernel-updates)).
- **Uninstall itself.** There is no uninstall script yet.

## Requirements

- Ubuntu 26.04 on a Galaxy Book6 Ultra
- Secure Boot with a Machine Owner Key enrolled (step 1 below), or Secure Boot
  turned off
- An internet connection: the installer downloads Intel's camera software
  and Samsung's Windows camera driver, and builds for a few minutes
- Ubuntu's `universe` repository, which is enabled by default; the installer
  adds every package it needs from there and from `main`

## Install

### 1. Enroll a signing key (Skip if secure boot is disabled)

Secure Boot must be able to trust the modules DKMS builds:

```bash
sudo apt install dkms
sudo dkms generate_mok
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der   # sets a one-time password
sudo reboot
```

At boot, MOK Manager appears: **Enroll MOK → Continue → Yes**, then the
password. Skipping that screen discards the request. Confirm with
`mokutil --test-key /var/lib/shim-signed/mok/MOK.der`.

### 2. Install

```bash
sudo ./install.sh
sudo reboot
```

The installer adds the packages it needs, builds the sensor driver and the
`ipu_bridge` override through DKMS, builds Intel's camera HAL and
`icamerasrc` (as your user, under `ipu7-hal/work/`, a few minutes; it
downloads Intel's sources from GitHub), installs the result to
`/opt/ipu7-camera`, and sets up the relay. After the reboot, pick
**Virtual Camera** in the browser or in Zoom.

Running it again over an earlier installation of this repository replaces
that installation.

### The Windows driver files

The ISP configuration is built from two files of Samsung's Windows camera
driver, `graph_settings_SC200PC_KAFC917_PTL.bin` and
`SC200PC_KAFC917_PTL.aiqb` (`sc200pc.inf`, DriverVer 71.26100.0.11). They
cannot be distributed here, so the installer gets them itself, from the first
of:

1. `win/` in this repository, from an earlier run
2. a mounted Windows partition:
   `Windows/System32/DriverStore/FileRepository/sc200pc.inf_amd64_*`
3. the camera driver on Samsung's
   [download center](https://www.samsung.com/global/galaxybooks-downloadcenter/),
   `BASW-A4296A0R_1063.ZIP` (Intel camera driver 71.26100.23.20550, which
   carries the SC200PC files at 71.26100.0.11), downloaded automatically

To use a copy you already have, pass it with `--windows-driver`: that zip,
the driver's `.cab` from the Microsoft Update Catalog (search for
`SSLC2000`), a directory it was unpacked to, or a download URL.

```bash
sudo ./install.sh --windows-driver ~/Downloads/BASW-A4296A0R_1063.ZIP
```

The files are checked against known checksums and copied to `win/`, which git
ignores. A different driver version is refused, since the conversion has only
been checked against this one.

## Use

Pick **Virtual Camera** as the camera in the app's video settings. In the
browser, allow the site to use the camera when asked.

If the camera is missing, check the service that feeds it:

```bash
systemctl status v4l2-relayd@sc200pc
```

## How it works

Out of the box, Ubuntu already loads the IPU7 driver and its firmware, and it
ships Intel's image-processing kernel module (`linux-modules-ipu7-generic`).
Three pieces are missing, and this repository supplies them:

1. **A sensor driver.** No kernel driver claims the ACPI device `SSLC2000`,
   so the sensor sits unused. `dkms/sc200pc-0.9.0` is that driver.
2. **An `ipu_bridge` entry.** Without one, the IPU7 driver never connects to
   the sensor (`no subdev found in graph`). `dkms/ipu-bridge-sslc2000-*` is
   the in-tree `ipu-bridge.c` with the entry added.
3. **An image-processing configuration.** Intel's Linux camera software only
   ships settings for sensors of laptops sold with Linux. `ipu7-hal/` builds
   one from Samsung's Windows files.

The picture flows like this:

```
SC200PC ─CSI─▶ IPU7 ISYS ─▶ Intel camera HAL (PSYS, 3A) ─▶ icamerasrc
                         ─▶ v4l2-relayd ─▶ v4l2loopback "Virtual Camera"
                         ─▶ browsers via PipeWire, Zoom directly
```

- **Intel camera HAL** `intel/ipu7-camera-hal` at `e5172cc` (the PTL release
  of 2025-12-10), with the matching `ipu7-camera-bins` and `icamerasrc`,
  built by `ipu7-hal/build.sh`. Their versions are pinned: the converted
  graph settings depend on that release's data layout.
- **v4l2-relayd** runs the HAL only while an application is streaming from
  the loopback device, and closes the camera when the last one stops. The
  WirePlumber rule `51-ipu7-isp.conf` keeps browsers from also seeing the
  raw sensor as a second camera.
- **Graph settings.** The Windows file uses Intel's static-graph format with
  a Windows-only structure version, a two-exposure (DOL) graph, and a packed
  ISYS input layout. `ipu7-hal/` stamps it with the Linux release's hashes,
  rebuilds it as Linux graph 100002, and switches the input feeder to the
  unpacked 16-bit lines the in-tree ISYS delivers. That last mismatch made
  the PSYS firmware accept tasks and silently never complete them.
- **Tuning.** The Windows `.aiqb` loads as is, except that one LAIQ record
  (`0x108`) is a newer version than the Linux AIC understands; it and two
  related records are taken from Intel's Linux OV08X40 tuning, which halves
  the colour noise. The AE exposure plan is stretched so AE uses the whole
  frame before raising gain. `icamerasrc` gets an `fps-range` property so AE
  may stretch the frame down to 24 fps; analogue gain is capped at 11x.

`ipu7-hal/` holds these tools and patches, plus the test scripts used to
develop them (`run.sh`, `control-test.sh`, `noise-measure.py` and others).

## Sensor driver notes

The sensor driver started as the Galaxy Book6 Pro driver by James Abbott (see
Credits). Two bugs were reported against the Pro driver by DC Ippolito on Ultra hardware
(`Jabbslad/sc200pc-linux` issue 1). Both are fixed here, and both were then
confirmed independently against the OEM Windows driver `sc200pc.sys`
v71.26100.0.11:

**Link frequency: 195 MHz → 416 MHz.** IPU7 ISYS programs its D-PHY timing
from `V4L2_CID_LINK_FREQ`. At the wrong rate the sensor probes, streaming
starts, and no frame ever arrives, with nothing logged. 832 Mbps/lane appears
as a single hardcoded constant in the Windows driver, and it is the only value
consistent with the timing: a 1928 px line at 10 bpp over 2 lanes inside the
init table's 14.75 µs line time needs at least 654 Mbps/lane.

**Analogue gain encoding.** The register pair is a 16-bit composite, not a
linear code: `0x3e08` is a thermometer-coded octave (`0x00/0x01/0x03/0x07` =
1/2/4/8×) and `0x3e09` a fine step (`0x10`–`0x1f` = 1.0–1.9375×). The Windows
driver clamps the composite to `[0x10, 0x71f]`, and `0x71f` is exactly
`(0x07 << 8) | 0x1f`, fixing the ceiling at 15.5×. Writing a linear code into
`0x3e09` alone addresses only the fine field, collapsing every request to ~1×.

**Digital gain uses `0x3e07` only.** The OEM driver never writes the coarse
register `0x3e06` — not in its init table, not from any runtime path — so this
driver leaves it at its reset value.

A gain sweep against raw frames confirms the result is linear across the whole
1×–30.5× control range, matching a pedestal of 64 to within ~1.5 LSB at every
step.

Further changes, also matched against the Windows driver:

- **Group hold.** Every exposure, gain and frame-length update is wrapped in
  `0x3812 = 0x00 … 0x30`, as the Windows driver does, so the values change
  on the same frame.
- **Controls before stream-on.** Exposure and gain are programmed while the
  sensor is still in standby, so the first frames do not go out at the init
  table's own values.
- **Automatic frame extension.** When an exposure no longer fits the frame,
  the driver lengthens it, down to 24 fps (`SC200PC_FPS_MIN`). The Windows
  driver likewise rewrites the frame length with every exposure update.

## Kernel updates

`ipu-bridge-sslc2000` carries a copy of the kernel's `ipu-bridge.c` with a
two-line `SSLC2000` entry added. DKMS installs it to `/updates` so it
overrides the in-tree module. The bundled copy is Linux 7.0's. On a kernel
where that file changed, re-extract it and re-apply the entry; DKMS will
otherwise keep building the stale copy without complaint.

## Credits and licence

The sensor driver was written by **James Abbott**
([Jabbslad/sc200pc-linux](https://github.com/Jabbslad/sc200pc-linux)) for the
Galaxy Book6 Pro. This repository is an Ultra-targeted fork.

The two driver bugs were reported by **DC Ippolito** on Galaxy Book6 Ultra
hardware, in issue 1 of that repository.

`ipu-bridge.c` is from the Linux kernel, by Dan Scally, GPL-2.0. Intel's camera
HAL, binaries and `icamerasrc` are fetched from Intel's repositories at build
time under their own licences; the patches in `ipu7-hal/` apply to them.

Licensed GPL-2.0, consistent with the `MODULE_LICENSE("GPL")` the driver
declares. The upstream repository carries no `LICENSE` file; if James Abbott
would prefer different terms, or would rather this not be redistributed, open
an issue and it will be changed or taken down.
