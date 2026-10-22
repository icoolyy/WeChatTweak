# WeChatTweak

[![README](https://img.shields.io/badge/GitHub-black?logo=github&logoColor=white)](https://github.com/sunnyyoung/WeChatTweak)
[![README](https://img.shields.io/badge/Telegram-black?logo=telegram&logoColor=white)](https://t.me/wechattweak)
[![README](https://img.shields.io/badge/FAQ-black?logo=googledocs&logoColor=white)](https://github.com/sunnyyoung/WeChatTweak/wiki/FAQ)

A command-line tool for tweaking WeChat.

## 本分支兼容修复

`hotfix/wechat-4.1.13-raycast` 提供全量补丁预检、整包备份恢复，以及微信 4.1.13 / build 269602 / arm64 的原生联系人桥接和配套 Raycast 搜索。真实微信临时副本已通过鉴权搜索、打开会话确认、安装签名和正常启动自动加载验证。搜索范围是微信已加载的联系人缓存；防撤回和多开的实际效果仍需专用测试。

查看 [安装与恢复步骤](docs/installation.md)、[逐项兼容状态](docs/compatibility.md) 和 [原生验证证据](docs/research/269602-native-compatibility.md)。本分支需使用自身构建产物，下面的官方 Homebrew 命令不会安装本分支改动。

```sh
make test
make build
./dist/wechattweak doctor --json
./dist/wechattweak patch --dry-run
```

## 功能

- 阻止消息撤回
- 阻止自动更新
- 客户端多开

## 安装&使用

```bash
# 安装
brew install sunnyyoung/tap/wechattweak

# 更新
brew upgrade wechattweak

# 执行 Patch
wechattweak patch

# 查看所有支持的 WeChat 版本
wechattweak versions
```

## 参考

- [微信 macOS 客户端无限多开功能实践](https://blog.sunnyyoung.net/wei-xin-macos-ke-hu-duan-wu-xian-duo-kai-gong-neng-shi-jian/)
- [微信 macOS 客户端拦截撤回功能实践](https://blog.sunnyyoung.net/wei-xin-macos-ke-hu-duan-lan-jie-che-hui-gong-neng-shi-jian/)
- [让微信 macOS 客户端支持 Alfred](https://blog.sunnyyoung.net/rang-wei-xin-macos-ke-hu-duan-zhi-chi-alfred/)

## 贡献者

This project exists thanks to all the people who contribute.

[![Contributors](https://contrib.rocks/image?repo=sunnyyoung/WeChatTweak)](https://github.com/sunnyyoung/WeChatTweak/graphs/contributors)

## License

The [AGPL-3.0](LICENSE).
