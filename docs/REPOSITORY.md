# chat-sync 仓库维护

- GitHub：`https://github.com/wherexml/chat-sync`，初始化为 Private。未经明确要求，不改为公开。
- `origin`：上述私有仓库；`upstream`：`https://github.com/bojieli/greenbubbles.git`。
- 保留 GreenBubbles Git 历史、原始许可和归属信息；本次仅调整仓库身份，不更改应用名、bundle identifier 或签名。
- 提交当前源码、品牌资源、模块文档和脱敏验收记录；本机安装目录、数据库、密钥、缓存及未经复核的原生截图不上传。已经跟踪的合成时间线截图保留。
- 推送 `main` 触发现有 CI；不推送 release tags，不触发发行或 Homebrew 发布。
- 初始化不代表新增应用功能通过验收，也不重新安装应用；各模块已有安装与重启证据、待验项以对应文档为准。

## 重复验证

```sh
gh repo view wherexml/chat-sync --json nameWithOwner,visibility,url
git remote -v
swift scripts/check-secret-hygiene.swift
gh run list --repo wherexml/chat-sync --branch main
```

初始化 CI 兼容性：macOS runner 默认 Swift 6.1.2，窗口隐藏遍历使用标准 `for-in`，兼容其严格格式检查。

Swift 6.1 编译兼容：图片和 PDF 加载闭包显式标注 `@MainActor`，使非 Sendable 的 AppKit/PDFKit 预览对象留在 UI actor 内，避免跨隔离域返回值。

搜索框 AppKit coordinator 显式使用主线程隔离；Rust 附件读取移除冗余引用，展示辅助函数置于现有测试模块之前，满足严格 Clippy 检查。

既有搜索进程集成测试的参数断言同步 `--json` 输出协议；保留凭证和查询仅经 stdin 传递的全部断言，不新增单元测试。
