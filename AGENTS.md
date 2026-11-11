# we-sync local development

Inherit parent repository instructions and user privacy constraints.

- After every application change and local installation, perform a real end-to-end acceptance: quit the installed app, reopen it through native UI, verify automatic connection without key entry, then verify affected features. Record repeatable, scrubbed evidence. Synthetic tests do not substitute for this installed-app restart check.
- Do not declare delivery complete while the installed app cannot reconnect or required UI checks remain blocked.
- Preserve the application-owned remembered connection. Never put credential values in commands, logs, screenshots or documentation; never enumerate Keychain credentials.
- Avoid replacing an installed app with a newly ad-hoc-signed build as a routine update: its changed identity can invalidate macOS privacy grants. A repeatable update path must use a stable legitimate code-signing identity. Do not weaken code-signing requirements or bypass TCC to avoid password prompts. Verify the signing/permission migration before the next install.
- Never operate WeChat directly. Data checks must use bounded GreenBubbles interfaces. The wechat-web-explorer reference and original backup are read-only.
- Do not add unit tests after implementation. Prefer synthetic CLI/native E2E plus bounded authorized installed-app acceptance.

## Brand assets

- Conversation-list timestamp rules and restart acceptance: see `docs/CONVERSATION_TIMESTAMPS.md`. Keep live and imported lists consistent.

同一会话 ID 的最近消息日期改变时，`HistoryConversationTimestamp` 须以日期重建时间内容，避免摘要变新但时间停住；合成截图与保持分类不变的原生验收见 `docs/CONVERSATION_TIMESTAMPS.md`。

- Keep the supplied twin-bot paths in `assets/greenbubbles-twin-bots.svg`; product icons use a white rounded tile, menu bar icons use transparent monochrome templates. See `docs/BRANDING.md`.
- Welcome uses the application's full-color, high-resolution product icon; never enlarge the 44 px menu bar template. See `docs/BRANDING.md`.
- Regenerate `Resources/Brand` with `python3 scripts/generate-brand-assets.py`; include `GreenBubbles-black.png` in every app package. Resource-only updates still require the signing and restart acceptance above.
- Local-only stable certificate signing and migration are documented in `docs/LOCAL_SIGNING.md`. Keep the same certificate across updates, preserve bundled CLI bytes for icon-only changes, and never bypass native security prompts or equate a local certificate with Developer ID distribution.

- Message browsing uses a bounded, connection-scoped timeline cache. Preserve pagination continuity, stale content on refresh failure, and source isolation; see `docs/MESSAGE_CACHE.md` for limits and repeatable E2E.

- Message timeline separators follow [docs/MESSAGE_TIMESTAMPS.md](docs/MESSAGE_TIMESTAMPS.md): centered, 15-minute adjacent-message gaps or day boundaries; shared by live and imported timelines.

Image thumbnail bounds and native alignment acceptance: see [docs/IMAGE_ALIGNMENT.md](docs/IMAGE_ALIGNMENT.md). Keep portrait thumbnails aligned with the same-side text bubble edge.

Public repository: `wherexml/wesync` (GitHub verified 2026-11-11); `origin` is the development repository and `upstream` preserves the original project. See [docs/REPOSITORY.md](docs/REPOSITORY.md). Do not publish personal data, credentials, local app bundles, or unreviewed native screenshots.

正文表情、仅 MD5 的图片表情恢复、专用签名 helper 与原生验收：见 [docs/EMOJI_DISPLAY.md](docs/EMOJI_DISPLAY.md)。保留原消息及复制内容，不绕过 TLS、摘要校验或已记住连接的工具绑定。

聊天明暗模式配色统一使用 `HistoryChatPalette`；发送正文与引用、文件说明须保持深色可读。规范及验收见 [docs/DARK_MODE.md](docs/DARK_MODE.md)。

原生桌面视觉层见 [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)：保持 SwiftUI/AppKit，参考 ChunUI，样式使用 `HistoryDesign`，聊天配色继续使用 `HistoryChatPalette`。

聊天栏仅保留齿轮“高级设置”直达连接设置，不恢复旧的多项下拉菜单；入口及重启验收见 `docs/DESIGN_SYSTEM.md`。

搜索样式与按需展开消息搜索见 `docs/SEARCH.md`：保留 NSSearchField 输入法；搜索按钮位于刷新左侧，输入框仅点击后在按钮左侧出现。 搜索框保留原生 bezeled 布局，仅绘制 cell 内部，避免图标与占位文字、光标重叠；不要再次设置 `isBezeled = false`。

会话默认后台补齐，已读历史加密缓存跨重启恢复，聊天向上滚动预取并保持阅读锚点；实现边界、隐私与原生验收见 [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md)。

左侧会话列表由数据库/WAL 文件变化触发，合并事件并将自动读取限为至少间隔 60 秒；无变化不查询。刷新按钮同时核对全目录与当前消息。保留选择、筛选及历史阅读位置，失败保留旧列表并暂停自动重试；见 [docs/CONVERSATION_REFRESH.md](docs/CONVERSATION_REFRESH.md)。

SQLite 只能打开私有临时副本；原库、WAL 与回滚日志仅用只读文件描述符获取，不读取源 SHM。保留未 checkpoint 的已提交数据，避免原地创建或重建 sidecar；见 [docs/SOURCE_READ_ISOLATION.md](docs/SOURCE_READ_ISOLATION.md)。

会话时间范围默认 1 个月，可选 1 周、1 个月、3 个月、1 年、所有；按最近消息时间筛选并持久化，保留缓存和分页。规则及原生重启验收见 [docs/CONVERSATION_RANGE.md](docs/CONVERSATION_RANGE.md)。

Agent 只发布 `we-sync-setup` 和 `we-search`。重装先用 doctor 验证原连接，保留应用钥匙串和 CLI 的现有凭据，不重复采集。底层命令仍为 `greenbubbles`；安装、迁移与验收见 [docs/AGENT_SKILLS.md](docs/AGENT_SKILLS.md)。

会话侧栏折叠后为 76 pt 头像栏，保留选择、筛选和分页，持久化折叠状态；规范与原生验收见 `docs/DESIGN_SYSTEM.md`。

会话右键菜单使用原始鼠标事件定位的 AppKit NSMenu，避免 List 行焦点滚动造成偏移；保留普通点击与折叠菜单，验收见 `docs/DESIGN_SYSTEM.md`。

欢迎页保留三个操作入口，第 2、3 项右侧问号点击显示用途；去掉底部两行说明。会话首次出现及缓存切换默认定位最新，搜索优先定位命中，历史分页保持锚点；见 `docs/DESIGN_SYSTEM.md`、`docs/MESSAGE_CACHE.md`。

AI 读取黑名单位于高级设置的“会话显示”之前，支持个人/群聊多选；读取层与旧导出均须遵守策略，不允许增加 CLI/环境变量豁免。签名工具摘要迁移及原生重启验收见 [docs/AI_READ_BLACKLIST.md](docs/AI_READ_BLACKLIST.md)。

黑名单选择器沿用聊天目录顺序，分类、已选与搜索均保持相对次序，不按姓名排序；缺失已选项追加末尾，见 `docs/AI_READ_BLACKLIST.md`。

合并转发记录使用可点击卡片与原生明细，解析限制、附件占位及重启验收见 `docs/MERGED_RECORDS.md`。不从转发 XML 自动获取远端附件。

转发记录本机图片恢复使用父消息绑定的子序号、同会话精确原消息定位及现有附件校验；CLI 更新须迁移已记住工具摘要，见 `docs/MERGED_RECORDS.md`。

同身份更新免重复授权的 build 36 → 37 实机冷启动与刷新验收见 `docs/LOCAL_SIGNING.md`、`docs/acceptance/reconnect-upgrade-20261016.json`；普通更新不得重新迁移签名身份，CLI 改动仍需摘要迁移及重启验收。

应用及内置工具显示名为 `we-sync`，安装到 `/Applications/we-sync.app`。源码仓库为 `wherexml/wesync`。保留原 Bundle ID、证书、凭据及 CLI/helper 身份，旧安装路径使用兼容软链接。改名、打包与重启验收见 [docs/WESYNC_RENAME.md](docs/WESYNC_RENAME.md)。

高级设置使用紧凑分组与可折叠连接配置，已连接时默认折叠并以“完成”关闭；首次连接默认展开。标题与操作栏固定，详见 `docs/DESIGN_SYSTEM.md`。

连接配置展开默认只读，点击“修改连接”后才显示整行路径与凭据输入；忘记连接需确认。交互与验收见 `docs/DESIGN_SYSTEM.md`。

主窗口使用唯一 `Window(id: "history")`，Dock/Finder 重开与菜单栏打开须复用窗口，隐藏、最小化和关闭后可恢复；规范与原生验收见 `docs/SINGLE_WINDOW.md`。

GitHub Actions 已按用户要求停用，日常检查统一先运行 `python3 scripts/local-ci.py`，本机全部通过后再提交推送；不得擅自重新启用云端 CI 或购买额度。范围、复验和报告见 [docs/LOCAL_CI.md](docs/LOCAL_CI.md)。应用改动仍执行既有签名与原生重启验收。

依赖升级须同步分发基线与许可证清单，运行完整本机检查；加密/压缩依赖验证旧数据兼容，安装仍使用同身份工具摘要迁移及原生冷启动。见 [docs/DEPENDENCY_UPGRADES.md](docs/DEPENDENCY_UPGRADES.md)。

原生合成预览也须使用既有 Apple Development 证书，`package-presentation-preview.py` 必须传入 `--identity`，禁止 ad-hoc 重建后反复要求测试钥匙串密码；旧临时签名预览先停止，不迁移生产凭据或放宽 ACL/TCC。见 `docs/DESIGN_SYSTEM.md`。

最近正文后台预热为 100 个个人会话 + 50 个群聊，各 40 条；前台读取优先、附件按需，缓存上限 160 会话 / 10,000 条。回到最新按钮距底部 320pt 内隐藏；合成无钥匙串场景及安装验收见 `docs/MESSAGE_CACHE.md`。

合并转发文件使用父消息绑定子序号及 fullmd5 内容校验，PDF 原生预览、其他文件原生存储；不按同名信任文件、不自动读取远端附件。见 `docs/MERGED_RECORDS.md`。

真实黑名单非空时，完整 Rust 进程 E2E 在本机 Docker 独立账户运行；不挂载用户 home/真实策略，不添加生产豁免。macOS 原生检查与安装验收保留，见 `docs/LOCAL_CI.md`。

会话变化在应用后台也按 60 秒限频处理，并触发已缓存/当前会话正文更新；当前会话优先，历史阅读锚点和连续游标须保留，失败暂停、主动刷新恢复。见 `docs/MESSAGE_CACHE.md`、`docs/CONVERSATION_REFRESH.md`。

依赖安全修复不得增加审计豁免；真实黑名单非空时，依赖升级双向快照验收使用 `scripts/dependency-upgrade-isolated.py` 的独立 Docker 账户与断网测试，见 `docs/DEPENDENCY_UPGRADES.md`。

SQLCipher 安全升级须验证真实链接版本和旧版生成的数据；仅在用户明确要求时对 we-sync 和自带输入助手执行应用级 TCC 重置，保留钥匙串连接。验收见 [docs/DEPENDENCY_UPGRADES.md](docs/DEPENDENCY_UPGRADES.md) 和 [docs/LOCAL_SIGNING.md](docs/LOCAL_SIGNING.md)。

首次启动的初始化设置先检查本机记录的磁盘访问，再接入原安全连接表单。允许稍后设置，备份和导出记录不依赖完全磁盘访问。旧连接优先自动恢复；权限失效时重新授权后复用钥匙串，见 [docs/FIRST_RUN_SETUP.md](docs/FIRST_RUN_SETUP.md)。

产品首页源文件位于 `website/`。`python3 scripts/build-website.py` 生成三语静态页面及 Cloudflare Pages 部署包。首屏和底部下载区的 SVG 对话气泡位于波形后方，减少动态效果时波形静止。连接、搜索和 Codex 提问演示使用同一组合成会话，见 [docs/WEBSITE.md](docs/WEBSITE.md)。

经用户授权的公开 DMG 在本机使用 Developer ID 签名，App 和 DMG 分别公证并贴票据。GitHub Releases 公开下载与校验和通过后再部署首页链接，见 [docs/MACOS_RELEASE.md](docs/MACOS_RELEASE.md)。

应用菜单与菜单栏图标均保留设置、关于入口；折叠列表不得叠加 inset 缩进。缓存头像去重、编码、加密与写盘在串行后台执行，退出等待末次保存；规范与原生验收见 [docs/INTERACTION_RESPONSIVENESS.md](docs/INTERACTION_RESPONSIVENESS.md)。

缓存核验覆盖已加载窗口（最多 400 条），不完整读取不据此删除；源变化即使摘要不变也标记待核验，完整目录后清理已移除会话。切换/滚动内容无关诊断默认关闭，测量后恢复偏好；规范与现场边界见 [docs/TIMELINE_INVESTIGATION.md](docs/TIMELINE_INVESTIGATION.md)。
