**Title:** Request: SC200PC (module KAFC917) support on Panther Lake / IPU75XA — Samsung Galaxy Book6 Ultra

## Summary

The front camera of the Samsung Galaxy Book6 Ultra is a SmartSens SC200PC (module KAFC917) on IPU7.5 (Panther Lake). Intel's Windows driver package for this laptop already contains the tuning and graph settings for it. Could a Linux build of the same configuration, i.e. `SC200PC_KAFC917.IPU75XA.bin` and `sc200pc-uf.json`, be added to this repository?

## Hardware

- Laptop: Samsung Galaxy Book6 Ultra, `PAMC-960UJH-PTLH-0`, BIOS `PAMC.1.4.49.421`
- SoC: Intel Panther Lake, IPU7.5 at PCI `0000:00:05.0` (device `0xb05d`)
- Sensor: SmartSens SC200PC, ACPI `SSLC2000`, I2C `0x36`, chip ID `0x0b71`
- Link: MIPI CSI-2 D-PHY, 2 lanes, CSI port 0, 832 Mbps/lane (link frequency 416 MHz)
- Mode: 1928x1088 RAW10, BGGR, 30 fps

## What already works on Linux

- `intel-ipu7` / `intel-ipu7-isys` in-tree (Ubuntu 26.04, kernel 7.0.0-34): firmware authenticates and the ISYS capture nodes are present.
- An open-source V4L2 sensor driver for the SC200PC, plus an `SSLC2000` entry in `ipu_bridge`. The sensor streams, and raw frames reach the ISYS.
- Image processing currently runs through libcamera's software ISP. That works, but in normal indoor light it has no noise reduction and runs at maximum gain, so the picture is very grainy. The hardware ISP would make a big difference on this machine.

## What the Windows driver package contains

`sc200pc.inf` (Provider: Intel Corporation, DriverVer `11/17/2025, 71.26100.0.11`, HW ID `ACPI\SSLC2000`) installs:

| File | SHA-256 |
|---|---|
| `SC200PC_KAFC917_PTL.aiqb` | `65b75702f33e880f9976cf51a3afa41e577dd33c1f1995e9a9fdfd1e29e5c99e` |
| `SC200PC_KAFC917_PTL.cpf` | `4945a3850729c9484078bd4420fa2a601f2c43afeaaef43fa1751199b5ec8cd0` |
| `graph_settings_SC200PC_KAFC917_PTL.bin` | `acd119628426009170a12ee86ed7fa7e1bd7650e259339b43551b4685f8c9bd0` |

The graph settings binary has the same outer layout as the Linux IPU75XA binaries: 301 resolutions, 1 sensor mode, and NV12 outputs from 640x360 to 1920x1080 at 15 and 30 fps. However, its common hash is `1550038503`, which no Linux IPU75XA release has used (361789904, 847164584, 1110027246, 1677127292, 929000173). The graph hashes it contains (graph 100032: `3891494696`, graph 100035: `419742221`) don't match any published release either. So the file can't be used with this HAL and has to be regenerated with the current Linux graph tooling.

## Request

1. `SC200PC_KAFC917.IPU75XA.bin`, generated for the current HAL (`staticGraphCommonHashCode` 929000173).
2. `config/linux/ipu75xa/sensors/sc200pc-uf.json`. I'm happy to write and test this myself if the graph binary is available.
3. `SC200PC_KAFC917_PTL.aiqb` alongside it, if it can be redistributed.

I can test on the hardware and report back, including PSYS behaviour on this kernel.
