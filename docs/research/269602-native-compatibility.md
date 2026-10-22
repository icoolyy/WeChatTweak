# 微信 4.1.13 (269602) 验证记录

日期：2026-10-22。以下区分本机直接验证、上游报告和未完成工作。

## 本机应用与补丁位置

- Apple Silicon，App Store 微信 `4.1.13`，`CFBundleVersion=269602`。
- 业务模块：`Contents/Resources/wechat.dylib`，342,999,376 字节，包含 arm64/x86_64 两个切片。
- 原模块 SHA-256：`6e82322680d7747020c305f67e932b235fe68b22578c24d9c524dabb31a4694a`。
- 主程序是启动器，不适合继续使用旧版业务函数地址。

| 功能 | arm64 VA | 文件偏移 | 本机原始字节 | 配置补丁字节 |
|---|---|---|---|---|
| revoke | `0x44de938` | `0xee7a938` | `F44FBEA9FD7B01A9` | `00008052C0035FD6` |
| multiInstance | `0x27370c` | `0xac0f70c` | `FF0306D1FC6F14A9` | `20008052C0035FD6` |

地址来源为 [上游 PR #1042](https://github.com/sunnyyoung/WeChatTweak/pull/1042)。本次独立解析本机 Mach-O，并逐字节核对，两个地址均匹配。没有直接执行该 PR 的安装脚本或复用其补丁器。

本地聚焦反汇编确认两处均为函数入口。revoke 入口保存 `x20/x19`、`x29/x30`，随后构造比较字面量；multiInstance 入口建立 `0x180` 字节栈帧。上游给出了撤回判定和单实例检测的进一步语义证据，本机尚未完成真实消息撤回与第二实例验收，不能用静态匹配代替行为结论。

[PR #1043](https://github.com/sunnyyoung/WeChatTweak/pull/1043) 使用另一组保留/隐藏提示的补丁点。本分支没有混合两种策略。

## 无写入预检

执行本分支构建的 CLI：

```text
wechattweak patch --config config.json --dry-run
WeChat: 4.1.13 (269602)
Preflight passed: 2 writes, 0 already patched
.../Contents/Resources/wechat.dylib @ 0xee7a938: 8 bytes
.../Contents/Resources/wechat.dylib @ 0xac0f70c: 8 bytes
Dry run: no files changed
```

`doctor --json` 报告 `patchState=ready`、`pendingWrites=2`、`unverifiedLegacyEntries=0`、`contactsBridgeAvailable=false`。`ready` 表示文件和字节预检可通过，不能解释为联系人功能或消息级行为已验证。

## 真实应用包副本的事务验证

为隔离原安装，在临时副本保留禁用的主入口，并将副本 bundle ID 改为 `test.wechattweak.native-copy`，然后重新签名得到有效实验基线。使用本分支实际 CLI 对该副本执行 `patch`：两个补丁写入、完整备份与 `codesign --verify --deep --strict` 全部成功；随后 `doctor` 报告两个位置均已补丁。

再通过实际 CLI 执行 `restore`，恢复包通过同样的严格签名验证，恢复后的业务模块 SHA-256 回到上表原值。原 `/Applications/WeChat.app` 业务模块的 SHA-256 仍为原值。该验证覆盖真实包的补丁、签名与整包恢复，不覆盖正常主入口启动、消息撤回或多开行为。临时实验副本和备份在记录结果后删除，不是用户安装的备份。

## 加载探针

研究源码为 `Native/Probes/load_probe.c`。它仅在构造函数中写入加载标记及指定类是否存在，然后 `_exit(0)`，不枚举账号或联系人。

探针只在临时应用副本执行。运行前，将该副本 arm64 的 `LC_MAIN` 入口 `0xbf98` 从原 `01000014` 改为 `C0035FD6`（`ret`），并重签副本。这样，即使系统忽略注入变量，副本也不会进入 `WeChatMain`。随后对副本使用 `DYLD_INSERT_LIBRARIES`，进程退出码为 0，结果：

```text
native_probe_loaded=1
MMServiceCenter=0
ContactStorage=0
MMContactSearchLogic=0
WCContactData=0
```

该实验只证明重签的此类副本可以执行注入的原生探针，以及这些旧 Objective-C 类未注册。它没有证明 App Store 原签名允许同样注入、没有实现长期加载生命周期、没有读取联系人，也没有证明桥接权限和凭据存储路径可用。禁止将这个会退出进程的探针安装到日常微信。

## 联系人桥接的实际阻塞

本机业务模块的全局已定义导出仅见 `_WeChatMain` 和 `_SetWeixinCallbackFunc`。检查后者的代码，只能确认它按索引将回调指针写入两个槽，不能推断为联系人枚举或打开聊天接口，因此未调用它。

模块中存在 `mmui::ContactServiceWrapper`、`mmui::SearchContactView`、`OpenChatSingleWindow` 等 Qt 类型/方法名字符串，但字符串不是已验证的可调用 ABI。当前尚缺：

1. 登录后联系人服务实例的可靠获取方式。
2. 真实联系人结构、稳定 ID、返回对象所有权和线程规则。
3. 按稳定 ID 打开会话的函数及成功确认方式。
4. 登录退出和微信重启后的对象重新获取方式。

因此计划 Task 4 的完整门槛没有通过，Task 5 未实现。未启动 `48065` 服务、未创建凭据或启动项、未用空联系人/模拟数据返回成功。Raycast 当前交付独立诊断功能；完整搜索与打开聊天仍未完成。

## 继续定位：Qt 元数据与只读对象探针

新增可复现的离线工具 `Native/Research/inspect_269602.py`，先校验整个原始模块 SHA-256，再解析 arm64 的 Qt 元数据、`LC_FUNCTION_STARTS` 和候选虚表。真实模块执行输出为：

```text
Parsed metaobjects 1294
function starts 373953 metaObject implementations 1216
mapped mmui vtables 1341
```

输出不含账号数据。工具拒绝 SHA 不匹配的文件，且不覆盖已有输出目录。以下是后续运行时探针使用的静态对应关系，不是可调用 ABI：

| 类型/候选 | 虚表 VA | 元对象 VA / 证据 |
|---|---|---|
| WeChatApplication | `0x95a38e0` | `0x9596d38` |
| ContactServiceWrapper | `0x95e6960` | `0x959a9c8` |
| ContactsManagerDetailModel | `0x95eae30` | `0x959ade8` |
| MainWindow | `0x9605c90` | `0x959c648` |
| SearchContentView | `0x961baa0` | `0x959d9c8` |
| ContactService 析构候选 | `0x9878088` | `0x3b6e248` 的析构日志及 vptr 写入；构造候选 `0x3b6dd64` |

`GetContactList` 日志引用对应函数 `0x27cf52c`。反汇编显示它遍历输入的名字容器、查询缓存并构建结果集合；不能把它直接当成全量联系人枚举。搜索得到的 `GetAllContactLab…` 在引用处构造的是标签相关名称，也不能作为全量联系人接口的证明。Qt 中 `GotoChatAndCloseSPWindow` 为 signal，其生成代码调用 `QMetaObject::activate`，不能把发射此信号等同于成功打开聊天。

原生 C++ RTTI 类型名大量被替换为散列样式名称，仅按可读 `ContactService` 搜索 RTTI 会漏检；Qt 元数据与指令引用是当前更可靠的定位线索。另核对了 MIT 项目 macfriends-cli，其原生适配器仍返回 fixture 与 `contacts_primitive_unresolved`，未将它当成真实实现复用。

新增 `Native/Probes/object_inventory.c` 和堆扫描测试。探针等待 30 秒，在匹配 arm64 UUID `CDB81058-0FAC-3518-95F5-C0CC7860F9B5` 后只统计候选虚表，不调用对象方法、不输出联系人或内存地址。测试覆盖普通对象、控制块后对象、释放后排除、缺少匹配模块、0600 输出、拒绝覆盖文件及跟随符号链接；`rtk proxy python3 tools/test_native_probes.py` 全部通过。控制块后的对象测试先复现漏检（3/4），修正后为 4/4，释放后为 0。

真实运行时验证准备在 `/tmp/wechattweak-runtime-inventory/WeChat.app` 的重签副本进行，该副本已通过 `codesign --verify --deep --strict`，原安装未改动。用户随后明确允许退出并启动临时副本，已正常退出原微信并执行加载。首次真实扫描在系统 caulk 分配区崩溃：崩溃栈为 caulk::…::zone_enumerate → wct_heap_inventory → inventory_once。原因是该分配区要求非空 memory_reader_t，而最初只在系统默认分配区测试的 NULL 回调不适用。新增注册自定义 malloc zone 的回归，先复现 failed_zones=1，再改为向所有分配区传递显式当前进程读取回调，回归为 failed_zones=0；独立宿主注入测试重新通过。在同一获准临时副本重试已成功：module_match=1、scan_result=0、failed_zones=0；WeChatApplication=1、WindowManager=1、MainWindowSecondary=1、ChatSessionList=2、SearchContentView=1、ContactServiceDestructorCandidate=1，联系人包装类/详情模型/表格视图均为 0。界面确认已登录，扫描后进程保持运行。此结果仅证明候选对象可被观察，真实联系人枚举和打开聊天仍未验收。

## 真实缓存字段与原生打开会话验证

用户批准临时会话控制后，在登录的临时副本完成以下只读验证。可复现脚本为 `Native/Research/inspect_live_269602.py`，仅接受已停止的指定临时进程、正确 UUID，不执行目标表达式，也不输出联系人名字或 ID。

服务获取路径已由指令和运行时对象类型共同确认：模块全局 `0x9e66158` → 管理器（vtable `0x98c53d0`）→ `+0x68` 账号管理器（`0x98ba858`）→ `+0x368` 服务注册表（`0x98b87f8`）→ `+0x70` 注册表中 vtable `0x98b92d8` 的联系人存储对象。注册表和联系人主缓存均为 libc++ unordered_map 布局；主缓存偏移 `0x98`，节点键在 `+0x10`，记录 shared_ptr 在 `+0x28`。运行时遍历条数与容器声明条数一致，所有记录的 `+0x8` 稳定 ID 与索引键相同。

字段绑定函数 `0x4844efc` 直接把数据库字段名与结构偏移关联，独立于显示名称推测：`username=0x8`、`alias=0x20`、`encrypt_username=0x38`、`remark=0x60`、`remark_quan_pin=0x78`、`remark_pin_yin_initial=0x90`、`nick_name=0xa8`、`pin_yin_initial=0xc0`、`quan_pin=0xd8`。内置 filehelper 的 ID 与昵称已匹配。缓存快照证明真实记录和稳定身份映射，不证明整个数据库的加载覆盖范围。`0x108` 的第二索引是按 encrypt_username 哈希建立的索引，不能把它的条数当成全量好友数。原生查找 `0x4148a3c` 与删除 `0x4148dbc` 都持有存储对象 `+0x130` 的 std::mutex；注册表查找 `0x41343c4` 持有 `+0x30` 的 recursive_mutex。运行中的适配器仍需正确使用同步和生命周期规则。

原生打开会话入口 `0x296598` 的实参由调用点 `0x170f234` 和 `0x296c40` 及被调函数共同核对：`x0` 为全局 `0x9f2ffb0` 指向的 WeChatApplication（vtable `0x95a38e0`），`x1` 指向 24 字节 libc++ string，`x2` 指向可为空的 shared_ptr 引用，`x3/x4=0` 为已观察到的默认路径。返回值为 void，不能拿寄存器残值判断成功。

`Native/Probes/open_chat_probe.c` 先检查主线程、UUID、入口 32 字节和应用对象类型，仅以固定内置 `filehelper` 调用该入口。真实调用返回后，界面明确切到 File Transfer，输入框为空，未输入或发送消息。随后程序从 ChatMasterViewModel（vtable `0x95c3c60`）的 `+0xf8` 会话列表 → `+0x40` 已选 cell → `+0x148` SessionKey 核对 filehelper，返回 1。该路径来自 `0xa256e8`、`0xa47f60` 和 `0x1af10`，也校验 QObject back-pointer 和 cell 类型。先前尝试的 model+0x1f0 是待处理请求字段，完成后为空，不能作为会话打开确认。

该实验已经证明内置目标的真实原生打开及程序确认。进一步已确认不依赖堆扫描的已选模型路径：WeChatApplication+0x10 → pimpl[0] LoginState（0x95a36a0）→ +0x28 MainWindow（0x9700e58）→ +0x390 的 map 中 key=0 的 ChatMasterView（0x95c1ca8）→ +0x168 保存的接口指针减 0x10 → ChatMasterViewModel（0x95c3c60）；真实只读路径和 C 探针均确认 filehelper 已选中。该状态路径可用于区分登录阶段。

新增 Native/269602/ContactSearch 与 ContactCache：搜索的中文、备注、别名、拼音、首字母、稳定 ID 和结果上限测试先为 7 项失败，实施后全部通过；缓存读取的有效快照测试先失败，实施后与末项 ID 错误、循环链表、截断读取、声明条数错误及超大条数拒绝测试全部通过。尚需在运行进程内以正确锁和生命周期规则接入这些组件。

一般联系人搜索接口、非内置会话、登录退出/重启后的重新获取、鉴权通信及自动加载安装仍需完成，不能将此探针视为已交付的完整桥接。

## 构建环境记录

本机 CLT 存在三项基线问题：SwiftPM 私有接口与动态库不一致、重复 `SwiftBridging` module map，以及没有 XCTest。系统工具链文件未被修改；验证通过临时复制的 ManifestAPI/PluginAPI 接口、VFS overlay 和任务内缓存进行。回归套件使用真实 Swift 核心代码及独立可执行测试程序，不依赖 XCTest。

原 Makefile 的双架构一次构建依赖本机不存在的 `xcbuild`，现改成单架构分别构建后用 `lipo` 合并。正常工具链下使用 `make build`；本机验证使用 `make build SWIFT=/tmp/wechattweak-swift`。该临时路径不是项目运行依赖，也不应写进普通用户的安装配置。

完整功能仍未验收；后续记录必须据真实命令输出更新，不能将本文件作为支持声明。
