#import "Server.h"
#import "NativeOperation.h"
#include <pthread.h>

static WCTBridgeServer *activeServer;
extern "C" int wct_bridge_start(const char *tokenPath,unsigned short port) {
    if(!pthread_main_np() || activeServer || !tokenPath) return 0;
    NSString *path=[NSString stringWithUTF8String:tokenPath];
    if(!path) return 0;
    WCTBridgeServer *server=[[WCTBridgeServer alloc] initWithTokenPath:path port:port
        operation:^NSDictionary *(NSString *operation,NSDictionary *arguments,WCTOperationContext *context) {
            return WCTNativeOperation(operation,arguments,context);
        }];
    if(![server start:nil]) return 0;
    activeServer=server;
    return server.port;
}
extern "C" void wct_bridge_stop(void) {
    if(!pthread_main_np()) return;
    [activeServer stop];activeServer=nil;
}

// Loading a research dylib alone must not write to the user's home directory.
// The transactional installer places this marker beside the installed payload.
__attribute__((constructor)) static void loadBridge(void) {
    dispatch_async(dispatch_get_main_queue(),^{ @autoreleasepool {
        NSBundle *bundle=[NSBundle mainBundle];
        if(![bundle.bundleIdentifier isEqual:@"com.tencent.xinWeChat"] ||
           ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"269602"]) return;
        NSString *marker=[bundle.bundlePath stringByAppendingPathComponent:@"Contents/Resources/WeChatTweak.enabled"];
        if(![[NSFileManager defaultManager] fileExistsAtPath:marker]) return;
        NSString *token=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/WeChatTweak/bridge-token"];
        wct_bridge_start(token.fileSystemRepresentation,48065);
    }});
}
