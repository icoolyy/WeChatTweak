# 269602 原生适配器实施补充

本文件记录已观察到的 ABI 与边界，不代替完整产品验收。适用模块 UUID、原 SHA 和补丁位置见 `269602-native-compatibility.md`。

## 已实现边界

`Native/269602/Adapter.h` 使用 C ABI 返回 malloc-owned UTF-8 JSON；调用方必须用 `wct_native_free` 释放。所有目标操作必须在微信主线程执行，其他线程返回 `wrong_thread`。未匹配模块、登录状态、对象类型或字段边界时失败，不使用旧版本地址。

联系人来自当前 `ContactStorage` 的真实已加载缓存。适配器每次重新从管理器和服务注册表获取存储，不跨请求保留原生对象。它先以 trylock 获得注册表 recursive_mutex，再以 trylock 获得缓存 mutex；任何忙状态都立即失败并释放已持有锁，避免反向等待。持锁期间把经过键/ID/UTF-8/长度校验的记录复制为自有不可变对象，再释放锁完成搜索和 JSON 序列化。损坏末项不会返回前面的部分结果。支持来源标为 `loadedContacts`，没有把缓存条数当成数据库覆盖证明。

搜索返回 `{ok,source,session,items}`，每项 `id` 与 `arg` 均为真实稳定 ID。显示优先采用备注，然后昵称，再回退 ID。拼音字段只用于匹配，不进入响应。`fuzzy=0` 为字段精确匹配，`fuzzy=1` 为子串匹配；两者均忽略大小写、音调和全半角差异。最多返回 100 项。

原生打开入口相对地址 `0x296598`，在实际调用点确认的低层签名为：

```c
void open(void *application, const void *libcxx_string_24,
          const void *empty_shared_ptr_16, uintptr_t default0, uintptr_t default0);
```

适配器只允许缓存内已知 ID，校验入口 32 字节、应用 vtable 与主窗口模型后调用。输入字符串使用已验证的 libc++ long representation，参数有效期覆盖同步调用，原生路径自行复制后才安排异步工作。调用前释放所有存储锁。`request_open` 返回 `requested=true` 只表示请求已提交，不能当作打开成功。桥接必须随后读取真实已选 SessionKey 并比较 ID，同时核对 `session` 代次，最多等待五秒。会话 getter 采用已验证的直接主窗口路径，不扫描堆。

## 实际验证

四套独立宿主 fixture 通过 `rtk proxy python3 tools/test_native.py` 执行，覆盖 OS 原生互斥锁、缓存读取、搜索和 API 的失败边界。

真实临时微信中，`wct_native_probe_search_validation()` 返回 `15`，四个位分别证明中文、拼音、首字母及实际备注数据搜索。`health` 为 ready，两个能力可用。正式适配器以 `filehelper` 的 long string representation 提交打开请求，随后 getter 返回 `filehelper`，实际 UI 同样显示 File Transfer；没有输入或发送消息。

运行中锁签名与 SDK 的初始签名不同。首轮运行时布局拒绝已复现到本机标准 `std::mutex`/`std::recursive_mutex`；修正后 OS 原生锁、忙锁非阻塞和实际微信锁均通过。没有通过取消互斥或继续读取未知布局来绕过失败。

## 通信及凭据验证

`Native/Probes/loopback_probe.mm` 是限时可行性探针，只提供鉴权的 `/probe` 健康信息，没有联系人占位端点。实际临时微信成功绑定 `127.0.0.1:48065`。凭据为系统随机源生成的 32 字节、编码为 64 个十六进制字符，以 O_EXCL/O_NOFOLLOW 和 0600 写入 `/tmp/wechattweak-runtime-inventory/probe-token`。客户端核对当前 UID、权限和长度，未输出凭据值。

同一组 40 次真实请求中，无凭据/错误凭据均为 401，Origin 请求为 403，有效凭据为 200，且健康来自真实主线程适配器。首次压力测试暴露接受连接继承非阻塞标记后过早返回 400 的问题；显式设置接入连接的阻塞读取与超时后，同组 40 次请求无失败。此修正必须带入正式传输层。

该临时路径已证明可写和可读。正式安装的默认凭据位置计划为当前用户 `~/Library/Application Support/WeChatTweak/bridge-token`，安装流程仍需验证；开发测试可以显式指定任务临时路径。凭据不得通过健康响应、URL、日志或仓库内容传递。正式协议必须继续覆盖请求界限、超时、端口占用、退出清理及跨站拒绝。

## 尚待验收

已正常重启临时副本并重新登录：登录入口阶段为 not_logged_in、两个能力均为 false；进入主界面后为 ready，代次从 0 增加到 1，真实搜索验证再次返回 15，filehelper 请求和已选 ID 确认再次通过。新进程使用新的启动 nonce，没有复用旧进程对象。未执行账号注销或切换账号。

完整产品鉴权协议及配套 Raycast、非调试器自动加载和安装恢复还需完成。已加载联系人的工作能力不意味着已经完成这些交付项。
