#import "ContactSearch.h"
#include <stdio.h>

static unsigned failures;
static void check(BOOL condition, const char *name) {
    if (!condition) { ++failures; fprintf(stderr, "FAIL: %s\n", name); }
}

int main(void) { @autoreleasepool {
    NSArray *contacts = @[
        @{@"id":@"wxid_fixture_a", @"nickname":@"王小明", @"remark":@"产品经理",
          @"alias":@"Alice", @"remarkPinyin":@"chanpinjingli", @"remarkInitials":@"cpjl",
          @"nicknamePinyin":@"wangxiaoming", @"nicknameInitials":@"wxm"},
        @{@"id":@"wxid_fixture_b", @"nickname":@"小王", @"remark":@"", @"alias":@"Bob"},
        @{@"id":@"filehelper", @"nickname":@"文件传输助手", @"remark":@""}
    ];
    check(WCTSearchContacts(contacts,@"王",NO,YES,100).count==2, "Chinese fuzzy search");
    NSArray *remark = WCTSearchContacts(contacts,@"产品经理",NO,NO,100);
    check(remark.count==1, "exact remark search");
    if (remark.count) {
        check([remark[0][@"arg"] isEqual:@"wxid_fixture_a"], "stable ID survives display rename");
        check([remark[0][@"title"] isEqual:@"产品经理"], "remark is preferred display title");
        check(remark[0][@"remarkPinyin"]==nil, "private matching fields not returned");
    }
    check(WCTSearchContacts(contacts,@"chanpin",NO,YES,100).count==0, "pinyin opt-out");
    check(WCTSearchContacts(contacts,@"chanpin",YES,YES,100).count==1, "remark pinyin");
    check(WCTSearchContacts(contacts,@"CPJL",YES,NO,100).count==1, "case insensitive initials");
    check(WCTSearchContacts(contacts,@"alice",NO,NO,100).count==1, "case insensitive alias");
    check(WCTSearchContacts(contacts,@"产品",NO,NO,100).count==0, "exact excludes substring");
    check(WCTSearchContacts(contacts,@"wxid_fixture_b",NO,NO,100).count==1, "stable ID search");
    check(WCTSearchContacts(contacts,@"missing",YES,YES,100).count==0, "no match");
    NSMutableArray *many=[NSMutableArray array];
    for (unsigned i=0;i<150;++i)
        [many addObject:@{@"id":[NSString stringWithFormat:@"fixture_%03u",i], @"nickname":@"same"}];
    NSArray *limited=WCTSearchContacts(many,@"",YES,YES,1000);
    check(limited.count==100, "result limit hard cap");
    if (limited.count==100)
        check([limited[99][@"arg"] isEqual:@"fixture_099"], "stable ID tie-break order");
    check(WCTSearchContacts(contacts,@"",YES,YES,0).count==0, "zero caller limit");
    printf("contact search failures=%u\n",failures);
    return failures ? 1:0;
} }
