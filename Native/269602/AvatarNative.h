#pragma once
#import <Foundation/Foundation.h>
// Main-thread-only resolver for this verified build. No paths leave the adapter.
NSData *WCTReadNativeAvatarFile(uintptr_t base, NSString *identifier);

// Main-thread session invalidation and bounded missing-avatar scheduling.
void WCTAvatarNativeSession(NSString *epoch);
bool WCTRequestNativeAvatar(uintptr_t base, NSString *identifier);
void WCTAvatarNativeSearchIDs(NSSet<NSString*> *identifiers,NSString *epoch);
NSData *WCTReadDownloadedAvatar(NSString *identifier);
bool WCTNativeAvatarPending(NSString *identifier);
