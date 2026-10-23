#import "Protocol.h"
#include <stdio.h>

static unsigned failures;
static void check(BOOL condition,const char *name) {
    if(!condition) {++failures;fprintf(stderr,"FAIL: %s\n",name);}
}
int main(void) { @autoreleasepool {
    NSString *token=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    __block unsigned calls=0;
    WCTBridgeOperation operation=^NSDictionary*(NSString *name,NSDictionary *args,WCTOperationContext *context) {
        (void)args;(void)context;++calls;
        if([name isEqual:@"health"]) return @{@"state":@"ready",@"build":@"269602",@"session":@"fixture-1",
            @"capabilities":@{@"contacts":@YES,@"openChat":@YES},@"privateAccount":@"must not leak"};
        if([name isEqual:@"avatar"]) {
            check([args[@"id"] isEqual:@"fixture_id"] && [args[@"expectedSession"] isEqual:@"fixture-1"],"avatar epoch arguments");
            return @{@"ok":@YES,@"id":@"fixture_id",@"session":@"fixture-1",@"mime":@"image/png",@"data":@"aGVsbG8=",@"digest":[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]};
        }
        if([name isEqual:@"open"]) return @{@"ok":@YES,@"confirmed":@YES};
        return @{@"ok":@YES,@"session":@"fixture-1",@"items":@[@{@"title":@"Fixture",@"arg":@"fixture_id"}]};
    };
    auto request=^WCTHTTPReply*(NSString *target,NSString *extra,BOOL auth) {
        NSString *head=[NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: 127.0.0.1:48065\r\n%@%@\r\n",target,
            auth?[NSString stringWithFormat:@"Authorization: Bearer %@\r\n",token]:@"",extra?:@""];
        return WCTHandleHTTP([head dataUsingEncoding:NSUTF8StringEncoding],token,operation,
                            [[WCTOperationContext alloc] initWithTimeout:5]);
    };
    WCTHTTPReply *health=request(@"/health",@"",NO);
    check(health.status==200 && [health.body[@"protocol"] isEqual:@1],"public typed health");
    check(health.body[@"privateAccount"]==nil,"health allowlist excludes account data");
    for(NSString *key in @[@"accountContext",@"contactPagination",@"persistentContacts",@"avatars",@"quicklinks",@"fullContacts"])
        check([health.body[@"capabilities"][key] isEqual:@NO],"unverified enhanced capabilities default unavailable");
    WCTHTTPReply *search=request(@"/wechat/search?keyword=fixture&usePinyin=1&fuzzy=1",@"",YES);
    check(search.status==200 && [search.body[@"items"] count]==1,"authenticated real operation dispatch");
    check(request(@"/wechat/avatar?id=fixture_id&epoch=fixture-1",@"",YES).status==200,"authenticated avatar route");
    check(request(@"/wechat/avatar?id=fixture_id&epoch=fixture-1",@"",NO).status==401,"avatar requires authentication");
    check(request(@"/wechat/avatar?id=fixture_id",@"",YES).status==400,"avatar requires epoch");
    check(request(@"/wechat/avatar?id=fixture_id&epoch=fixture-1&path=/tmp/test",@"",YES).status==400,"avatar refuses file paths");
    check(request(@"/wechat/avatar?id=fixture_id&id=other&epoch=fixture-1",@"",YES).status==400,"avatar refuses duplicate IDs");
    check(request(@"/wechat/avatar?id=%0A&epoch=fixture-1",@"",YES).status==400,"avatar refuses control characters");
    unsigned before=calls;
    check(request(@"/wechat/search",@"",NO).status==401,"unauthenticated legacy request rejected");
    check(calls==before,"unauthorized never reaches adapter");
    check(request(@"/wechat/search",@"Origin: https://example.invalid\r\n",YES).status==403,"Origin rejected");
    check(request(@"/health",@"Host: localhost\r\n",NO).status==400,"duplicate header rejected");
    check(request(@"/wechat/search?keyword=%E4",@"",YES).status==400,"malformed UTF-8 percent encoding rejected");
    check(request(@"/wechat/search?keyword=%00",@"",YES).status==400,"embedded NUL rejected");
    check(request(@"/wechat/search?keyword=a&keyword=b",@"",YES).status==400,"duplicate query key rejected");
    check(request(@"/wechat/search?fuzzy=2",@"",YES).status==400,"invalid boolean rejected");
    NSString *large=[@"x" stringByPaddingToLength:1025 withString:@"x" startingAtIndex:0];
    check(request([@"/wechat/search?keyword=" stringByAppendingString:large],@"",YES).status==400,"query UTF-8 byte limit");
    check(request(@"/wechat/start?session=fixture_id&epoch=fixture-1",@"",YES).status==200,"confirmed chat open");
    check(request(@"/wechat/start?session=fixture_id",@"",YES).status==400,"open requires session epoch");
    NSData *oversized=[[NSMutableData alloc] initWithLength:16385];
    check(WCTHandleHTTP(oversized,token,operation,[[WCTOperationContext alloc] initWithTimeout:5]).status==413,"request byte limit");
    NSString *raw=@"GET /health HTTP/1.1\r\nHost: attacker.invalid\r\n\r\n";
    check(WCTHandleHTTP([raw dataUsingEncoding:NSUTF8StringEncoding],token,operation,
        [[WCTOperationContext alloc] initWithTimeout:5]).status==400,"non-loopback Host rejected");
    WCTOperationContext *cancelled=[[WCTOperationContext alloc] initWithTimeout:5];cancelled.cancelled=YES;
    before=calls;
    raw=[NSString stringWithFormat:@"GET /wechat/start?session=fixture_id&epoch=fixture-1 HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer %@\r\n\r\n",token];
    check(WCTHandleHTTP([raw dataUsingEncoding:NSUTF8StringEncoding],token,operation,cancelled).status==504,"cancelled context fails before action");
    check(calls==before,"cancelled action never reaches adapter");
    WCTBridgeOperation pending=^NSDictionary*(NSString *name,NSDictionary *args,WCTOperationContext *context) {
        (void)name;(void)args;(void)context;return @{@"ok":@YES,@"requested":@YES};
    };
    check(WCTHandleHTTP([raw dataUsingEncoding:NSUTF8StringEncoding],token,pending,
        [[WCTOperationContext alloc] initWithTimeout:5]).status==504,"request acceptance alone is not open success");
    NSString *challenge=[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
    WCTHTTPReply *proof=request([@"/health?challenge=" stringByAppendingString:challenge],@"",NO);
    check([proof.body[@"proof"] length]==64 && [proof.body[@"proof"] isEqual:WCTHealthProof(token,challenge)],"health proof provided for nonce");
    // Independently calculated with Python's standard hmac/sha256 implementation.
    check([proof.body[@"proof"] isEqual:@"262e7d483a209927d1b17b9566d1bf7948b9feccc36b193624e2aaa082ac20bd"],"health proof matches independent HMAC vector");
    check(![WCTHealthProof(token,challenge) isEqual:WCTHealthProof(token,[@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0])],"proof changes with nonce");
    printf("bridge protocol failures=%u\n",failures);
    return failures?1:0;
} }
