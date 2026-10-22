#import "NativeOperation.h"
#import "../269602/Adapter.h"
#include <dispatch/dispatch.h>
#include <unistd.h>

static NSDictionary *failure(NSString *code) {
    return @{@"ok":@NO,@"error":@{@"code":code}};
}

@interface WCTNativeReplyBox : NSObject
@property(atomic,copy) NSDictionary *value;
@end
@implementation WCTNativeReplyBox
@end

static NSDictionary *decode(char *raw) {
    if(!raw) return failure(@"native_failed");
    NSData *data=[NSData dataWithBytes:raw length:strlen(raw)];
    wct_native_free(raw);
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:[NSDictionary class]]?value:failure(@"native_failed");
}

static NSDictionary *onMain(WCTOperationContext *context,NSDictionary *(^work)(void)) {
    if(context.expired) return failure(@"operation_timeout");
    // Never wait on the queue that must execute the work.
    if([NSThread isMainThread]) return failure(@"wrong_thread");
    static dispatch_semaphore_t slots=dispatch_semaphore_create(8);
    // A timed-out request may still have a cancelled block queued behind a
    // modal/busy UI. Retain its slot until that actual block runs, not merely
    // until its network waiter returns, so queued native work stays bounded.
    if(dispatch_semaphore_wait(slots,DISPATCH_TIME_NOW)) return failure(@"native_busy");
    WCTNativeReplyBox *box=[WCTNativeReplyBox new];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(),^{ @autoreleasepool {
        if(!context.expired) {
            @try {box.value=work();}
            @catch(NSException *) {box.value=failure(@"native_failed");}
        }
        dispatch_semaphore_signal(slots);
        dispatch_semaphore_signal(done);
    }});
    long result=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(context.timeRemaining*NSEC_PER_SEC)));
    if(result || context.expired) {context.cancelled=YES;return failure(@"operation_timeout");}
    return box.value?:failure(@"native_failed");
}

NSDictionary *WCTNativeOperation(NSString *operation,NSDictionary *arguments,WCTOperationContext *context) {
    if([operation isEqual:@"health"])
        return onMain(context,^NSDictionary*{return decode(wct_native_health_json());});
    if([operation isEqual:@"search"])
        return onMain(context,^NSDictionary*{
            return decode(wct_native_search_json([arguments[@"keyword"] UTF8String],
                [arguments[@"pinyin"] boolValue],[arguments[@"fuzzy"] boolValue]));
        });
    if(![operation isEqual:@"open"]) return failure(@"invalid_query");
    NSString *identifier=arguments[@"id"],*expected=arguments[@"expectedSession"];
    NSDictionary *requested=onMain(context,^NSDictionary*{
        NSDictionary *health=decode(wct_native_health_json());
        if(![health[@"session"] isEqual:expected]) return failure(@"stale_session");
        return decode(wct_native_request_open_json(identifier.UTF8String));
    });
    if(![requested[@"ok"] isEqual:@YES]) return requested;
    while(!context.expired) {
        NSDictionary *checked=onMain(context,^NSDictionary*{
            NSDictionary *health=decode(wct_native_health_json());
            if(![health[@"session"] isEqual:expected]) return failure(@"stale_session");
            if(![health[@"state"] isEqual:@"ready"]) return failure(@"not_ready");
            char *raw=wct_native_selected_id();
            NSString *selected=raw?[NSString stringWithUTF8String:raw]:nil;
            wct_native_free(raw);
            return @{@"ok":@YES,@"confirmed":@([selected isEqual:identifier])};
        });
        if(![checked[@"ok"] isEqual:@YES] || [checked[@"confirmed"] isEqual:@YES]) return checked;
        usleep((useconds_t)(MIN(context.timeRemaining,0.05)*1000000));
    }
    return failure(@"operation_timeout");
}
