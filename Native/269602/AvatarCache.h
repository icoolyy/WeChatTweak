#pragma once
#import "ContactCache.h"

// Reads only an owned snapshot from HeadCache's validated LRU while its owner
// registry and mutex are held. No file paths, native calls or network requests.
NSData *WCTReadCachedAvatar(uintptr_t storage, NSString *identifier,
                           WCTReadMemory reader, NSError **error);
// Accept bounded PNG/JPEG only, decode a <=128px thumbnail, strip metadata.
// Returns JSON-safe mime/data/digest fields, or nil for missing/invalid images.
NSDictionary *WCTAvatarPayload(NSData *data);
