#import "AvatarDownload.h"
NSURL *WCTAvatarDownloadURL(NSString *nativeURL){
    if(!nativeURL.length || [nativeURL lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>8192 ||
       [nativeURL rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:nativeURL];
    if(!([parts.scheme.lowercaseString isEqual:@"http"] || [parts.scheme.lowercaseString isEqual:@"https"]) ||
       ![parts.host.lowercaseString isEqual:@"wx.qlogo.cn"] || parts.user || parts.password || parts.fragment ||
       (parts.port && parts.port.integerValue!=443) || ![parts.path hasPrefix:@"/"])return nil;
    parts.scheme=@"https";parts.host=@"wx.qlogo.cn";parts.port=nil;return parts.URL;
}

#import "AvatarCache.h"
@interface WCTAvatarDownload : NSObject <NSURLSessionDataDelegate>
@property(nonatomic,strong) NSURLSession *session;
// Cancellation may read this handle while the delegate queue tears it down.
@property(atomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,strong) NSMutableData *bytes;
@property(nonatomic,copy) void (^completion)(NSData *);
- (void)finish:(NSData *)image;
@end
@implementation WCTAvatarDownload
- (void)finish:(NSData *)image {
    void (^completion)(NSData *)=self.completion;if(!completion)return;
    self.completion=nil;self.bytes=nil;
    [self.session invalidateAndCancel];self.task=nil;self.session=nil;completion(image);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    (void)session;(void)task;(void)response;
    NSURL *safe=WCTAvatarDownloadURL(request.URL.absoluteString);
    // Never forward the original source path to an unapproved redirect host.
    completion(safe && [safe isEqual:request.URL]?request:nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))completion {
    (void)session;(void)task;
    completion([challenge.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust]?NSURLSessionAuthChallengePerformDefaultHandling:NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    (void)session;(void)task;
    BOOL valid=[response isKindOfClass:NSHTTPURLResponse.class] && [(NSHTTPURLResponse*)response statusCode]==200 &&
        response.expectedContentLength<=512*1024 && WCTAvatarDownloadURL(response.URL.absoluteString)!=nil;
    completion(valid?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session;
    if(data.length>512*1024-self.bytes.length){[task cancel];[self finish:nil];return;}
    [self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;(void)task;
    if(!self.completion)return;
    NSDictionary *payload=error?nil:WCTAvatarPayload(self.bytes);
    NSData *image=payload?[[NSData alloc] initWithBase64EncodedString:payload[@"data"] options:0]:nil;
    [self finish:image];
}
@end
id WCTDownloadAvatarWithConfiguration(NSURL *url,NSURLSessionConfiguration *configuration,void (^completion)(NSData *image)) {
    NSURL *safe=WCTAvatarDownloadURL(url.absoluteString);
    if(!safe || ![safe isEqual:url]){completion(nil);return nil;}
    NSURLSessionConfiguration *config=[configuration copy];
    config.URLCache=nil;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;config.HTTPShouldSetCookies=NO;
    config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;config.timeoutIntervalForRequest=4;config.timeoutIntervalForResource=5;
    WCTAvatarDownload *download=[WCTAvatarDownload new];download.bytes=[NSMutableData new];download.completion=completion;
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;
    download.session=[NSURLSession sessionWithConfiguration:config delegate:download delegateQueue:queue];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:safe];request.HTTPShouldHandleCookies=NO;
    download.task=[download.session dataTaskWithRequest:request];[download.task resume];return download;
}
id WCTDownloadAvatar(NSURL *url,void (^completion)(NSData *image)) {
    return WCTDownloadAvatarWithConfiguration(url,NSURLSessionConfiguration.ephemeralSessionConfiguration,completion);
}
void WCTCancelAvatarDownload(id handle) {
    if([handle isKindOfClass:WCTAvatarDownload.class])[((WCTAvatarDownload*)handle).task cancel];
}
