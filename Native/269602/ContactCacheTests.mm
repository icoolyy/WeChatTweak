#import "ContactCache.h"
#include <stdio.h>
#include <string.h>
#include <vector>

struct Region { uintptr_t start; size_t size; };
static unsigned failures;
static void check(BOOL condition, const char *name) {
    if (!condition) { ++failures; fprintf(stderr,"FAIL: %s\n",name); }
}
static void put64(unsigned char *p, uint64_t value) { memcpy(p,&value,8); }
static void short_string(unsigned char *p,const char *value) {
    size_t n=strlen(value); if(n>22) abort(); memset(p,0,24);memcpy(p,value,n);p[23]=(unsigned char)n;
}

int main(void) { @autoreleasepool {
    // Literal layout derived independently from the real 269602 instructions:
    // storage map+0x98, header bucket-count+8 / first-node+16 / size+24;
    // node next+0, key+0x10, shared object+0x28; record id+8, remark+0x60,
    // nickname+0xa8. Each string is 24 bytes with the short length at byte 23.
    unsigned char storage[0xc0]={0}, nodeA[0x38]={0}, nodeB[0x38]={0};
    unsigned char recordA[0x100]={0}, recordB[0x100]={0};
    char long_name[]="A nickname exceeding twenty two bytes";
    put64(storage+0xa0,3);put64(storage+0xa8,(uintptr_t)nodeA);put64(storage+0xb0,2);
    put64(nodeA,(uintptr_t)nodeB);short_string(nodeA+0x10,"wxid_a");put64(nodeA+0x28,(uintptr_t)recordA);
    short_string(nodeB+0x10,"wxid_b");put64(nodeB+0x28,(uintptr_t)recordB);
    short_string(recordA+8,"wxid_a");short_string(recordA+0x60,"备注甲");short_string(recordA+0xa8,"小甲");
    short_string(recordB+8,"wxid_b");
    put64(recordB+0xa8,(uintptr_t)long_name);put64(recordB+0xb0,strlen(long_name));put64(recordB+0xb8,((uint64_t)1<<63)|sizeof(long_name));
    std::vector<Region> regions={{(uintptr_t)storage,sizeof(storage)}, {(uintptr_t)nodeA,sizeof(nodeA)},
        {(uintptr_t)nodeB,sizeof(nodeB)}, {(uintptr_t)recordA,sizeof(recordA)},
        {(uintptr_t)recordB,sizeof(recordB)}, {(uintptr_t)long_name,sizeof(long_name)}};
    __block BOOL truncateB=NO;
    uintptr_t recordBAddress=(uintptr_t)recordB;
    WCTReadMemory read=^BOOL(uintptr_t address,void *output,size_t size) {
        for(Region r:regions) {
            size_t available=r.size;
            if(truncateB && r.start==recordBAddress) available=0xe0;
            if(address>=r.start && size<=available && address-r.start<=available-size) {
                memcpy(output,(void*)address,size);return YES;
            }
        }
        return NO;
    };
    NSError *error=nil;
    NSArray *result=WCTReadContactCache((uintptr_t)storage,read,&error);
    check(result.count==2 && !error,"complete two-contact snapshot");
    if(result.count==2) {
        check([result[0][@"id"] isEqual:@"wxid_a"] && [result[0][@"remark"] isEqual:@"备注甲"],"stable ID and Unicode remark");
        check([result[1][@"nickname"] isEqual:[NSString stringWithUTF8String:long_name]],"long string layout");
    }
    short_string(recordB+8,"wrong_id");
    error=nil;check(WCTReadContactCache((uintptr_t)storage,read,&error)==nil && error,"later invalid ID rejects entire snapshot");
    short_string(recordB+8,"wxid_b");
    put64(nodeB,(uintptr_t)nodeA);error=nil;
    check(WCTReadContactCache((uintptr_t)storage,read,&error)==nil && error,"cyclic list rejected");
    put64(nodeB,0);truncateB=YES;error=nil;
    check(WCTReadContactCache((uintptr_t)storage,read,&error)==nil && error,"truncated record rejected");
    truncateB=NO;put64(storage+0xb0,3);error=nil;
    check(WCTReadContactCache((uintptr_t)storage,read,&error)==nil && error,"declared count mismatch rejected");
    put64(storage+0xb0,UINT64_MAX);error=nil;
    check(WCTReadContactCache((uintptr_t)storage,read,&error)==nil && error,"oversized count rejected before allocation");
    printf("contact cache failures=%u\n",failures);
    return failures?1:0;
} }
