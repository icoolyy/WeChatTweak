#import "ContactCache.h"
#include <string.h>

namespace {
struct Reader {
    WCTReadMemory read;
    bool valid=true;
    bool bytes(uintptr_t address, void *output, size_t size) {
        if (!valid || !address || address>UINTPTR_MAX-size || !read(address,output,size)) {
            valid=false;return false;
        }
        return true;
    }
    uint64_t pointer(uintptr_t address) {
        uint64_t value=0;bytes(address,&value,8);return value;
    }
    NSString *string(uintptr_t address) {
        unsigned char raw[24]={0};
        if(!bytes(address,raw,24)) return nil;
        if(!(raw[23]&128)) {
            if(raw[23]>22) {valid=false;return nil;}
            NSString *value=[[NSString alloc] initWithBytes:raw length:raw[23] encoding:NSUTF8StringEncoding];
            if(!value) valid=false;
            return value;
        }
        uint64_t source=0,length=0,capacity=0;
        memcpy(&source,raw,8);memcpy(&length,raw+8,8);memcpy(&capacity,raw+16,8);
        capacity &= ~((uint64_t)1<<63);
        if(!source || length>4096 || capacity<=length) {valid=false;return nil;}
        NSMutableData *data=[NSMutableData dataWithLength:length];
        if(length && !bytes(source,data.mutableBytes,length)) return nil;
        NSString *value=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if(!value) valid=false;
        return value;
    }
};
}

NSArray<NSDictionary *> *WCTReadContactCache(uintptr_t storage, WCTReadMemory reader,
                                             NSError **error) {
    if(error) *error=nil;
    Reader memory{reader};
    if(!reader || storage>UINTPTR_MAX-0xc0) memory.valid=false;
    uint64_t buckets=memory.pointer(storage+0xa0);
    uintptr_t node=memory.pointer(storage+0xa8);
    uint64_t count=memory.pointer(storage+0xb0);
    if(count>30000 || buckets>1048576 || (count && (!buckets || !node))) memory.valid=false;
    NSMutableArray *contacts=[NSMutableArray array];
    NSMutableSet *seen=[NSMutableSet set];
    NSArray *names=@[@"id",@"alias",@"remark",@"remarkPinyin",@"remarkInitials",@"nickname",@"nicknameInitials",@"nicknamePinyin"];
    const uintptr_t offsets[]={8,0x20,0x60,0x78,0x90,0xa8,0xc0,0xd8};
    while(memory.valid && node) {
        if(contacts.count>=count || [seen containsObject:@(node)] || node>UINTPTR_MAX-0x38) {
            memory.valid=false;break;
        }
        [seen addObject:@(node)];
        NSString *key=memory.string(node+0x10);
        uintptr_t record=memory.pointer(node+0x28);
        if(!record || record>UINTPTR_MAX-0xf0) {memory.valid=false;break;}
        NSMutableDictionary *contact=[NSMutableDictionary dictionary];
        for(NSUInteger i=0;i<names.count && memory.valid;++i) {
            NSString *value=memory.string(record+offsets[i]);
            if(value) contact[names[i]]=value;
        }
        if(!memory.valid || !key.length || [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>1024 ||
           ![contact[@"id"] isEqual:key]) {memory.valid=false;break;}
        [contacts addObject:[contact copy]];
        node=memory.pointer(node);
    }
    if(!memory.valid || contacts.count!=count) {
        if(error) *error=[NSError errorWithDomain:@"WeChatTweak.Native" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"Contact snapshot is unavailable or malformed."}];
        return nil;
    }
    return [contacts copy];
}
