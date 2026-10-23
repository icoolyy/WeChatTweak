// Throwaway acceptance probe; deliberately excluded from every production source list.
#import <Foundation/Foundation.h>
#include "../269602/Adapter.h"
#include "../269602/Runtime.h"
#include "../269602/NativeMutex.h"
#import "../269602/AvatarCache.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

// A nontrivial C++ return value uses arm64's indirect result register x8,
// matching the foreign shared_ptr return ABI; no host std::shared_ptr crosses it.
struct ForeignPair { uintptr_t object=0,control=0; ~ForeignPair() {} };
static int output=-1;
static NSString *epoch;
static NSMutableArray<NSString *> *requested;
static NSSet<NSString *> *knownIDs;
static unsigned ticks;
static NSDictionary *decode(char *raw) {
    if(!raw)return nil;NSData *data=[NSData dataWithBytes:raw length:strlen(raw)];wct_native_free(raw);
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
#ifdef WCT_AVATAR_PATH_PROBE
struct ForeignString {uintptr_t words[3]={};~ForeignString(){}};
static bool cachedNativePath(NSString *identifier) {
    uintptr_t base=wct_269602_module_base();
    const char *bytes=identifier.UTF8String;size_t length=strlen(bytes);
    uintptr_t key[3]={(uintptr_t)bytes,length,(1ULL<<63)|(length+1)};
    ForeignString value=((ForeignString (*)(void*,const void*))(base+0x3cedc44))(nullptr,key);
    NSError *error=nil;NSString *path=WCTReadNativeString((uintptr_t)&value,^BOOL(uintptr_t a,void *out,size_t n){return WCTReadBytes(a,out,n);},&error);
    ((void (*)(void*))(base+0x2afd8))(&value);
    NSArray *roots=@[[NSHomeDirectory() stringByAppendingString:@"/Documents/xwechat_files/"],
        [NSHomeDirectory() stringByAppendingString:@"/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/"]];
    BOOL rooted=NO;for(NSString *root in roots)if(path.isAbsolutePath && [path hasPrefix:root] && [path.pathComponents containsObject:@"head_image"])rooted=YES;
    if(!rooted || error){dprintf(output,"native_path_rooted=%d native_path_readable=%d\n",rooted,!error && path.length>0);return false;}
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);if(fd<0){dprintf(output,"native_path_missing=1\n");return false;}
    struct stat metadata={};bool valid=fstat(fd,&metadata)==0 && S_ISREG(metadata.st_mode) && metadata.st_uid==getuid() && metadata.st_size>0 && metadata.st_size<=512*1024;
    NSMutableData *data=valid?[NSMutableData dataWithLength:metadata.st_size]:nil;size_t offset=0;
    while(valid && offset<data.length){ssize_t n=read(fd,(char*)data.mutableBytes+offset,data.length-offset);if(n<=0){valid=false;break;}offset+=n;}
    close(fd);BOOL image=valid && WCTAvatarPayload(data)!=nil;
    dprintf(output,"native_file_bounded=%d native_file_image=%d\n",valid,image);return image;
}
#endif
static bool cachedHD(NSString *identifier) {
    uintptr_t base=wct_269602_module_base(),manager=base?WCTReadPointer(base+0x9e66158):0;
    uintptr_t account=manager?WCTReadPointer(manager+0x68):0,factory=account?WCTReadPointer(account+0x368):0;
    if(!factory || WCTReadPointer(factory)!=base+0x98b87f8)return false;
    WCTNativeMutex registry;if(registry.acquire(factory+0x30)!=WCTLockAcquired)return false;
    uintptr_t node=WCTReadPointer(factory+0x80),head=0;unsigned count=0;
    while(node && ++count<=4096) {uintptr_t value=WCTReadPointer(node+0x28);if(value && WCTReadPointer(value)==base+0x98b9710)head=value;node=WCTReadPointer(node);}
    if(node || !head)return false;
    WCTNativeMutex cache;if(cache.acquire(head+0x108)!=WCTLockAcquired)return false;
    NSError *error=nil;NSData *data=WCTReadCachedAvatar(head,[identifier stringByAppendingString:@"_hd"],^BOOL(uintptr_t a,void *out,size_t n){return WCTReadBytes(a,out,n);},&error);
    cache.release();registry.release();return !error && WCTAvatarPayload(data)!=nil;
}
#ifdef WCT_SMALL_AVATAR_PROBE
static uintptr_t originalBase,expectedAccount,expectedState,smallVtable[9];
static void *cloneSmall(void *source) {
    void *copy=((void *(*)(void*))(originalBase+0x3cf752c))(source);
    *(uintptr_t*)copy=(uintptr_t)smallVtable;return copy;
}
static void copySmall(void *source,void *destination) {
    ((void (*)(void*,void*))(originalBase+0x3cf75ac))(source,destination);
    *(uintptr_t*)destination=(uintptr_t)smallVtable;
}
#ifdef WCT_AVATAR_RESPONSE_PROBE
static uintptr_t sceneVtable[66],sceneResponse,sceneExecute;
static void observeResponse(void *scene,void *key,void *error) {
    int32_t code=0;bool readable=WCTReadBytes((uintptr_t)error+8,&code,4);
    dprintf(output,"response_observed=1 code_readable=%d code=%d\n",readable,readable?code:0);
    NSError *stringError=nil;
    NSString *nativeID=WCTReadNativeString((uintptr_t)scene+0x210,^BOOL(uintptr_t a,void *out,size_t n){return WCTReadBytes(a,out,n);},&stringError);
    dprintf(output,"response_id_valid=%d response_id_known=%d\n",!stringError && nativeID.length>0,[knownIDs containsObject:nativeID?:@""]);
    ((void (*)(void*,void*,void*))sceneResponse)(scene,key,error);
}
static void observeExecution(void *scene) {
    dprintf(output,"scene_execute_begin=1\n");
    ((void (*)(void*))sceneExecute)(scene);
    dprintf(output,"scene_execute_returned=1\n");
}
static void requestObserved(const void *identifier) {
    using Constructor=ForeignPair (*)(void*,const void*,const int*,const int*);
    using Getter=ForeignPair (*)(void*);
    using Release=void (*)(void*);
    auto release=(Release)(originalBase+0x1312c8);int kind=0,width=300;
    ForeignPair scene=((Constructor)(originalBase+0x2be4a38))(nullptr,identifier,&kind,&width);
    uintptr_t vt=WCTReadPointer(scene.object);
    if(vt!=originalBase+0x9812ef0){dprintf(output,"scene_type_mismatch=1\n");release(&scene);return;}
    for(unsigned i=0;i<66;++i)sceneVtable[i]=WCTReadPointer(vt-16+i*8);
    sceneResponse=sceneVtable[12];sceneVtable[12]=(uintptr_t)observeResponse;
    sceneExecute=sceneVtable[13];sceneVtable[13]=(uintptr_t)observeExecution;
    *(uintptr_t*)scene.object=(uintptr_t)(sceneVtable+2);
    ForeignPair account=((Getter)(originalBase+0x42b0808))(nullptr);
    ForeignPair services=((Getter)(originalBase+0x1661598))((void*)account.object);
    ForeignPair dispatcher=((Getter)(originalBase+0x2261230))((void*)services.object);
    int context=0;
    ((void (*)(void*,const int*,const void*))(originalBase+0x3431c2c))((void*)(dispatcher.object+0x98),&context,&scene);
    release(&dispatcher);release(&services);release(&account);release(&scene);
}
#endif
static void executeSmall(void *job) {
    uintptr_t manager=WCTReadPointer(originalBase+0x9e66158);
    if(WCTReadPointer(manager+0x68)!=expectedAccount || WCTLoginState(originalBase)!=expectedState){dprintf(output,"job_stale=1\n");return;}
    dprintf(output,"small_job_executed=1\n");
#ifdef WCT_AVATAR_RESPONSE_PROBE
    requestObserved((const char*)job+8);
#else
    ((void (*)(void*,const void*))(originalBase+0x2bddf4c))(nullptr,(const char*)job+8);
#endif
    dprintf(output,"small_job_returned=1\n");
}
#endif
static bool trigger(NSString *identifier) {
    uintptr_t base=wct_269602_module_base();if(!base || !WCTLoginState(base))return false;
    uintptr_t manager=WCTReadPointer(base+0x9e66158);
    if(!manager || WCTReadPointer(manager)!=base+0x98c53d0)return false;
    uintptr_t queue=WCTReadPointer(manager+0x290);
    if(!queue || !WCTReadPointer(queue+0x10))return false;
    const unsigned char entry[]={0xff,0xc3,0x06,0xd1,0xfc,0x6f,0x16,0xa9};
    if(memcmp((const void*)(base+0x41842c8),entry,sizeof(entry)))return false;
    // Copy the same native job used by 3cee4dc -> 3cf7670. The dispatcher
    // consumes its heap std::function target, whose native vtable owns cleanup.
    using Allocate=void *(*)(size_t);
    using Destroy=void (*)(void *);
    auto allocate=(Allocate)(base+0x6cb2154);
    auto destroy=(Destroy)(base+0x3cf7628);
    uintptr_t *job=(uintptr_t*)allocate(0x28);memset(job,0,0x28);job[0]=base+0x9889b58;
#ifdef WCT_SMALL_AVATAR_PROBE
    originalBase=base;expectedAccount=WCTReadPointer(manager+0x68);expectedState=WCTLoginState(base);
    for(unsigned i=0;i<9;++i)smallVtable[i]=WCTReadPointer(base+0x9889b58+i*8);
    smallVtable[2]=(uintptr_t)cloneSmall;smallVtable[3]=(uintptr_t)copySmall;smallVtable[6]=(uintptr_t)executeSmall;
    job[0]=(uintptr_t)smallVtable;
#endif
    const char *utf8=identifier.UTF8String;size_t length=strlen(utf8);
    if(length<=22) {memcpy(job+1,utf8,length);((unsigned char*)job)[0x1f]=(unsigned char)length;}
    else {char *bytes=(char*)allocate(length+1);memcpy(bytes,utf8,length+1);job[1]=(uintptr_t)bytes;job[2]=length;job[3]=(1ULL<<63)|(length+1);}
    *(uint32_t*)((unsigned char*)job+0x20)=200;
    uintptr_t function[4]={0,0,0,(uintptr_t)job};
    // 3b964 constructs a 32-byte source-location record, NOT a string.
    uintptr_t origin[4]={(uintptr_t)"WCTAvatarLoad",(uintptr_t)"AvatarLoadProbe",1,base+0x3cee904};
    using Dispatch=ForeignPair (*)(void *,const void *,void *,bool);
    try {
        dprintf(output,"dispatch_begin=1\n");
        ForeignPair result=((Dispatch)(base+0x41842c8))((void*)queue,origin,function,true);
        dprintf(output,"dispatch_returned=1 consumed=%d\n",function[3]==0);
        ((Destroy)(base+0x1312c8))(&result);
        if(function[3])destroy((void*)function[3]);
    } catch(...) {if(function[3])destroy((void*)function[3]);return false;}
    return true;
}
static void capture(void *) { @autoreleasepool {
    NSDictionary *health=decode(wct_native_health_json());
    if(![health[@"state"] isEqual:@"ready"]){dprintf(output,"ready=0\n");return;}
    NSDictionary *results=decode(wct_native_search_json("",1,1));
    if(!epoch) {
        dprintf(output,"baseline_begin=1\n");
        epoch=[results[@"session"] copy];knownIDs=[NSSet setWithArray:[results[@"items"] valueForKey:@"id"]];requested=[NSMutableArray array];unsigned available=0,missing=0;
        for(NSDictionary *contact in results[@"items"]) {
            NSString *identifier=contact[@"id"];
            NSDictionary *avatar=decode(wct_native_avatar_json(identifier.UTF8String,epoch.UTF8String));
            if([avatar[@"ok"] isEqual:@YES])++available;
            else if([avatar[@"error"][@"code"] isEqual:@"avatar_not_found"]) {
                ++missing;
                if(requested.count<3 &&
#ifdef WCT_SPREAD_AVATAR_PROBE
                   missing%30==15 &&
#endif
                   ![identifier hasPrefix:@"@placeholder"] && trigger(identifier)) [requested addObject:identifier];
            }
        }
        dprintf(output,"baseline_available=%u baseline_missing=%u requested=%lu\n",available,missing,(unsigned long)requested.count);
    }
    if(![results[@"session"] isEqual:epoch]){dprintf(output,"session_changed=1\n");return;}
    unsigned available=0,invalid=0,hd=0,local=0;
    for(NSString *identifier in requested) {
        if(cachedHD(identifier))++hd;
#ifdef WCT_AVATAR_PATH_PROBE
        if(cachedNativePath(identifier))++local;
#endif
        NSDictionary *avatar=decode(wct_native_avatar_json(identifier.UTF8String,epoch.UTF8String));
        if([avatar[@"ok"] isEqual:@YES])++available;
        else if([avatar[@"error"][@"code"] isEqual:@"invalid_native_layout"])++invalid;
    }
    dprintf(output,"tick=%u requested=%lu now_available=%u hd_available=%u local_available=%u invalid_layout=%u\n",++ticks,(unsigned long)requested.count,available,hd,local,invalid);
} }
static void initialize(void *) { @autoreleasepool {
    NSString *bundle=NSBundle.mainBundle.bundlePath;
    if(![bundle hasPrefix:@"/tmp/wechattweak-runtime-inventory/"] && ![bundle hasPrefix:@"/private/tmp/wechattweak-runtime-inventory/"])return;
#if defined(WCT_AVATAR_PATH_PROBE)
    NSString *path=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/avatar-path-probe-%d.log",getpid()];
#elif defined(WCT_AVATAR_RESPONSE_PROBE)
    NSString *path=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/avatar-response2-probe-%d.log",getpid()];
#elif defined(WCT_SPREAD_AVATAR_PROBE)
    NSString *path=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/avatar-spread-probe-%d.log",getpid()];
#elif defined(WCT_SMALL_AVATAR_PROBE)
    NSString *path=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/avatar-small-probe-%d.log",getpid()];
#else
    NSString *path=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/avatar-load-probe-%d.log",getpid()];
#endif
    output=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(output<0)return;
    for(unsigned i=1;i<=120;++i) dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,(int64_t)i*5*NSEC_PER_SEC),dispatch_get_main_queue(),nullptr,capture);
} }
__attribute__((constructor)) static void start(){dispatch_async_f(dispatch_get_main_queue(),nullptr,initialize);}
