#include "heap_inventory.h"
#include <stdio.h>
#include <stdlib.h>

static uintptr_t custom_zone_marker = 0x4321;
static size_t custom_size(malloc_zone_t *zone, const void *ptr) {
    (void)zone; (void)ptr; return 0;
}
static void custom_lock(malloc_zone_t *zone) { (void)zone; }
static kern_return_t custom_enumerate(task_t task, void *context, unsigned mask,
                                      vm_address_t zone, memory_reader_t reader,
                                      vm_range_recorder_t recorder) {
    (void)context; (void)mask; (void)zone; (void)recorder;
    // Framework zones such as caulk require a real memory-reader callback.
    if (!reader) return KERN_INVALID_ARGUMENT;
    void *local = NULL;
    kern_return_t result = reader(task, (vm_address_t)&custom_zone_marker,
                                 sizeof(custom_zone_marker), &local);
    return result == KERN_SUCCESS && local == &custom_zone_marker ? KERN_SUCCESS : KERN_FAILURE;
}

int main(void) {
    static malloc_introspection_t custom_api = {
        .enumerator = custom_enumerate, .force_lock = custom_lock, .force_unlock = custom_lock
    };
    static malloc_zone_t custom_zone = {
        .size = custom_size, .zone_name = "WCTReaderRequiredFixture", .version = 4,
        .introspect = &custom_api
    };
    malloc_zone_register(&custom_zone);
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
    WCTHeapTarget targets[] = {{(uintptr_t)fake_vtable, "fixture", 0, 0},
                               {(uintptr_t)absent_vtable, "absent", 0, 0}};
    WCTHeapInventory inventory = {targets, 2, 0, 0};
    kern_return_t result = wct_heap_inventory(&inventory);
    printf("result=%d fixture=%llu absent=%llu failed_zones=%u\n", result,
           (unsigned long long)targets[0].count,
           (unsigned long long)targets[1].count, inventory.failed_zones);
    uintptr_t first = targets[0].first_candidate;
    if (first != (uintptr_t)objects[0] && first != (uintptr_t)objects[1] &&
        first != (uintptr_t)objects[2] && first != (uintptr_t)(shared+3)) return 1;
    if (targets[1].first_candidate) return 1;
    for (unsigned i = 0; i < 3; ++i) free(objects[i]);
    free(shared);
    if (result != KERN_SUCCESS || targets[0].count != 4 || targets[1].count != 0 || inventory.failed_zones) return 1;
    targets[0].count = targets[1].count = 0;
    targets[0].first_candidate = targets[1].first_candidate = 0;
    result = wct_heap_inventory(&inventory);
    malloc_zone_unregister(&custom_zone);
    printf("after_free=%llu\n", (unsigned long long)targets[0].count);
    return result != KERN_SUCCESS || targets[0].count != 0 || targets[0].first_candidate != 0;
}
