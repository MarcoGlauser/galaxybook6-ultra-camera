Follow-up with some findings. I tried running the Windows graph settings through this HAL. It gets as far as the PSYS firmware, which accepts the graph and then never completes a task. Details below in case it helps pin down what's missing.

## The Windows graph file matches the Dec 2025 release

`graph_settings_SC200PC_KAFC917_PTL.bin` from the Windows driver has exactly the layout of this repo at `e5172cc` (PTL release for iot on 2025-12-10):

- The header is 4 words (no timestamp or tool version) and each `GraphConfigurationHeader` is 116 bytes. It has 301 resolutions and 1 sensor mode (1928x1088, no crop or scale).
- It uses graph 100032 (Dol2Inputs_NoDvs_WithTnr) for 300 settings and 100035 for raw. `sizeof(GraphConfiguration100032)` is 6244 and `sizeof(GraphConfiguration100035)` is 248 in both the Windows file and `e5172cc`, and no other release matches both.
- The system API blobs in `lbffDol2InputsOuterNodeConfiguration` line up with `e5172cc`'s kernel order (1854/1854 bytes; all 11 IO-buffer records start with UUID 47358).

Only the hashes differ: common hash `1550038503` vs `1110027246`, graph 100032 `3891494696` vs `611075083`, and graph 100035 `419742221` vs `1527132867`. With the hashes replaced, `StaticGraphReader` loads the file and builds a coherent topology.

## What else was needed

The sensor is linear. `sc200pc.sys` has only 1928x1088 at 30 and 15 fps and no DOL mode, but every setting in the file is keyed `Dol2Inputs`. To get to streaming I built with `-DDOL_FEATURE` (stream id 60014 matches the file) and patched the following:

1. `GraphConfig::createQueryKeyAttribute` sets `Dol2Inputs`.
2. `PipeManager::bindExternalPorts` feeds the single ISYS frame to both LBFF inputs (terminals 5 and 6). I also tried giving the DOL-long input a separate buffer holding a copy of the frame; the result is the same.
3. `PipeManager::isSameStreamConfig` accepts SBGGR10 as SGRBG10. The graph's LBFF input crop starts one row down.
4. The main output goes through `SwNntm`/`SwScaler`, which don't exist in this HAL. So in each setting I moved the BBPS MP buffer size from the link to `sw_nntm` to the link to `image_mp`, and mapped the preview sink to `ImageMpSink`.
5. I added a pipe scheduler profile for graph 100032.

## Result

Test setup: Ubuntu 26.04 with kernel 7.0.0-34 (in-tree ISYS) and Ubuntu's `intel-ipu7-psys` from `linux-modules-ipu7-generic`. Firmware is `ipu7ptl_fw.bin` PSYS 1.2.1.251215214352. The HAL is `e5172cc` with the patches above, plus `ipu7-camera-bins` `ed16ac7` and `icamerasrc` `4fb31db`.

- Configure succeeds, the sensor streams, SOF events arrive, and AIC runs for seq 0 (`runAIC, ret:0`).
- PSYS debug shows `GRAPH_OPEN_ACK` with node_ctx_id 0 on q 4 and 1 on q 5, then `frame 0 to task queue` for both nodes.
- After that nothing comes back: no task ACK, no error event, no kernel message. The HAL times out waiting for events. On module unload after a stuck run the driver logs `fw not ready for shutdown, state 0x57a7e400`.

So the firmware takes the task for the LBFF node and silently stalls.

A likely reason is the firmware version. The Windows IPU package on this machine (`iacamera64.inf`, 71.26100.23.20550) ships `cpd_component_signed.bin` as PSYS `1.2.1.250813145956` (commit `0c665a59`). `iacamera64.sys` embeds common hash `1550038503`, as do all of the package's own TPG graph settings, so the Windows graph was generated for that August firmware. `linux-firmware` ships `1.2.1.251215214352` (commit `ee59e1e0`). I tried loading the Windows firmware on Linux. It authenticates, but the in-tree ISYS then fails stream open (`IPU_INSYS_RESP_TYPE_STREAM_OPEN_DONE`, error group 1 code 6), so the two firmware generations aren't interchangeable, and I can't test the Windows graph against its own firmware.

## Questions

- Is there a way to get firmware-side diagnostics for a stalled task, such as a PSYS firmware log or a debug firmware?
- Is a Windows graph settings file for the same platform expected to be usable with a Linux HAL of matching layout? Or does the firmware difference (0c665a59 vs ee59e1e0) mean it always has to be regenerated?
- If regeneration is required, the original request stands: a `SC200PC_KAFC917` IPU75XA graph built for this HAL (or a way to convert the Windows one) would unblock this sensor.

Happy to share the patches or run any test you suggest.
