#import "AvatarStore.h"
#import "AvatarDownload.h"
#include <atomic>
#include <chrono>
@interface WCTAvatarPending : NSObject {
@public std::atomic<bool> current;
}
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,strong) id handle;
@property(nonatomic) BOOL resolved;
@end
@implementation WCTAvatarPending
- (instancetype)init {if((self=[super init]))current=true;return self;}
@end
@interface WCTAvatarStore ()
@property(nonatomic,copy) WCTAvatarResolve resolver;
@property(nonatomic,copy) WCTAvatarFetch fetch;
@property(nonatomic,copy) void (^cancel)(id);
@property(nonatomic,copy) NSString *epoch;
@property(nonatomic,copy) NSSet *allowed;
@property(nonatomic,strong) NSMutableSet<WCTAvatarPending*> *work;
@property(nonatomic,strong) NSMutableDictionary<NSString*,WCTAvatarPending*> *requests;
@property(nonatomic,strong) NSMutableDictionary<NSString*,NSNumber*> *attempts;
@property(nonatomic,strong) NSMutableDictionary<NSString*,NSData*> *images;
@property(nonatomic,strong) NSMutableArray<NSString*> *order;
@property(nonatomic) NSUInteger bytes;
@end
static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
@implementation WCTAvatarStore
- (instancetype)initWithResolver:(WCTAvatarResolve)resolver fetch:(WCTAvatarFetch)fetch cancel:(void (^)(id))cancel {
    if((self=[super init])){_resolver=[resolver copy];_fetch=[fetch copy];_cancel=[cancel copy];_work=[NSMutableSet new];_requests=[NSMutableDictionary new];_attempts=[NSMutableDictionary new];_images=[NSMutableDictionary new];_order=[NSMutableArray new];_allowed=[NSSet set];}return self;
}
- (void)activate:(NSString *)epoch {
    NSAssert(NSThread.isMainThread,@"main thread required");
    if([epoch isEqual:self.epoch])return;
    for(WCTAvatarPending *request in self.work){request->current=false;if(request.handle)self.cancel(request.handle);}
    [self.requests removeAllObjects];[self.attempts removeAllObjects];[self.images removeAllObjects];[self.order removeAllObjects];self.bytes=0;
    self.allowed=[NSSet set];self.epoch=[epoch copy];
    // Keep stale work's slots until its real resolver/download completion.
}
- (void)allow:(NSSet<NSString*> *)identifiers epoch:(NSString *)epoch {
    NSAssert(NSThread.isMainThread,@"main thread required");
    if(![epoch isEqual:self.epoch])return;
    self.allowed=[identifiers copy];
    for(WCTAvatarPending *request in self.work)if(![identifiers containsObject:request.identifier]){
        request->current=false;if(request.handle)self.cancel(request.handle);
        if(self.requests[request.identifier]==request){[self.requests removeObjectForKey:request.identifier];[self.attempts removeObjectForKey:request.identifier];}
    }
}
- (NSData *)image:(NSString *)identifier {
    NSAssert(NSThread.isMainThread,@"main thread required");
    NSData *image=self.images[identifier];if(image){[self.order removeObject:identifier];[self.order addObject:identifier];}return image;
}
- (BOOL)pending:(NSString *)identifier {
    NSAssert(NSThread.isMainThread,@"main thread required");
    WCTAvatarPending *request=self.requests[identifier];if(request)return request->current.load();
    // Capacity is temporary, including stale callbacks whose real completion
    // still owns a slot. Let the bridge retry rather than finalize a miss.
    return [self.allowed containsObject:identifier] && !self.images[identifier] && !self.attempts[identifier] && self.work.count>=4;
}
- (void)complete:(WCTAvatarPending *)request image:(NSData *)image {
    if(![self.work containsObject:request])return;
    [self.work removeObject:request];request.handle=nil;
    if(self.requests[request.identifier]==request)[self.requests removeObjectForKey:request.identifier];
    BOOL valid=request->current.exchange(false) && [self.allowed containsObject:request.identifier];
    if(!valid)return;
    if(!image.length || image.length>128*1024)return;
    [self.attempts removeObjectForKey:request.identifier];
    self.bytes-=self.images[request.identifier].length;
    self.images[request.identifier]=image;self.bytes+=image.length;
    [self.order removeObject:request.identifier];[self.order addObject:request.identifier];
    while(self.order.count>64 || self.bytes>4*1024*1024){NSString *old=self.order.firstObject;self.bytes-=self.images[old].length;[self.images removeObjectForKey:old];[self.order removeObjectAtIndex:0];}
}
- (BOOL)request:(NSString *)identifier {
    NSAssert(NSThread.isMainThread,@"main thread required");
    if(!self.epoch || ![self.allowed containsObject:identifier] || self.images[identifier])return NO;
    if(self.requests[identifier])return YES;
    double time=now();for(NSString *key in [self.attempts.allKeys copy])if(time-[self.attempts[key] doubleValue]>=30)[self.attempts removeObjectForKey:key];
    if(self.work.count>=4 || self.attempts.count>=128 || self.attempts[identifier])return NO;
    WCTAvatarPending *request=[WCTAvatarPending new];request.identifier=identifier;
    [self.work addObject:request];self.requests[identifier]=request;self.attempts[identifier]=@(time);
    self.resolver(identifier,^BOOL{return request->current.load();},^(NSString *nativeURL){
        dispatch_async(dispatch_get_main_queue(),^{
            if(![self.work containsObject:request] || request.resolved)return;
            request.resolved=YES;
            NSURL *url=WCTAvatarDownloadURL(nativeURL);
            if(!request->current || ![self.allowed containsObject:identifier] || !url){[self complete:request image:nil];return;}
            request.handle=self.fetch(url,^(NSData *image){dispatch_async(dispatch_get_main_queue(),^{[self complete:request image:image];});});
        });
    });return YES;
}
@end
