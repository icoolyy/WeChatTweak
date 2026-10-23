#import "AvatarCache.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CommonCrypto/CommonDigest.h>

NSData *WCTReadCachedAvatar(uintptr_t storage,NSString *identifier,WCTReadMemory reader,NSError **error) {
    if(error) *error=nil;
    __block BOOL valid=reader && storage && storage<=UINTPTR_MAX-0x148;
    auto pointer=^uintptr_t(uintptr_t address){uintptr_t v=0;if(!valid || !address || address>UINTPTR_MAX-8 || !reader(address,&v,8))valid=NO;return v;};
    uintptr_t sentinel=storage+0x98,tail=valid?pointer(sentinel):0,node=valid?pointer(storage+0xa0):0;
    NSUInteger count=valid?pointer(storage+0xa8):0;
    if(count>4096 || !identifier.length || [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>1024)valid=NO;
    NSMutableSet *seen=[NSMutableSet set];uintptr_t previous=sentinel;
    NSData *copied=nil;BOOL matched=NO;
    while(valid && node!=sentinel) {
        if(!node || node>UINTPTR_MAX-0xe0 || seen.count>=count || [seen containsObject:@(node)] || pointer(node)!=previous){valid=NO;break;}
        [seen addObject:@(node)];NSError *stringError=nil;
        NSString *key=WCTReadNativeString(node+0x10,reader,&stringError);
        if(!key.length || stringError){valid=NO;break;}
        if([key isEqual:identifier]) {
            if(matched){valid=NO;break;}matched=YES;
            NSString *owner=WCTReadNativeString(node+0x28,reader,&stringError);
            if(stringError || ![owner isEqual:identifier]){valid=NO;break;}
            uintptr_t record=node+0x28,vector=pointer(record+0x70);
            if(!vector) vector=record+0x50;
            if(vector>UINTPTR_MAX-24){valid=NO;break;}
            uintptr_t begin=pointer(vector),end=pointer(vector+8),capacity=pointer(vector+16);
            if(end<begin || capacity<end || end-begin>512*1024 || (!begin && (end || capacity))){valid=NO;break;}
            if(valid && end>begin) {
                NSMutableData *bytes=[NSMutableData dataWithLength:end-begin];
                if(!reader(begin,bytes.mutableBytes,bytes.length)){valid=NO;break;}
                copied=[bytes copy];
            }
        }
        previous=node;node=pointer(node+8);
    }
    if(!valid || seen.count!=count || previous!=tail) {
        if(error)*error=[NSError errorWithDomain:@"WeChatTweak.Avatar" code:1 userInfo:nil];return nil;
    }
    return copied;
}

NSDictionary *WCTAvatarPayload(NSData *data) {
    if(!data.length || data.length>512*1024)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceShouldCache:@NO});
    if(!source)return nil;
    CFStringRef type=CGImageSourceGetType(source);
    BOOL allowed=type && (CFEqual(type,CFSTR("public.png")) || CFEqual(type,CFSTR("public.jpeg")));
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,nullptr));
    NSUInteger width=[properties[(__bridge NSString*)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height=[properties[(__bridge NSString*)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    if(!allowed || CGImageSourceGetCount(source)!=1 || CGImageSourceGetStatus(source)!=kCGImageStatusComplete || !width || !height || width>4096 || height>4096){CFRelease(source);return nil;}
    CGImageRef thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
        (__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@128});
    CFRelease(source);if(!thumbnail)return nil;
    NSMutableData *output=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)output,CFSTR("public.png"),1,nullptr);
    BOOL saved=NO;
    if(destination){CGImageDestinationAddImage(destination,thumbnail,nullptr);saved=CGImageDestinationFinalize(destination);CFRelease(destination);}
    CGImageRelease(thumbnail);
    if(!saved || !output.length || output.length>128*1024)return nil;
    unsigned char digest[32];CC_SHA256(output.bytes,(CC_LONG)output.length,digest);
    NSMutableString *hex=[NSMutableString stringWithCapacity:64];for(unsigned char byte:digest)[hex appendFormat:@"%02x",byte];
    return @{@"mime":@"image/png",@"data":[output base64EncodedStringWithOptions:0],@"digest":hex};
}
