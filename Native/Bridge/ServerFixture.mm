// Test-only executable. Never included in the production dylib source list.
#import "Server.h"
#include <dispatch/dispatch.h>
#include <unistd.h>
#include <stdio.h>
#include <signal.h>

static dispatch_source_t stopSignal;

int main(int argc,char **argv) { @autoreleasepool {
    if(argc<2) return 64;
    NSString *path=[NSString stringWithUTF8String:argv[1]];
    unsigned port=argc>2?(unsigned)strtoul(argv[2],nullptr,10):0;
    NSString *epoch=[NSString stringWithFormat:@"fixture-%d",getpid()];
    WCTBridgeOperation fixture=^NSDictionary*(NSString *operation,NSDictionary *arguments,WCTOperationContext *context) {
        if([operation isEqual:@"health"]) return @{@"state":@"ready",@"build":@"269602",@"session":epoch,
            @"contactsSource":@"loadedContacts",@"capabilities":@{@"contacts":@YES,@"openChat":@YES}};
        if([operation isEqual:@"avatar"]) {
            if(![arguments[@"expectedSession"] isEqual:epoch])return @{@"error":@{@"code":@"stale_session"}};
            if(![arguments[@"id"] isEqual:@"fixture_0"])return @{@"error":@{@"code":@"avatar_not_found"}};
            return @{@"ok":@YES,@"id":@"fixture_0",@"session":epoch,@"mime":@"image/png",@"data":@"aGVsbG8=",@"digest":[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]};
        }
        if([operation isEqual:@"open"]) {
            if(![arguments[@"expectedSession"] isEqual:epoch]) return @{@"error":@{@"code":@"stale_session"}};
            return @{@"ok":@YES,@"confirmed":@YES};
        }
        if([arguments[@"keyword"] isEqual:@"timeout"]) usleep(6000000);
        if(context.expired) return @{@"error":@{@"code":@"operation_timeout"}};
        NSMutableArray *items=[NSMutableArray array];
        unsigned count=[arguments[@"keyword"] isEqual:@"many"]?150:1;
        for(unsigned i=0;i<count;++i) [items addObject:@{@"title":@"Fixture",@"arg":[NSString stringWithFormat:@"fixture_%u",i]}];
        return @{@"ok":@YES,@"session":epoch,@"source":@"loadedContacts",@"items":items};
    };
    WCTBridgeServer *server=[[WCTBridgeServer alloc] initWithTokenPath:path port:(uint16_t)port operation:fixture];
    NSError *error=nil;
    if(![server start:&error]) {fprintf(stderr,"fixture_start_failed=%ld\n",(long)error.code);return 1;}
    printf("port=%u\n",server.port);fflush(stdout);
    signal(SIGTERM,SIG_IGN);
    stopSignal=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
    dispatch_source_set_event_handler(stopSignal,^{[server stop];exit(0);});
    dispatch_resume(stopSignal);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60LL*NSEC_PER_SEC),dispatch_get_main_queue(),^{[server stop];exit(0);});
    dispatch_main();
} }
