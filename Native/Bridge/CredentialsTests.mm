#import "Credentials.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>

static unsigned failures;
static void check(BOOL condition,const char *name) {
    if(!condition) {++failures;fprintf(stderr,"FAIL: %s\n",name);}
}
int main(void) { @autoreleasepool {
    char scratch[]="/tmp/wct-credential-tests-XXXXXX";
    if(!mkdtemp(scratch)) return 1;
    NSString *root=[NSString stringWithUTF8String:scratch];
    NSString *path=[root stringByAppendingPathComponent:@"private/token"];
    NSError *error=nil;
    NSString *created=WCTLoadOrCreateToken(path,&error);
    check(created.length==64 && !error,"create 32 random bytes as 64 hex characters");
    struct stat metadata={};
    check(!lstat(path.fileSystemRepresentation,&metadata) && metadata.st_uid==getuid() &&
        (metadata.st_mode&0777)==0600 && S_ISREG(metadata.st_mode),"private owned regular credential file");
    error=nil;
    check(created && [WCTLoadOrCreateToken(path,&error) isEqual:created] && !error,"reuse valid credential across restart");
    NSString *other=[root stringByAppendingPathComponent:@"other/token"];
    NSString *second=WCTLoadOrCreateToken(other,&error);
    check(second.length==64 && ![second isEqual:created],"independent installations get different credentials");
    if(created) {
        chmod(path.fileSystemRepresentation,0644);error=nil;
        check(WCTLoadOrCreateToken(path,&error)==nil && error,"unsafe existing mode rejected");
        lstat(path.fileSystemRepresentation,&metadata);check((metadata.st_mode&0777)==0644,"unsafe mode not silently changed");
        chmod(path.fileSystemRepresentation,0600);
        [@"invalid" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];error=nil;
        check(WCTLoadOrCreateToken(path,&error)==nil && error,"malformed existing token rejected");
    }
    NSString *link=[root stringByAppendingPathComponent:@"link"];
    symlink(path.fileSystemRepresentation,link.fileSystemRepresentation);error=nil;
    check(WCTLoadOrCreateToken(link,&error)==nil && error,"symlink credential refused");
    NSString *fifo=[root stringByAppendingPathComponent:@"fifo"];
    mkfifo(fifo.fileSystemRepresentation,0600);error=nil;
    check(WCTLoadOrCreateToken(fifo,&error)==nil && error,"FIFO refused without blocking");
    NSString *unsafe=[root stringByAppendingPathComponent:@"unsafe"];
    mkdir(unsafe.fileSystemRepresentation,0777);chmod(unsafe.fileSystemRepresentation,0777);error=nil;
    check(WCTLoadOrCreateToken([unsafe stringByAppendingPathComponent:@"token"],&error)==nil && error,"writable credential directory refused");
    error=nil;check(WCTLoadOrCreateToken(@"relative-token",&error)==nil && error,"relative path refused");
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
    printf("bridge credential failures=%u\n",failures);
    return failures?1:0;
} }
