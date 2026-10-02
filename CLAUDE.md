# GreenBubbles

Conversation-list timestamps follow [docs/CONVERSATION_TIMESTAMPS.md](docs/CONVERSATION_TIMESTAMPS.md): today `HH:mm`, yesterday `昨天 HH:mm`, earlier `MM/dd`.

Follow [AGENTS.md](AGENTS.md), including remembered-connection privacy, stable signing, and installed-app restart acceptance requirements.

Brand asset sources, regeneration, packaging and pending installation acceptance are documented in [docs/BRANDING.md](docs/BRANDING.md).

For local update signing and permission migration, follow [docs/LOCAL_SIGNING.md](docs/LOCAL_SIGNING.md). The icon-only staging script preserves installed program code and connection-tool digests; it does not install automatically.

Message cache behavior, capacity, privacy boundaries and E2E reproduction: [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md).

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
