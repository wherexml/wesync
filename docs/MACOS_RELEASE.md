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
