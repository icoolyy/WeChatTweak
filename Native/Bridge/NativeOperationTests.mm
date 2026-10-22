#import "NativeOperation.h"
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

static unsigned failures=0, calls=0, opens=0;
static bool changed=false, selected=false;
static void check(bool value,const char *name) {if(!value){++failures;fprintf(stderr,"FAIL: %s\n",name);}}
extern "C" char *wct_native_health_json(void) {
    check([NSThread isMainThread],"health main thread");++calls;
    return strdup(changed?"{\"session\":\"epoch2\",\"state\":\"ready\"}":"{\"session\":\"epoch1\",\"state\":\"ready\"}");
}
extern "C" char *wct_native_search_json(const char *,int,int) {
    check([NSThread isMainThread],"search main thread");++calls;
    return strdup("{\"ok\":true,\"items\":[]}");
}
extern "C" char *wct_native_request_open_json(const char *) {
    check([NSThread isMainThread],"open main thread");++calls;++opens;
    return strdup("{\"ok\":true,\"requested\":true}");
}
extern "C" char *wct_native_selected_id(void) {check([NSThread isMainThread],"selection main thread");return selected?strdup("filehelper"):nullptr;}
extern "C" void wct_native_free(void *value) {free(value);}

int main() { @autoreleasepool {
    dispatch_async(dispatch_get_main_queue(),^{usleep(250000);});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ @autoreleasepool {
        NSDictionary *args=@{@"id":@"filehelper",@"expectedSession":@"epoch1"};
        check([WCTNativeOperation(@"health",@{},[[WCTOperationContext alloc] initWithTimeout:0.05])[@"error"][@"code"] isEqual:@"operation_timeout"],"queued request times out");
        for(unsigned i=0;i<7;++i)
            check([WCTNativeOperation(@"health",@{},[[WCTOperationContext alloc] initWithTimeout:0.01])[@"error"][@"code"] isEqual:@"operation_timeout"],"bounded queued request expires");
        check([WCTNativeOperation(@"health",@{},[[WCTOperationContext alloc] initWithTimeout:0.01])[@"error"][@"code"] isEqual:@"native_busy"],"queued work retains all eight slots after network timeout");
        dispatch_sync(dispatch_get_main_queue(),^{});
        check(calls==0,"cancelled queued work never calls native");
        WCTOperationContext *expired=[[WCTOperationContext alloc] initWithTimeout:0];
        check([WCTNativeOperation(@"health",@{},expired)[@"error"][@"code"] isEqual:@"operation_timeout"],"expired request");
        check(calls==0,"expired work skipped");
        WCTOperationContext *shortWait=[[WCTOperationContext alloc] initWithTimeout:0.15];
        check([WCTNativeOperation(@"open",args,shortWait)[@"error"][@"code"] isEqual:@"operation_timeout"],"requested is not confirmation");
        selected=true;
        check([WCTNativeOperation(@"open",args,[[WCTOperationContext alloc] initWithTimeout:1])[@"confirmed"] isEqual:@YES],"confirmed selection");
        changed=true;
        unsigned before=opens;
        check([WCTNativeOperation(@"open",args,[[WCTOperationContext alloc] initWithTimeout:1])[@"error"][@"code"] isEqual:@"stale_session"],"stale epoch");
        check(opens==before,"stale epoch cannot open");
        printf("Native operation tests: %u failures\n",failures);exit(failures?1:0);
    }});
    // AppKit drives the real main thread through CFRunLoop. dispatch_main()
    // may retire that thread in command-line hosts, unlike a GUI application.
    CFRunLoopRun();
} }
