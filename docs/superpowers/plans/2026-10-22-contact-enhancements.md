# Contact Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完善当前微信构建的联系人搜索、持久化、头像、快捷访问和更新能力诊断。

**Architecture:** 在现有鉴权桥接和原生适配器上扩展能力。稳定账号身份是持久化与快捷链接的前提；原生调用先取得证据，再开放能力。渠道诊断独立实施，不依赖原生研究成功。

**Tech Stack:** Objective-C++/C++、Foundation、Swift CLI、TypeScript、React、Raycast API 1.93.2。

**Spec:** [已确认设计](../specs/2026-10-22-contact-enhancements-design.md)

## Global Constraints

- 仅 App Store 微信4.1.13 / build269602 / arm64；其他版本、官网渠道和 Intel 推迟。
- 沿用当前分支，不新增工作树，不读取聊天内容或发送消息，不自动推送。
- 最近10条、置顶100条；每页最多100条；保持鉴权、操作期限和 epoch 校验。
- 不强制退出正式微信；临时副本的重启、登录或切换账号验证需先协调。
- 不把缓存分页描述为完整联系人；不把设置说明描述为已阻止 App Store 更新。
- 不记录原始账号标识、凭证或联系人内容；能力不足时明确不可用。
- 本会话内实施，最后进行一次独立整体审查；不采用每任务子代理实现。

## Review Focus

- 登录状态变化或账号切换时，旧异步结果不能写入新账号或打开旧联系人（任务2、3、6）。
- 同账号重启后旧 epoch 必须失效，稳定作用域仍可恢复记录（任务2、3）。
- 联系人缓存并发变化时，分页不能静默重复或漏项（任务4）。
- 头像输入中的符号链接、非法类型和超大文件不能变成任意文件读取（任务5）。
- 分享、损坏或撤销的快捷链接不能绕过账号检查和桥接鉴权（任务6）。

---

### Task 1: 准确的渠道和更新诊断

**Files:** 修改 `Sources/WeChatTweakCore/AppInfo.swift`、`Sources/WeChatTweak/Tweak.swift`、`raycast/src/diagnostics.ts`、`raycast/src/manageTweak.tsx`、`config.json`；测试 `Tests/WeChatTweakCoreTests/AppInfoTests.swift`、`raycast/src/diagnostics.test.ts`。

**Interfaces:** doctor JSON 增加 `distribution: "appStore" | "unknown"` 和 `automaticUpdates: { status: "managedByAppStore" | "unsupported", independentlyBlocked: false }`。receipt 只证明当前检测到渠道，不证明阻止更新。

- [x] 写失败测试：有/无 `_MASReceipt/receipt`、异常 receipt 路径、旧 doctor JSON；断言缺字段兼容、默认不声明阻止更新。
- [x] 运行对应 Swift 与 Raycast 测试，确认新增断言先失败。
- [x] 实现只读渠道检测、管理页说明；静态检查当前内部更新入口并记录证据。纠正269602过时说明，保留防撤回/多开真实验收未完成状态。
- [x] 运行 `rtk proxy /tmp/wechattweak-run` 和 raycast 内 `rtk proxy npm test`，通过后提交 `fix: report App Store update limitations accurately`。

### Task 2: 原生身份研究与鉴权账号上下文

**Files:** 新增 `Native/Research/account_identity_269602.md`、`Native/269602/AccountIdentity.h/.mm`、`Native/269602/AccountIdentityTests.mm`；修改 `Native/269602/Adapter.h/.mm`、`Native/Bridge/Credentials.h/.mm`、`Native/Bridge/NativeOperation.mm`、`Native/Bridge/Protocol.mm`、`Makefile`、`tools/test_native.py`、`tools/test_bridge_transport.py`、`raycast/src/bridge.ts`、`raycast/src/bridge.test.ts`。

**Interfaces:** 适配器内部 `NSString *WCTCopyCurrentAccountIdentifier(void)`，仅主线程，返回受 ARC 管理的值或 nil；不暴露原始值给客户端。鉴权 `GET /wechat/context` 返回 `{ accountScope: string, session: string }`；客户端 `BridgeClient.accountContext(signal?: AbortSignal): Promise<AccountContext>`，`AccountContext = { accountScope: string; session: string }`。scope 为本机私钥对已验证标识的域分隔 HMAC-SHA256。

- [ ] 记录静态定位、指令边界、ABI、所有权、锁与生命周期。编写仅输出可用性和相等性结果的临时探针；未取得证据前不填写猜测入口地址。
- [ ] 协调临时副本验证：同账号重启相等、退出时不可用、不同账号不相等。若无法取得不同账号验证，保持持久能力关闭并明确记录具体缺口；继续独立任务。
- [ ] 写失败测试：HMAC 固定向量、私钥类型/权限拒绝、身份缺失、前后 epoch 变化、未鉴权 context 请求、响应禁止原始身份。
- [ ] 运行原生/协议测试确认失败，再实现身份适配、私钥派生与 context。旧桥接没有能力时客户端返回明确不支持，保持现有搜索可用。
- [ ] 运行 `rtk proxy python3 tools/test_native.py`、`rtk proxy python3 tools/test_bridge_transport.py` 和 Raycast 测试；结合探针验收后提交 `feat: expose verified account-scoped bridge context`。

### Task 3: 按账号持久化记录与当前联系人校验

**Files:** 修改 `raycast/src/services/contactBook.ts`、`contactService.ts`、`runtime.ts`、`raycast/src/hooks/useSearch.ts`、`raycast/src/types/index.ts`、`Native/Bridge/Protocol.mm`、`Native/Bridge/NativeOperation.mm`、`Native/269602/Adapter.h/.mm`；测试 `raycast/src/contactBook.test.ts`、`contactService.test.ts`、`bridge.test.ts` 和 `Native/Bridge/ProtocolTests.mm`。

**Interfaces:** `ContactBook.activate(context: AccountContext, signal?: AbortSignal)`、`read(context)`、`clearRecent(context)`；保存动作同时传入 context 与当前 SearchResult。鉴权 `GET /wechat/contact?id=<id>&epoch=<session>` 精确匹配缓存 ID，返回当前 SearchResult，未加载时明确 unavailable；`BridgeClient.resolveContact(id, context, signal?)` 执行调用与 scope/epoch 校验。返回 scope 必须与请求上下文相同。

- [ ] 写失败测试：账号 A/B 分区；A 重启保留10条最近和100条置顶；延迟旧操作拒绝；取消激活不清数据；损坏分区不影响另一分区；v1 数据不自动归属；恢复后失效 ID 不可打开。
- [ ] 运行 Raycast 测试确认失败，再实现 v2 分区存储、串行写队列、当前活动上下文检查与恢复校验；持久记录不保存旧 session 用作打开凭据。
- [ ] 在原生/协议测试中验证精确查询不采用模糊搜索，缺失/重复/多余参数拒绝，epoch 变化拒绝。
- [ ] 运行原生、传输和 Raycast 测试，实际验证重启恢复与账号隔离，通过后提交 `feat: persist verified contacts per account`。

### Task 4: 稳定缓存分页和原生完整查询调查

**Files:** 修改 `Native/269602/ContactSearch.h/.mm`、`ContactSearchTests.mm`、`Adapter.mm`、`Native/Bridge/NativeOperation.mm`、`Protocol.mm`、`raycast/src/bridge.ts`、`services/contactService.ts`、`hooks/useSearch.ts`、`index.tsx`；新增 `Native/Research/contact_sources_269602.md`；修改对应现有测试。

**Interfaces:** `searchPage(keyword, { cursor?, limit?, pinyin, fuzzy }, signal?)` 返回 `{ items, session, accountScope, source: "loadedContacts", total, nextCursor? }`。客户端保留现有 search 包装；服务端游标为有界、签名数据，绑定规范化查询、scope、epoch、排序后内容摘要和位置。每页1–100，非法值拒绝。

- [ ] 写失败测试：235条三页100/100/35，顺序稳定无重复；错误查询/epoch/scope/快照/签名/limit 拒绝；取消旧查询不能追加结果。
- [ ] 运行新增测试确认失败，再实现稳定排序分页和 Raycast 加载更多；快照变化显示刷新提示，不拼接新旧结果。
- [ ] 调查原生加载/查询服务，记录覆盖范围及所有权；未经运行时验证继续使用 `loadedContacts`。若存在已验证全量入口，再补独立测试后声明对应能力。
- [ ] 运行原生、传输、Raycast 测试及真实超过100条分页验收，通过后提交 `feat: paginate verified contact snapshots`。

### Task 5: 受限本地头像（按用户批准调整为当前会话）

**Files:** `Native/Research/avatar_cache_269602.md`、`Native/269602/AvatarCache.h/.mm`、`AvatarCacheTests.mm`、`raycast/src/services/avatarLoader.ts`；修改 Adapter、鉴权桥接协议/调度、客户端与联系人列表、生产源文件列表及原生测试工具。

**Interfaces:** `wct_native_avatar_json(id, expectedEpoch)` 只接受当前已校验联系人和桥接epoch，从该账号factory中的HeadCache复制内存；鉴权 `GET /wechat/avatar?id=<id>&epoch=<session>` 返回 `{ok,id,session,mime:"image/png",data,digest}`。原始编码图片上限512KiB，输出最多128像素、128KiB PNG，缺失404。客户端返回校验后的 data URI；只做命令实例内缓存，不保存文件，不依赖尚未验收的跨重启账号作用域。

- [x] 静态与临时副本确认缓存对象、匹配key/记录ID及图片数据；不获取远端URL或解密数据库。
- [x] 原生缓存损坏/超限/伪图片、鉴权/期限、旧epoch/未知ID/路径参数拒绝，以及客户端完整性/并发/会话清理回归。
- [x] 失败测试后实现受限读取和内存缓存；独立审查并修复队列名额抢占及旧会话阻塞。
- [x] 当前微信运行时读取、真实桥接拒绝用例、Raycast实际显示与缺失回退验收。
- [ ] 正式安装升级桥接库（本轮仅获准临时副本验证及恢复正式微信）。

跨账号真人验收仍缺第二账号，不声称已经完成；跨重启头像复用、全量头像和下载策略不在当前实现范围。

### Task 6: 可撤销安全快捷链接

**Files:** 新增 `raycast/src/services/quicklinks.ts`、`quicklinks.test.ts`、`raycast/src/openContact.tsx`；修改 `raycast/package.json`、`components/searchListltem.tsx`、`services/contactService.ts`。

**Interfaces:** `QuicklinkStore.create(context, contactID): Promise<string>`、`resolve(handle): Promise<{ accountScope, contactID }>`、`revoke(handle): Promise<void>`；句柄为32随机字节十六进制。专用命令 LaunchContext 仅接受 `{ v: "1", handle }`，额外字段拒绝。URL 使用当前扩展 author/name/command 与 Raycast 标准 context 编码。

- [ ] 写失败测试：URL 不含 token、scope、ID 或名称；未知/撤销/超长/额外字段拒绝；当前 B 账号拒绝 A 链接；A 重启重新解析当前联系人/epoch；只有打开确认才记录最近。
- [ ] 运行测试确认失败，再实现本地句柄存储、创建/撤销动作和启动命令；每次都执行桥接鉴权、context、resolveContact、confirmed open。
- [ ] 运行 Raycast 测试、typecheck、lint、build，真实创建/撤销及重启打开验收，通过后提交 `feat: add account-validated Raycast quicklinks`。

### Task 7: 整体验证、使用文档与审查

**Files:** 修改 `README.md`、`Native/README.md`、`raycast/README.md`、兼容性表及本计划检查项；以真实完成情况更新能力说明。

- [ ] 补充安装新版桥接/正常退出后重启、Raycast 根目录开发/构建、记录上限、账号切换、缓存来源、头像回退、链接撤销、App Store 设置步骤；明确未验收项。
- [ ] 顺序运行 `rtk proxy make test SWIFT=/tmp/wechattweak-swift`、`rtk proxy make build SWIFT=/tmp/wechattweak-swift`、`rtk proxy python3 tools/test_cli.py dist/wechattweak`；Raycast 内运行 test、typecheck、lint、build。Swift 构建不并发。
- [ ] 对最终代码进行一次独立整体审查，修复重要问题并只重跑相关检查；正式微信替换安装和重启需协调，不自动推送。
- [ ] 交付准确的实现/验证清单及用户最终操作步骤；原生验证不足的项列为未完成，不宣称全量支持。

## Execution status — 2026-10-22

- Task 1 已实现并通过23项 Swift、16项 Raycast 回归、CLI 集成、typecheck/lint/build；真实 doctor 检查确认 App Store 渠道、补丁已应用、现有桥接可用。
- Task 2 已完成临时副本的同账号两进程比较和未登录→登录→未登录观察；候选比较值一致，未登录时不可用。用户没有第二个测试账号，明确保留未验收限制；字段不可变语义、所有权及跨账号切换证据仍不足，未开放生产账号上下文与持久化。探针已从临时副本移除，正式微信重新启动且 doctor 确认桥接可用，正式安装未改动。
- Task 4 已提前完成纯分页核心及8套原生测试，含235条分页和独立 HMAC 向量；尚未连接 HTTP 或 Raycast，不视为分页功能已交付。
- Task 3、5、6 仍需账号身份和各自原生证据；没有开放未经验证的持久化、真实头像或快捷链接。
- 补充健康协议增强能力白名单与旧桥接默认关闭行为；Raycast 管理页明确展示会话内记录、最多100条、缓存范围、默认头像和持久链接尚未开放。


### 当前会话头像实施进展（2026-10-22）

用户已同意 Task 5 先按当前桥接 epoch 实现，不以跨重启账号作用域或第二测试账号作为前提；这不开放持久化或快捷链接。当前实现从原生内存缓存复制编码图片，故没有文件路径解析或符号链接访问。输出统一为最多128像素、128KiB PNG，并附SHA-256；Raycast 使用命令内有界内存缓存和受限并发，图片源为 data URI，2026-10-23已通过真实显示验收。

- [x] 原生缓存遍历、所有权复制、图片类型/大小/缩略图回归。
- [x] 鉴权头像接口、期限、参数/epoch约束和真实传输回归。
- [x] 客户端完整性验证、默认回退、有界缓存、并发和会话变化回归。
- [x] 独立审查并修复队列名额抢占与旧会话阻塞。
- [x] 临时微信真实缓存命中与精确ID约束验收（未逐一人工核对所有联系人）。
- [x] Raycast真实图片显示与缺失回退验收。
- [ ] 验收后更新已安装桥接及可用性文档。

证据、限制与待验收假设见 `Native/Research/avatar_cache_269602.md`。当前会话头像已通过临时副本运行时验收；正式安装仍需升级桥接，不把它等同于全量或跨账号验收。


### 完整头像后续验证（2026-10-23）

- [x] 当前账号原生路径解析与受限文件读取，新增路径/符号链接/大小fixture。
- [x] 原生回调调度与实际执行计数验证；缺失头像等待回归。
- [x] 修复轮询重复复制全联系人导致的主线程负担。
- [x] 用户授权的3个缺失头像HTTPS下载均返回有效图片。
- [x] 独立下载组件离线测试：域名/HTTPS、HTTP失败、非图片、流式超限。
- [x] 当前搜索结果直接下载范围授权（2026-10-23用户明确允许）。
- [x] 下载组件接入、当前搜索结果ID限制、全局并发/去重/epoch取消、批量真实验收与Raycast最终验收：最终构建100条中77张可用、23回退、0接口错误。
- [x] 临时副本正常退出、普通桥接备份恢复；正式微信已恢复ready、contacts/openChat可用。正式安装需另行升级。

本轮按需加载已完成最终构建的真实HTTP／客户端／Raycast验收；不把它表述为100%头像覆盖或第二账号已验收。13组原生、22项Raycast、类型检查/lint/构建与传输回归通过。
