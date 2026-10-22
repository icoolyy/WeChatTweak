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

真实运行时验证准备在 `/tmp/wechattweak-runtime-inventory/WeChat.app` 的重签副本进行，该副本已通过 `codesign --verify --deep --strict`，原安装未改动。此探针尚未注入真实微信：需要先正常退出当前微信，避免同账号并发，再启动临时副本。已向用户提出本次会话控制选择，未收到选择前不执行退出、启动或登录操作。真实联系人枚举和打开聊天仍未验收。

## 构建环境记录

本机 CLT 存在三项基线问题：SwiftPM 私有接口与动态库不一致、重复 `SwiftBridging` module map，以及没有 XCTest。系统工具链文件未被修改；验证通过临时复制的 ManifestAPI/PluginAPI 接口、VFS overlay 和任务内缓存进行。回归套件使用真实 Swift 核心代码及独立可执行测试程序，不依赖 XCTest。

原 Makefile 的双架构一次构建依赖本机不存在的 `xcbuild`，现改成单架构分别构建后用 `lipo` 合并。正常工具链下使用 `make build`；本机验证使用 `make build SWIFT=/tmp/wechattweak-swift`。该临时路径不是项目运行依赖，也不应写进普通用户的安装配置。

完整功能仍未验收；后续记录必须据真实命令输出更新，不能将本文件作为支持声明。
