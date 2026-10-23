#import "AvatarCache.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <vector>
#include <stdio.h>
struct Region {uintptr_t address;size_t length;};
static unsigned failures;
static void check(BOOL value,const char *name){if(!value){++failures;fprintf(stderr,"FAIL: %s\n",name);}}
static void put(unsigned char *p,uint64_t value){memcpy(p,&value,8);}
static void string(unsigned char *p,const char *value){memset(p,0,24);memcpy(p,value,strlen(value));p[23]=strlen(value);}
static NSData *image(NSString *type) {
    unsigned char pixel[]={255,0,0,255};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixel,1,1,8,4,space,kCGImageAlphaPremultipliedLast);
    CGImageRef value=CGBitmapContextCreateImage(context);
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,(__bridge CFStringRef)type,1,nullptr);
    CGImageDestinationAddImage(destination,value,nullptr);CGImageDestinationFinalize(destination);
    CFRelease(destination);CGImageRelease(value);CGContextRelease(context);CGColorSpaceRelease(space);return data;
}
int main(){@autoreleasepool{
    NSData *png=image(@"public.png"),*jpeg=image(@"public.jpeg");
    for(NSData *data in @[png,jpeg]) {
        NSDictionary *payload=WCTAvatarPayload(data);
        check([payload[@"mime"] isEqual:@"image/png"],"normalize PNG and JPEG to stripped PNG thumbnail");
        NSData *decoded=[[NSData alloc] initWithBase64EncodedString:payload[@"data"]?:@"" options:0];
        check(decoded.length>8 && [payload[@"digest"] length]==64,"bounded PNG and digest returned");
    }
    check(WCTAvatarPayload([NSData dataWithBytes:"not an image" length:12])==nil,"bad type rejected");
    check(WCTAvatarPayload([NSMutableData dataWithLength:512*1024+1])==nil,"oversized data rejected");
    check(WCTAvatarPayload([png subdataWithRange:NSMakeRange(0,24)])==nil,"truncated image rejected");
    unsigned char cache[0x148]={},node[0xe0]={},vector[24]={};
    uintptr_t sentinel=(uintptr_t)cache+0x98;
    put(cache+0x98,(uintptr_t)node);put(cache+0xa0,(uintptr_t)node);put(cache+0xa8,1);
    put(node,sentinel);put(node+8,sentinel);string(node+0x10,"fixture");string(node+0x28,"fixture");
    // HeadInfo +0x70 is a shared pointer to an encoded-byte vector.
    put(node+0x28+0x70,(uintptr_t)vector);
    put(vector,(uintptr_t)png.bytes);put(vector+8,(uintptr_t)png.bytes+png.length);put(vector+16,(uintptr_t)png.bytes+png.length);
    std::vector<Region> regions={{(uintptr_t)cache,sizeof(cache)},{(uintptr_t)node,sizeof(node)},
        {(uintptr_t)vector,sizeof(vector)},{(uintptr_t)png.bytes,png.length}};
    WCTReadMemory reader=^BOOL(uintptr_t address,void *out,size_t n){for(auto r:regions)if(address>=r.address && n<=r.length && address-r.address<=r.length-n){memcpy(out,(void*)address,n);return YES;}return NO;};
    NSError *error=nil;
    check(WCTReadCachedAvatar((uintptr_t)cache,@"fixture",reader,&error)!=nil && !error,"matched cached avatar copied");
    check(WCTReadCachedAvatar((uintptr_t)cache,@"other",reader,&error)==nil && !error,"unknown contact has no avatar");
    string(node+0x28,"wrong");check(WCTReadCachedAvatar((uintptr_t)cache,@"fixture",reader,&error)==nil && error,"record identity mismatch refused");string(node+0x28,"fixture");
    put(vector+8,(uintptr_t)png.bytes+512*1024+1);error=nil;
    check(WCTReadCachedAvatar((uintptr_t)cache,@"fixture",reader,&error)==nil && error,"oversized native vector refused before copy");put(vector+8,(uintptr_t)png.bytes+png.length);
    put(node+8,(uintptr_t)node);error=nil;
    check(WCTReadCachedAvatar((uintptr_t)cache,@"other",reader,&error)==nil && error,"cyclic LRU refused");
    printf("avatar cache failures=%u\n",failures);return failures?1:0;
}}
