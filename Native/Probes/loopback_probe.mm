// Bounded communication feasibility probe, not the contacts HTTP service.
// Only GET /probe is supported. It exposes authenticated, account-free health.
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <atomic>
#include <string>
#include <chrono>
#include <algorithm>

static std::atomic<int> listener{-1};
static const char *token_path="/tmp/wechattweak-runtime-inventory/probe-token";
extern "C" void wct_loopback_probe_stop(void) {
    int fd=listener.exchange(-1);
    if(fd>=0) close(fd);
}

extern "C" int wct_loopback_probe_start(char *(*health)(void),void (*release)(void*)) {
    if(!health || !release || listener.load()>=0) return -1;
    int fd=socket(AF_INET,SOCK_STREAM,0);
    if(fd<0) return -2;
    sockaddr_in address={};address.sin_family=AF_INET;address.sin_port=htons(48065);
    address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(fd,(sockaddr*)&address,sizeof(address)) || listen(fd,4)) {close(fd);return -3;}
    fcntl(fd,F_SETFD,FD_CLOEXEC);fcntl(fd,F_SETFL,O_NONBLOCK);
    int output=open(token_path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(output<0) {close(fd);return -4;}
    unsigned char random[32];arc4random_buf(random,sizeof(random));
    std::string token;
    const char *hex="0123456789abcdef";
    for(unsigned char b:random) {token+=hex[b>>4];token+=hex[b&15];}
    struct stat created={};
    bool saved=write(output,token.data(),token.size())==(ssize_t)token.size() && !fstat(output,&created);
    close(output);
    if(!saved) {close(fd);unlink(token_path);return -5;}
    listener.store(fd);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(120);
        while(listener.load()==fd && std::chrono::steady_clock::now()<deadline) { @autoreleasepool {
            pollfd waiting={fd,POLLIN,0};
            if(poll(&waiting,1,100)<=0) continue;
            int client=accept(fd,nullptr,nullptr);
            if(client<0) continue;
            // Darwin can inherit O_NONBLOCK from the listener. Explicitly choose
            // blocking, bounded reads; EAGAIN must not look like a short request.
            int flags=fcntl(client,F_GETFL,0);
            if(flags<0 || fcntl(client,F_SETFL,flags&~O_NONBLOCK)<0) {close(client);continue;}
            fcntl(client,F_SETFD,FD_CLOEXEC);
            int one=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
            timeval timeout={1,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
            std::string request;char chunk[1024];
            while(request.size()<2048 && request.find("\r\n\r\n")==std::string::npos) {
                ssize_t n=recv(client,chunk,std::min(sizeof(chunk),2048-request.size()),0);
                if(n<=0) break;request.append(chunk,n);
            }
            int status=400;std::string body="{\"error\":{\"code\":\"invalid_probe_request\"}}";
            size_t end=request.find("\r\n\r\n");
            if(end!=std::string::npos && request.rfind("GET /probe HTTP/1.1\r\n",0)==0) {
                bool origin=false,duplicate=false;std::string authorization;
                size_t at=request.find("\r\n")+2;
                while(at<end) {
                    size_t next=request.find("\r\n",at),colon=request.find(':',at);
                    if(colon==std::string::npos || colon>=next) {duplicate=true;break;}
                    std::string key=request.substr(at,colon-at),value=request.substr(colon+1,next-colon-1);
                    std::transform(key.begin(),key.end(),key.begin(),[](unsigned char c){return (char)tolower(c);});
                    while(!value.empty() && (value[0]==' ' || value[0]=='\t')) value.erase(0,1);
                    if(key=="origin") origin=true;
                    if(key=="authorization") {if(!authorization.empty()) duplicate=true;authorization=value;}
                    at=next+2;
                }
                std::string expected="Bearer "+token;
                unsigned difference=(unsigned)(authorization.size()^expected.size());
                if(authorization.size()==expected.size())
                    for(size_t i=0;i<expected.size();++i) difference|=(unsigned char)authorization[i]^(unsigned char)expected[i];
                status=origin?403:(duplicate?400:(difference?401:200));
                body=status==403?"{\"error\":{\"code\":\"origin_rejected\"}}":"{\"error\":{\"code\":\"unauthorized\"}}";
                if(status==200) {
                    __block NSData *data=nil;
                    dispatch_sync(dispatch_get_main_queue(),^{ @autoreleasepool {
                        char *raw=health();
                        if(raw) {data=[[NSString stringWithUTF8String:raw] dataUsingEncoding:NSUTF8StringEncoding];release(raw);}
                    }});
                    body=data?std::string((const char*)data.bytes,data.length):"{\"error\":{\"code\":\"native_failed\"}}";
                }
            }
            std::string response="HTTP/1.1 "+std::to_string(status)+" Probe\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+std::to_string(body.size())+"\r\n\r\n"+body;
            size_t sent=0;
            while(sent<response.size()) {ssize_t n=send(client,response.data()+sent,response.size()-sent,0);if(n<=0) break;sent+=n;}
            close(client);
        }}
        int expected=fd;
        if(listener.compare_exchange_strong(expected,-1)) close(fd);
        struct stat current={};
        if(!lstat(token_path,&current) && current.st_ino==created.st_ino && current.st_dev==created.st_dev) unlink(token_path);
    });
    return 0;
}
