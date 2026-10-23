#import <Foundation/Foundation.h>
#import "Adapter.h"
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string>

static unsigned failures;
static NSDictionary *decode(char *raw) {
    if(!raw) return nil;
    NSData *data=[[NSString stringWithUTF8String:raw] dataUsingEncoding:NSUTF8StringEncoding];
    wct_native_free(raw);
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
static void check(BOOL condition,const char *name) {
    if(!condition) {++failures;fprintf(stderr,"FAIL: %s\n",name);}
}
static BOOL code(NSDictionary *response,NSString *value) {
    return [response[@"error"][@"code"] isEqual:value];
}
int main(void) { @autoreleasepool {
    NSDictionary *health=decode(wct_native_health_json());
    check([health[@"state"] isEqual:@"unsupported"],"missing module health unavailable");
    check([health[@"capabilities"][@"contacts"] isEqual:@NO],"missing module has no contact capability");
    check(code(decode(wct_native_search_json("filehelper",1,1)),@"unsupported_build"),"missing module search rejected");
    check(code(decode(wct_native_search_json(NULL,1,1)),@"invalid_query"),"null query rejected");
    check(code(decode(wct_native_search_json(std::string(1025,'x').c_str(),1,1)),@"invalid_query"),"oversized UTF-8 input rejected");
    const char bad[]={char(0xff),0};
    check(code(decode(wct_native_search_json(bad,1,1)),@"invalid_query"),"malformed UTF-8 rejected");
    check(code(decode(wct_native_search_json("",2,1)),@"invalid_query"),"invalid boolean option rejected");
    check(code(decode(wct_native_request_open_json("")),@"invalid_query"),"empty contact ID rejected");
    check(code(decode(wct_native_request_open_json("filehelper")),@"unsupported_build"),"open fails closed without target");
    check(wct_native_selected_id()==NULL,"no stale selected ID without target");
    check(code(decode(wct_native_avatar_json("filehelper","epoch")),@"unsupported_build"),"avatar fails closed without target");
    check(code(decode(wct_native_avatar_json(NULL,"epoch")),@"invalid_query"),"avatar rejects missing contact");
    check(code(decode(wct_native_avatar_json("filehelper","")),@"invalid_query"),"avatar requires epoch");
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
        check(code(decode(wct_native_search_json("",1,1)),@"wrong_thread"),"off-main search rejected");
        dispatch_semaphore_signal(done);
    }});
    dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
    wct_native_free(NULL);
    printf("native adapter failures=%u\n",failures);
    return failures?1:0;
} }
