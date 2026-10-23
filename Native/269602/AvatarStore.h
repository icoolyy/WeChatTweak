#pragma once
#import <Foundation/Foundation.h>
typedef void (^WCTAvatarResolve)(NSString *identifier,BOOL (^current)(void),void (^completion)(NSString *nativeURL));
typedef id (^WCTAvatarFetch)(NSURL *url,void (^completion)(NSData *image));
// All methods main-thread only. Resolver/fetch completions may use any queue.
@interface WCTAvatarStore : NSObject
- (instancetype)initWithResolver:(WCTAvatarResolve)resolver fetch:(WCTAvatarFetch)fetch cancel:(void (^)(id))cancel;
- (void)activate:(NSString *)epoch;
- (void)allow:(NSSet<NSString*> *)identifiers epoch:(NSString *)epoch;
- (NSData *)image:(NSString *)identifier;
- (BOOL)request:(NSString *)identifier;
- (BOOL)pending:(NSString *)identifier;
@end
