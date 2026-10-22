#import "Protocol.h"
#include <time.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>

static NSTimeInterval now() {
    timespec value={};clock_gettime(CLOCK_MONOTONIC,&value);
    return (double)value.tv_sec+(double)value.tv_nsec/1e9;
}
@implementation WCTOperationContext
- (instancetype)initWithTimeout:(NSTimeInterval)timeout {
    if((self=[super init])) _deadline=now()+MAX(timeout,0.0);
    return self;
}
- (BOOL)expired {return self.cancelled || now()>=self.deadline;}
- (NSTimeInterval)timeRemaining {return self.cancelled?0:MAX(0.0,self.deadline-now());}
@end
@implementation WCTHTTPReply
@end

static WCTHTTPReply *reply(NSInteger status,NSDictionary *body) {
    WCTHTTPReply *value=[WCTHTTPReply new];value.status=status;value.body=body;return value;
}
static WCTHTTPReply *error(NSInteger status,NSString *code) {
    return reply(status,@{@"ok":@NO,@"error":@{@"code":code,@"message":@"WeChat bridge request failed."}});
}
static BOOL sameSecret(NSString *a,NSString *b) {
    NSData *left=[a dataUsingEncoding:NSUTF8StringEncoding],*right=[b dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger difference=left.length^right.length;
    const unsigned char *x=(const unsigned char*)left.bytes,*y=(const unsigned char*)right.bytes;
    for(NSUInteger i=0;i<right.length;++i) difference|=(i<left.length?x[i]:0)^y[i];
    return difference==0;
}
static BOOL localHost(NSString *host) {
    NSArray *parts=[host.lowercaseString componentsSeparatedByString:@":"];
    if(parts.count>2 || ![@[@"127.0.0.1",@"localhost"] containsObject:parts[0]]) return NO;
    if(parts.count==1) return YES;
    NSString *port=parts[1];
    return port.length && [port rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location==NSNotFound
        && port.integerValue>0 && port.integerValue<=65535;
}
static BOOL hexNonce(NSString *value) {
    return value.length==64 && [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}
static BOOL allowedKeys(NSDictionary *values,NSArray *allowed) {
    for(NSString *key in values) if(![allowed containsObject:key]) return NO;
    return YES;
}
static WCTHTTPReply *nativeFailure(NSDictionary *result) {
    id details=[result isKindOfClass:[NSDictionary class]]?result[@"error"]:nil;
    id code=[details isKindOfClass:[NSDictionary class]]?details[@"code"]:nil;
    if(![code isKindOfClass:[NSString class]]) code=nil;
    NSDictionary *statuses=@{@"unsupported_build":@422,@"not_logged_in":@409,@"not_ready":@503,
        @"native_busy":@503,@"invalid_native_layout":@503,@"invalid_query":@400,
        @"contact_not_found":@404,@"stale_session":@409,@"operation_timeout":@504};
    NSNumber *status=statuses[code?:@""];
    return error(status?status.integerValue:500,status?code:@"native_failed");
}

NSString *WCTHealthProof(NSString *token,NSString *challenge) {
    NSData *key=[token dataUsingEncoding:NSUTF8StringEncoding];
    NSData *message=[[@"wechattweak-health-v1:" stringByAppendingString:challenge] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,key.bytes,key.length,message.bytes,message.length,digest);
    NSMutableString *hex=[NSMutableString stringWithCapacity:64];
    for(unsigned char byte:digest) [hex appendFormat:@"%02x",byte];
    return hex;
}

WCTHTTPReply *WCTHandleHTTP(NSData *request, NSString *token,
                           WCTBridgeOperation operation, WCTOperationContext *context) {
    if(request.length>16384) return error(413,@"request_too_large");
    NSString *text=[[NSString alloc] initWithData:request encoding:NSASCIIStringEncoding];
    if(!text) return error(400,@"invalid_request");
    NSString *remaining=[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@""];
    if([remaining rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]].location!=NSNotFound)
        return error(400,@"invalid_request");
    NSRange boundary=[text rangeOfString:@"\r\n\r\n"];
    if(boundary.location==NSNotFound || NSMaxRange(boundary)!=text.length) return error(400,@"invalid_request");
    NSArray *lines=[[text substringToIndex:boundary.location] componentsSeparatedByString:@"\r\n"];
    NSArray *first=[lines[0] componentsSeparatedByString:@" "];
    if(first.count!=3 || ![first[2] isEqual:@"HTTP/1.1"]) return error(400,@"invalid_request");
    NSMutableDictionary *headers=[NSMutableDictionary dictionary];
    NSCharacterSet *headerToken=[[NSCharacterSet characterSetWithCharactersInString:@"!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet];
    for(NSUInteger i=1;i<lines.count;++i) {
        NSString *line=lines[i];NSRange colon=[line rangeOfString:@":"];
        if(colon.location==NSNotFound || !colon.location) return error(400,@"invalid_request");
        NSString *name=[line substringToIndex:colon.location];
        if([name rangeOfCharacterFromSet:headerToken].location!=NSNotFound) return error(400,@"invalid_request");
        name=name.lowercaseString;
        if(headers[name]) return error(400,@"duplicate_header");
        headers[name]=[[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t"]];
    }
    if(!headers[@"host"] || !localHost(headers[@"host"])) return error(400,@"invalid_host");
    if(headers[@"origin"]) return error(403,@"origin_rejected");
    if(headers[@"transfer-encoding"] || (headers[@"content-length"] && ![headers[@"content-length"] isEqual:@"0"])) return error(400,@"unexpected_body");
    if(![first[0] isEqual:@"GET"]) return error(405,@"method_not_allowed");
    NSString *target=first[1];
    if(![target hasPrefix:@"/"] || [target containsString:@"#"]) return error(400,@"invalid_request");
    NSRange separator=[target rangeOfString:@"?"];
    NSString *path=separator.location==NSNotFound?target:[target substringToIndex:separator.location];
    BOOL health=[path isEqual:@"/health"];
    if(!health && ![@[@"/wechat/search",@"/wechat/start"] containsObject:path]) return error(404,@"not_found");
    if(!health && !sameSecret(headers[@"authorization"]?:@"",[@"Bearer " stringByAppendingString:token])) return error(401,@"unauthorized");
    NSMutableDictionary *query=[NSMutableDictionary dictionary];
    if(separator.location!=NSNotFound) {
        NSString *encoded=[target substringFromIndex:NSMaxRange(separator)];
        if(encoded.length) for(NSString *part in [encoded componentsSeparatedByString:@"&"]) {
            NSRange equals=[part rangeOfString:@"="];
            if(equals.location==NSNotFound) return error(400,@"invalid_query");
            NSString *name=[[[part substringToIndex:equals.location] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            NSString *value=[[[part substringFromIndex:NSMaxRange(equals)] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            if(!name.length || !value || query[name] || [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0,1)]].location!=NSNotFound)
                return error(400,@"invalid_query");
            query[name]=value;
        }
    }
    if(context.expired) return error(504,@"operation_timeout");
    if(health) {
        if(!allowedKeys(query,@[@"challenge"]) || (query[@"challenge"] && !hexNonce(query[@"challenge"]))) return error(400,@"invalid_query");
        NSDictionary *state=operation(@"health",@{},context);
        if(![state isKindOfClass:[NSDictionary class]]) return error(500,@"native_failed");
        if(state[@"error"]) return nativeFailure(state);
        NSMutableDictionary *body=[@{@"protocol":@1,@"service":@"WeChatTweak"} mutableCopy];
        for(NSString *key in @[@"state",@"build",@"session",@"contactsSource"])
            if([state[key] isKindOfClass:[NSString class]] && [state[key] length]<=128) body[key]=state[key];
        NSDictionary *caps=[state[@"capabilities"] isKindOfClass:[NSDictionary class]]?state[@"capabilities"]:@{};
        NSMutableDictionary *capabilities=[NSMutableDictionary dictionary];
        for(NSString *key in @[@"contacts",@"openChat",@"accountContext",@"contactPagination",@"persistentContacts",@"avatars",@"quicklinks",@"fullContacts"])
            capabilities[key]=@([caps[key] isEqual:@YES]);
        body[@"capabilities"]=capabilities;
        if(query[@"challenge"]) body[@"proof"]=WCTHealthProof(token,query[@"challenge"]);
        return reply(200,body);
    }
    NSDictionary *result=nil;
    if([path isEqual:@"/wechat/search"]) {
        if(!allowedKeys(query,@[@"keyword",@"usePinyin",@"fuzzy"])) return error(400,@"invalid_query");
        NSString *keyword=query[@"keyword"]?:@"",*pinyin=query[@"usePinyin"]?:@"1",*fuzzy=query[@"fuzzy"]?:@"1";
        if([keyword lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>1024 || ![@[@"0",@"1"] containsObject:pinyin] || ![@[@"0",@"1"] containsObject:fuzzy]) return error(400,@"invalid_query");
        result=operation(@"search",@{@"keyword":keyword,@"pinyin":@([pinyin isEqual:@"1"]),@"fuzzy":@([fuzzy isEqual:@"1"])},context);
        if(![result isKindOfClass:[NSDictionary class]] || ![result[@"ok"] isEqual:@YES]) return nativeFailure(result);
        NSArray *items=result[@"items"];
        if(![items isKindOfClass:[NSArray class]]) return error(500,@"invalid_native_response");
        if(items.count>100) items=[items subarrayWithRange:NSMakeRange(0,100)];
        NSMutableDictionary *body=[@{@"ok":@YES,@"items":items} mutableCopy];
        for(NSString *key in @[@"session",@"source"]) if(result[key]) body[key]=result[key];
        return reply(200,body);
    }
    if(!allowedKeys(query,@[@"session",@"epoch"]) || ![query[@"session"] length] || ![query[@"epoch"] length] ||
       [query[@"session"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>1024 || [query[@"epoch"] length]>128) return error(400,@"invalid_query");
    result=operation(@"open",@{@"id":query[@"session"],@"expectedSession":query[@"epoch"]},context);
    if(![result isKindOfClass:[NSDictionary class]] || ![result[@"ok"] isEqual:@YES]) return nativeFailure(result);
    if(![result[@"confirmed"] isEqual:@YES]) return error(504,@"open_not_confirmed");
    return reply(200,@{@"ok":@YES,@"confirmed":@YES});
}
