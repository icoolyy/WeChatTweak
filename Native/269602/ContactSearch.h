#import <Foundation/Foundation.h>

// Input is an owned snapshot. Private pinyin fields are used for matching only;
// returned items contain the stable ID, display title and optional remark.
NSArray<NSDictionary *> *WCTSearchContacts(NSArray<NSDictionary *> *contacts,
                                          NSString *keyword, BOOL pinyin,
                                          BOOL fuzzy, NSUInteger limit);
