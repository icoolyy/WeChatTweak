#import <Foundation/Foundation.h>
#include <stdint.h>

typedef BOOL (^WCTReadMemory)(uintptr_t address, void *output, size_t size);

// Caller must hold the native storage mutex or stop the entire target process.
// Returns an owned immutable snapshot; failure never returns a partial snapshot.
NSArray<NSDictionary *> *WCTReadContactCache(uintptr_t storage, WCTReadMemory reader,
                                             NSError **error);
