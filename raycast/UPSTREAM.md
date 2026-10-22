# 上游来源及本项目适配

- 来源：raycast/extensions 的 extensions/wechat
- 固定提交：7705eb923c4fc5e012ea5d3de55b3ea87bacd91c
- 源码：https://github.com/raycast/extensions/tree/7705eb923c4fc5e012ea5d3de55b3ea87bacd91c/extensions/wechat
- 引入日期：2026-10-22
- 上游 MIT 许可和版权声明：[LICENSE.upstream](LICENSE.upstream)。

用户引入的原始快照位于 `upstream-wechat/`，保留不变供来源追溯。日常维护、构建和载入使用本目录的 package.json 与 src/，不要从快照目录启动旧扩展。

主扩展沿用上游的 WeChat 命名、index/manageTweak 入口、联系人列表组件、搜索 Hook、置顶/最近联系人分区以及头像和微信图标资源。服务层改为本项目已验证的鉴权 BridgeClient 和现代 CLI；本地历史绑定桥接会话世代；原始无鉴权 HTTP 快捷链接已移除。上游安装器的旧框架检测、brew install wechattweak-cli、install/uninstall 命令和强制 killall 均不进入主扩展。

本项目新增桥接与 CLI 代码遵循仓库 AGPL-3.0-only 许可；分发派生扩展时同时保留上述 MIT 声明和仓库许可。
