#include "NativeMutex.h"
#include <mutex>
#include <thread>
#include <atomic>
#include <stdio.h>

int main() {
    unsigned failures=0;
    std::mutex normal;
    normal.lock();normal.unlock(); // Force the same live state as a used native lock.
    {
        WCTNativeMutex lock;
        if(lock.acquire((uintptr_t)normal.native_handle())!=WCTLockAcquired) {
            ++failures;fprintf(stderr,"FAIL: initialized std::mutex native handle\n");
        }
    }
    std::recursive_mutex recursive;
    {
        WCTNativeMutex lock;
        if(lock.acquire((uintptr_t)recursive.native_handle())!=WCTLockAcquired) {
            ++failures;fprintf(stderr,"FAIL: initialized std::recursive_mutex native handle\n");
        }
    }
    if(pthread_mutex_trylock(normal.native_handle())) ++failures;
    else pthread_mutex_unlock(normal.native_handle());
    std::atomic<bool> owned=false,done=false;
    std::thread worker([&]{normal.lock();owned=true;while(!done.load()) std::this_thread::yield();normal.unlock();});
    while(!owned.load()) std::this_thread::yield();
    {
        WCTNativeMutex lock;
        if(lock.acquire((uintptr_t)normal.native_handle())!=WCTLockBusy) {
            ++failures;fprintf(stderr,"FAIL: busy lock is nonblocking\n");
        }
    }
    done=true;worker.join();
    pthread_mutex_t invalid={};
    WCTNativeMutex rejected;
    if(rejected.acquire((uintptr_t)&invalid)!=WCTLockInvalid) ++failures;
    if(rejected.acquire(UINTPTR_MAX)!=WCTLockInvalid) ++failures;
    printf("native mutex failures=%u\n",failures);
    return failures?1:0;
}
