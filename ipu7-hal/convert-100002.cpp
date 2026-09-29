// Rebuild the SC200PC Windows graph settings as Linux graph 100002.
//
// The Windows file (after patch-hashes.py) uses graph 100032,
// Dol2Inputs_NoDvs_WithTnr: IsysDol -> LbffDol2Inputs -> BbpsWithTnr -> the
// Windows-only SwNntm/SwScaler. The sensor is linear, and the PSYS firmware
// never completes that graph's tasks on Linux, while Intel's own Linux graph
// 100002 (Isys -> LbffBayer -> BbpsWithTnr) runs fine.
//
// LbffBayer's kernels are LbffDol2Inputs' kernels minus ifd_pipe_long_1_3,
// dol_lite_1_1 and odr_awb_sve_1_3, and the terminal ids of the two agree.
// So every setting is rebuilt as graph 100002 by copying each shared kernel's
// resolution info, resolution history, bpp and system API data across,
// matched by kernel UUID and laid out the way OuterNode::InitRunKernels reads
// them. BbpsWithTnr is copied whole. The raw-only graph 100035 is dropped.
//
// Build against ipu7-camera-hal e5172cc modules/ipu_desc/ipu75xa, plus the
// kernel_meta.h emitted by gen-kernel-meta.py.
//
// Usage: convert-100002 <hash-patched windows .bin> <output .bin>
#include "Ipu75xaStaticGraphReaderAutogen.h"
#include "kernel_meta.h"

#include <cstdio>
#include <cstring>
#include <map>
#include <vector>

using Src = LbffDol2InputsMeta;
using Dst = LbffBayerMeta;

// Sensor line as the in-tree ISYS delivers it: unpacked 16-bit, 64-byte aligned.
static constexpr uint32_t kIsysStride = ((1928 * 2) + 63) / 64 * 64;
static constexpr uint32_t kIsysHeight = 1088;
#ifndef TUNING_MODE
#define TUNING_MODE 4
#endif
static constexpr uint8_t kTuningMode = TUNING_MODE;

template <class M> static int rcbIndex(uint32_t i) {
    if (!((M::rcb >> i) & 1))
        return -1;
    return __builtin_popcountll(M::rcb & ((1ULL << i) - 1));
}

// InitRunKernels advances the history group before using it for kernel i.
template <class M> static int historyIndex(uint32_t i) {
    return __builtin_popcountll(M::hist & ((2ULL << i) - 1));
}

template <class M> static uint32_t apiOffset(uint32_t i) {
    uint32_t off = 0;
    for (uint32_t k = 0; k < i; k++)
        off += M::apiSizes[k];
    return off;
}

template <class M> static int findKernel(uint16_t uuid) {
    for (uint32_t i = 0; i < M::count; i++)
        if (M::uuids[i] == uuid)
            return static_cast<int>(i);
    return -1;
}

static bool convertLbff(const LbffDol2InputsOuterNodeConfiguration& s,
                        LbffBayerOuterNodeConfiguration& d) {
    constexpr int nHist = sizeof(d.resolutionHistories) / sizeof(d.resolutionHistories[0]);
    constexpr int nRcb = sizeof(d.resolutionInfos) / sizeof(d.resolutionInfos[0]);
    int histFrom[nHist];
    bool rcbSet[nRcb] = {};
    std::fill(histFrom, histFrom + nHist, -1);

    d.streamId = s.streamId;
    d.tuningMode = s.tuningMode;
    for (uint32_t i = 0; i < Dst::count; i++) {
        const int j = findKernel<Src>(Dst::uuids[i]);
        if (j < 0 || Dst::apiSizes[i] != Src::apiSizes[j]) {
            fprintf(stderr, "kernel %u (uuid %u) has no counterpart\n", i, Dst::uuids[i]);
            return false;
        }
        memcpy(d.systemApiConfiguration + apiOffset<Dst>(i),
               s.systemApiConfiguration + apiOffset<Src>(j), Dst::apiSizes[i]);
        d.bppInfos[i] = s.bppInfos[j];

        const int ri = rcbIndex<Dst>(i);
        if (ri >= 0) {
            const int rj = rcbIndex<Src>(j);
            if (rj < 0) {
                fprintf(stderr, "kernel uuid %u has no resolution info in source\n", Dst::uuids[i]);
                return false;
            }
            d.resolutionInfos[ri] = s.resolutionInfos[rj];
            rcbSet[ri] = true;
        }

        const int hd = historyIndex<Dst>(i), hs = historyIndex<Src>(j);
        if (histFrom[hd] < 0) {
            histFrom[hd] = hs;
            d.resolutionHistories[hd] = s.resolutionHistories[hs];
        } else if (histFrom[hd] != hs &&
                   memcmp(&s.resolutionHistories[hs], &s.resolutionHistories[histFrom[hd]],
                          sizeof(StaticGraphKernelRes)) != 0) {
            fprintf(stderr, "history group %d: source groups %d and %d differ\n", hd,
                    histFrom[hd], hs);
            return false;
        }
    }
    for (int k = 0; k < nRcb; k++)
        if (!rcbSet[k]) {
            fprintf(stderr, "resolution info %d left unset\n", k);
            return false;
        }
    return true;
}

template <class M> static uint8_t* kernelApi(uint8_t* api, uint16_t uuid) {
    const int i = findKernel<M>(uuid);
    return i < 0 ? nullptr : api + apiOffset<M>(static_cast<uint32_t>(i));
}

static void setWord(uint8_t* record, int word, uint32_t value) {
    memcpy(record + 2 + 4 * word, &value, 4);
}

static uint32_t getWord(const uint8_t* record, int word) {
    uint32_t v;
    memcpy(&v, record + 2 + 4 * word, 4);
    return v;
}

/*
 * Align the converted setting with what Intel's Linux graph 100002 carries
 * (compared against OV08X40_KAFE799.IPU75XA.bin from the same release):
 *
 * - ifd_pipe_1_3 (55223), the LBFF input feeder, is set up on Windows for
 *   packed ISYS output: 25 pixels per 32 bytes, stride 2496 for 1928 px, a
 *   12-bit feeder output. The in-tree ISYS delivers unpacked 16-bit lines.
 *   Words 11 and 24 hold the stride in their top half; 15, 18, 19 and 36
 *   carry the format and take the Linux values; the feeder outputs 16 bits.
 * - The DOL graph left a flag set in the BLC, linearization, 3A CCM and AE
 *   statistics records (byte 4) and in the RGBS grid record (byte 5); the
 *   Linux graph has them clear.
 * - The BBPS input/output records (25579, 20865) carry 0x2 in the third byte
 *   of word 34 on Linux.
 * - Node stream ids 60014 (DOL) become 60001, tuning mode 1 becomes 4.
 * - The ISYS -> LBFF link carries unpacked frames, and the BBPS 13 -> 5
 *   self link streams as in Intel's graphs.
 */
static void linuxize(GraphConfiguration100002& d) {
    auto& lb = d.lbffBayerOuterNodeConfiguration;
    uint8_t* api = lb.systemApiConfiguration;

    if (uint8_t* ifd = kernelApi<Dst>(api, 55223)) {
        setWord(ifd, 11, (getWord(ifd, 11) & 0xffffU) | (kIsysStride << 16));
        setWord(ifd, 24, (getWord(ifd, 24) & 0xffffU) | (kIsysStride << 16));
        setWord(ifd, 15, 0xffff0101U);
        setWord(ifd, 18, 0x20000004U);
        setWord(ifd, 19, 0x00000101U);
        setWord(ifd, 36, 0x00010000U);
        lb.bppInfos[findKernel<Dst>(55223)].output_bpp = 16;
    }
    // bxt_blc, linearization, ccm_3a, aestatistics: byte 4; rgbs_grid: byte 5.
    for (uint16_t uuid : {11700, 10326, 62344, 55073})
        if (uint8_t* r = kernelApi<Dst>(api, uuid))
            r[4] = 0;
    if (uint8_t* r = kernelApi<Dst>(api, 15021))
        r[5] = 0;

    auto& bb = d.bbpsWithTnrOuterNodeConfiguration;
    for (uint16_t uuid : {25579, 20865})
        if (uint8_t* r = kernelApi<BbpsWithTnrMeta>(bb.systemApiConfiguration, uuid))
            setWord(r, 34, getWord(r, 34) | 0x00020000U);

    d.isysOuterNodeConfiguration.streamId = 60001;
    lb.streamId = 60001;
    bb.streamId = 60001;
    d.isysOuterNodeConfiguration.tuningMode = kTuningMode;
    lb.tuningMode = kTuningMode;
    bb.tuningMode = kTuningMode;

    d.linkConfigurations[2].bufferSize = kIsysStride * kIsysHeight;
    // Intel's Linux 100002 graphs stream the BBPS 13 -> 5 self link as well.
    d.linkConfigurations[10].streamingMode = 2;
}

static bool convertBlock(const GraphConfiguration100032& s, GraphConfiguration100002& d) {
    memset(&d, 0, sizeof(d));

    d.sinkMappingConfiguration = s.sinkMappingConfiguration;
    auto& sink = d.sinkMappingConfiguration;
    if (sink.preview == static_cast<uint8_t>(HwSink::ProcessedMainSink))
        sink.preview = static_cast<uint8_t>(HwSink::ImageMpSink);
    if (sink.video == static_cast<uint8_t>(HwSink::ProcessedSecondarySink))
        sink.video = static_cast<uint8_t>(HwSink::ImageDpSink);
    sink.rawDolLong = 0;

    const auto& si = s.isysDolOuterNodeConfiguration;
    auto& di = d.isysOuterNodeConfiguration;
    di.streamId = si.streamId;
    di.tuningMode = si.tuningMode;
    di.resolutionInfos[0] = si.resolutionInfos[0];
    di.resolutionHistories[0] = si.resolutionHistories[0];
    di.bppInfos[0] = si.bppInfos[0];

    if (!convertLbff(s.lbffDol2InputsOuterNodeConfiguration, d.lbffBayerOuterNodeConfiguration))
        return false;

    d.bbpsWithTnrOuterNodeConfiguration = s.bbpsWithTnrOuterNodeConfiguration;

    // 100002 link index <- 100032 link index (see the two StaticGraph ctors).
    static const int linkMap[15] = {0, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17};
    for (int k = 0; k < 15; k++)
        d.linkConfigurations[k] = s.linkConfigurations[linkMap[k]];
    // The full-size and preview outputs went to SwNntm on Windows.
    if (d.linkConfigurations[13].bufferSize == 0)
        d.linkConfigurations[13] = s.linkConfigurations[18];
    if (d.linkConfigurations[14].bufferSize == 0)
        d.linkConfigurations[14] = s.linkConfigurations[19];
    linuxize(d);
    return true;
}

template <class T> static void put(std::vector<char>& out, const T& v) {
    const char* p = reinterpret_cast<const char*>(&v);
    out.insert(out.end(), p, p + sizeof(T));
}

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <in.bin> <out.bin>\n", argv[0]);
        return 1;
    }
    FILE* f = fopen(argv[1], "rb");
    if (!f) {
        perror(argv[1]);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    std::vector<char> in(ftell(f));
    rewind(f);
    if (fread(in.data(), 1, in.size(), f) != in.size())
        return 1;
    fclose(f);

    const char* p = in.data();
    BinaryHeader hdr;
    memcpy(&hdr, p, sizeof(hdr));
    p += sizeof(hdr);
    DataRangeHeader range;
    memcpy(&range, p, sizeof(range));
    p += sizeof(range);
    uint32_t nDesc = 0;
    for (int k = 0; k < enNumOfOutPins; k++)
        nDesc += range.NumberOfPinResolutions[k];
    const DriverDesc* descs = reinterpret_cast<const DriverDesc*>(p);
    p += sizeof(DriverDesc) * nDesc;
    uint32_t nGraphs;
    memcpy(&nGraphs, p, 4);
    p += 4 + nGraphs * sizeof(GraphHashCode);
    uint32_t nZoom;
    memcpy(&nZoom, p, 4);
    const char* zoom = p;
    p += 4 + nZoom * sizeof(ZoomKeyResolution);
    const auto* heads = reinterpret_cast<const GraphConfigurationHeader*>(p);
    p += sizeof(GraphConfigurationHeader) * hdr.numberOfResolutions;
    const auto* modes = reinterpret_cast<const SensorMode*>(p);
    p += sizeof(SensorMode) * hdr.numberOfSensorModes;
    const char* data = p;

    // Drop the raw pin (it only served graph 100035) and its driver descriptors.
    DataRangeHeader outRange = range;
    const uint32_t keepDesc = nDesc - range.NumberOfPinResolutions[enRaw] -
                              range.NumberOfPinResolutions[enIr];
    outRange.NumberOfPinResolutions[enRaw] = 0;
    outRange.NumberOfPinResolutions[enIr] = 0;

    std::vector<GraphConfigurationHeader> outHeads;
    std::vector<char> outData;
    std::map<int32_t, int32_t> newOffset;
    for (uint32_t i = 0; i < hdr.numberOfResolutions; i++) {
        GraphConfigurationHeader h = heads[i];
        if (h.graphId != 100032)
            continue;
        auto it = newOffset.find(h.resConfigDataOffset);
        if (it == newOffset.end()) {
            GraphConfiguration100002 block;
            const auto* src =
                reinterpret_cast<const GraphConfiguration100032*>(data + h.resConfigDataOffset);
            if (!convertBlock(*src, block)) {
                fprintf(stderr, "setting %u failed\n", h.settingId);
                return 1;
            }
            it = newOffset.emplace(h.resConfigDataOffset, static_cast<int32_t>(outData.size())).first;
            put(outData, block);
        }
        h.additonalFeaturesBit = 0;
        h.settingsKey.attributes &=
            ~static_cast<uint32_t>(GraphConfigurationKeyAttributes::Dol2Inputs);
        h.graphId = 100002;
        h.graphHashCode = StaticGraph100002::hashCode;
        h.resConfigDataOffset = it->second;
        outHeads.push_back(h);
    }

    std::vector<char> out;
    BinaryHeader outHdr = hdr;
    outHdr.numberOfResolutions = static_cast<uint32_t>(outHeads.size());
    put(out, outHdr);
    put(out, outRange);
    out.insert(out.end(), reinterpret_cast<const char*>(descs),
               reinterpret_cast<const char*>(descs + keepDesc));
    put(out, static_cast<uint32_t>(1));
    put(out, GraphHashCode{100002, StaticGraph100002::hashCode});
    out.insert(out.end(), zoom, zoom + 4 + nZoom * sizeof(ZoomKeyResolution));
    for (const auto& h : outHeads)
        put(out, h);
    out.insert(out.end(), reinterpret_cast<const char*>(modes),
               reinterpret_cast<const char*>(modes + hdr.numberOfSensorModes));
    out.insert(out.end(), outData.begin(), outData.end());

    f = fopen(argv[2], "wb");
    fwrite(out.data(), 1, out.size(), f);
    fclose(f);
    printf("wrote %zu settings, %zu unique blocks, %zu bytes\n", outHeads.size(),
           newOffset.size(), out.size());
    return 0;
}
