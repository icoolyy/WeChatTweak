#pragma once
#include <functional>
#include <memory>
#include <new>
#include <typeinfo>
// Matches this build's libc++ __function::__base<void()> virtual ABI. Only
// virtual calls cross runtimes; callback storage and destruction stay here.
class WCTForeignTask final {
    std::shared_ptr<const std::function<void()>> work;
public:
    explicit WCTForeignTask(std::function<void()> callback):work(std::make_shared<const std::function<void()>>(std::move(callback))){}
    virtual ~WCTForeignTask()=default;
    virtual WCTForeignTask *clone() const {return new WCTForeignTask(*this);}
    virtual void clone(void *destination) const {new(destination) WCTForeignTask(*this);}
    virtual void destroy() noexcept {this->~WCTForeignTask();}
    virtual void destroyDeallocate() noexcept {delete this;}
    virtual void invoke() {(*work)();}
    virtual const void *target(const std::type_info&) const noexcept {return nullptr;}
    virtual const std::type_info &targetType() const noexcept {return typeid(void);}
};
static_assert(sizeof(WCTForeignTask)<=24,"Must fit native function's inline buffer");
inline void *WCTMakeForeignTask(std::function<void()> callback){return new WCTForeignTask(std::move(callback));}
