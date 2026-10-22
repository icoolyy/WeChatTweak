# 本分支安装、验证与恢复

适用于 Apple Silicon、App Store 微信 4.1.13（build 269602）。原生联系人搜索范围是微信已经加载的缓存；不会读取完整联系人数据库。防撤回和多开只完成字节与签名验证，实际效果仍需专用测试。

## 构建产物

在本仓库根目录执行：

```sh
git switch hotfix/wechat-4.1.13-raycast
make test
make build
```

将 `dist/wechattweak`、`dist/config.json`、`dist/WeChatTweakBridge.dylib` 一起保留。CLI 为本分支的 `2.1.0-dev`，不能用 Homebrew 官方 2.0.1 替代。CLI 可双架构构建，原生桥接目前仅支持 arm64。当前机器 CLT 的临时构建绕过方式见原生验证记录；已有 dist 产物可以直接运行。

## 安装到微信

先进行只读检查：

```sh
./dist/wechattweak doctor --json
./dist/wechattweak patch --install-bridge --dry-run
```

预检同时验证两个补丁原始字节、业务模块代码指纹、启动器加载命令空间和桥接库架构。遇到构建号或指纹不匹配时停止，不修改版本号强行绕过。

从微信菜单正常退出全部实例后，在正常终端执行：

```sh
./dist/wechattweak patch --install-bridge
```

如果 `/Applications/WeChat.app` 或相邻备份目录没有当前用户写权限，在正常终端用 `sudo` 执行同一命令。诊断和 Raycast 不需要 sudo。CLI 必须能够枚举运行中的应用；受限环境不能确认退出状态时会拒绝修改。

默认完整备份位于 `/Applications/.WeChatTweakBackups/<本次ID>/`，包含 `original.app` 和 `manifest.json`；保存 CLI 打印的准确路径。先备份，再在暂存副本中写入、安装桥接库、重签和严格校验，成功后替换原包。需要容纳完整备份和暂存副本的磁盘空间。可用 `--backup-dir /绝对路径` 更改备份目录。

自定义应用路径使用 `--app /完整路径/WeChat.app`；自定义配置使用 `--config /完整路径/config.json`；自定义桥接库使用 `--bridge-library /完整路径/WeChatTweakBridge.dylib`。

## 启动和检查

正常启动微信并完成手机登录确认，无须调试器、DYLD 环境变量或独立后台进程。桥接随微信启动，只监听 `127.0.0.1:48065`，退出微信即停止。登录前服务可响应健康检查，但联系人能力关闭。

凭证由运行微信的当前用户生成在 `~/Library/Application Support/WeChatTweak/bridge-token`，64 个十六进制字符，权限 600。不要复制内容到 URL、日志或 Raycast 偏好设置中。端口冲突时不会覆盖已有凭证，也不会假装启动成功。

```sh
./dist/wechattweak doctor --json
```

预期补丁状态 `applied`；登录后 `contactsBridgeAvailable` 为 true。该字段描述当前正在运行的已验证桥接，独立于所检查应用文件的补丁状态。

## 载入配套 Raycast 扩展

在仓库根目录执行：

```sh
npm --prefix raycast ci
npm --prefix raycast test
npm --prefix raycast run typecheck
npm --prefix raycast run lint
npm --prefix raycast run build
npm --prefix raycast run dev
```

Node 需要 22.6 或更新版本。`build` 仅构建到仓库内；`dev` 将开发扩展载入 Raycast。主扩展已基于 `raycast/upstream-wechat` 的原始源码适配，入口为 `raycast/`，原始子目录仅留作来源快照。在扩展偏好设置中将 **WeChatTweak CLI Path** 设为本仓库 `dist/wechattweak` 的绝对路径，**Bridge Credential Path** 留空使用默认位置（开发验证可填私有凭证文件的绝对路径）。

使用 **Search Contacts and Chat** 搜索昵称、备注、微信号或拼音，Enter 打开选中会话；实际选中目标后才报告成功。最多返回 100 条；尚未加载到微信缓存的联系人不会出现。界面使用默认头像，无头像下载。支持置顶和最近10条联系人，均绑定当前桥接会话，世代变化后不复用旧结果。

使用 **Manage WeChatTweak** 分别查看 Homebrew、CLI、微信版本、字节补丁和桥接状态。在 Raycast 设置中启用带本地开发标识的适配版 WeChat，停用旧商店 WeChat；二者命令同名。旧扩展不能直接复用新的私有接口。之前的独立 WeChatTweak Diagnostics 已被本扩展替换。

客户端先通过随机挑战校验服务身份，确认成功后才发送 Authorization Bearer 凭证。微信重启或会话变化会拒绝旧搜索结果，需重新搜索；不要回退到无鉴权访问。

## 恢复

退出全部微信实例，替换为安装时打印的准确备份路径：

```sh
sudo ./dist/wechattweak restore --backup /Applications/.WeChatTweakBackups/实际备份ID
```

恢复完整应用及原签名，同时移除该备份之后安装的桥接文件和加载命令。微信升级后不能用旧备份覆盖新构建。备份保留，不自动删除。恢复后凭证文件可以留存，它自身不会启动服务；Raycast 开发扩展可在 Raycast 设置中移除。

本次开发验证仅修改临时微信副本，原 `/Applications/WeChat.app` 尚未安装本分支。不要同时运行临时副本与原应用访问同一账号。防撤回需要你主动准备专用测试消息；本轮未发送或撤回任何用户消息。
