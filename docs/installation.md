# 本分支安装、验证与恢复步骤

本分支已提供补丁器修复和 269602 的字节配置，但真实防撤回、多开效果尚未验收，Raycast 联系人搜索与打开聊天仍未完成。详情见 [兼容范围](compatibility.md) 和 [原生验证记录](research/269602-native-compatibility.md)。

## 1. 获取和构建本分支产物

在仓库根目录执行：

```sh
git switch hotfix/wechat-4.1.13-raycast
make test
make build
```

产物为 `dist/wechattweak` 和 `dist/config.json`；必须一起保留。默认配置从可执行文件所在目录读取，与终端当前目录无关。不要用 `brew upgrade wechattweak` 代替本分支构建，那会获取官方版本。

本机开发环境的 CLT 异常及本次构建使用的临时绕过方式记录在原生验证文档中。已有构建产物可以直接运行；正常工具链的源代码构建不需要该绕过方式。

## 2. 先做只读检查

```sh
./dist/wechattweak --version
./dist/wechattweak doctor --json
./dist/wechattweak patch --dry-run
```

本机预期是 `4.1.13 (269602)`、两个待写入位置、零条缺少原始字节校验的条目。若构建号不同或出现 `Original bytes mismatch`，停止应用补丁，不要修改版本号或跳过校验。

需要自定义应用或配置时，使用 `--app '/完整路径/WeChat.app'` 与 `--config '/完整路径/config.json'`。只有显式传入 HTTP(S) URL 时才下载远程配置。

## 3. 应用实验性核心补丁

先从微信菜单退出全部微信实例。该步骤会修改微信应用并进行 ad-hoc 重签；由于真实消息级效果尚未验收，建议先在专用测试环境验证。

对默认 App Store 安装，在仓库根目录执行：

```sh
sudo ./dist/wechattweak patch
```

默认完整备份保存在 `/Applications/.WeChatTweakBackups/<本次生成的ID>/`，其中包括 `original.app` 和 `manifest.json`。CLI 成功或暂存阶段失败时会打印具体备份路径，请保留。写入和签名都先发生在临时应用包，成功后才替换原包；备份不会被自动删除。

磁盘需要容纳完整备份和暂存应用。备份位置可显式指定，例如：

```sh
sudo ./dist/wechattweak patch --backup-dir /Applications/.WeChatTweakBackups
```

`sudo` 用于写入 root 拥有的 App Store 应用及相邻备份目录；只读诊断和 Raycast 扩展不需要管理员权限。

## 4. 验收核心补丁

重新打开微信，并执行：

```sh
./dist/wechattweak doctor --json
```

预期字节状态为 `applied`。多开测试可在已打开微信的情况下执行：

```sh
open -n /Applications/WeChat.app
```

检查第二实例实际行为。防撤回应仅使用你主动准备的专用测试消息验证。字节状态和签名通过不能代替这两项验收；本轮未发送或撤回任何用户消息。

## 5. 安装 Raycast 诊断扩展

本分支提供的是独立诊断命令，不替换旧搜索接口，不需要开启 `48065` 服务、辅助功能权限或登录启动项。

```sh
cd raycast
npm ci
npm test
npm run typecheck
npm run lint
npm run build
npm run dev
```

Node.js 需要 22.6 或更新版本。`build` 仅输出本地 `raycast/dist/`；`dev` 才会将开发扩展载入 Raycast。

打开 **Check WeChatTweak Compatibility**，将 **WeChatTweak CLI Path** 设置为本分支 `dist/wechattweak` 的绝对路径。该命令使用独立名称，不会覆盖原有 WeChat 扩展。

在 Raycast 设置中停用旧 WeChat 扩展的 **Search Contacts and Chat** 和旧 **Manage WeChatTweak** 命令，避免继续请求不存在的旧接口。新诊断命令会分别显示 Homebrew、CLI、微信、补丁和联系人能力；联系人能力当前应明确显示尚未提供适配器。

## 6. 恢复完整原应用

先退出所有微信实例，将下面的备份路径替换为 CLI 当时打印的真实路径：

```sh
sudo ./dist/wechattweak restore --backup /Applications/.WeChatTweakBackups/实际备份ID
```

恢复会校验应用标识、构建号、备份内容、类型及权限，再恢复原应用和原签名。若微信已经升级，恢复旧版备份会被拒绝，避免覆盖新版本；请保留备份并使用对应版本的正常安装包处理。

无需删除凭据或启动项，因为本轮没有创建联系人桥接服务。可以在 Raycast 设置中移除本分支诊断扩展；仓库内 `raycast/dist/` 只是构建产物。

## 完整联系人功能还缺什么

需要继续完成真实 Qt/C++ 联系人服务实例获取、联系人结构与稳定 ID、打开会话 ABI、线程与对象生命周期验证，然后才能实现鉴权桥接及搜索客户端。以上任何安装步骤都不会自动补齐这部分功能。
