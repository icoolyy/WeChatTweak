#import "AvatarStore.h"
#include <stdio.h>
static unsigned failures;
static void check(BOOL v,const char*n){if(!v){++failures;fprintf(stderr,"FAIL: %s\n",n);}}
static void pump(){for(unsigned i=0;i<5;++i)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];}
int main(){@autoreleasepool{
 NSMutableArray *resolves=[NSMutableArray new],*predicates=[NSMutableArray new],*downloads=[NSMutableArray new];__block unsigned cancelled=0,fetches=0;
 WCTAvatarStore *store=[[WCTAvatarStore alloc] initWithResolver:^(NSString *identifier,BOOL (^current)(void),void (^completion)(NSString *)){(void)identifier;[resolves addObject:[completion copy]];[predicates addObject:[current copy]];} fetch:^id(NSURL *url,void (^completion)(NSData *)){(void)url;++fetches;[downloads addObject:[completion copy]];return [NSObject new];} cancel:^(id handle){(void)handle;++cancelled;}];
 [store activate:@"e1"];[store allow:[NSSet setWithArray:@[@"a",@"b",@"c",@"d",@"e"]] epoch:@"e1"];
 check(![store request:@"unknown"],"only emitted search IDs can request external avatars");
 for(NSString *key in @[@"a",@"b",@"c",@"d"])check([store request:key],"four slots accepted");
 check(resolves.count==4 && ![store request:@"e"],"resolver and download share four slots");
 check([store request:@"a"] && resolves.count==4,"same contact is deduplicated");
 if(resolves.count<4)return 1;
 ((void(^)(NSString*))resolves[0])(@"https://wx.qlogo.cn/fixture");
 ((void(^)(NSString*))resolves[0])(@"https://wx.qlogo.cn/fixture");pump();
 check(fetches==1 && ![store request:@"e"],"slot retained until download completes");
 ((void(^)(NSData*))downloads[0])([NSData dataWithBytes:"x" length:1]);pump();
 check([store image:@"a"].length==1 && ![store pending:@"a"],"completed image cached");
 check([store request:@"e"],"completed slot becomes available");
 [store allow:[NSSet setWithObject:@"b"] epoch:@"e1"];
 check(((BOOL(^)(void))predicates[1])(),"remaining result keeps permission");
 check(!((BOOL(^)(void))predicates[2])(),"removed search result cancels queued resolver");
 ((void(^)(NSString*))resolves[1])(@"https://wx.qlogo.cn/fixture");pump();
 [store activate:@"e2"];check(cancelled==1 && [store image:@"a"]==nil,"epoch clears cache and cancels download");
 check([store image:@"b"]==nil,"epoch clears in-flight contact cache");
 [store allow:[NSSet setWithObject:@"z"] epoch:@"e2"];
 check(![store request:@"z"] && [store pending:@"z"],"full stale slots remain retryable for new query");
 ((void(^)(NSString*))resolves[2])(@"https://wx.qlogo.cn/fixture");pump();check(fetches==2,"stale resolver cannot start network");
 check([store request:@"z"],"retry proceeds after stale slot clears");
 [store allow:[NSSet set] epoch:@"e2"];[store allow:[NSSet setWithObject:@"z"] epoch:@"e2"];
 ((void(^)(NSString*))resolves.lastObject)(nil);pump();
 check([store request:@"z"],"cancel-only attempt does not impose failed download cooldown");
 ((void(^)(NSData*))downloads[1])([NSData dataWithBytes:"x" length:1]);pump();check([store image:@"b"]==nil,"late old epoch result cannot enter new cache");
 NSMutableArray *ids=[NSMutableArray new];for(unsigned i=0;i<80;++i)[ids addObject:[NSString stringWithFormat:@"fixture-%u",i]];
 WCTAvatarStore *bounded=[[WCTAvatarStore alloc] initWithResolver:^(NSString *identifier,BOOL (^current)(void),void (^completion)(NSString*)){(void)identifier;completion(current()?@"https://wx.qlogo.cn/fixture":nil);} fetch:^id(NSURL *url,void (^completion)(NSData*)){(void)url;completion([NSData dataWithBytes:"x" length:1]);return [NSObject new];} cancel:^(id handle){(void)handle;}];
 [bounded activate:@"bounded"];[bounded allow:[NSSet setWithArray:ids] epoch:@"bounded"];
 for(NSString *identifier in ids){[bounded request:identifier];pump();}
 check([bounded image:ids[0]]==nil && [bounded image:ids[16]]!=nil && [bounded image:ids[79]]!=nil,"LRU retains at most64 images");
 WCTAvatarStore *byteBounded=[[WCTAvatarStore alloc] initWithResolver:^(NSString *identifier,BOOL (^current)(void),void (^completion)(NSString*)){(void)identifier;completion(current()?@"https://wx.qlogo.cn/fixture":nil);} fetch:^id(NSURL *url,void (^completion)(NSData*)){(void)url;completion([NSMutableData dataWithLength:128*1024]);return [NSObject new];} cancel:^(id handle){(void)handle;}];
 [byteBounded activate:@"bytes"];[byteBounded allow:[NSSet setWithArray:ids] epoch:@"bytes"];
 for(unsigned i=0;i<40;++i){[byteBounded request:ids[i]];pump();}
 check([byteBounded image:ids[0]]==nil && [byteBounded image:ids[8]]!=nil && [byteBounded image:ids[39]].length==128*1024,"cache also enforces4MiB byte limit");
 printf("avatar store failures=%u\n",failures);return failures?1:0;
}}
