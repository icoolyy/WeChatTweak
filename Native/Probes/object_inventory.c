// Research-only read-only probe for arm64 WeChat 4.1.13 (269602).
// Requires an explicit output path and matching LC_UUID. Does not exit WeChat.
#include "heap_inventory.h"
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static WCTHeapTarget targets[] = {
    {0x95a38e0, "WeChatApplication", 0},
    {0x95a3978, "WindowManager", 0},
    {0x95e6960, "ContactServiceWrapper", 0},
    {0x95e69e8, "ContactServiceWrapperBatchProcessor", 0},
    {0x95eae30, "ContactsManagerDetailModel", 0},
    {0x95edac8, "ContactsTableBaseView", 0},
    {0x9605c90, "MainWindow", 0},
    {0x9700e58, "MainWindowSecondary", 0},
    {0x95c2480, "ChatSessionList", 0},
    {0x961baa0, "SearchContentView", 0},
    // Candidate inferred from destructor log + the vptr store at 0x3b6e278.
    // This label is a research observation, not a callable service interface.
    {0x9878088, "ContactServiceDestructorCandidate", 0},
};

static uintptr_t module_base(void) {
    static const unsigned char expected[16] = {
        0xcd,0xb8,0x10,0x58,0x0f,0xac,0x35,0x18,
        0x95,0xf5,0xc0,0xcc,0x78,0x60,0xf9,0xb5};
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "/Contents/Resources/wechat.dylib")) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) continue;
        const char *p = (const char *)(header + 1);
        const char *end = p + header->sizeofcmds;
        for (uint32_t j = 0; j < header->ncmds && p + sizeof(struct load_command) <= end; ++j) {
            const struct load_command *command = (const void *)p;
            if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end-p)) break;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *uuid = (const void *)p;
                if (!memcmp(uuid->uuid, expected, sizeof(expected))) return (uintptr_t)header;
            }
            p += command->cmdsize;
        }
    }
    return 0;
}

static void inventory_once(void *context) {
    int fd = (int)(intptr_t)context;
    uintptr_t base = module_base();
    if (!base) {
        dprintf(fd, "module_match=0\n");
        close(fd);
        return;
    }
    for (unsigned i = 0; i < sizeof(targets)/sizeof(targets[0]); ++i) targets[i].vtable += base;
    WCTHeapInventory inventory = {targets, sizeof(targets)/sizeof(targets[0]), 0, 0};
    kern_return_t result = wct_heap_inventory(&inventory);
    dprintf(fd, "module_match=1\nscan_result=%d\nfailed_zones=%u\n", result, inventory.failed_zones);
    for (unsigned i = 0; i < inventory.count; ++i)
        dprintf(fd, "%s=%llu\n", targets[i].name, (unsigned long long)targets[i].count);
    close(fd);
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
