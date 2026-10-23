#include "ForeignTask.h"
#include <cstdio>
#include <memory>
#include <cstddef>
static unsigned failures=0;
static void check(bool v,const char *n){if(!v){++failures;std::fprintf(stderr,"FAIL: %s\n",n);}}
int main(){
 int calls=0;auto lifetime=std::make_shared<int>(1);std::weak_ptr<int> weak=lifetime;
 auto *task=WCTMakeForeignTask([lifetime,&calls]{++calls;});lifetime.reset();
 check(task!=nullptr,"owned task is created");if(!task)return 1;
 auto **vt=*reinterpret_cast<void***>(task);
 using Clone=void *(*)(const void*);using Copy=void (*)(const void*,void*);using Action=void (*)(void*);
 void *copy=reinterpret_cast<Clone>(vt[2])(task);
 alignas(std::max_align_t) unsigned char placement[32];reinterpret_cast<Copy>(vt[3])(task,placement);
 reinterpret_cast<Action>(vt[6])(task);reinterpret_cast<Action>(vt[6])(copy);reinterpret_cast<Action>(vt[6])(placement);
 check(calls==3,"foreign invoke and cloned callbacks execute");
 reinterpret_cast<Action>(vt[5])(task);reinterpret_cast<Action>(vt[5])(copy);check(!weak.expired(),"placement owns callback");
 reinterpret_cast<Action>(vt[4])(placement);check(weak.expired(),"every ownership path releases callback");
 std::printf("foreign task failures=%u\n",failures);return failures?1:0;
}
