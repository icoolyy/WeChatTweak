#import "Adapter.h"
#import "ContactCache.h"
#import "ContactSearch.h"
#include "Runtime.h"
#include "NativeMutex.h"
#include <pthread.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

namespace {
enum Status { Ready, WrongThread, Unsupported, LoggedOut, Busy, BadLayout, NotReady };
static NSString *code(Status status) {
    switch(status) {
        case WrongThread:return @"wrong_thread";
        case Unsupported:return @"unsupported_build";
        case LoggedOut:return @"not_logged_in";
        case Busy:return @"native_busy";
        case BadLayout:return @"invalid_native_layout";
        case NotReady:return @"not_ready";
        case Ready:return @"ready";
    }
}
static char *json(id object) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if(!data) return strdup("{\"ok\":false,\"error\":{\"code\":\"serialization_failed\"}}");
    char *result=(char*)malloc(data.length+1);
    if(!result) return NULL;
    memcpy(result,data.bytes,data.length);result[data.length]=0;return result;
}
static char *failure(NSString *value) {
    return json(@{@"ok":@NO,@"error":@{@"code":value,@"message":@"WeChat native operation is unavailable."}});
}
static NSString *input(const char *raw,BOOL allowEmpty) {
    if(!raw) return nil;
    size_t length=strnlen(raw,1025);
    if(length>1024 || (!allowEmpty && !length)) return nil;
    return [[NSString alloc] initWithBytes:raw length:length encoding:NSUTF8StringEncoding];
}
static Status lockStatus(WCTLockResult value) {
    return value==WCTLockAcquired ? Ready : (value==WCTLockBusy ? Busy:BadLayout);
}
struct Source {
    Status status=Unsupported;
    uintptr_t base=0,state=0,storage=0;
    WCTNativeMutex registryLock,cacheLock;
    Source() {
        if(!pthread_main_np()) {status=WrongThread;return;}
        base=wct_269602_module_base();
        if(!base) return;
        state=WCTLoginState(base);
        if(!state) {status=LoggedOut;return;}
        uintptr_t manager=WCTReadPointer(base+0x9e66158);
        if(!manager || WCTReadPointer(manager)!=base+0x98c53d0) {status=NotReady;return;}
        uintptr_t account=WCTReadPointer(manager+0x68);
        if(!account || WCTReadPointer(account)!=base+0x98ba858) {status=NotReady;return;}
        uintptr_t factory=WCTReadPointer(account+0x368);
        if(!factory || WCTReadPointer(factory)!=base+0x98b87f8) {status=NotReady;return;}
        status=lockStatus(registryLock.acquire(factory+0x30));
        if(status!=Ready) return;
        uint64_t declared=WCTReadPointer(factory+0x88);
        if(declared>4096) {status=BadLayout;return;}
        uintptr_t node=WCTReadPointer(factory+0x80);
        NSMutableSet *seen=[NSMutableSet set];
        unsigned matches=0;
        while(node) {
            if(seen.count>=declared || [seen containsObject:@(node)] || node>UINTPTR_MAX-0x38) {status=BadLayout;return;}
            [seen addObject:@(node)];
            uintptr_t value=WCTReadPointer(node+0x28);
            if(value && WCTReadPointer(value)==base+0x98b92d8) {storage=value;++matches;}
            node=WCTReadPointer(node);
        }
        if(seen.count!=declared || matches>1) {status=BadLayout;return;}
        if(!storage) {status=NotReady;return;}
        // Nonblocking acquisition avoids an inverse-lock-order deadlock. Hold
        // registry ownership until the copied snapshot no longer needs storage.
        status=lockStatus(cacheLock.acquire(storage+0x130));
        if(status!=Ready) return;
        uint64_t count=WCTReadPointer(storage+0xb0);
        if(!count) status=NotReady;
        if(count>30000) status=BadLayout;
    }
    NSArray *snapshot() {
        if(status!=Ready) return nil;
        NSError *error=nil;
        NSArray *value=WCTReadContactCache(storage,^BOOL(uintptr_t a,void *out,size_t n) {
            return WCTReadBytes(a,out,n);
        },&error);
        if(!value || error) status=BadLayout;
        return value;
    }
    void unlock() {cacheLock.release();registryLock.release();}
};
static NSString *session(Source &source) {
    static NSString *boot=[[NSUUID UUID] UUIDString];
    static uintptr_t previousState=0,previousStorage=0;
    static uint64_t generation=0;
    if(source.status!=Busy && (source.state!=previousState || source.storage!=previousStorage)) {
        previousState=source.state;previousStorage=source.storage;++generation;
    }
    return [NSString stringWithFormat:@"%@-%llu",boot,(unsigned long long)generation];
}
static BOOL hasID(NSArray *items,NSString *identifier) {
    for(NSDictionary *item in items) if([item[@"arg"] isEqual:identifier]) return YES;
    return NO;
}
}

char *wct_native_health_json(void) { @autoreleasepool {
    if(!pthread_main_np()) return json(@{@"state":@"wrong_thread",@"capabilities":@{@"contacts":@NO,@"openChat":@NO}});
    Source source;
    BOOL ready=source.status==Ready;
    return json(@{@"state":source.status==Unsupported?@"unsupported":code(source.status),
        @"session":session(source),@"build":@"269602",@"contactsSource":@"loadedContacts",
        @"capabilities":@{@"contacts":@(ready),@"openChat":@(ready && WCTViewModel(source.base)!=0)}});
} }

char *wct_native_search_json(const char *raw,int pinyin,int fuzzy) { @autoreleasepool {
    if(!pthread_main_np()) return failure(@"wrong_thread");
    NSString *keyword=input(raw,YES);
    if(!keyword || (pinyin!=0 && pinyin!=1) || (fuzzy!=0 && fuzzy!=1)) return failure(@"invalid_query");
    Source source;
    if(source.status!=Ready) return failure(code(source.status));
    NSArray *contacts=source.snapshot();
    if(!contacts) return failure(code(source.status));
    // All strings are copied before releasing native ownership/locks. Matching
    // and JSON serialization never hold a native object reference.
    NSString *generation=session(source);
    source.unlock();
    return json(@{@"ok":@YES,@"source":@"loadedContacts",@"session":generation,
        @"items":WCTSearchContacts(contacts,keyword,pinyin!=0,fuzzy!=0,100)});
} }

char *wct_native_request_open_json(const char *raw) { @autoreleasepool {
    if(!pthread_main_np()) return failure(@"wrong_thread");
    NSString *identifier=input(raw,NO);
    if(!identifier || [identifier rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound)
        return failure(@"invalid_query");
    Source source;
    if(source.status!=Ready) return failure(code(source.status));
    NSArray *contacts=source.snapshot();
    if(!contacts) return failure(code(source.status));
    BOOL known=NO;
    for(NSDictionary *contact in contacts) if([contact[@"id"] isEqual:identifier]) {known=YES;break;}
    if(!known) return failure(@"contact_not_found");
    if(!WCTViewModel(source.base)) return failure(@"not_ready");
    static const unsigned char entry[]={0xff,0x83,0x01,0xd1,0xf6,0x57,0x03,0xa9,0xf4,0x4f,0x04,0xa9,0xfd,0x7b,0x05,0xa9,
        0xfd,0x43,0x01,0x91,0xf3,0x03,0x04,0xaa,0xf4,0x03,0x03,0xaa,0xf5,0x03,0x02,0xaa};
    if(memcmp((const void*)(source.base+0x296598),entry,sizeof(entry))) return failure(@"invalid_native_layout");
    NSString *generation=session(source);
    uintptr_t app=WCTReadPointer(source.base+0x9f2ffb0);
    if(!app || WCTReadPointer(app)!=source.base+0x95a38e0) return failure(@"invalid_native_layout");
    // Match the verified foreign const-string representation explicitly. Always
    // use its long form; the input bytes remain owned here until the native call
    // returns, and the native path copies them before any asynchronous work.
    const char *bytes=identifier.UTF8String;
    uint64_t key[3]={(uintptr_t)bytes,strlen(bytes),((uint64_t)1<<63)|(strlen(bytes)+1)};
    uintptr_t optional[2]={0,0};
    source.unlock(); // Native open may look up contacts; never call it with locks held.
    typedef void (*Open)(void*,const void*,const void*,uintptr_t,uintptr_t);
    ((Open)(source.base+0x296598))((void*)app,key,optional,0,0);
    return json(@{@"ok":@YES,@"requested":@YES,@"session":generation});
} }

char *wct_native_selected_id(void) { @autoreleasepool {
    if(!pthread_main_np()) return NULL;
    uintptr_t base=wct_269602_module_base();
    uintptr_t key=base?WCTSelectedKey(base):0;
    if(!key) return NULL;
    NSString *value=WCTReadNativeString(key,^BOOL(uintptr_t a,void *out,size_t n) {
        return WCTReadBytes(a,out,n);
    },nil);
    return value ? strdup(value.UTF8String):NULL;
} }
void wct_native_free(void *value) { free(value); }
int wct_native_probe_search_validation(void) { @autoreleasepool {
    Source source;
    NSArray *contacts=source.snapshot();
    if(!contacts) return 0;
    source.unlock();
    int result=0;
    if(hasID(WCTSearchContacts(contacts,@"文件传输助手",NO,NO,100),@"filehelper")) result|=1;
    if(hasID(WCTSearchContacts(contacts,@"wenjian",YES,YES,100),@"filehelper")) result|=2;
    if(hasID(WCTSearchContacts(contacts,@"WJCSZS",YES,NO,100),@"filehelper")) result|=4;
    for(NSDictionary *contact in contacts) {
        if([contact[@"remark"] length] && hasID(WCTSearchContacts(contacts,contact[@"remark"],NO,NO,100),contact[@"id"])) {
            result|=8;break;
        }
    }
    return result;
} }
