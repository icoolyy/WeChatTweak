#pragma once
#import <Foundation/Foundation.h>
// Paths come only from the current account's verified native resolver. The
// account-specific head_image root is mandatory; no caller-supplied path API.
NSData *WCTReadAvatarFile(NSString *nativePath, NSString *nativeRoot);
