# Galaxy Book6 Ultra camera on Linux

Front camera enablement for the Samsung Galaxy Book6 Ultra (PAMC, SKU
`PAMC-960UJH-PTLH-0`, Panther Lake). The sensor is a Samsung/SmartSens SC200PC
declared in ACPI as `SSLC2000`, wired to the Intel IPU7.

Tested on Ubuntu 26.04 LTS, kernel 7.0.0-29-generic, libcamera 0.7.0.

## What is missing without this

The kernel already has everything except the sensor:

- `intel-ipu7` binds, loads `ipu7ptl_fw.bin` and authenticates it
- `ipu_bridge`, `int3472` and the 32 ISYS capture nodes are all present
- the sensor's I2C client is enumerated at `i2c-3` address `0x36`

Two pieces are absent, and both are needed:

1. **No V4L2 driver claims `SSLC2000`.** Nothing in the kernel matches
   `acpi:SSLC2000:SSLC2000:`, so the I2C client sits unbound.
2. **`ipu_bridge` has no `SSLC2000` entry**, so it builds no software-node
   graph and `intel-ipu7` logs `no subdev found in graph`.

Note this machine has no vision-sensing controller in its ACPI tables, so
unlike the Dell XPS and ThinkPad X1 Carbon Panther Lake laptops, `intel_cvs`
is not required here.

## Install

Secure Boot must be able to trust the modules, so enroll a key first:

```bash
sudo apt install build-essential dkms v4l-utils \
    libcamera-tools libcamera-ipa pipewire-libcamera gstreamer1.0-libcamera
sudo dkms generate_mok
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der   # sets a one-time password
sudo reboot
```

At boot, MOK Manager appears: **Enroll MOK → Continue → Yes**, then the
password. Skipping that screen discards the request. Confirm with
`mokutil --test-key /var/lib/shim-signed/mok/MOK.der`, then:

```bash
sudo ./install.sh
sudo reboot
cam -l
```

### One more step, easy to miss

Add yourself to the `video` group:

```bash
sudo usermod -aG video "$USER"
```

WirePlumber enumerates cameras once at startup, and logind applies its device
ACL slightly later. Without group membership WirePlumber loses that race, fails
to open `/dev/media0`, and the camera is simply absent from PipeWire until you
restart WirePlumber by hand.

## What this driver corrects

Two bugs were reported against the Pro driver by DC Ippolito on Ultra hardware
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

## Tuning

`tuning/sc200pc.yaml` is for libcamera's simple soft-ISP pipeline.

`blackLevel: 4096` is the factory pedestal: 64 at 10 bits, which is what
libcamera wants on a 16-bit scale. Three independent sources agree — a raw
measurement on this machine, two records in the factory tuning binary, and
upstream libcamera's own convention for the OV2740.

The colour matrices are the per-illuminant base matrices from Samsung's
factory tuning file `SC200PC_KAFC917_PTL.aiqb`, at their stated colour
temperatures. That file also carries 24 hue-sector matrices per illuminant for
Intel's hue-segmented colour pipeline; those are deliberately not used, since
libcamera applies one matrix to every hue and averaging them applies every
sector's saturation boost to all hues at once.

**The green row is forced to identity.** Clipped highlights reach the matrix as
`(gainR, 1, gainB)` once libcamera folds in the AWB gains, and the factory
green cross-terms then pull G below the clipped R and B, so blown whites render
magenta. Identity keeps G at 1.0 there. It costs the factory's green
correction, which is the right trade for a laptop camera facing a window.

`aiqb/` holds the parser used to extract all of this. It decodes the CPFF
container, walks the section and record structure, and emits libcamera YAML.
The tuning binary itself is not included here; it lives in the Windows driver
package on the machine, under
`Windows/System32/DriverStore/FileRepository/sc200pc.inf_amd64_*`.

## Known limitations

**Noise.** In ordinary indoor light the AGC pins exposure at 33 ms and gain at
its ceiling and still asks for more, leaving the raw frame around 38% of full
scale, which the pipeline then stretches. That is visible as grain. The only
lever is longer exposure at a lower frame rate; the OEM mode table has a 15 fps
mode and the driver exposes `vertical_blanking` up to 31679, but libcamera's
simple AGC drives only exposure and gain, never blanking.

There is no fixing this in tuning. On Windows the IPU7 hardware ISP applies
temporal noise reduction and neural tone mapping — the `.aiqb` names those
blocks. That ISP has no open userspace, mainline ships only the ISYS half of
the IPU7 driver, and Intel's out-of-tree PSYS module defers permanently on
Panther Lake (`intel/ipu7-drivers` issue 63). libcamera's soft ISP has no
noise reduction stage at all.

**Two harmless libcamera warnings** persist until `sc200pc` gets a
`CameraSensorProperties` entry upstream:

```
No static properties available for 'sc200pc'
IPASoft: Failed to create camera sensor helper for sc200pc
```

**Applications opening `/dev/video0` directly** get raw Bayer, since those are
the IPU7 ISYS transport nodes. Firefox does this unless
`media.webrtc.camera.allow-pipewire` is set to true in `about:config`. The
bundled WirePlumber rule hides those nodes from PipeWire but cannot prevent a
direct open.

**`ipu-bridge-sslc2000` is kernel-version specific.** It carries a copy of
`ipu-bridge.c` with a two-line `SSLC2000` entry added, and DKMS installs it to
`/updates` so it overrides the in-tree module. The bundled copy is Linux 7.0's.
On a kernel where that file changed, re-extract it and re-apply the entry —
DKMS will otherwise keep building the stale copy without complaint.

## Credits and licence

The sensor driver was written by **James Abbott**
([Jabbslad/sc200pc-linux](https://github.com/Jabbslad/sc200pc-linux)) for the
Galaxy Book6 Pro. This repository is an Ultra-targeted fork.

The two driver bugs were reported by **DC Ippolito** on Galaxy Book6 Ultra
hardware, in issue 1 of that repository.

`ipu-bridge.c` is from the Linux kernel, by Dan Scally, GPL-2.0.

Licensed GPL-2.0, consistent with the `MODULE_LICENSE("GPL")` the driver
declares. The upstream repository carries no `LICENSE` file; if James Abbott
would prefer different terms, or would rather this not be redistributed, open
an issue and it will be changed or taken down.
