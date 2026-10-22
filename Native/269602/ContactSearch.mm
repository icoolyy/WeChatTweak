#import "ContactSearch.h"

NSArray<NSDictionary *> *WCTSearchContacts(NSArray<NSDictionary *> *contacts,
                                          NSString *keyword, BOOL pinyin,
                                          BOOL fuzzy, NSUInteger limit) {
    limit = MIN(limit, (NSUInteger)100);
    if (!limit) return @[];
    NSArray *fields = pinyin
        ? @[@"id",@"nickname",@"remark",@"alias",@"remarkPinyin",@"remarkInitials",@"nicknamePinyin",@"nicknameInitials"]
        : @[@"id",@"nickname",@"remark",@"alias"];
    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *contact in contacts) {
        BOOL matches = !keyword.length;
        for (NSString *field in fields) {
            if (matches) break;
            NSString *value = contact[field];
            if (!value.length) continue;
            matches = fuzzy ? [value rangeOfString:keyword options:options].location != NSNotFound
                            : [value compare:keyword options:options] == NSOrderedSame;
        }
        if (!matches) continue;
        NSString *identifier = contact[@"id"];
        NSString *nickname = contact[@"nickname"] ?: @"";
        NSString *remark = contact[@"remark"] ?: @"";
        NSString *title = remark.length ? remark : (nickname.length ? nickname : identifier);
        NSString *subtitle = remark.length && nickname.length ? nickname : (contact[@"alias"] ?: @"");
        [items addObject:@{@"id":identifier, @"arg":identifier, @"title":title,
                          @"subtitle":subtitle, @"remark":remark}];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult result = [a[@"title"] localizedStandardCompare:b[@"title"]];
        return result == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : result;
    }];
    if (items.count > limit) [items removeObjectsInRange:NSMakeRange(limit, items.count-limit)];
    return [items copy];
}
