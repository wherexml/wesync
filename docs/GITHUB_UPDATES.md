# GitHub 更新

## 目标与边界

参考 CyberMe 的后台检查、签名验证、下载及确认重启流程。we-sync 保留 SwiftUI/AppKit，使用 Sparkle 的原生更新窗口；应用菜单及菜单栏均提供“检查更新…”。GitHub 托管 appcast 与版本 DMG，不需要额外服务或用户登录。

公开发行版使用固定 Developer ID 团队。Apple Development 本机安装继续沿用其身份、凭据与权限，不自动替换成另一团队的发行版；手动检查可打开 GitHub 版本页。初始化更新签名密钥只进行一次，私钥保存在专用钥匙串条目，仓库仅保存公钥。

本轮建设更新机制，不发布新二进制版本，也不启用 GitHub Actions。现有已签名、公证的公开版本可以作为初始 feed 条目；后续正式发行必须先验证候选包，再更新 feed。

## 实施前失败场景

- 网络离线、TLS/重定向错误、损坏或过大的 feed、重复点击；不得阻塞主线程、影响聊天或在后台反复弹错。
- 把预发布、较旧 build、同版本或不兼容系统/架构当成升级；版本号、build 和 DMG 文件信息不一致。
- 包被篡改、更新签名不匹配、应用身份或嵌套签名不正确；不得关闭签名验证、Gatekeeper 或 TCC。
- SwiftPM 动态 framework 未嵌入、符号链接丢失、nested helper 未按同团队签名，导致打包或启动失败。
- 本机开发身份被公开发行团队覆盖，钥匙串、磁盘权限失效；普通升级不得迁移签名身份。
- 退出前缓存未保存、已记住 CLI 摘要改变后连接丢失、更新后重复窗口或无法自动连接。
- 下载取消、无写权限、安装失败或重启失败；不得破坏原应用、用户数据或旧备份。
- 更新私钥被输出、写入 Git、重新生成，或测试 feed/key 能通过生产环境变量开启。
- 仅合成检查通过就宣称安装版验收完成；仅创建本地 feed 就声称 GitHub 更新可访问。

## 验证计划

先以独立原生 E2E 验证“无更新、存在更新、签名拒绝、取消、实际安装与重启”，产出报告及合成截图。合成通道仅限 DEBUG 的独立 Preview Bundle ID，不改生产更新源、公钥或连接。

正式安装沿用原 Apple Development 身份，保留全部查询/输入 helper 字节；原生退出重开验证自动连接、设置、关于及检查更新入口。静态验证 framework、归档、版本、更新签名及旧版已公证 DMG，不额外发布一个版本来测试。

参考：CyberMe 的 `native/mygo/update.go` 与 `internal/updatefeed/feed.go`、[Sparkle 官方接入](https://sparkle-project.org/documentation/)、[发布更新](https://sparkle-project.org/documentation/publishing/)。

## 实现契约

- 固定 Sparkle **2.10.1**，SwiftPM revision/checksum 锁定。完整许可证与上游 artifact 比较，进入分发依赖基线，并独立放入应用包。`sparkle_bundle.py` 先签 Autoupdate、Updater.app、两个 XPC 再签 framework；主包最后签名，不关闭 library validation，保留 Downloader 沙盒。
- 更新源固定为 `https://raw.githubusercontent.com/wherexml/wesync/main/updates/appcast.xml`；下载只允许本仓库 HTTPS GitHub Releases 的 DMG。生产代码没有 feed/key 环境变量覆盖，只有 release 默认通道。
- Ed25519 公钥固定在源码和封装；专用 Sparkle 钥匙串 account 为 `me.greenbubbles.GreenBubbles.sparkle`。仅首次生成，普通发布只使用既有 key，不导出、不枚举钥匙串、不重新生成。
- `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 均开启，`SUSignedFeedFailureExpirationInterval=0`，不会因为 feed 验证失败一段时间就降级。后台默认每日检查，菜单可关闭；禁用无人值守安装和系统画像上报，下载后仍需用户确认安装/重启。
- 公开客户端仅在 Bundle ID 与 Developer ID 团队 `T695TT4HT9` 同时验证通过时启动 updater。本机 Apple Development 安装保留原团队，通过菜单查看 GitHub 版本页，普通升级不自动迁移权限身份。
- Sparkle 接管安装替换与重启；应用原有 `applicationShouldTerminate` 继续等候缓存末次写入。未来 CLI 改变时，封装内 ToolUpdate 精确绑定旧公开摘要和新摘要，既有安全校验仍要求主应用与工具同签名。

## 发布步骤

先按 [MACOS_RELEASE.md](MACOS_RELEASE.md) 获得新版本发布授权并完成源码检查、递增 build、Developer ID 签名、公证、贴票据、Draft/公开下载验证，再准备 feed：

```sh
python3 scripts/prepare-github-update.py \
  --dmg .build/distribution/we-sync-版本-macos-arm64.dmg \
  --out .local-install/新的更新源输出目录 --published
```

该脚本验证 DMG/App 的固定团队、Gatekeeper、票据、版本和架构，核对已有公开 stable 资产的 SHA-256，使用既有 key 签署 archive 与 appcast，并用 Sparkle 工具复验。无 `--published` 时只能准备候选，不能把它当作公开资产已验证。脚本不上传、不重新公证已有包、不安装。把核对后的 appcast 原样复制到 `updates/appcast.xml`，提交推送后回读准确 URL 并核对摘要及签名。

初始 feed 指向已有 `v0.10.1` 公证 DMG；没有修改该 Release 或资产。**旧版 0.10.1 未包含 updater，需要先手动安装首次带更新机制的公开版本，此后才能应用内升级。** 当前本机 build 74 仍为 Apple Development，不自动迁移到公开团队。新公开二进制尚未发布。

## 可重复原生 E2E

使用已安装的 Apple Development 身份运行：

```sh
python3 scripts/update-e2e/prepare.py --identity 现有证书SHA1 \
  --out .local-install/新的更新验收目录
```

该进程构建仅含生产 `HistoryUpdater` 与原生合成 Host 的独立应用，生成一次性合成密钥并写入私有测试目录，启动随机五位 loopback 端口。只在 DEBUG 且 `me.greenbubbles.UpdaterPreview` + `GBUpdatePreview` 时使用合成通道；release 中没有该分支。不启动业务 model、不访问真实连接钥匙串、不操作微信。所有测试标记均在独立目录。

1. 原生打开输出的应用，`current.xml` 复制为 server/appcast.xml，点击检查，确认最新版提示。
2. 替换为 `invalid.xml`，确认签名失败；替换为 `bad-archive.xml`，确认损坏 archive 被拒绝、旧 build 保留。
3. 替换为 `available.xml`，检查并关闭提示，确认暂缓不更改 build；再次检查、安装、确认重启，观察 build 1 → 2 和 `events.jsonl` 的新启动记录，再检查同版不重复提示。
4. `slow-download.py --root <同一目录> --identity <原证书>` 准备下一 build 的慢速包。原生进入下载后立即点击取消，观察 cancelled 事件、build 与合成用户数据不变。该进程另开随机五位 loopback 端口，测试结束只停止自己创建的 server。
5. 核对签名、合成数据 sentinel、安装前后 build 与窗口截图，输出脱敏 JSON。密钥材料、原始目录和安装包不提交。

本轮实际完成 build 1 → 2、再次检查同版、build 2 → 3，以及下载 build 4 时取消。首次取消尝试包过快已到就绪阶段，不计作取消通过；随后加慢并重新验证。未模拟磁盘满、进程崩溃或重启失败的全部回滚；不能把签名失败保留旧包等同所有失败模式均验证。

## 本轮结果

最终本机安装 **0.10.0（74）**，两次原生冷启动自动连接，无凭据输入或权限变更；应用/菜单栏的检查更新、设置、关于与刷新通过。主程序在两次启动后与候选摘要相同，既有 CLI/输入 helper 字节保留。独立原生升级 E2E **13/13**，真实已公证包与临时篡改副本的预检通过，完整本机 CI **23/23**。未新增单元测试。截图、计时/失败边界与可审计报告见 [验收记录](acceptance/github-updates-20261111/README.md)。
