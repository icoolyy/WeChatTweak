#import "Protocol.h"

// Run on a background queue. Native objects are accessed only on the main queue.
NSDictionary *WCTNativeOperation(NSString *operation, NSDictionary *arguments,
                                 WCTOperationContext *context);
