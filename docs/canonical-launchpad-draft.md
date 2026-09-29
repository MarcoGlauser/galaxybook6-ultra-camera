# Launchpad bug draft (Ubuntu)

File with `ubuntu-bug linux`. It attaches the kernel log, DMI data and hardware
details automatically. Launchpad shows descriptions as plain text, so the text
between the lines below is written without Markdown. Paste it as is.

---

Title:
[Samsung Galaxy Book6 Ultra] Front camera (SC200PC, IPU7.5) needs Intel camera HAL support

Description:
The front camera of the Samsung Galaxy Book6 Ultra (PAMC-960UJH-PTLH-0, Panther Lake) is not usable out of the box on Ubuntu 26.04. With the pieces below it works through libcamera's software ISP, but image quality is poor because the IPU7.5 hardware ISP can't be used. The missing part is Intel's camera HAL configuration for this sensor.

I've raised it with Intel at https://github.com/intel/ipu7-camera-hal/issues/74. Because Canonical already works with Intel on IPU7 enablement, I'm hoping this can be raised through that channel too.

HARDWARE
- Samsung Galaxy Book6 Ultra, SKU PAMC-960UJH-PTLH-0, BIOS PAMC.1.4.49.421
- Intel Panther Lake, IPU7.5 at 0000:00:05.0 (device 0xb05d)
- Sensor: SmartSens SC200PC, ACPI SSLC2000, I2C 0x36, module KAFC917
- MIPI CSI-2, 2 lanes, 832 Mbps/lane; 1928x1088 RAW10 BGGR at 30 fps

CURRENT STATE ON 7.0.0-34-generic
- intel-ipu7 and intel-ipu7-isys (in-tree) load; the firmware authenticates.
- There is no in-tree driver for SSLC2000, and ipu_bridge has no entry for it. I'm using an out-of-tree SC200PC V4L2 driver plus an ipu_bridge patch, both via DKMS, which I'm happy to share or help upstream. With those, the sensor streams and libcamera + PipeWire work.
- Ubuntu already ships intel-ipu7-psys for this kernel in linux-modules-ipu7-generic.

WHAT'S MISSING
The HAL-side files for this sensor on IPU75XA: a graph settings binary built for the current ipu7-camera-hal and a sc200pc-uf.json sensor config. Intel has already produced this configuration for Windows. Intel's Windows driver package for this laptop (sc200pc.inf, Provider: Intel Corporation, 71.26100.0.11) contains SC200PC_KAFC917_PTL.aiqb and graph_settings_SC200PC_KAFC917_PTL.bin. The graph binary has the same outer format as the Linux IPU75XA binaries, but it was generated with a structure version (common hash 1550038503) that no public ipu7-camera-hal release accepts, so it can't be reused directly.

REQUESTS
1. If possible, ask Intel for a Linux IPU75XA build of the SC200PC/KAFC917 configuration.
2. Consider adding SSLC2000 to ipu_bridge and carrying a sensor driver in the Ubuntu kernel. That alone would make the camera work through libcamera for every Galaxy Book6 owner.
3. If Intel can't provide a Linux build, a supported way to use or convert the files from the Windows driver package under Linux, for example a conversion tool or HAL support for the Windows graph settings format. This would also scale beyond this one laptop. Every IPU7 laptop that ships with Windows already has Intel-made tuning and graph files for its own sensor, so users could convert their own files instead of Intel producing and maintaining a Linux build for each OEM sensor.

I can test any packages or patches on this hardware.
