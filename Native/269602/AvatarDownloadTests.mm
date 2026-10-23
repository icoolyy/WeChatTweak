#import "AvatarDownload.h"
#include <stdio.h>
static unsigned failures=0;
static void check(BOOL v,const char*n){if(!v){++failures;fprintf(stderr,"FAIL: %s\n",n);}}
static NSData *fixtureBody;
static NSInteger fixtureStatus=200;
@interface AvatarProtocolFixture : NSURLProtocol
@end
@implementation AvatarProtocolFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {return [request.URL.host isEqual:@"wx.qlogo.cn"];}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)startLoading {
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:fixtureStatus HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    for(NSUInteger n=0;n<fixtureBody.length;n+=65536)[self.client URLProtocol:self didLoadData:[fixtureBody subdataWithRange:NSMakeRange(n,MIN((NSUInteger)65536,fixtureBody.length-n))]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
static NSData *downloadFixture(){
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.protocolClasses=@[AvatarProtocolFixture.class];
    __block BOOL done=NO;__block NSData *result=nil;
    WCTDownloadAvatarWithConfiguration([NSURL URLWithString:@"https://wx.qlogo.cn/fixture"],config,^(NSData *data){result=data;done=YES;});
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!done && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(done,"bounded fixture completes");return result;
}
int main(){@autoreleasepool{
 check([WCTAvatarDownloadURL(@"http://wx.qlogo.cn/mmhead/test/0").absoluteString isEqual:@"https://wx.qlogo.cn/mmhead/test/0"],"native HTTP image upgraded to HTTPS");
 check(WCTAvatarDownloadURL(@"https://wx.qlogo.cn/mmcrhead/test/0")!=nil,"group avatar source accepted");
 for(NSString *bad in @[@"https://example.com/x",@"https://wx.qlogo.cn.example.com/x",@"https://127.0.0.1/x",@"file:///tmp/avatar",@"https://user:secret@wx.qlogo.cn/x",@"https://wx.qlogo.cn:8443/x",@"https://wx.qlogo.cn/x#token",@"https://wx.qlogo.cn/x\n",@""])
 check(WCTAvatarDownloadURL(bad)==nil,"noncanonical or untrusted native source rejected");
 __block BOOL completed=NO;id handle=WCTDownloadAvatar([NSURL URLWithString:@"https://example.com/avatar"],^(NSData *data){completed=YES;check(data==nil,"untrusted URL cannot produce data");});
 check(handle==nil && completed,"network boundary independently rejects untrusted URL");
 fixtureBody=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=" options:0];
 check(downloadFixture()!=nil,"valid avatar is received through streaming transport");
 fixtureBody=[NSMutableData dataWithLength:512*1024+1];check(downloadFixture()==nil,"stream without declared length cannot exceed bound");
 fixtureBody=[@"not an image" dataUsingEncoding:NSUTF8StringEncoding];check(downloadFixture()==nil,"nonimage response rejected");
 fixtureStatus=403;check(downloadFixture()==nil,"failed HTTP response rejected");
 printf("avatar download failures=%u\n",failures);return failures?1:0;
}}
