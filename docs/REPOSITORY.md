# wesync 仓库维护

- GitHub 开源仓库为 [wherexml/wesync](https://github.com/wherexml/wesync)，MIT 许可。
- `origin` 指向该开发仓库，`upstream` 指向 `https://github.com/bojieli/greenbubbles.git`。
- [产品首页](https://wesync-mac.pages.dev/) 仅部署 `website/` 中的静态文件。部署和复验见 [WEBSITE.md](WEBSITE.md)。
- 保留 GreenBubbles Git 历史、原始许可和归属信息。应用展示名为 `we-sync`，沿用 Bundle ID、签名和底层 CLI 身份。改名边界见 [WESYNC_RENAME.md](WESYNC_RENAME.md)。
- 提交当前源码、品牌资源、模块文档和脱敏验收记录；本机安装目录、数据库、密钥、缓存及未经复核的原生截图不上传。已经跟踪的合成时间线截图保留。
- 2026-10-17 起按用户要求关闭此仓库 GitHub Actions，发布与 Homebrew 自动化保持暂停。日常推送先通过本机 CI。经用户明确授权的公开 DMG 在本机签名、公证并验证后发布对应标签，见 [macOS DMG 发布](MACOS_RELEASE.md)。
- 初始化不代表新增应用功能通过验收，也不重新安装应用；各模块已有安装与重启证据、待验项以对应文档为准。

## 重复验证

```sh
gh repo view wherexml/wesync --json nameWithOwner,visibility,url
git remote -v
swift scripts/check-secret-hygiene.swift
gh run list --repo wherexml/wesync --branch main
```

初始化 CI 兼容性：macOS runner 默认 Swift 6.1.2，窗口隐藏遍历使用标准 `for-in`，兼容其严格格式检查。

Swift 6.1 编译兼容：图片和 PDF 加载闭包显式标注 `@MainActor`，使非 Sendable 的 AppKit/PDFKit 预览对象留在 UI actor 内，避免跨隔离域返回值。

搜索框 AppKit coordinator 显式使用主线程隔离；Rust 附件读取移除冗余引用，展示辅助函数置于现有测试模块之前，满足严格 Clippy 检查。

2026-10-16 签名验收文档提交触发的 CI 发现现有 rustls 0.23.45 命中 RUSTSEC-2026-0346 至 0349；单独升级锁文件到 0.23.46 并同步第三方声明，不关闭依赖审计或忽略漏洞。该提交随后通过完整 CI，并经用户要求安装为本机 build 38；同证书 CLI 摘要迁移、两次原生冷启动及主动刷新通过，见 `LOCAL_SIGNING.md` 与 `acceptance/rustls-installed-20261016.json`。build 37 的历史记录仍仅代表资源升级验收。

既有搜索进程集成测试的参数断言同步 `--json` 输出协议；保留凭证和查询仅经 stdin 传递的全部断言，不新增单元测试。

2026-10-16 经用户明确要求，GitHub 仓库由 `wherexml/chat-sync` 改为 `wherexml/wesync`，API 回读确认仍为 Private，origin 已同步，upstream 不变。应用 WeSync build 39 的两次免重复授权冷启动通过；改名范围与验收见 [WESYNC_RENAME.md](WESYNC_RENAME.md)。
