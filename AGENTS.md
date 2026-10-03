# GreenBubbles local development

Inherit parent repository instructions and user privacy constraints.

- After every application change and local installation, perform a real end-to-end acceptance: quit the installed app, reopen it through native UI, verify automatic connection without key entry, then verify affected features. Record repeatable, scrubbed evidence. Synthetic tests do not substitute for this installed-app restart check.
- Do not declare delivery complete while the installed app cannot reconnect or required UI checks remain blocked.
- Preserve the application-owned remembered connection. Never put credential values in commands, logs, screenshots or documentation; never enumerate Keychain credentials.
- Avoid replacing an installed app with a newly ad-hoc-signed build as a routine update: its changed identity can invalidate macOS privacy grants. A repeatable update path must use a stable legitimate code-signing identity. Do not weaken code-signing requirements or bypass TCC to avoid password prompts. Verify the signing/permission migration before the next install.
- Never operate WeChat directly. Data checks must use bounded GreenBubbles interfaces. The wechat-web-explorer reference and original backup are read-only.
- Do not add unit tests after implementation. Prefer synthetic CLI/native E2E plus bounded authorized installed-app acceptance.

## Brand assets

- Conversation-list timestamp rules and restart acceptance: see `docs/CONVERSATION_TIMESTAMPS.md`. Keep live and imported lists consistent.

- Keep the supplied twin-bot paths in `assets/greenbubbles-twin-bots.svg`; product icons use a white rounded tile, menu bar icons use transparent monochrome templates. See `docs/BRANDING.md`.
- Regenerate `Resources/Brand` with `python3 scripts/generate-brand-assets.py`; include `GreenBubbles-black.png` in every app package. Resource-only updates still require the signing and restart acceptance above.
- Local-only stable certificate signing and migration are documented in `docs/LOCAL_SIGNING.md`. Keep the same certificate across updates, preserve bundled CLI bytes for icon-only changes, and never bypass native security prompts or equate a local certificate with Developer ID distribution.

- Message browsing uses a bounded, connection-scoped timeline cache. Preserve pagination continuity, stale content on refresh failure, and source isolation; see `docs/MESSAGE_CACHE.md` for limits and repeatable E2E.

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
