# WeChat Raycast 扩展（本项目适配版）

以用户引入的 `upstream-wechat/` 源码为基础，主实现位于 `raycast/src/`。保留原扩展的 **Search Contacts and Chat**、**Manage WeChatTweak** 两个命令、默认头像、置顶和最近联系人交互，接入本项目的鉴权桥接与 CLI。来源和许可见 [UPSTREAM.md](UPSTREAM.md)。旧快照只用于追溯，不从该子目录构建或载入。

## 构建和本地替换

在此目录运行：

```sh
npm ci
npm test
npm run typecheck
npm run lint
npm run build
npm run dev
```

使用 Node22.6+。API 固定1.93.2、React18.3.1，构建与测试均使用锁文件。`build` 仅输出本地 dist/，`dev` 将本地 WeChat 开发扩展载入 Raycast 并监听变化，不发布到商店。开发时保持该进程运行。

Raycast 设置中启用带本地开发标识的 WeChat，停用旧商店 WeChat，避免同名旧命令继续请求无鉴权接口；以前的 WeChatTweak Diagnostics 已由本扩展替换。

偏好设置：

- **WeChatTweak CLI Path**：本分支 dist/wechattweak 的绝对路径，必填。
- **Bridge Credential Path**：通常留空，使用 ~/Library/Application Support/WeChatTweak/bridge-token。填写的是路径，不能填凭证内容。
- **WeChat App Path**：通常留空，使用 /Applications/WeChat.app；用于目标应用诊断、预检、安装和恢复。
- **Restore Backup Path**：需要恢复时填写 CLI 打印的完整备份目录，内含 original.app 和 manifest.json。

## 搜索、历史和置顶

管理页增加安装渠道和自动更新状态：当前 App Store 版由 App Store 管理更新，尚不支持单独阻止微信更新，可打开 Apple 设置说明。此功能需要重新构建本项目 CLI；旧 CLI 会安全显示为未确认渠道，不会被误报为已经阻止更新。

微信登录且桥接就绪后，支持中文、备注、微信号和拼音搜索，每次最多100条已加载缓存记录。Enter 打开选中会话，只有原生确认后才写入最近联系人并关闭窗口。Cmd+Shift+P 置顶/取消置顶，Cmd+C 复制微信号，Cmd+Shift+X 清除当前会话最近联系人，Cmd+R 重新搜索。

历史保留最近10条，置顶上限100条，均仅用于当前已验证的桥接会话；微信重启或世代变化后旧记录不显示。不会直接迁移旧扩展缺少会话身份的历史记录。不会生成带凭证的 HTTP 快捷链接。

## 管理

管理页分别显示 Homebrew、CLI、目标应用/补丁文件和当前运行桥接。Homebrew不是本地 CLI 的前置条件。

只读预检调用 `patch --install-bridge --dry-run`；安装调用 `patch --install-bridge`；恢复调用 `restore --backup <准确路径>`。安装和恢复都需要确认，取消不执行命令。不会自动安装官方2.0.1或强制终止微信；先正常退出全部微信实例。权限不足时使用页面提供的终端命令，在正常终端中完成 sudo 验证。

完整安装与恢复见 [项目安装说明](../docs/installation.md)。本轮真实 UI 验证包括中文、拼音、置顶/取消、确认打开后的最近联系人、管理状态、只读预检以及取消安装；未发送消息、未修改原微信安装。
