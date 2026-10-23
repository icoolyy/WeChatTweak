#pragma once
#import <Foundation/Foundation.h>
NSURL *WCTAvatarDownloadURL(NSString *nativeURL);
// Ephemeral HTTPS, no cookies/credentials, bounded streaming; returns a cancel handle.
id WCTDownloadAvatar(NSURL *url,void (^completion)(NSData *image));
void WCTCancelAvatarDownload(id handle);
// Configuration injection for deterministic, network-free transport fixtures.
id WCTDownloadAvatarWithConfiguration(NSURL *url,NSURLSessionConfiguration *configuration,void (^completion)(NSData *image));
