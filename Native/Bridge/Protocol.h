#import <Foundation/Foundation.h>

@interface WCTOperationContext : NSObject
@property(atomic) BOOL cancelled;
@property(nonatomic,readonly) NSTimeInterval deadline;
- (instancetype)initWithTimeout:(NSTimeInterval)timeout;
- (BOOL)expired;
- (NSTimeInterval)timeRemaining;
@end

@interface WCTHTTPReply : NSObject
@property(nonatomic) NSInteger status;
@property(nonatomic,copy) NSDictionary *body;
@end

typedef NSDictionary *(^WCTBridgeOperation)(NSString *operation, NSDictionary *arguments,
                                           WCTOperationContext *context);
WCTHTTPReply *WCTHandleHTTP(NSData *request, NSString *token,
                           WCTBridgeOperation operation, WCTOperationContext *context);
NSString *WCTHealthProof(NSString *token, NSString *challenge);
