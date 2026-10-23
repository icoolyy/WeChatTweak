#import "AvatarFile.h"
#include <unistd.h>
#include <stdio.h>
static unsigned failures;
static void check(BOOL value,const char *name){if(!value){++failures;fprintf(stderr,"FAIL: %s\n",name);}}
int main(){@autoreleasepool{
    NSFileManager *files=NSFileManager.defaultManager;
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *root=[directory stringByAppendingPathComponent:@"account/head_image"];
    [files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *image=[root stringByAppendingPathComponent:@"fixture"];
    NSData *bytes=[@"fixture avatar bytes" dataUsingEncoding:NSUTF8StringEncoding];
    [bytes writeToFile:image atomically:YES];
    check([WCTReadAvatarFile(image,root) isEqual:bytes],"reads owned bytes inside current native avatar root");
    NSString *other=[directory stringByAppendingPathComponent:@"other/head_image/image"];
    [files createDirectoryAtPath:other.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [bytes writeToFile:other atomically:YES];
    check(WCTReadAvatarFile(other,root)==nil,"another account path rejected");
    check(WCTReadAvatarFile([root stringByAppendingPathComponent:@"../head_image/fixture"],root)==nil,"parent traversal rejected");
    NSString *link=[root stringByAppendingPathComponent:@"link"];
    symlink(image.fileSystemRepresentation,link.fileSystemRepresentation);
    check(WCTReadAvatarFile(link,root)==nil,"final symlink rejected");
    NSString *parent=[root stringByAppendingPathComponent:@"parent"];
    symlink(root.fileSystemRepresentation,parent.fileSystemRepresentation);
    check(WCTReadAvatarFile([parent stringByAppendingPathComponent:@"fixture"],root)==nil,"intermediate symlink rejected");
    check(WCTReadAvatarFile(root,root)==nil,"directory cannot be read as avatar");
    NSString *large=[root stringByAppendingPathComponent:@"large"];
    [[NSMutableData dataWithLength:512*1024+1] writeToFile:large atomically:YES];
    check(WCTReadAvatarFile(large,root)==nil,"oversized native file rejected");
    check(WCTReadAvatarFile(image,directory)==nil,"root must be dedicated head_image directory");
    check(WCTReadAvatarFile([root stringByAppendingPathComponent:@"missing"],root)==nil,"missing avatar falls back");
    [files removeItemAtPath:directory error:nil];
    printf("avatar file failures=%u\n",failures);return failures?1:0;
}}
