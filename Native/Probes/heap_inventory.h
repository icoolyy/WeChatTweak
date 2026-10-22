// Research only. Never invokes a method or retains an object found on the heap.
#pragma once
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <malloc/malloc.h>
#include <stdint.h>

typedef struct {
    uintptr_t vtable;
    const char *name;
    uint64_t count;
    uintptr_t first_candidate; // Observation only; never dereferenced or retained here.
} WCTHeapTarget;

typedef struct {
    WCTHeapTarget *targets;
    unsigned count;
    uint64_t ranges;
    unsigned failed_zones;
} WCTHeapInventory;

static kern_return_t wct_local_reader(task_t task, vm_address_t address,
                                       vm_size_t size, void **local) {
    (void)size;
    if (task != mach_task_self()) return KERN_INVALID_ARGUMENT;
    *local = (void *)address;
    return KERN_SUCCESS;
}

static void wct_record_ranges(task_t task, void *context, unsigned type,
                              vm_range_t *ranges, unsigned count) {
    WCTHeapInventory *inventory = context;
    if (type != MALLOC_PTR_IN_USE_RANGE_TYPE) return;
    for (unsigned i = 0; i < count; ++i) {
        if (ranges[i].size < sizeof(uintptr_t)) continue;
        uintptr_t prefix[8] = {0};
        mach_vm_size_t length = ranges[i].size < sizeof(prefix) ? ranges[i].size : sizeof(prefix);
        mach_vm_size_t copied = 0;
        // No malloc, stdio or object calls while a zone is locked. A concurrent
        // object destruction can change the value; results are observations only.
        if (mach_vm_read_overwrite(task, ranges[i].address, length,
                                  (mach_vm_address_t)prefix, &copied) != KERN_SUCCESS ||
            copied != length) continue;
        ++inventory->ranges;
        for (unsigned j = 0; j < inventory->count; ++j) {
            for (unsigned k = 0; k < length / sizeof(uintptr_t); ++k) {
                if (prefix[k] != inventory->targets[j].vtable) continue;
                ++inventory->targets[j].count;
                if (!inventory->targets[j].first_candidate)
                    inventory->targets[j].first_candidate = ranges[i].address + k * sizeof(uintptr_t);
                break; // Count an allocation once for each target, not each word.
            }
        }
    }
}

static kern_return_t wct_heap_inventory(WCTHeapInventory *inventory) {
    vm_address_t *zones = NULL;
    unsigned count = 0;
    task_t task = mach_task_self();
    kern_return_t result = malloc_get_all_zones(task, wct_local_reader, &zones, &count);
    if (result != KERN_SUCCESS) return result;
    for (unsigned i = 0; i < count; ++i) {
        malloc_zone_t *zone = (malloc_zone_t *)zones[i];
        const malloc_introspection_t *api = zone->introspect;
        if (!api || !api->enumerator || !api->force_lock || !api->force_unlock) {
            ++inventory->failed_zones;
            continue;
        }
        api->force_lock(zone);
        result = api->enumerator(task, inventory, MALLOC_PTR_IN_USE_RANGE_TYPE,
                                 zones[i], wct_local_reader, wct_record_ranges);
        api->force_unlock(zone);
        if (result != KERN_SUCCESS) ++inventory->failed_zones;
    }
    return KERN_SUCCESS;
}
