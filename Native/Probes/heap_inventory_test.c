#include "heap_inventory.h"
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    static const uintptr_t fake_vtable[] = {0x1234};
    static const uintptr_t absent_vtable[] = {0x5678};
    uintptr_t *objects[3];
    for (unsigned i = 0; i < 3; ++i) {
        objects[i] = malloc(128);
        if (!objects[i]) return 1;
        objects[i][0] = (uintptr_t)fake_vtable;
    }
    // std::make_shared can place a polymorphic object after its control block.
    uintptr_t *shared = calloc(1, 128);
    if (!shared) return 1;
    shared[3] = (uintptr_t)fake_vtable;
    WCTHeapTarget targets[] = {{(uintptr_t)fake_vtable, "fixture", 0},
                               {(uintptr_t)absent_vtable, "absent", 0}};
    WCTHeapInventory inventory = {targets, 2, 0, 0};
    kern_return_t result = wct_heap_inventory(&inventory);
    printf("result=%d fixture=%llu absent=%llu failed_zones=%u\n", result,
           (unsigned long long)targets[0].count,
           (unsigned long long)targets[1].count, inventory.failed_zones);
    for (unsigned i = 0; i < 3; ++i) free(objects[i]);
    free(shared);
    if (result != KERN_SUCCESS || targets[0].count != 4 || targets[1].count != 0) return 1;
    targets[0].count = targets[1].count = 0;
    result = wct_heap_inventory(&inventory);
    printf("after_free=%llu\n", (unsigned long long)targets[0].count);
    return result != KERN_SUCCESS || targets[0].count != 0;
}
