#include "Ipu75xaStaticGraphReaderAutogen.h"
#include <cstdio>
#include <vector>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END);
    std::vector<char> d(ftell(f)); rewind(f); fread(d.data(), 1, d.size(), f);
    StaticReaderBinaryData bin; bin.data = d.data(); bin.size = d.size();
    StaticGraphReader r;
    printf("Init: %d\n", (int)r.Init(bin));
    auto hdrs = r.GetGraphConfigurationHeaders();
    printf("headers: %d\n", hdrs.first);
    GraphConfigurationKey key = hdrs.second[299].settingsKey;   // 1080p preview+video
    IStaticGraphConfig *g = nullptr;
    printf("GetStaticGraphConfig: %d\n", (int)r.GetStaticGraphConfig(key, &g));
    if (!g) return 1;
    int32_t id, sid; g->getGraphId(&id); g->getSettingsId(&sid);
    printf("graph %d settings %d update: %d\n", id, sid, (int)g->updateConfiguration(0));
    GraphTopology *t = nullptr; g->getGraphTopology(&t);
    int active = 0;
    for (int i = 0; i < t->numOfLinks; i++) {
        GraphLink *l = t->links[i];
        if (!l->isActive) continue; active++;
        printf("  link %2d: src %2d node %2d t%-3u -> dst %2d node %2d t%-3u buf %u\n", i,
               (int)l->src, l->srcNode ? l->srcNode->resourceId : -1, l->srcTerminalId,
               (int)l->dest, l->destNode ? l->destNode->resourceId : -1, l->destTerminalId,
               l->linkConfiguration ? l->linkConfiguration->bufferSize : 0);
    }
    printf("links %d active %d\n", t->numOfLinks, active);
}
