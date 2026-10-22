#pragma once
#include <stdint.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static inline uintptr_t wct_269602_module_base(void) {
    static const unsigned char expected[16] = {
        0xcd,0xb8,0x10,0x58,0x0f,0xac,0x35,0x18,
        0x95,0xf5,0xc0,0xcc,0x78,0x60,0xf9,0xb5};
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "/Contents/Resources/wechat.dylib")) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) continue;
        const char *p = (const char *)(header + 1);
        const char *end = p + header->sizeofcmds;
        for (uint32_t j = 0; j < header->ncmds && p + sizeof(struct load_command) <= end; ++j) {
            const struct load_command *command = (const struct load_command *)p;
            if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end-p)) break;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *uuid = (const struct uuid_command *)p;
                if (!memcmp(uuid->uuid, expected, sizeof(expected))) return (uintptr_t)header;
            }
            p += command->cmdsize;
        }
    }
    return 0;
}
