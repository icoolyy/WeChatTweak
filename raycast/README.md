# WeChatTweak Diagnostics

本地 Raycast 诊断扩展，配套此分支的 `dist/wechattweak`。明确区分 CLI 安装、补丁状态与联系人能力；Homebrew 检查优先使用绝对路径，不依赖 Raycast 的 PATH。

```sh
npm ci
npm test
npm run typecheck
npm run lint
npm run build
npm run dev
```

在命令偏好设置中填写 CLI 绝对路径。官方 2.0.1 没有 `doctor` 协议，不能作为此扩展的后端。扩展当前只读，不安装、卸载或重启微信，不会发起不存在的联系人搜索请求。

联系人搜索和打开聊天尚未实现；原生适配器验证通过之前，不提供占位搜索命令。完整操作见 [安装与恢复](../docs/installation.md)。

API 固定在已验证的 1.93.2，React 与该 API 使用同一套 18.3 类型；本机 Raycast 版本为 1.104.31。未做 Raycast 窗口内手动验收。此扩展为本仓库新实现，没有复制已安装扩展的代码或图标。
