// Research-only, fixed builtin target. Invocation is NOT confirmation of success.
// Call on the main thread of the authorized temporary copy, then verify the UI.
#include "module_269602.h"
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <pthread.h>

static uintptr_t read_pointer(uintptr_t address) {
    uintptr_t value = 0;
    mach_vm_size_t copied = 0;
    if (mach_vm_read_overwrite(mach_task_self(), address, sizeof(value),
                              (mach_vm_address_t)&value, &copied) != KERN_SUCCESS ||
        copied != sizeof(value)) return 0;
    return value;
}

int wct_probe_open_filehelper(void) {
    if (!pthread_main_np()) return -1;
    uintptr_t base = wct_269602_module_base();
    if (!base) return -2;
    static const unsigned char original[32] = {
        0xff,0x83,0x01,0xd1,0xf6,0x57,0x03,0xa9,0xf4,0x4f,0x04,0xa9,0xfd,0x7b,0x05,0xa9,
        0xfd,0x43,0x01,0x91,0xf3,0x03,0x04,0xaa,0xf4,0x03,0x03,0xaa,0xf5,0x03,0x02,0xaa};
    if (memcmp((const void *)(base+0x296598), original, sizeof(original))) return -3;
    uintptr_t application = read_pointer(base+0x9f2ffb0);
    if (!application || read_pointer(application) != base+0x95a38e0) return -4;
    // Both 0x170f234 and 0x296c40 prepare these arguments before calling 0x296598:
    // x0 WeChatApplication, x1 pointer to 24-byte libc++ string, x2 const shared_ptr
    // reference, x3/x4 zero. Callee copies the string/shared_ptr and returns void.
    // Match the observed short-string layout; don't pass an owning C++ object
    // across a potentially different toolchain ABI.
    struct { unsigned char bytes[24]; } key = {{0}};
    memcpy(key.bytes, "filehelper", 10);
    key.bytes[23] = 10;
    struct { uintptr_t object, control; } optional = {0,0};
    typedef void (*OpenChat)(void *, const void *, const void *, uintptr_t, uintptr_t);
    ((OpenChat)(base+0x296598))((void *)application, &key, &optional, 0, 0);
    return 1; // Only states that the native call returned. Not a bridge success.
}

int wct_probe_current_filehelper(void) {
    if (!pthread_main_np()) return -1;
    uintptr_t base = wct_269602_module_base();
    if (!base) return -2;
    // Read the same path as 0x2966e0 / 0x285424 / 0x110f39c / 0x9d4bb0.
    // Only LoginState owns the verified main-window/session layout.
    uintptr_t app = read_pointer(base+0x9f2ffb0);
    if (!app || read_pointer(app) != base+0x95a38e0) return -3;
    uintptr_t state_data = read_pointer(app+0x10);
    uintptr_t state = state_data ? read_pointer(state_data) : 0;
    if (!state || read_pointer(state) != base+0x95a36a0) return -3;
    uintptr_t window = read_pointer(state+0x28);
    if (!window || read_pointer(window) != base+0x9700e58) return -3;
    uintptr_t node = read_pointer(window+0x390), view = 0;
    for (unsigned i = 0; node && i < 256; ++i) {
        int32_t key = (int32_t)read_pointer(node+0x20);
        if (key == 0) { view = read_pointer(node+0x28); break; }
        node = read_pointer(node+(key < 0 ? 8 : 0));
    }
    if (!view || read_pointer(view) != base+0x95c1ca8) return -3;
    uintptr_t interface = read_pointer(view+0x168);
    if (interface < 16) return -3;
    uintptr_t object = interface-16;
    if (read_pointer(object) != base+0x95c3c60) return -3;
    // QObjectPrivate's back-pointer must refer to this object. This excludes
    // structures that merely happen to contain the candidate vtable address.
    uintptr_t data = read_pointer(object+8);
    if (!data || read_pointer(data+8) != object) return -4;
    // 0xa256e8 reads the selected session cell at *(model+0xf8)+0x40.
    // 0xa47f60 returns cell+0x148 and 0x1af10 returns that key unchanged.
    // model+0x1f0 is a pending request, not the selected session after completion.
    uintptr_t list = read_pointer(object+0xf8);
    uintptr_t cell = list ? read_pointer(list+0x40) : 0;
    if (!cell) return -6;
    uintptr_t cell_type = read_pointer(cell);
    if (cell_type != base+0x95c3d28 && cell_type != base+0x96b7a90) return -7;
    unsigned char value[24] = {0};
    mach_vm_size_t copied = 0;
    if (mach_vm_read_overwrite(mach_task_self(), cell+0x148, sizeof(value),
                              (mach_vm_address_t)value, &copied) != KERN_SUCCESS ||
        copied != sizeof(value)) return -5;
    if (!(value[23] & 128)) return value[23] == 10 && !memcmp(value, "filehelper", 10);
    uintptr_t address = 0, length = 0;
    memcpy(&address, value, 8);
    memcpy(&length, value+8, 8);
    if (length != 10) return 0;
    unsigned char bytes[10];
    if (mach_vm_read_overwrite(mach_task_self(), address, 10,
                              (mach_vm_address_t)bytes, &copied) != KERN_SUCCESS || copied != 10) return -5;
    return !memcmp(bytes, "filehelper", 10);
}
