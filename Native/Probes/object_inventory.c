// Research-only read-only probe for arm64 WeChat 4.1.13 (269602).
// Requires an explicit output path and matching LC_UUID. Does not exit WeChat.
#include "heap_inventory.h"
#include "module_269602.h"
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

static const WCTHeapTarget targets[] = {
    {0x95a38e0, "WeChatApplication", 0, 0},
    {0x95a3978, "WindowManager", 0, 0},
    {0x95e6960, "ContactServiceWrapper", 0, 0},
    {0x95e69e8, "ContactServiceWrapperBatchProcessor", 0, 0},
    {0x95eae30, "ContactsManagerDetailModel", 0, 0},
    {0x95edac8, "ContactsTableBaseView", 0, 0},
    {0x9605c90, "MainWindow", 0, 0},
    {0x9700e58, "MainWindowSecondary", 0, 0},
    {0x95c2480, "ChatSessionList", 0, 0},
    {0x961baa0, "SearchContentView", 0, 0},
    // Candidate inferred from destructor log + the vptr store at 0x3b6e278.
    // This label is a research observation, not a callable service interface.
    {0x9878088, "ContactServiceDestructorCandidate", 0, 0},
};


static uintptr_t observed[sizeof(targets)/sizeof(targets[0])];

uintptr_t wct_inventory_candidate(unsigned index) {
    return index < sizeof(observed)/sizeof(observed[0]) ? observed[index] : 0;
}

static void inventory_once(void *context) {
    int fd = (int)(intptr_t)context;
    memset(observed, 0, sizeof(observed));
    uintptr_t base = wct_269602_module_base();
    if (!base) {
        dprintf(fd, "module_match=0\n");
        close(fd);
        return;
    }
    WCTHeapTarget snapshot[sizeof(targets)/sizeof(targets[0])];
    memcpy(snapshot, targets, sizeof(targets));
    for (unsigned i = 0; i < sizeof(targets)/sizeof(targets[0]); ++i) snapshot[i].vtable += base;
    WCTHeapInventory inventory = {snapshot, sizeof(targets)/sizeof(targets[0]), 0, 0};
    kern_return_t result = wct_heap_inventory(&inventory);
    dprintf(fd, "module_match=1\nscan_result=%d\nfailed_zones=%u\n", result, inventory.failed_zones);
    for (unsigned i = 0; i < inventory.count; ++i)
        dprintf(fd, "%s=%llu\n", snapshot[i].name, (unsigned long long)snapshot[i].count);
    for (unsigned i = 0; i < inventory.count; ++i) observed[i] = snapshot[i].first_candidate;
    close(fd);
}

int wct_inventory_snapshot(const char *output) {
    if (!pthread_main_np() || !output || output[0] != '/') return -1;
    int fd = open(output, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    inventory_once((void *)(intptr_t)fd);
    return 0;
}

__attribute__((constructor)) static void start_inventory(void) {
    const char *output = getenv("WCT_INVENTORY_OUTPUT");
    if (!output || output[0] != '/') return;
    int fd = open(output, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return;
    dprintf(fd, "probe_loaded=1\n");
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 30LL*NSEC_PER_SEC),
                     dispatch_get_main_queue(), (void *)(intptr_t)fd, inventory_once);
}
