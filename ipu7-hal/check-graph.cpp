// Check a converted graph settings file with the HAL's own static graph
// reader: it must load, every configuration in it must resolve to a graph
// with an active topology, and all of them must be graph 100002.
//
//   check-graph <SC200PC_KAFC917.IPU75XA.bin>
//
// Built and run by CI against the HAL revision build.sh pins.
#include "Ipu75xaStaticGraphReaderAutogen.h"
#include <cstdio>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <graph settings bin>\n", argv[0]);
        return 2;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror(argv[1]);
        return 2;
    }
    fseek(f, 0, SEEK_END);
    std::vector<char> d(ftell(f));
    rewind(f);
    if (fread(d.data(), 1, d.size(), f) != d.size()) {
        perror(argv[1]);
        return 2;
    }
    fclose(f);

    StaticReaderBinaryData bin;
    bin.data = d.data();
    bin.size = d.size();
    StaticGraphReader r;
    if (r.Init(bin) != StaticGraphStatus::SG_OK) {
        fprintf(stderr, "Init failed: hash mismatch or malformed file\n");
        return 1;
    }

    auto hdrs = r.GetGraphConfigurationHeaders();
    if (hdrs.first <= 0) {
        fprintf(stderr, "no graph configurations\n");
        return 1;
    }
    int bad = 0;
    for (int i = 0; i < hdrs.first; i++) {
        GraphConfigurationKey key = hdrs.second[i].settingsKey;
        IStaticGraphConfig *g = nullptr;
        int32_t id = 0;
        GraphTopology *t = nullptr;
        int active = 0;
        if (r.GetStaticGraphConfig(key, &g) == StaticGraphStatus::SG_OK && g) {
            g->getGraphId(&id);
            g->getGraphTopology(&t);
            for (int j = 0; t && j < t->numOfLinks; j++)
                active += t->links[j]->isActive;
        }
        if (id != 100002 || active == 0) {
            if (bad++ < 5)
                fprintf(stderr, "configuration %d: graph %d, %d active links\n", i, id, active);
        }
    }
    printf("%d configurations, %d bad\n", hdrs.first, bad);
    return bad ? 1 : 0;
}
