#import "Credentials.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <vector>

static NSString *failed(NSError **error,NSInteger code) {
    if(error) *error=[NSError errorWithDomain:@"WeChatTweak.Credentials" code:code
        userInfo:@{NSLocalizedDescriptionKey:@"Bridge credentials are unavailable or unsafe."}];
    return nil;
}
static NSString *readToken(int fd,NSError **error) {
    struct stat metadata={};
    if(fstat(fd,&metadata) || !S_ISREG(metadata.st_mode) || metadata.st_uid!=getuid() ||
       (metadata.st_mode&0777)!=0600 || metadata.st_size<64 || metadata.st_size>65) {
        close(fd);return failed(error,3);
    }
    char bytes[66]={0};size_t size=0;
    while(size<sizeof(bytes)) {
        ssize_t n=read(fd,bytes+size,sizeof(bytes)-size);
        if(n<0 && errno==EINTR) continue;
        if(n<0) {close(fd);return failed(error,4);}
        if(!n) break;
        size+=n;
    }
    close(fd);
    if(size==65 && bytes[64]=='\n') size=64;
    if(size!=64) return failed(error,5);
    for(size_t i=0;i<64;++i)
        if(!((bytes[i]>='0' && bytes[i]<='9') || (bytes[i]>='a' && bytes[i]<='f'))) return failed(error,5);
    return [[NSString alloc] initWithBytes:bytes length:64 encoding:NSASCIIStringEncoding];
}

NSString *WCTLoadOrCreateToken(NSString *path,NSError **error) {
    if(error) *error=nil;
    if(!path.isAbsolutePath || !path.lastPathComponent.length || path.length>4096) return failed(error,1);
    NSString *parent=path.stringByDeletingLastPathComponent;
    struct stat directory={};
    if(lstat(parent.fileSystemRepresentation,&directory)) {
        if(errno!=ENOENT || ![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:nil]) return failed(error,2);
        if(lstat(parent.fileSystemRepresentation,&directory)) return failed(error,2);
    }
    if(!S_ISDIR(directory.st_mode) || directory.st_uid!=getuid() || (directory.st_mode&0022)) return failed(error,2);
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if(fd>=0) return readToken(fd,error);
    if(errno!=ENOENT) return failed(error,3);
    // Publish a complete secret in one exclusive rename, so another launcher can
    // never observe a half-written token or replace an existing credential.
    NSString *pattern=[parent stringByAppendingPathComponent:@".bridge-token-XXXXXX"];
    const char *raw=pattern.fileSystemRepresentation;
    std::vector<char> temporary(raw,raw+strlen(raw)+1);
    fd=mkstemp(temporary.data());
    if(fd<0) return failed(error,4);
    fcntl(fd,F_SETFD,FD_CLOEXEC);
    unsigned char random[32];arc4random_buf(random,sizeof(random));
    char secret[64];const char *hex="0123456789abcdef";
    for(unsigned i=0;i<32;++i) {secret[2*i]=hex[random[i]>>4];secret[2*i+1]=hex[random[i]&15];}
    BOOL saved=!fchmod(fd,0600);size_t offset=0;
    while(saved && offset<sizeof(secret)) {
        ssize_t n=write(fd,secret+offset,sizeof(secret)-offset);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) {saved=NO;break;}
        offset+=n;
    }
    if(saved) saved=!fsync(fd);
    close(fd);
    if(!saved) {unlink(temporary.data());return failed(error,4);}
    if(renamex_np(temporary.data(),path.fileSystemRepresentation,RENAME_EXCL)) {
        int reason=errno;unlink(temporary.data());
        if(reason!=EEXIST) return failed(error,4);
    }
    fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    return fd<0 ? failed(error,3):readToken(fd,error);
}
