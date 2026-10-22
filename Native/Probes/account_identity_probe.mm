// Research only. Copy no account value into output; record a keyed comparison
// digest and availability. Not part of the production source list.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonHMAC.h>
#include "../269602/Runtime.h"
#include "../269602/ContactCache.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static int output=-1;
static NSData *key;
static void capture(void *) {
    @autoreleasepool {
        uintptr_t base=wct_269602_module_base();
        uintptr_t state=base?WCTLoginState(base):0;
        uintptr_t manager=state?WCTReadPointer(base+0x9e66158):0;
        uintptr_t account=manager && WCTReadPointer(manager)==base+0x98c53d0?WCTReadPointer(manager+0x68):0;
        NSString *candidate=nil;
        if(account && WCTReadPointer(account)==base+0x98ba858) {
            // vtable +0x18 -> 0x419ac60: add x0,x0,#0x48; ret.
            const uint32_t entry[]={0x91012000,0xd65f03c0};
            uint32_t observed[2]={};
            if(WCTReadBytes(base+0x419ac60,observed,sizeof(observed)) && !memcmp(entry,observed,sizeof(entry)))
                candidate=WCTReadNativeString(account+0x48,^BOOL(uintptr_t a,void *b,size_t n){return WCTReadBytes(a,b,n);},nil);
        }
        BOOL valid=candidate.length && [candidate lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=1024 &&
            [candidate rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@.-"] invertedSet]].location==NSNotFound;
        if(valid) {
            NSData *message=[[@"wct-research-account-v1:" stringByAppendingString:candidate] dataUsingEncoding:NSUTF8StringEncoding];
            unsigned char digest[32];CCHmac(kCCHmacAlgSHA256,key.bytes,key.length,message.bytes,message.length,digest);
            NSMutableString *hex=[NSMutableString string];
            for(unsigned char byte:digest) [hex appendFormat:@"%02x",byte];
            dprintf(output,"logged_in=1 candidate_valid=1 comparison=%s\n",hex.UTF8String);
        } else dprintf(output,"logged_in=%d candidate_valid=0\n",state!=0);
    }
}
static void initializeProbe(void *) {
    const char *path=getenv("WCT_ACCOUNT_PROBE_OUTPUT"),*secret=getenv("WCT_ACCOUNT_PROBE_KEY");
    NSString *bundle=NSBundle.mainBundle.bundlePath;
    if(![bundle hasPrefix:@"/private/tmp/wechattweak-runtime-inventory/"] &&
       ![bundle hasPrefix:@"/tmp/wechattweak-runtime-inventory/"]) return;
    NSString *defaultOutput=[NSString stringWithFormat:@"/tmp/wechattweak-runtime-inventory/account-probe-%d.log",getpid()];
    if(!path) path=defaultOutput.fileSystemRepresentation;
    if(!secret) secret="/tmp/wechattweak-runtime-inventory/account-probe-key";
    if(path[0]!='/' || secret[0]!='/') return;
    int fd=open(secret,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);struct stat info={};
    unsigned char bytes[32];
    BOOL valid=fd>=0 && !fstat(fd,&info) && S_ISREG(info.st_mode) && info.st_uid==getuid() &&
        (info.st_mode&0777)==0600 && info.st_size==32 && read(fd,bytes,sizeof(bytes))==32;
    if(fd>=0) close(fd);
    if(!valid) return;
    key=[NSData dataWithBytes:bytes length:32];memset(bytes,0,sizeof(bytes));
    output=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(output<0) return;
    for(int i=1;i<=120;++i) dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,(int64_t)i*5*NSEC_PER_SEC),dispatch_get_main_queue(),nullptr,capture);
}
// Match the production host: do not initialize NSBundle/Foundation while the
// WeChat custom loader is still constructing its application environment.
__attribute__((constructor)) static void start(void) {
    dispatch_async_f(dispatch_get_main_queue(),nullptr,initializeProbe);
}
