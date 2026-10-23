#import "AvatarNative.h"
#import "AvatarFile.h"
#import "AvatarDownload.h"
#import "AvatarStore.h"
#import "ContactCache.h"
#include "Runtime.h"
#include <pthread.h>
#include "ForeignTask.h"
#include <atomic>
#include <chrono>

namespace {
// Nontrivial foreign std::string results use x8. Never pass a host libc++
// string object into WeChat's independently linked C++ runtime.
struct NativeString {uintptr_t words[3]={};~NativeString(){}};
static NSString *copyString(NativeString &value,uintptr_t base) {
    NSString *result=WCTReadNativeString((uintptr_t)&value,^BOOL(uintptr_t a,void *out,size_t n){return WCTReadBytes(a,out,n);},nil);
    ((void (*)(void*))(base+0x2afd8))(&value);memset(&value,0,sizeof(value));return result;
}
}
NSData *WCTReadNativeAvatarFile(uintptr_t base,NSString *identifier) {
    if(!pthread_main_np() || !base || base!=wct_269602_module_base() || !identifier.length ||
       [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>1024 ||
       [identifier rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    static const unsigned char pathEntry[]={0xfc,0x6f,0xbc,0xa9,0xf6,0x57,0x01,0xa9};
    if(memcmp((void*)(base+0x3cedc44),pathEntry,sizeof(pathEntry)))return nil;
    NativeString rootValue,pathValue;
    NSString *root=nil,*path=nil;
    try {
        int kind=14;
        rootValue=((NativeString (*)(void*,const int*))(base+0x42afe80))(nullptr,&kind);
        root=copyString(rootValue,base);
        if(!root.isAbsolutePath)return nil;
        const char *bytes=identifier.UTF8String;size_t length=strlen(bytes);
        uintptr_t key[3]={(uintptr_t)bytes,length,(1ULL<<63)|(length+1)};
        pathValue=((NativeString (*)(void*,const void*))(base+0x3cedc44))(nullptr,key);
        path=copyString(pathValue,base);
    } catch(...) {
        ((void (*)(void*))(base+0x2afd8))(&rootValue);
        ((void (*)(void*))(base+0x2afd8))(&pathValue);return nil;
    }
    return WCTReadAvatarFile(path,[root stringByAppendingPathComponent:@"head_image"]);
}

namespace {
struct ForeignPair {uintptr_t object=0,control=0;~ForeignPair(){}};
struct OwnedPair {
    uintptr_t base;ForeignPair value;
    explicit OwnedPair(uintptr_t b):base(b){}
    ~OwnedPair(){if(value.control)((void (*)(void*))(base+0x1312c8))(&value);}
};
struct ResolveReply {
    void (^completion)(NSString*);std::atomic<bool> delivered{false},started{false};
    explicit ResolveReply(void (^value)(NSString*)):completion([value copy]){}
    void finish(NSString *url){if(!delivered.exchange(true))completion(url);}
    ~ResolveReply(){finish(nil);}
};
static void resolveURL(NSString *identifier,BOOL (^current)(void),void (^completion)(NSString*)) {
    uintptr_t base=wct_269602_module_base();
    uintptr_t manager=base?WCTReadPointer(base+0x9e66158):0;
    uintptr_t account=manager?WCTReadPointer(manager+0x68):0,state=base?WCTLoginState(base):0;
    uintptr_t queue=manager?WCTReadPointer(manager+0x290):0;
    if(!base || !account || !state || !queue || !WCTReadPointer(queue+0x10)){completion(nil);return;}
    static const unsigned char entry[]={0xff,0xc3,0x06,0xd1,0xfc,0x6f,0x16,0xa9};
    if(memcmp((void*)(base+0x41842c8),entry,sizeof(entry))){completion(nil);return;}
    auto reply=std::make_shared<ResolveReply>(completion);
    auto callback=[reply,current,base,manager,account,state,identifier]{@autoreleasepool{
        if(reply->started.exchange(true))return;
        if(!current() || WCTReadPointer(manager+0x68)!=account || WCTLoginState(base)!=state){reply->finish(nil);return;}
        try {
            using Getter=ForeignPair (*)(void*);
            OwnedPair nativeAccount(base),services(base),metadata(base),record(base);
            nativeAccount.value=((Getter)(base+0x42b0808))(nullptr);
            if(nativeAccount.value.object!=account){reply->finish(nil);return;}
            services.value=((Getter)(base+0x1661598))((void*)nativeAccount.value.object);
            if(!services.value.object){reply->finish(nil);return;}
            metadata.value=((Getter)(base+0x20ca29c))((void*)services.value.object);
            if(!metadata.value.object){reply->finish(nil);return;}
            const char *bytes=identifier.UTF8String;size_t length=strlen(bytes);
            uintptr_t key[3]={(uintptr_t)bytes,length,(1ULL<<63)|(length+1)};
            record.value=((ForeignPair (*)(void*,const void*))(base+0x27cb684))((void*)metadata.value.object,key);
            NSString *source=nil;
            if(record.value.object && record.value.object<=UINTPTR_MAX-0x120) {
                for(uintptr_t offset:{(uintptr_t)0x108,(uintptr_t)0xf0}) {
                    NSError *error=nil;
                    NSString *candidate=WCTReadNativeString(record.value.object+offset,^BOOL(uintptr_t a,void *out,size_t n){return WCTReadBytes(a,out,n);},&error);
                    NSURL *url=error?nil:WCTAvatarDownloadURL(candidate);
                    if(url){source=url.absoluteString;break;}
                }
            }
            reply->finish(current()?source:nil);
        }catch(...){reply->finish(nil);}
    }};
    uintptr_t function[4]={0,0,0,(uintptr_t)WCTMakeForeignTask(callback)};
    uintptr_t origin[4]={(uintptr_t)"WCTAvatarSource",(uintptr_t)"ResolveAvatar",1,base+0x3cee904};
    try {
        OwnedPair result(base);
        result.value=((ForeignPair (*)(void*,const void*,void*,bool))(base+0x41842c8))((void*)queue,origin,function,true);
    }catch(...){if(function[3])delete (WCTForeignTask*)function[3];reply->finish(nil);return;}
    if(function[3]){delete (WCTForeignTask*)function[3];reply->finish(nil);}
}
static WCTAvatarStore *store() {
    static WCTAvatarStore *value=[[WCTAvatarStore alloc] initWithResolver:^(NSString *identifier,BOOL (^current)(void),void (^completion)(NSString*)){resolveURL(identifier,current,completion);} fetch:^id(NSURL *url,void (^completion)(NSData*)){return WCTDownloadAvatar(url,completion);} cancel:^(id handle){WCTCancelAvatarDownload(handle);}];return value;
}
}
void WCTAvatarNativeSession(NSString *epoch) {if(pthread_main_np())[store() activate:epoch];}
void WCTAvatarNativeSearchIDs(NSSet<NSString*> *identifiers,NSString *epoch) {if(pthread_main_np())[store() allow:identifiers epoch:epoch];}
NSData *WCTReadDownloadedAvatar(NSString *identifier) {return pthread_main_np()?[store() image:identifier]:nil;}
bool WCTNativeAvatarPending(NSString *identifier) {return pthread_main_np() && [store() pending:identifier];}
bool WCTRequestNativeAvatar(uintptr_t base,NSString *identifier) {
    if(!pthread_main_np() || !base || base!=wct_269602_module_base())return false;
    return [store() request:identifier];
}
