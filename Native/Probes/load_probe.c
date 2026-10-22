// Research-only: exits before WeChatMain. Never install in a normal WeChat launch.
// Reports loading and legacy Objective-C class availability without reading accounts.
#include <fcntl.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((constructor)) static void probe_loaded(void) {
    const char *marker = getenv("WCT_PROBE_MARKER");
    if (!marker) _exit(64);
    int fd = open(marker, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) _exit(65);
    dprintf(fd, "native_probe_loaded=1\n");
    const char *names[] = {"MMServiceCenter", "ContactStorage", "MMContactSearchLogic", "WCContactData"};
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); ++i)
        dprintf(fd, "%s=%d\n", names[i], objc_getClass(names[i]) != Nil);
    close(fd);
    _exit(0);
}
