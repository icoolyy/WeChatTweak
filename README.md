# WeChatTweak · 微信 4.1.13 与 Raycast 适配

本项目在 WeChatTweak 基础上提供微信补丁 CLI、微信进程内的联系人桥接，以及配套 Raycast 扩展。当前分支为 `hotfix/wechat-4.1.13-raycast`，CLI 版本为 `2.1.0-dev`，属于本项目开发版本，不是上游官方发布版本。

**使用扩展前，必须先给准备启动的微信安装桥接：`patch --install-bridge`。** 安装 CLI、载入 Raycast 扩展或登录未安装桥接的原版微信，都不会自动启动联系人服务。安装成功后，正常从 Dock、Finder 或终端打开同一份微信即可，无需特殊启动参数。

## 当前支持范围

| 项目 | 状态 |
|---|---|
| 微信版本 | 已验证 App Store 微信 **4.1.13，build 269602** |
| 架构 | 原生桥接仅支持 **Apple Silicon / arm64**；CLI 双架构构建不代表 Intel 微信已适配 |
| Raycast 搜索与打开会话 | 已在真实微信副本及 Raycast 窗口验证，支持中文、备注、微信号和拼音 |
| 联系人范围 | 微信已经加载的联系人缓存；每次搜索最多 100 条，不是完整联系人数据库 |
| 置顶与最近联系人 | 支持最多 100 个置顶、最近 10 条；绑定当前桥接会话，世代变化后旧记录不显示 |
| 备份、安装和恢复 | 整包备份、暂存写入、重签名、严格签名校验及恢复保护已验证 |
| 防撤回、客户端多开 | 已配置对应字节补丁；真实消息和第二实例效果尚未验收 |
| 阻止自动更新 | App Store 管理更新；尚不支持单独阻止微信更新，管理页提供渠道诊断和设置说明 |
| 其他微信构建、官网版、x86_64 | 未验证本次原生桥接兼容性 |

重启及登录前后重新获取原生对象已验证；主动切换账号和长期运行的稳定性仍未完成实测。完整验证边界见 [兼容性记录](docs/compatibility.md)。

## 1. 准备环境和构建产物

需要 Apple Silicon Mac、上述版本的微信、已安装的 Raycast。源码构建使用 Swift 6、macOS SDK、Clang、`make`、`codesign`；自动化测试使用 Python 3。Raycast 扩展使用 Node.js **22.6 或更新版本**及 npm。Homebrew 不是使用本项目本地 CLI 的前置条件。

以下命令均在仓库根目录执行。如果已经有本分支构建好的 `dist/`，可以直接进入下一节；新获取的源码通常需要先构建：

```sh
make test
make build
```

构建后应得到以下三个文件，使用时一起保留：

```text
dist/
├── wechattweak                 # CLI
├── config.json                # 本分支补丁配置
└── WeChatTweakBridge.dylib     # arm64 原生桥接
```

默认配置和桥接库从 CLI 所在目录读取，不依赖终端当前目录。不要用官方 `brew install` / `brew upgrade wechattweak` 代替本分支构建，也不要让旧 `wechattweak-cli` 的 `install/uninstall` 命令接管本项目安装。

本机开发曾遇到 CLT 接口、module map 和 `xcbuild` 问题，验证时使用过任务临时工具链绕过。该临时路径不是项目依赖，不能作为通用安装命令；详见 [工具链验证记录](docs/research/269602-native-compatibility.md#构建环境记录)。已有完整 `dist/` 的使用不需要这些临时文件。

## 2. 检查微信并安装桥接

默认目标应用为 `/Applications/WeChat.app`。先执行只读检查：

```sh
./dist/wechattweak --version
./dist/wechattweak versions
./dist/wechattweak doctor --json
./dist/wechattweak patch --install-bridge --dry-run
```

预检会校验微信构建、所有补丁目标、预期指令、原生业务代码指纹、桥接库架构和加载命令空间。未安装时，当前构建通常显示两个待写入位置及 `Bridge preflight passed: install/update required`。已安装时可以显示无需改动。若构建或字节不匹配，先排查，不改版本号强行跳过校验。

**从微信菜单正常退出所有微信实例，包括此前用于测试的临时副本。** 然后在正常终端中安装：

```sh
sudo ./dist/wechattweak patch --install-bridge
```

默认 App Store 安装常需要管理员权限。如果当前用户对应用和相邻目录已有写权限，可以不加 `sudo`。诊断、启动微信和运行 Raycast 不需要 `sudo`。CLI 无法确认运行状态时会拒绝修改，请在正常终端执行。

安装会：

1. 保留完整原应用备份，包括原签名文件。
2. 在暂存副本中应用补丁、安装桥接库和自动加载标记。
3. 重新签名并进行严格校验。
4. 校验成功后替换目标应用；暂存或签名失败时保留原应用。

默认备份位置为：

```text
/Applications/.WeChatTweakBackups/<本次生成的ID>/
├── original.app
└── manifest.json
```

**保存 CLI 打印的准确备份路径。** 不同安装或更新可能生成不同备份；要恢复到最初未修改的应用，使用首次安装前的备份。磁盘需能容纳完整备份和暂存副本。

只运行 `patch` 会应用配置中的字节补丁。要让 Raycast 搜索可用，安装时必须带 `--install-bridge`。

## 3. 打开哪份微信，如何确认成功

安装完成后，正常启动刚才安装的目标应用：

```sh
open /Applications/WeChat.app
```

完成微信登录以及手机上的确认，再运行：

```sh
./dist/wechattweak doctor --json
```

正常情况下，输出包含：

```json
{
  "patchState": "applied",
  "contactsBridgeAvailable": true
}
```

这是诊断结果的部分字段，不是完整输出。两项状态的含义不同：

- `patchState` 描述 `--app` 指定应用文件中的补丁字节。`ready` 表示预检通过、**尚待应用**，不是桥接已经就绪。
- `contactsBridgeAvailable` 描述当前正在运行的桥接，通过身份校验且联系人和打开会话能力均可用时才是 `true`。

桥接随微信进程自动启动，退出微信即停止，只监听 `127.0.0.1:48065`。登录前可以响应健康检查，但联系人能力关闭；登录完成后才可搜索。无需 LLDB、`DYLD_INSERT_LIBRARIES` 或单独启动 HTTP 服务。

如果曾使用 `/tmp/wechattweak-runtime-inventory/WeChat.app` 测试，该目录中的副本与 `/Applications/WeChat.app` 是两份不同应用。给临时副本安装桥接，不会给正式安装同步安装。日常使用请按上一节安装正式应用，退出临时副本后再启动正式应用；不要让两份应用同时访问同一账号。临时副本可能随系统清理而消失，不作为长期安装位置。

## 4. 载入配套 Raycast 扩展

主扩展已基于 `raycast/upstream-wechat/` 的上游源码适配，日常构建入口是仓库中的 **`raycast/`**；`upstream-wechat/` 仅保留原始快照供追溯，不从该子目录载入旧版本。

在仓库根目录执行：

```sh
npm --prefix raycast ci
npm --prefix raycast test
npm --prefix raycast run typecheck
npm --prefix raycast run lint
npm --prefix raycast run build
npm --prefix raycast run dev
```

`build` 只生成本地 `raycast/dist/`，不会自动安装到 Raycast；`dev` 才会载入本地开发扩展并监听代码变化。开发使用时保持该进程运行，需要重新载入时再次执行 `npm --prefix raycast run dev`，不需要每次重新安装微信桥接。

在 Raycast 设置 → Extensions 中：

1. 启用带本地开发标识的 **WeChat**。
2. 停用旧商店版 **WeChat**，避免同名命令调用旧接口。
3. 之前的独立 **WeChatTweak Diagnostics** 已由本扩展替代，不再作为使用入口。

设置本地 WeChat 扩展的偏好：

| 偏好项 | 填写方式 |
|---|---|
| **WeChatTweak CLI Path** | 必填，本仓库 `dist/wechattweak` 的绝对路径；不能填目录或旧版 CLI |
| **Bridge Credential Path** | 通常留空，使用当前用户的默认凭证文件；填写时是文件路径，不是凭证内容 |
| **WeChat App Path** | 通常留空，使用 `/Applications/WeChat.app`；自定义时应与 CLI 安装、启动的应用一致 |
| **Restore Backup Path** | 仅恢复时需要，填 CLI 打印的完整备份目录，内含 `original.app` 和 `manifest.json` |

在仓库根目录可用以下命令输出需要填写的 CLI 绝对路径：

```sh
printf '%s/dist/wechattweak\n' "$PWD"
```

## 5. 日常搜索和管理

### Search Contacts and Chat

打开 Raycast，运行 **Search Contacts and Chat**。输入昵称、备注、微信号或拼音，选择联系人后按 Enter 打开微信会话。只有原生确认实际选中目标后，扩展才记录最近联系人并关闭窗口。

| 操作 | 快捷键 |
|---|---|
| 打开选中会话 | Enter |
| 置顶 / 取消置顶 | ⌘ ⇧ P |
| 复制微信号 | ⌘ C |
| 清除当前会话最近联系人 | ⌘ ⇧ X，确认后执行 |
| 重新搜索 | ⌘ R |

联系人界面使用默认头像。每次搜索最多返回 100 条已加载缓存记录；没有搜索到某人，不等于该联系人不存在。置顶上限 100 条，最近联系人保留 10 条，二者绑定当前已验证的桥接会话。微信重启或会话世代变化后旧记录不显示，需要重新搜索和置顶；不会直接复用旧扩展缺少会话身份的历史。

### Manage WeChatTweak

管理页分别展示 Homebrew、CLI、目标微信应用、字节补丁、桥接文件和当前运行桥接，支持：

- **只读预检**：调用本分支 CLI 的 `patch --install-bridge --dry-run`。
- **安装或更新 WeChatTweak**：确认后调用 `patch --install-bridge`；执行前先退出全部微信。
- **恢复原微信**：填写准确备份路径并确认后调用 `restore --backup`。
- **复制终端安装 / 恢复命令**：权限不足时在正常终端完成操作。

取消安装、恢复或清除历史的确认不会执行对应操作。管理页不会自动下载官方 2.0.1，也不会强制终止微信。

## 6. 常见问题

| 现象 | 原因与处理 |
|---|---|
| 微信已登录，但提示“微信桥接未启动”或连接失败 | 确认执行过 `patch --install-bridge`，并启动的是同一路径的微信；只登录未装桥接的原版不会提供服务 |
| `patchState: ready` | 文件预检通过但尚未应用；退出微信后执行安装命令 |
| `patchState: applied`，但联系人不可用 | 补丁文件状态不能证明运行桥接可用；检查微信进程、登录状态、桥接库和端口 |
| 原应用显示待应用，但运行桥接可用 | 可能正在运行临时副本；目标文件诊断与运行桥接相互独立，先统一应用路径 |
| 提示“请先登录微信” | 完成电脑微信登录和手机确认，然后重新搜索 |
| 提示会话已变化 | 微信重启或原生会话世代变化，重新搜索后再打开，不使用旧列表 |
| 提示凭证不可读或身份校验失败 | 检查凭证路径是否属于当前运行微信的用户、权限是否为 600；以普通用户启动微信，重启后重试 |
| 提示端口冲突或 48065 被占用 | 查看占用情况，正常退出占用端口的旧服务后重启已安装桥接的微信 |
| Homebrew 显示未安装 | 不影响直接使用本分支本地 CLI；检查 CLI Path 和桥接状态 |
| 修改源码后 Raycast 没变化 | 确认 `npm --prefix raycast run dev` 正在运行，启用的是本地适配版而非旧商店版 |
| 找不到联系人或列表不完整 | 仅搜索微信已加载的缓存，每次最多 100 条；尝试更精确的关键词 |
| `Original bytes mismatch`、代码指纹不匹配、构建不支持 | 停止安装，核对微信渠道及构建号；不要手改配置版本或跳过校验 |
| 安装提示微信仍在运行 | 正常退出所有实例和临时副本；在正常终端重试 |
| Swift / SDK 编译错误 | 先确认 Swift 6 与所选 SDK 配套，参阅工具链验证记录；现有本分支产物可直接用于安装 |

默认凭证位置：

```text
~/Library/Application Support/WeChatTweak/bridge-token
```

凭证由运行微信的当前用户生成，文件要求属于该用户、权限为 `600`。客户端先通过随机挑战验证桥接身份，之后才发送 Authorization Bearer；不要把凭证内容填到偏好设置、URL、日志或仓库中。

以下命令只检查端口及文件元数据，不输出凭证内容：

```sh
lsof -nP -iTCP:48065 -sTCP:LISTEN
stat -f '%Su %Sp %N' "$HOME/Library/Application Support/WeChatTweak/bridge-token"
```

## 7. 恢复、更新及自定义路径

### 恢复原微信

先退出全部微信，将下列占位路径替换为安装时保存的真实备份目录：

```sh
sudo ./dist/wechattweak restore \
  --backup '/Applications/.WeChatTweakBackups/实际备份ID'
```

恢复会校验应用标识、构建号、备份内容、类型和权限，再恢复整包及原签名。若使用首次安装前的备份，恢复后桥接库及加载命令一并移除。备份不会自动删除。

恢复后可以在 Raycast 设置中停用本地 WeChat 扩展并停止开发进程。凭证文件本身不会启动服务，可以保留。

### 微信或本项目更新后

当前 App Store 版微信的自动更新由 App Store 管理。新版 `doctor --json` 会报告 `distribution: "appStore"`、`automaticUpdates.status: "managedByAppStore"` 和 `independentlyBlocked: false`；Raycast 管理页同步展示这一限制。未检测到普通 receipt 文件时仅报告 `unknown`，不会据此认定为官网版。

如果需要手动管理更新，在 Mac 上打开 **App Store → 设置 → 自动更新**，根据需要调整。这个开关影响 App Store 安装的其他应用，本项目不会替你修改。设置位置见 [Apple 官方说明](https://support.apple.com/en-gb/guide/app-store/mchlp2257/mac)。当前没有已验证的微信内部更新补丁可代替此设置。

微信升级可能替换已修改的应用及桥接。更新后先运行 `doctor --json` 和 `patch --install-bridge --dry-run`，只有当前构建重新通过预检才安装。本分支目前只验证上述构建；不能用旧备份覆盖已升级到不同构建的微信，CLI 会拒绝此类恢复。

更新本项目后重新执行构建及验证，再按同一安装流程更新桥接，并重启微信。Raycast 依赖变化时在仓库根目录重新执行 `npm --prefix raycast ci`，之后载入开发扩展。

### 自定义应用、备份和配置

参数接受绝对路径。以下是占位示例，执行前替换为自己的路径：

```sh
# 自定义应用的只读诊断
./dist/wechattweak doctor --app '/完整路径/WeChat.app' --json

# 自定义目标和备份目录，先执行预检
./dist/wechattweak patch \
  --app '/完整路径/WeChat.app' \
  --backup-dir '/完整路径/WeChatTweakBackups' \
  --install-bridge --dry-run
```

确认后去掉 `--dry-run` 执行安装，并按目录权限决定是否使用 `sudo`。恢复同一目标时也传入相同的 `--app`。自定义配置使用 `--config '/完整路径/config.json'`；自定义桥接库使用 `--bridge-library '/完整路径/WeChatTweakBridge.dylib'`。只有显式传入 HTTP(S) 配置 URL 才会下载远程配置，默认使用本地文件。

## 项目结构与进一步阅读

```text
Sources/WeChatTweak/          CLI 命令
Sources/WeChatTweakCore/      版本读取、补丁预检、整包事务及桥接诊断
Native/269602/               已验证的微信原生适配器
Native/Bridge/               回环协议、鉴权、主线程调度与自动加载
raycast/src/                 适配后的 Raycast 主扩展
raycast/upstream-wechat/     原始上游源码快照，不作为构建入口
docs/                       安装、兼容性与研究记录
```

- [安装与恢复详细记录](docs/installation.md)
- [逐项兼容性与验证范围](docs/compatibility.md)
- [Raycast 扩展说明](raycast/README.md)
- [Raycast 上游来源及改动说明](raycast/UPSTREAM.md)
- [原生适配与正式桥接验收记录](docs/research/269602-adapter-contract.md)
- [原生研究及工具链记录](docs/research/269602-native-compatibility.md)

## 来源与许可

本项目基于 [sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak)，主体遵循 [AGPL-3.0](LICENSE)。Raycast 界面和资源源于 `raycast/extensions` 的 WeChat 扩展，原始快照与版权说明保留在仓库中；对应 MIT 声明见 [LICENSE.upstream](raycast/LICENSE.upstream)。

上游技术参考：

- [微信 macOS 客户端无限多开功能实践](https://blog.sunnyyoung.net/wei-xin-macos-ke-hu-duan-wu-xian-duo-kai-gong-neng-shi-jian/)
- [微信 macOS 客户端拦截撤回功能实践](https://blog.sunnyyoung.net/wei-xin-macos-ke-hu-duan-lan-jie-che-hui-gong-neng-shi-jian/)
- [让微信 macOS 客户端支持 Alfred](https://blog.sunnyyoung.net/rang-wei-xin-macos-ke-hu-duan-zhi-chi-alfred/)
