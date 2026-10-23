#import "AvatarFile.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

namespace {
struct Descriptor {
    int value;
    explicit Descriptor(int fd):value(fd){}
    ~Descriptor(){if(value>=0)close(value);}
    void reset(int fd){if(value>=0)close(value);value=fd;}
};
static BOOL safePath(NSString *path) {
    return path.isAbsolutePath && [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<PATH_MAX &&
        [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound &&
        [path isEqual:path.stringByStandardizingPath];
}
}
NSData *WCTReadAvatarFile(NSString *nativePath,NSString *nativeRoot) {
    if(!safePath(nativePath) || !safePath(nativeRoot) || ![nativeRoot.lastPathComponent isEqual:@"head_image"] ||
       ![nativePath hasPrefix:[nativeRoot stringByAppendingString:@"/"]])return nil;
    // Resolve only the trusted native account root (macOS container roots may
    // themselves be redirected). Never resolve a caller's relative filename.
    char canonical[PATH_MAX];if(!realpath(nativeRoot.fileSystemRepresentation,canonical))return nil;
    NSString *root=[NSString stringWithUTF8String:canonical];if(!root)return nil;
    Descriptor directory(open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC));
    if(directory.value<0)return nil;
    for(NSString *component in root.pathComponents) {
        if([component isEqual:@"/"])continue;
        int next=openat(directory.value,component.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        if(next<0)return nil;directory.reset(next);
    }
    struct stat rootMetadata={};
    if(fstat(directory.value,&rootMetadata) || rootMetadata.st_uid!=getuid())return nil;
    NSString *relative=[nativePath substringFromIndex:nativeRoot.length+1];
    NSArray<NSString*> *parts=[relative componentsSeparatedByString:@"/"];
    for(NSUInteger i=0;i<parts.count;++i) {
        NSString *component=parts[i];
        if(!component.length || [component isEqual:@"."] || [component isEqual:@".."])return nil;
        if(i+1<parts.count) {
            int next=openat(directory.value,component.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if(next<0)return nil;directory.reset(next);continue;
        }
        Descriptor file(openat(directory.value,component.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC));
        struct stat before={},after={};
        if(file.value<0 || fstat(file.value,&before) || !S_ISREG(before.st_mode) || before.st_uid!=getuid() ||
           before.st_size<=0 || before.st_size>512*1024)return nil;
        NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)before.st_size];size_t offset=0;
        while(offset<data.length) {
            ssize_t count=read(file.value,(char*)data.mutableBytes+offset,data.length-offset);
            if(count<0 && errno==EINTR)continue;
            if(count<=0)return nil;offset+=(size_t)count;
        }
        if(fstat(file.value,&after) || before.st_dev!=after.st_dev || before.st_ino!=after.st_ino || before.st_size!=after.st_size ||
           before.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec || before.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec ||
           before.st_ctimespec.tv_sec!=after.st_ctimespec.tv_sec || before.st_ctimespec.tv_nsec!=after.st_ctimespec.tv_nsec)return nil;
        return [data copy];
    }
    return nil;
}
