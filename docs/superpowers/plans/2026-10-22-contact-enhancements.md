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

- [ ] 写失败测试：有/无 `_MASReceipt/receipt`、异常 receipt 路径、旧 doctor JSON；断言缺字段兼容、默认不声明阻止更新。
- [ ] 运行对应 Swift 与 Raycast 测试，确认新增断言先失败。
- [ ] 实现只读渠道检测、管理页说明；静态检查当前内部更新入口并记录证据。纠正269602过时说明，保留防撤回/多开真实验收未完成状态。
- [ ] 运行 `rtk proxy /tmp/wechattweak-run` 和 raycast 内 `rtk proxy npm test`，通过后提交 `fix: report App Store update limitations accurately`。

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

### Task 5: 受限本地头像

**Files:** 新增 `Native/Research/avatar_cache_269602.md`、`Native/269602/AvatarCache.h/.mm`、`AvatarCacheTests.mm`、`raycast/src/services/avatarCache.ts`；修改 `Native/Bridge/Protocol.mm`、`NativeOperation.mm`、`Server.mm`、`raycast/src/bridge.ts`、`components/searchListltem.tsx`、生产源文件列表和原生测试工具。

**Interfaces:** `WCTReadLocalAvatar(identifier, accountIdentifier)` 只接受已校验联系人/账号，由已验证原生缓存路径解析；鉴权 `GET /wechat/avatar?id=<id>&epoch=<session>` 返回受限 JSON `{ mime: "image/png" | "image/jpeg", data: <base64> }`，解码后上限512KiB；缺失返回404。客户端 `avatar(id, context, signal?)` 输出按 scope 分区的 Raycast 可用缓存文件路径。

- [ ] 静态与临时副本验证缓存路径和账号归属，记录证据；无法证明时保留默认图标，明确缺口，不获取任意远端 URL。
- [ ] 写失败测试：正确账号命中、跨账号拒绝、路径穿越/父目录及末级符号链接拒绝、超限/伪 MIME 拒绝、缓存缺失默认图标；头像请求保持鉴权/期限/响应上限。
- [ ] 运行测试确认失败，再实现受限读取和客户端缓存；不把文件路径或账户标识暴露在 URL 中。
- [ ] 运行原生、传输与 Raycast 测试，核对真实头像及缺失回退，通过后提交 `feat: show verified local contact avatars`。

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
