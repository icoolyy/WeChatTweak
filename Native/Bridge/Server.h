#import "Protocol.h"

@interface WCTBridgeServer : NSObject
@property(nonatomic,readonly) uint16_t port;
- (instancetype)initWithTokenPath:(NSString *)tokenPath port:(uint16_t)port
                         operation:(WCTBridgeOperation)operation;
- (BOOL)start:(NSError **)error;
// Stops accepting requests and cancels queued operations. Does not wait for UI.
- (void)stop;
@end
