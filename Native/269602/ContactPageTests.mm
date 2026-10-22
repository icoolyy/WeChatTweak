#import "ContactPage.h"
#include <stdio.h>
static unsigned failures;
static void check(BOOL condition,const char *name) {if(!condition){++failures;fprintf(stderr,"FAIL: %s\n",name);}}
int main(void) { @autoreleasepool {
    NSMutableArray *contacts=[NSMutableArray array];
    for(unsigned i=0;i<235;++i) [contacts addObject:@{@"id":[NSString stringWithFormat:@"fixture_%03u",i],@"nickname":@"same"}];
    NSData *key=[NSMutableData dataWithLength:32];NSString *scope=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    auto page = ^NSDictionary *(NSArray *items,NSString *query,NSString *account,NSString *epoch,NSString *cursor,NSUInteger limit){
        return WCTContactPage(items,query,YES,YES,account,epoch,cursor,limit,key);
    };
    NSDictionary *a=page(contacts,@"",scope,@"epoch1",nil,100);
    // Independently calculated using Python hashlib/hmac and canonical JSON.
    check([a[@"nextCursor"] isEqual:@"100:e5be694d54321b9b678ae00eac2c9db3f4600edfae8c2f9eac3ef2fc0e05b419:0e2764836428a98f716e20191eeae0781911a4cc3907842a71f7fcc7d22e7c8e"],"independent HMAC cursor vector");
    check([a[@"total"] unsignedIntegerValue]==235 && [a[@"items"] count]==100,"first page and total");
    check([a[@"source"] isEqual:@"loadedContacts"],"source remains explicit");
    NSDictionary *b=page(contacts,@"",scope,@"epoch1",a[@"nextCursor"],100);
    NSDictionary *c=page(contacts,@"",scope,@"epoch1",b[@"nextCursor"],100);
    check([b[@"items"] count]==100 && [c[@"items"] count]==35 && !c[@"nextCursor"],"three complete pages");
    NSMutableSet *seen=[NSMutableSet set];
    for(NSDictionary *p in @[a,b,c]) for(NSDictionary *item in p[@"items"]) [seen addObject:item[@"id"]];
    check(seen.count==235,"no duplicate or lost IDs");
    check([b[@"items"][0][@"id"] isEqual:@"fixture_100"],"stable ordering");
    NSArray *reversed=[[contacts reverseObjectEnumerator] allObjects];
    check([page(reversed,@"",scope,@"epoch1",a[@"nextCursor"],100)[@"items"] isEqual:b[@"items"]],"cache iteration order does not change pages");
    check([WCTContactPage(contacts,@"",NO,YES,scope,@"epoch1",a[@"nextCursor"],100,key)[@"ok"] isEqual:@NO],"pinyin option bound to cursor");
    check([WCTContactPage(contacts,@"",YES,NO,scope,@"epoch1",a[@"nextCursor"],100,key)[@"ok"] isEqual:@NO],"match mode bound to cursor");
    check([WCTContactPage(contacts,@"",YES,YES,scope,@"epoch1",a[@"nextCursor"],100,[NSData dataWithBytes:"different key" length:13])[@"ok"] isEqual:@NO],"invalid signing key refused");
    for(NSDictionary *bad in @[
        page(contacts,@"same",scope,@"epoch1",a[@"nextCursor"],100),
        page(contacts,@"",scope,@"epoch2",a[@"nextCursor"],100),
        page(contacts,@"",[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0],@"epoch1",a[@"nextCursor"],100),
        page(contacts,@"",scope,@"epoch1",[a[@"nextCursor"] stringByAppendingString:@"0"],100),
        page(contacts,@"",scope,@"epoch1",a[@"nextCursor"],99),
        page(contacts,@"",scope,@"epoch1",nil,0),page(contacts,@"",scope,@"epoch1",nil,101),
        page(contacts,@"",@"",@"epoch1",nil,100),
    ]) check([bad[@"ok"] isEqual:@NO],"bad cursor/query/account/epoch/limit refused");
    [contacts addObject:@{@"id":@"fixture_new",@"nickname":@"new"}];
    check([page(contacts,@"",scope,@"epoch1",a[@"nextCursor"],100)[@"error"][@"code"] isEqual:@"stale_cursor"],"cache mutation requires refresh");
    check([page(@[],@"",scope,@"epoch1",nil,100)[@"items"] count]==0,"empty snapshot valid");
    printf("contact page failures=%u\n",failures);return failures?1:0;
} }
