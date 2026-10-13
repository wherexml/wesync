# GreenBubbles

Conversation-list timestamps follow [docs/CONVERSATION_TIMESTAMPS.md](docs/CONVERSATION_TIMESTAMPS.md): today `HH:mm`, yesterday `昨天 HH:mm`, earlier `MM/dd`.

Follow [AGENTS.md](AGENTS.md), including remembered-connection privacy, stable signing, and installed-app restart acceptance requirements.

Brand asset sources, regeneration, packaging and pending installation acceptance are documented in [docs/BRANDING.md](docs/BRANDING.md).

For local update signing and permission migration, follow [docs/LOCAL_SIGNING.md](docs/LOCAL_SIGNING.md). The icon-only staging script preserves installed program code and connection-tool digests; it does not install automatically.

Message cache behavior, capacity, privacy boundaries and E2E reproduction: [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md).

Conversation catalog refresh is triggered by database/WAL file changes, coalesced with at least 60 seconds between automatic reads; no changes means no query. Manual refresh reconciles the full catalog and current messages. Preserve selection, filters and loaded history, and pause automatic retries on failure. See [docs/CONVERSATION_REFRESH.md](docs/CONVERSATION_REFRESH.md).

For a stable conversation ID, key the shared timestamp TimelineView by its message date so a refreshed summary cannot retain the old timestamp. Verify without switching categories; see [docs/CONVERSATION_TIMESTAMPS.md](docs/CONVERSATION_TIMESTAMPS.md).

- Message timeline separators follow [docs/MESSAGE_TIMESTAMPS.md](docs/MESSAGE_TIMESTAMPS.md): centered, 15-minute adjacent-message gaps or day boundaries; shared by live and imported timelines.

Image thumbnail bounds and native alignment acceptance: see [docs/IMAGE_ALIGNMENT.md](docs/IMAGE_ALIGNMENT.md). Keep portrait thumbnails aligned with the same-side text bubble edge.

Private repository: `wherexml/chat-sync`; `origin` is the private development repository and `upstream` preserves the original project. See [docs/REPOSITORY.md](docs/REPOSITORY.md). Do not publish personal data, credentials, local app bundles, or unreviewed native screenshots.

正文表情、仅 MD5 的图片表情恢复、专用签名 helper 与原生验收：见 [docs/EMOJI_DISPLAY.md](docs/EMOJI_DISPLAY.md)。保留原消息及复制内容，不绕过 TLS、摘要校验或已记住连接的工具绑定。

聊天明暗模式配色统一使用 `HistoryChatPalette`；发送正文与引用、文件说明须保持深色可读。规范及验收见 [docs/DARK_MODE.md](docs/DARK_MODE.md)。

原生桌面视觉层见 [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)：保持 SwiftUI/AppKit，参考 ChunUI，样式使用 `HistoryDesign`，聊天配色继续使用 `HistoryChatPalette`。

聊天栏仅保留齿轮“高级设置”直达连接设置，不恢复旧的多项下拉菜单；入口及重启验收见 `docs/DESIGN_SYSTEM.md`。

搜索样式与按需展开消息搜索见 `docs/SEARCH.md`：保留 NSSearchField 输入法；搜索按钮位于刷新左侧，输入框仅点击后在按钮左侧出现。

会话默认后台补齐，已读历史加密缓存跨重启恢复，聊天向上滚动预取并保持阅读锚点；实现边界、隐私与原生验收见 [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md)。

会话时间范围默认 1 个月，可选 1 周、1 个月、3 个月、1 年、所有；按最近消息时间筛选并持久化，保留缓存和分页。规则及原生重启验收见 [docs/CONVERSATION_RANGE.md](docs/CONVERSATION_RANGE.md)。

Agent skills 统一使用 `wechatsync-setup`、`wechatsync-context`、`wechatsync-personal-memory`，见 [docs/AGENT_SKILLS.md](docs/AGENT_SKILLS.md)。底层程序仍为 `greenbubbles`，不要将 skill 名称改动传播到 CLI 命令、协议标识或应用签名身份。

会话侧栏折叠后为 76 pt 头像栏，保留选择、筛选和分页，持久化折叠状态；规范与原生验收见 `docs/DESIGN_SYSTEM.md`。

会话右键菜单使用原始鼠标事件定位的 AppKit NSMenu，避免 List 行焦点滚动造成偏移；保留普通点击与折叠菜单，验收见 `docs/DESIGN_SYSTEM.md`。

欢迎页保留三个操作入口，第 2、3 项右侧问号点击显示用途；去掉底部两行说明。会话首次出现及缓存切换默认定位最新，搜索优先定位命中，历史分页保持锚点；见 `docs/DESIGN_SYSTEM.md`、`docs/MESSAGE_CACHE.md`。

AI 读取黑名单位于高级设置的“会话显示”之前，支持个人/群聊多选；读取层与旧导出均须遵守策略，不允许增加 CLI/环境变量豁免。签名工具摘要迁移及原生重启验收见 [docs/AI_READ_BLACKLIST.md](docs/AI_READ_BLACKLIST.md)。

黑名单选择器沿用聊天目录顺序，分类、已选与搜索均保持相对次序，不按姓名排序；缺失已选项追加末尾，见 `docs/AI_READ_BLACKLIST.md`。

合并转发记录使用可点击卡片与原生明细，解析限制、附件占位及重启验收见 `docs/MERGED_RECORDS.md`。不从转发 XML 自动获取远端附件。
