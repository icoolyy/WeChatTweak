#pragma once
#include "Runtime.h"
#include <pthread.h>
#include <errno.h>

enum WCTLockResult { WCTLockAcquired, WCTLockBusy, WCTLockInvalid };
class WCTNativeMutex {
    pthread_mutex_t *held=nullptr;
public:
    WCTNativeMutex()=default;
    WCTNativeMutex(const WCTNativeMutex&)=delete;
    WCTNativeMutex& operator=(const WCTNativeMutex&)=delete;
    WCTLockResult acquire(uintptr_t address) {
        if(held) return WCTLockInvalid;
        uint64_t signature=0;
        // Initial normal mutex, live general mutex, live normal fast mutex.
        // The two live values are observed in this build and independently
        // exercised via the SDK's std::mutex / std::recursive_mutex handles.
        if(!WCTReadBytes(address,&signature,8) ||
           (signature!=0x32aaaba7 && signature!=0x4d555458 && signature!=0x4d55545a)) return WCTLockInvalid;
        int result=pthread_mutex_trylock((pthread_mutex_t*)address);
        if(result==EBUSY) return WCTLockBusy;
        if(result) return WCTLockInvalid;
        held=(pthread_mutex_t*)address;return WCTLockAcquired;
    }
    void release() {if(held) {pthread_mutex_unlock(held);held=nullptr;}}
    ~WCTNativeMutex() {release();}
};
