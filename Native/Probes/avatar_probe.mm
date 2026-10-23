// Temporary-copy-only acceptance probe. No names, IDs, paths or image bytes in output.
#import <Foundation/Foundation.h>
#include "../269602/Adapter.h"
#include <fcntl.h>
#include <unistd.h>
static NSDictionary *decode(char *raw){if(!raw)return nil;NSData *d=[NSData dataWithBytes:raw length:strlen(raw)];wct_native_free(raw);return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];}
static int output=-1;
static void capture(void *){@autoreleasepool{
    NSDictionary *health=decode(wct_native_health_json());
    if(![health[@"state"] isEqual:@"ready"]){dprintf(output,"ready=0\n");return;}
    NSDictionary *results=decode(wct_native_search_json("",1,1));unsigned attempted=0,available=0,invalid=0;
    for(NSDictionary *contact in results[@"items"]){
        NSDictionary *avatar=decode(wct_native_avatar_json([contact[@"id"] UTF8String],[results[@"session"] UTF8String]));
        ++attempted;if([avatar[@"ok"] isEqual:@YES])++available;
        else if([avatar[@"error"][@"code"] isEqual:@"invalid_native_layout"])++invalid;
        if(attempted>=25)break;
    }
    dprintf(output,"ready=1 native_avatar_capability=%d sampled=%u available=%u invalid_layout=%u\n",[health[@"capabilities"][@"avatars"] isEqual:@YES],attempted,available,invalid);
}}
static void initialize(void *){@autoreleasepool{
    NSString *bundle=NSBundle.mainBundle.bundlePath;
    if(![bundle hasPrefix:@"/private/tmp/wechattweak-runtime-inventory/"] && ![bundle hasPrefix:@"/tmp/wechattweak-runtime-inventory/"])return;
    NSString *path=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/avatar-probe-%d.log",getpid()];
    output=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(output<0)return;
    for(int i=1;i<=12;++i)dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,(int64_t)i*15*NSEC_PER_SEC),dispatch_get_main_queue(),nullptr,capture);
}}
__attribute__((constructor)) static void start(){dispatch_async_f(dispatch_get_main_queue(),nullptr,initialize);}
