#pragma once
#include "Module.h"
#include <mach/mach.h>
#include <mach/mach_vm.h>

static inline int WCTReadBytes(uintptr_t address, void *output, size_t size) {
    if(!address || address>UINTPTR_MAX-size) return 0;
    mach_vm_size_t copied=0;
    return mach_vm_read_overwrite(mach_task_self(),address,size,
        (mach_vm_address_t)output,&copied)==KERN_SUCCESS && copied==size;
}
static inline uintptr_t WCTReadPointer(uintptr_t address) {
    uintptr_t value=0;return WCTReadBytes(address,&value,8)?value:0;
}
static inline uintptr_t WCTLoginState(uintptr_t base) {
    uintptr_t app=WCTReadPointer(base+0x9f2ffb0);
    if(!app || WCTReadPointer(app)!=base+0x95a38e0) return 0;
    uintptr_t data=WCTReadPointer(app+0x10);
    uintptr_t state=data?WCTReadPointer(data):0;
    return state && WCTReadPointer(state)==base+0x95a36a0 ? state:0;
}
static inline uintptr_t WCTViewModel(uintptr_t base) {
    uintptr_t state=WCTLoginState(base);
    uintptr_t window=state?WCTReadPointer(state+0x28):0;
    if(!window || WCTReadPointer(window)!=base+0x9700e58) return 0;
    uintptr_t node=WCTReadPointer(window+0x390),view=0;
    for(unsigned i=0;node && i<256;++i) {
        if(node>UINTPTR_MAX-0x30) return 0;
        int32_t key=(int32_t)WCTReadPointer(node+0x20);
        if(key==0) {view=WCTReadPointer(node+0x28);break;}
        node=WCTReadPointer(node+(key<0?8:0));
    }
    if(!view || WCTReadPointer(view)!=base+0x95c1ca8) return 0;
    uintptr_t interface=WCTReadPointer(view+0x168);
    if(interface<16) return 0;
    uintptr_t model=interface-16;
    if(WCTReadPointer(model)!=base+0x95c3c60) return 0;
    uintptr_t data=WCTReadPointer(model+8);
    return data && WCTReadPointer(data+8)==model ? model:0;
}
static inline uintptr_t WCTSelectedKey(uintptr_t base) {
    uintptr_t model=WCTViewModel(base);
    uintptr_t list=model?WCTReadPointer(model+0xf8):0;
    uintptr_t cell=list?WCTReadPointer(list+0x40):0;
    uintptr_t type=cell?WCTReadPointer(cell):0;
    if(type!=base+0x95c3d28 && type!=base+0x96b7a90) return 0;
    return cell+0x148;
}
