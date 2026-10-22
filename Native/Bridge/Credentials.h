#import <Foundation/Foundation.h>

// Uses only an absolute caller-selected path. Existing credentials are never
// repaired or overwritten. A newly created credential is published atomically.
NSString *WCTLoadOrCreateToken(NSString *path,NSError **error);
