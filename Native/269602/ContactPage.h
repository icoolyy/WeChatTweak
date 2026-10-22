#import <Foundation/Foundation.h>

// Pure pagination over an owned validated snapshot. This does not enumerate the
// database. Requires a verified account scope before the HTTP layer may use it.
NSDictionary *WCTContactPage(NSArray<NSDictionary *> *contacts, NSString *keyword,
                             BOOL pinyin, BOOL fuzzy, NSString *accountScope,
                             NSString *epoch, NSString *cursor, NSUInteger limit,
                             NSData *signingKey);
