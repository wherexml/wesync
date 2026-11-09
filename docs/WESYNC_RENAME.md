# we-sync 改名与兼容边界

应用、内置读取工具的界面名称和发行包统一使用 `we-sync`。安装路径为 `/Applications/we-sync.app`。项目源自 GreenBubbles，私有仓库仍为 `wherexml/wesync`，沿用上游历史、MIT 许可与归属。

## 实施前的失败场景

- 只改展示名称会让高级设置继续显示已保存的旧工具路径，或让发行脚本找不到 App、DMG。
- 移除旧安装路径会让已保存的工具路径和既有命令失效。把任意外部工具显示为内置工具也会隐藏真实配置。
- 安装路径变化会影响原生应用与 AI 的读取边界。新路径仍须验证直接父进程、完整 App 签名和工具证书，外部 CLI 继续执行黑名单。
- 改 Bundle ID、签名、凭据服务或 helper 身份会使现有授权、连接与缓存失去连续性。改查询工具字节而遗漏签名摘要迁移也会阻止自动连接。
- 如果安装未通过冷启动，需要能恢复旧包和原有路径。已经迁移到新工具摘要的连接也需要签名迁移才能回退工具。

## 命名与迁移

- Finder、菜单栏、侧栏和 App/DMG 使用 `we-sync`。高级设置只读区将当前包内的读取工具显示为 `we-sync`，外部工具保留实际路径。编辑状态仍可查看工具路径及更换工具。
- `/Applications/GreenBubbles.app` 和 `/Applications/WeSync.app` 均使用相对软链接 `we-sync.app`。已保存的旧路径解析为当前包内工具，自动连接继续验证原摘要或包内签名保护的迁移摘要。底层 `greenbubbles` 命令、Bundle ID、证书、凭据服务和 helper 标识沿用。
- 新路径上的原生应用仍须通过黑名单的人类浏览身份校验。校验限定安装目录、直接父进程和两个包内查询工具，继续验证完整应用签名和工具证书。原有 LaunchAgent 标识沿用，当前包内的注册清单指向新安装目录。

## 打包产物

本地打包脚本生成 `we-sync.app` 和 `we-sync.dmg`。镜像卷名为 `we-sync`，根目录包含 App 和指向 `/Applications` 的链接。发行工作流使用 `we-sync-<版本>-macos-arm64.dmg`，将该文件名用于公证、挂载校验、校验和和发布说明。CLI ZIP 继续采用 `greenbubbles` 命名，供既有 CLI 下载和 Homebrew 流程使用。旧 App 软链接由本机升级步骤建立。

## 本机验收

1. 运行 `python3 scripts/local-ci.py` 和 `cargo build --release --locked --manifest-path Native/GreenBubbles/Cargo.toml`。
2. 首次迁移使用 `scripts/stage-local-tool-update.py --source /Applications/WeSync.app --identity EXISTING_CERT --output NEW_DIRECTORY`。核对候选包和原安装的 designated requirement、完整签名、旧新工具摘要与保留的发送工具。后续暂存默认从 `/Applications/we-sync.app` 读取。
3. 原生退出并确认进程消失，备份旧包，安装 `/Applications/we-sync.app` 并把两个旧安装路径设为相对软链接，指向 `we-sync.app`。
4. 通过 Finder 或 macOS 应用入口启动，等待自动连接，主动刷新会话和正文。展开高级设置的连接区，确认内置工具显示 `we-sync`。确认菜单栏的打开和退出项名称一致。
5. 再次原生退出并确认进程消失，重新打开并复验自动连接和刷新。两次启动均检查钥匙串和磁盘权限提示。验证旧路径及命令仍解析到当前安装。
6. 仅归档脱敏证据。回退前检查当前记住的工具摘要；如果已迁移，用相同身份签署旧代码的回退候选包，先绑定已记住的后继摘要，再恢复旧代码和兼容路径。

历史 WeSync build 39 验收见 [脱敏记录](acceptance/wesync-rename-20261016.json)。

build 58 → 59 的实机结果见 [改名验收记录](acceptance/we-sync-20261109.json)。该次验收记录了当时的依赖审计失败，后续 SQLCipher 安全升级已修复该问题。build 61 同时包含改名和首次设置引导，冷启动和刷新见 [首次设置实机验收](acceptance/first-run-setup-20261109.json)。
