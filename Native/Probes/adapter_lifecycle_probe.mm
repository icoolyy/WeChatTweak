// Temporary-copy only: record an account-free native health snapshot before login.
#include "../269602/Adapter.h"
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void capture(void *context) {
    int fd=(int)(intptr_t)context;
    char *health=wct_native_health_json();
    if(health) {dprintf(fd,"%s\n",health);wct_native_free(health);}
    close(fd);
}
__attribute__((constructor)) static void start(void) {
    const char *path=getenv("WCT_LIFECYCLE_OUTPUT");
    if(!path || path[0]!='/') return;
    int fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0) return;
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,10LL*NSEC_PER_SEC),
        dispatch_get_main_queue(),(void*)(intptr_t)fd,capture);
}
