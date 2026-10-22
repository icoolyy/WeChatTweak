#import "ContactPage.h"
#import "ContactSearch.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

static NSString *hex(const unsigned char *bytes,NSUInteger size) {
    NSMutableString *result=[NSMutableString stringWithCapacity:size*2];
    for(NSUInteger i=0;i<size;++i) [result appendFormat:@"%02x",bytes[i]];
    return result;
}
static BOOL hex64(NSString *s) {
    return s.length==64 && [s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}
static NSDictionary *failure(NSString *code) {return @{@"ok":@NO,@"error":@{@"code":code}};}
static NSString *signature(NSData *key,NSString *position,NSString *snapshot,NSString *keyword,
                            BOOL pinyin,BOOL fuzzy,NSString *scope,NSString *epoch,NSUInteger limit) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@[@"wct-contact-page-v1",position,snapshot,keyword,@(pinyin),@(fuzzy),scope,epoch,@(limit)] options:0 error:nil];
    unsigned char digest[32];CCHmac(kCCHmacAlgSHA256,key.bytes,key.length,data.bytes,data.length,digest);
    return hex(digest,32);
}
static BOOL equalSignature(NSString *a,NSString *b) {
    if(!hex64(a) || !hex64(b)) return NO;
    unsigned difference=0;
    for(NSUInteger i=0;i<64;++i) difference|=[a characterAtIndex:i]^[b characterAtIndex:i];
    return difference==0;
}
NSDictionary *WCTContactPage(NSArray<NSDictionary *> *contacts,NSString *keyword,
                             BOOL pinyin,BOOL fuzzy,NSString *scope,NSString *epoch,
                             NSString *cursor,NSUInteger limit,NSData *key) {
    if(!hex64(scope) || !epoch.length || epoch.length>128 || key.length!=32 || !limit || limit>100 ||
       contacts.count>30000 || !keyword || [keyword lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>1024)
        return failure(@"invalid_query");
    NSArray *items=WCTMatchingContacts(contacts,keyword,pinyin,fuzzy);
    NSData *snapshot=[NSJSONSerialization dataWithJSONObject:items options:NSJSONWritingSortedKeys error:nil];
    if(!snapshot || snapshot.length>UINT32_MAX) return failure(@"invalid_native_layout");
    unsigned char hash[32];CC_SHA256(snapshot.bytes,(CC_LONG)snapshot.length,hash);
    NSString *fingerprint=hex(hash,32);NSUInteger offset=0;
    if(cursor) {
        if(!cursor.length || cursor.length>160) return failure(@"invalid_cursor");
        NSArray<NSString *> *parts=[cursor componentsSeparatedByString:@":"];
        if(parts.count!=3 || !hex64(parts[1]) || !hex64(parts[2])) return failure(@"invalid_cursor");
        NSString *position=parts[0];
        if(!position.length || position.length>5 || [position hasPrefix:@"0"] ||
           [position rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location!=NSNotFound)
            return failure(@"invalid_cursor");
        NSString *expected=signature(key,position,parts[1],keyword,pinyin,fuzzy,scope,epoch,limit);
        if(!equalSignature(expected,parts[2])) return failure(@"invalid_cursor");
        if(![parts[1] isEqual:fingerprint]) return failure(@"stale_cursor");
        offset=position.integerValue;
        if(offset>=items.count) return failure(@"invalid_cursor");
    }
    NSUInteger count=MIN(limit,items.count-offset);
    NSMutableDictionary *result=[@{@"ok":@YES,@"items":[items subarrayWithRange:NSMakeRange(offset,count)],
        @"total":@(items.count),@"source":@"loadedContacts",@"accountScope":scope,@"session":epoch} mutableCopy];
    if(offset+count<items.count) {
        NSString *position=[NSString stringWithFormat:@"%lu",(unsigned long)(offset+count)];
        result[@"nextCursor"]=[NSString stringWithFormat:@"%@:%@:%@",position,fingerprint,
            signature(key,position,fingerprint,keyword,pinyin,fuzzy,scope,epoch,limit)];
    }
    return result;
}
