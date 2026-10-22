#import "Server.h"
#import "Credentials.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
#include <atomic>
#include <memory>
#include <time.h>

namespace {
static char acceptQueueKey;
static double monotonic() {timespec t={};clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static WCTHTTPReply *failed(NSInteger status,NSString *code) {
    WCTHTTPReply *reply=[WCTHTTPReply new];reply.status=status;
    reply.body=@{@"ok":@NO,@"error":@{@"code":code,@"message":@"WeChat bridge request failed."}};return reply;
}
struct State {
    std::atomic<int> fd{-1},active{0};
    std::atomic<bool> stopped{false};
    bool attempted=false;
    uint16_t port=0;
    NSString *path;
    NSString *token;
    WCTBridgeOperation operation;
    NSMutableSet<WCTOperationContext *> *contexts=[NSMutableSet new];
    dispatch_queue_t acceptQueue=dispatch_queue_create("WeChatTweak.accept",DISPATCH_QUEUE_SERIAL);
};
struct Lease {
    std::shared_ptr<State> state;
    WCTOperationContext *context;
    ~Lease() { @autoreleasepool {
        @synchronized(state->contexts) {[state->contexts removeObject:context];}
        state->active.fetch_sub(1);
    }}
};
static void sendReply(int client,WCTHTTPReply *reply) {
    NSData *body=[NSJSONSerialization dataWithJSONObject:reply.body options:0 error:nil];
    if(!body || body.length>2*1024*1024) {
        reply=failed(500,@"invalid_native_response");
        body=[NSJSONSerialization dataWithJSONObject:reply.body options:0 error:nil];
    }
    NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %ld WeChatTweak\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n",(long)reply.status,(unsigned long)body.length];
    NSMutableData *response=[[header dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [response appendData:body];
    const char *bytes=(const char*)response.bytes;size_t sent=0;
    double deadline=monotonic()+1;
    while(sent<response.length && monotonic()<deadline) {
        ssize_t n=send(client,bytes+sent,response.length-sent,MSG_DONTWAIT);
        if(n>0) {sent+=n;continue;}
        if(n<0 && errno==EINTR) continue;
        if(n<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) {pollfd writable={client,POLLOUT,0};poll(&writable,1,50);continue;}
        break;
    }
}
}

@interface WCTReplyBox : NSObject
@property(atomic,strong) WCTHTTPReply *reply;
@end
@implementation WCTReplyBox
@end

static void serve(std::shared_ptr<Lease> lease,int client) {
    auto state=lease->state;WCTOperationContext *context=lease->context;
    NSMutableData *request=[NSMutableData data];
    WCTHTTPReply *response=nil;
    double headerDeadline=monotonic()+2;
    BOOL complete=NO;
    while(!context.expired && monotonic()<headerDeadline) {
        unsigned char buffer[1024];
        size_t capacity=MIN(sizeof(buffer),(size_t)(16385-request.length));
        ssize_t n=recv(client,buffer,capacity,0);
        if(n<0 && errno==EINTR) continue;
        if(n<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) continue;
        if(n<=0) break;
        [request appendBytes:buffer length:n];
        if(request.length>16384) {response=failed(413,@"request_too_large");break;}
        const char end[]={13,10,13,10};
        if([request rangeOfData:[NSData dataWithBytes:end length:4] options:0 range:NSMakeRange(0,request.length)].location!=NSNotFound) {complete=YES;break;}
    }
    if(!response && !complete) response=failed(context.expired?504:408,context.expired?@"operation_timeout":@"request_timeout");
    if(!response) {
        WCTReplyBox *box=[WCTReplyBox new];
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
            // Retain the lease until actual work completes, including a late
            // adapter. Timed-out sockets cannot free an unlimited work queue.
            auto retained=lease;
            @try {
                box.reply=context.expired?failed(504,@"operation_timeout"):
                    WCTHandleHTTP(request,state->token,state->operation,context);
            } @catch(NSException *exception) {
                (void)exception;box.reply=failed(500,@"native_failed");
            }
            dispatch_semaphore_signal(done);
        }});
        int64_t nanoseconds=(int64_t)(context.timeRemaining*NSEC_PER_SEC);
        if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,nanoseconds))) {
            context.cancelled=YES;response=failed(504,@"operation_timeout");
        } else response=box.reply?:failed(500,@"native_failed");
    }
    sendReply(client,response);close(client);
}

@implementation WCTBridgeServer {
    std::shared_ptr<State> _state;
}
- (instancetype)initWithTokenPath:(NSString *)path port:(uint16_t)port operation:(WCTBridgeOperation)operation {
    if((self=[super init])) {
        _state=std::make_shared<State>();_state->path=[path copy];_state->port=port;_state->operation=[operation copy];
        dispatch_queue_set_specific(_state->acceptQueue,&acceptQueueKey,_state.get(),nullptr);
    }
    return self;
}
- (uint16_t)port {return _state->port;}
- (BOOL)start:(NSError **)error {
    if(error) *error=nil;
    auto state=_state;
    if(state->attempted || !state->operation) {
        if(error) *error=[NSError errorWithDomain:@"WeChatTweak.Server" code:1 userInfo:nil];return NO;
    }
    state->attempted=true;
    int fd=socket(AF_INET,SOCK_STREAM,0),one=1;
    if(fd<0) {if(error) *error=[NSError errorWithDomain:@"WeChatTweak.Server" code:2 userInfo:nil];return NO;}
    setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    sockaddr_in address={};address.sin_family=AF_INET;address.sin_port=htons(state->port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(fd,(sockaddr*)&address,sizeof(address)) || listen(fd,8)) {
        close(fd);if(error) *error=[NSError errorWithDomain:@"WeChatTweak.Server" code:3 userInfo:nil];return NO;
    }
    fcntl(fd,F_SETFD,FD_CLOEXEC);fcntl(fd,F_SETFL,O_NONBLOCK);
    state->token=WCTLoadOrCreateToken(state->path,error);
    if(!state->token) {close(fd);return NO;}
    socklen_t length=sizeof(address);
    if(getsockname(fd,(sockaddr*)&address,&length)) {
        close(fd);if(error) *error=[NSError errorWithDomain:@"WeChatTweak.Server" code:2 userInfo:nil];return NO;
    }
    state->port=ntohs(address.sin_port);state->fd.store(fd);
    dispatch_async(state->acceptQueue,^{ @autoreleasepool {
        while(!state->stopped.load()) {
            pollfd waiting={fd,POLLIN,0};
            if(poll(&waiting,1,100)<=0 || state->stopped.load()) continue;
            int client=accept(fd,nullptr,nullptr);
            if(client<0) continue;
            int flags=fcntl(client,F_GETFL,0);
            if(flags<0 || fcntl(client,F_SETFL,flags&~O_NONBLOCK)<0) {close(client);continue;}
            fcntl(client,F_SETFD,FD_CLOEXEC);
            int ignore=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&ignore,sizeof(ignore));
            timeval timeout={0,200000};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
            if(state->active.fetch_add(1)>=8) {
                state->active.fetch_sub(1);sendReply(client,failed(503,@"bridge_busy"));close(client);continue;
            }
            auto lease=std::make_shared<Lease>();lease->state=state;
            lease->context=[[WCTOperationContext alloc] initWithTimeout:5];
            @synchronized(state->contexts) {
                if(state->stopped.load()) lease->context.cancelled=YES;
                [state->contexts addObject:lease->context];
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {serve(lease,client);} });
        }
        int owned=state->fd.exchange(-1);if(owned>=0) close(owned);
    }});
    return YES;
}
- (void)stop {
    auto state=_state;
    if(!state) return;
    state->stopped.store(true);
    @synchronized(state->contexts) {for(WCTOperationContext *context in state->contexts) context.cancelled=YES;}
    int fd=state->fd.load();if(fd>=0) shutdown(fd,SHUT_RDWR);
    // The accept loop owns close(). Waiting only for that loop prevents a new
    // server reusing its descriptor while the old loop might still accept on it.
    if(fd>=0 && dispatch_get_specific(&acceptQueueKey)!=state.get()) dispatch_sync(state->acceptQueue,^{});
}
- (void)dealloc {[self stop];}
@end
