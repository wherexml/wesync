# macOS DMG 发布

we-sync 的公开发行使用 Developer ID Application 签名及 Apple 公证。Apple 芯片和 macOS 14 或更新版本。已有 Apple Development 本机安装和公开包属于不同签名身份。覆盖前先查阅[本机签名规范](LOCAL_SIGNING.md)，备份原应用并确认连接恢复方案。

## 发布门槛

- 缺少 Developer ID、公证未获 Accepted、票据或 Gatekeeper 校验失败时，保留候选包与回执，暂缓发布。
- 标签、源码、依赖清单、包内版本和文件名必须一致。暂存目录不包含聊天、密钥或本机配置。
- App 单独公证并贴票据后，再封入 DMG。DMG 签名、公证和贴票据后，只读挂载并复验 App。
- 先上传至 GitHub Draft，回下载验证 SHA-256。发布后从匿名下载地址复核，最后部署使用该版本地址的首页。
- GitHub Actions 保持关闭。经用户明确授权的公开 DMG 在本机发布，只上传 DMG 和校验和。

## 本机复验

```sh
python3 scripts/local-ci.py
bash scripts/check-public-release.sh v0.10.1
GREENBUBBLES_SIGNING_IDENTITY=DEVELOPER_ID_APPLICATION \
GREENBUBBLES_TEAM_IDENTIFIER=TEAM_ID \
GREENBUBBLES_NOTARY_PROFILE=EXISTING_PROFILE \
GREENBUBBLES_OUTPUT_DIRECTORY="$PWD/.build/distribution" \
  bash scripts/package-send-helper.sh
```

执行前切到准备发布的提交并创建对应本机注释标签。脚本记录两次公证的提交与结果 JSON。等待超时先用 `notarytool info` 查询原提交 ID，已通过的同一文件直接贴票据。

最终产物命名为 `we-sync-<版本>-macos-arm64.dmg`。在 Gatekeeper 核验 DMG 并只读挂载后，核对 `Applications` 链接、App 的签名和票据、两个 Bundle 版本、Mach-O 架构、许可证与清单。用 SHA-256 比较本机包、草稿回下载和公开下载。首页部署与浏览器验收见 [WEBSITE.md](WEBSITE.md)。

## GitHub 应用内更新

Sparkle 的接入、密钥作用域、完整升级 E2E 及签名通道见 [GITHUB_UPDATES.md](GITHUB_UPDATES.md)。公开发行仍由明确授权触发；机制接入不代表授权新版本发布。

打包同时嵌入并按 Developer ID 签署 Sparkle 的 framework、Autoupdate、Updater 和 XPC；保留 Downloader 的沙盒权限，不关闭 library validation。完整 Sparkle 许可证独立放在包内 `SPARKLE_LICENSE.txt`，不修改 Rust 的许可证生成输出。

`GREENBUBBLES_BUILD` 必须递增，默认使用当前 Git 提交数（首个旧公开版 build 为 1）。应用和输入助手同步设置 build，不以市场版本字符串代替更新比较。发布前把上一公开 DMG 内已验证 CLI 的 SHA-256 追加到 `Packaging/GreenBubbles/ToolPredecessors.json`；打包在工具签名后生成封装内 `ToolUpdate.json`，以便保留旧连接。

先完成现有 Draft 上传与下载摘要复核，公开资产验证后运行 `python3 scripts/prepare-github-update.py --dmg <版本化DMG> --out <新私有输出目录> --published`。该命令只准备并验证签名 feed，不发布、不安装、不重新公证已有包。核对输出后把原样 `appcast.xml` 提交到 `updates/`；feed 本身有签名，修改字节后必须重新签名。未来有明确发布授权时仍先发布不可变 GitHub Release 资产，再更新 feed，最后部署首页。
