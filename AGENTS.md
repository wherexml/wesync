# WeSync local development

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
- Regenerate `Resources/Brand` with `python3 scripts/generate-brand-assets.py`; include `GreenBubbles-black.png` in every app package. Resource-only updates still require the signing and restart acceptance above.
- Local-only stable certificate signing and migration are documented in `docs/LOCAL_SIGNING.md`. Keep the same certificate across updates, preserve bundled CLI bytes for icon-only changes, and never bypass native security prompts or equate a local certificate with Developer ID distribution.

- Message browsing uses a bounded, connection-scoped timeline cache. Preserve pagination continuity, stale content on refresh failure, and source isolation; see `docs/MESSAGE_CACHE.md` for limits and repeatable E2E.

- Message timeline separators follow [docs/MESSAGE_TIMESTAMPS.md](docs/MESSAGE_TIMESTAMPS.md): centered, 15-minute adjacent-message gaps or day boundaries; shared by live and imported timelines.

Image thumbnail bounds and native alignment acceptance: see [docs/IMAGE_ALIGNMENT.md](docs/IMAGE_ALIGNMENT.md). Keep portrait thumbnails aligned with the same-side text bubble edge.

Private repository: `wherexml/wesync`; `origin` is the private development repository and `upstream` preserves the original project. See [docs/REPOSITORY.md](docs/REPOSITORY.md). Do not publish personal data, credentials, local app bundles, or unreviewed native screenshots.

正文表情、仅 MD5 的图片表情恢复、专用签名 helper 与原生验收：见 [docs/EMOJI_DISPLAY.md](docs/EMOJI_DISPLAY.md)。保留原消息及复制内容，不绕过 TLS、摘要校验或已记住连接的工具绑定。

聊天明暗模式配色统一使用 `HistoryChatPalette`；发送正文与引用、文件说明须保持深色可读。规范及验收见 [docs/DARK_MODE.md](docs/DARK_MODE.md)。

原生桌面视觉层见 [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)：保持 SwiftUI/AppKit，参考 ChunUI，样式使用 `HistoryDesign`，聊天配色继续使用 `HistoryChatPalette`。

聊天栏仅保留齿轮“高级设置”直达连接设置，不恢复旧的多项下拉菜单；入口及重启验收见 `docs/DESIGN_SYSTEM.md`。

搜索样式与按需展开消息搜索见 `docs/SEARCH.md`：保留 NSSearchField 输入法；搜索按钮位于刷新左侧，输入框仅点击后在按钮左侧出现。

会话默认后台补齐，已读历史加密缓存跨重启恢复，聊天向上滚动预取并保持阅读锚点；实现边界、隐私与原生验收见 [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md)。

左侧会话列表由数据库/WAL 文件变化触发，合并事件并将自动读取限为至少间隔 60 秒；无变化不查询。刷新按钮同时核对全目录与当前消息。保留选择、筛选及历史阅读位置，失败保留旧列表并暂停自动重试；见 [docs/CONVERSATION_REFRESH.md](docs/CONVERSATION_REFRESH.md)。

会话时间范围默认 1 个月，可选 1 周、1 个月、3 个月、1 年、所有；按最近消息时间筛选并持久化，保留缓存和分页。规则及原生重启验收见 [docs/CONVERSATION_RANGE.md](docs/CONVERSATION_RANGE.md)。

Agent skills 统一使用 `wechatsync-setup`、`wechatsync-context`、`wechatsync-personal-memory`，见 [docs/AGENT_SKILLS.md](docs/AGENT_SKILLS.md)。底层程序仍为 `greenbubbles`，不要将 skill 名称改动传播到 CLI 命令、协议标识或应用签名身份。

会话侧栏折叠后为 76 pt 头像栏，保留选择、筛选和分页，持久化折叠状态；规范与原生验收见 `docs/DESIGN_SYSTEM.md`。

会话右键菜单使用原始鼠标事件定位的 AppKit NSMenu，避免 List 行焦点滚动造成偏移；保留普通点击与折叠菜单，验收见 `docs/DESIGN_SYSTEM.md`。

欢迎页保留三个操作入口，第 2、3 项右侧问号点击显示用途；去掉底部两行说明。会话首次出现及缓存切换默认定位最新，搜索优先定位命中，历史分页保持锚点；见 `docs/DESIGN_SYSTEM.md`、`docs/MESSAGE_CACHE.md`。

AI 读取黑名单位于高级设置的“会话显示”之前，支持个人/群聊多选；读取层与旧导出均须遵守策略，不允许增加 CLI/环境变量豁免。签名工具摘要迁移及原生重启验收见 [docs/AI_READ_BLACKLIST.md](docs/AI_READ_BLACKLIST.md)。

黑名单选择器沿用聊天目录顺序，分类、已选与搜索均保持相对次序，不按姓名排序；缺失已选项追加末尾，见 `docs/AI_READ_BLACKLIST.md`。

合并转发记录使用可点击卡片与原生明细，解析限制、附件占位及重启验收见 `docs/MERGED_RECORDS.md`。不从转发 XML 自动获取远端附件。

转发记录本机图片恢复使用父消息绑定的子序号、同会话精确原消息定位及现有附件校验；CLI 更新须迁移已记住工具摘要，见 `docs/MERGED_RECORDS.md`。

同身份更新免重复授权的 build 36 → 37 实机冷启动与刷新验收见 `docs/LOCAL_SIGNING.md`、`docs/acceptance/reconnect-upgrade-20261016.json`；普通更新不得重新迁移签名身份，CLI 改动仍需摘要迁移及重启验收。

应用显示名 WeSync、私有仓库 `wherexml/wesync`；保持原 Bundle ID、证书、凭据及 CLI/helper 身份，旧安装路径使用兼容软链接。改名、打包与重启验收见 [docs/WESYNC_RENAME.md](docs/WESYNC_RENAME.md)。

高级设置使用紧凑分组与可折叠连接配置，已连接时默认折叠并以“完成”关闭；首次连接默认展开。标题与操作栏固定，详见 `docs/DESIGN_SYSTEM.md`。

连接配置展开默认只读，点击“修改连接”后才显示整行路径与凭据输入；忘记连接需确认。交互与验收见 `docs/DESIGN_SYSTEM.md`。
