# we-sync

Conversation-list timestamps follow [docs/CONVERSATION_TIMESTAMPS.md](docs/CONVERSATION_TIMESTAMPS.md): today `HH:mm`, yesterday `昨天 HH:mm`, earlier `MM/dd`.

Follow [AGENTS.md](AGENTS.md), including remembered-connection privacy, stable signing, and installed-app restart acceptance requirements.

Brand asset sources, regeneration, packaging and pending installation acceptance are documented in [docs/BRANDING.md](docs/BRANDING.md).

For local update signing and permission migration, follow [docs/LOCAL_SIGNING.md](docs/LOCAL_SIGNING.md). The icon-only staging script preserves installed program code and connection-tool digests; it does not install automatically.

Message cache behavior, capacity, privacy boundaries and E2E reproduction: [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md).

Conversation catalog refresh is triggered by database/WAL file changes, coalesced with at least 60 seconds between automatic reads; no changes means no query. Manual refresh reconciles the full catalog and current messages. Preserve selection, filters and loaded history, and pause automatic retries on failure. See [docs/CONVERSATION_REFRESH.md](docs/CONVERSATION_REFRESH.md).

For a stable conversation ID, key the shared timestamp TimelineView by its message date so a refreshed summary cannot retain the old timestamp. Verify without switching categories; see [docs/CONVERSATION_TIMESTAMPS.md](docs/CONVERSATION_TIMESTAMPS.md).

- Message timeline separators follow [docs/MESSAGE_TIMESTAMPS.md](docs/MESSAGE_TIMESTAMPS.md): centered, 15-minute adjacent-message gaps or day boundaries; shared by live and imported timelines.

Image thumbnail bounds and native alignment acceptance: see [docs/IMAGE_ALIGNMENT.md](docs/IMAGE_ALIGNMENT.md). Keep portrait thumbnails aligned with the same-side text bubble edge.

Private repository: `wherexml/wesync`; `origin` is the private development repository and `upstream` preserves the original project. See [docs/REPOSITORY.md](docs/REPOSITORY.md). Do not publish personal data, credentials, local app bundles, or unreviewed native screenshots.

正文表情、仅 MD5 的图片表情恢复、专用签名 helper 与原生验收：见 [docs/EMOJI_DISPLAY.md](docs/EMOJI_DISPLAY.md)。保留原消息及复制内容，不绕过 TLS、摘要校验或已记住连接的工具绑定。

聊天明暗模式配色统一使用 `HistoryChatPalette`；发送正文与引用、文件说明须保持深色可读。规范及验收见 [docs/DARK_MODE.md](docs/DARK_MODE.md)。

原生桌面视觉层见 [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)：保持 SwiftUI/AppKit，参考 ChunUI，样式使用 `HistoryDesign`，聊天配色继续使用 `HistoryChatPalette`。

聊天栏仅保留齿轮“高级设置”直达连接设置，不恢复旧的多项下拉菜单；入口及重启验收见 `docs/DESIGN_SYSTEM.md`。

搜索样式与按需展开消息搜索见 `docs/SEARCH.md`：保留 NSSearchField 输入法；搜索按钮位于刷新左侧，输入框仅点击后在按钮左侧出现。 搜索框保留原生 bezeled 布局，仅绘制 cell 内部，避免图标与占位文字、光标重叠；不要再次设置 `isBezeled = false`。

会话默认后台补齐，已读历史加密缓存跨重启恢复，聊天向上滚动预取并保持阅读锚点；实现边界、隐私与原生验收见 [docs/MESSAGE_CACHE.md](docs/MESSAGE_CACHE.md)。

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

合并转发文件使用父消息绑定子序号及 fullmd5 内容校验，PDF 原生预览、其他文件原生存储；不按同名信任文件、不自动读取远端附件。见 `docs/MERGED_RECORDS.md`。

真实黑名单非空时，完整 Rust 进程 E2E 在本机 Docker 独立账户运行；不挂载用户 home/真实策略，不添加生产豁免。macOS 原生检查与安装验收保留，见 `docs/LOCAL_CI.md`。

会话变化在应用后台也按 60 秒限频处理，并触发已缓存/当前会话正文更新；当前会话优先，历史阅读锚点和连续游标须保留，失败暂停、主动刷新恢复。见 `docs/MESSAGE_CACHE.md`、`docs/CONVERSATION_REFRESH.md`。

依赖安全修复不得增加审计豁免；真实黑名单非空时，依赖升级双向快照验收使用 `scripts/dependency-upgrade-isolated.py` 的独立 Docker 账户与断网测试，见 `docs/DEPENDENCY_UPGRADES.md`。

SQLCipher 安全升级须验证真实链接版本和旧版生成的数据；用户要求重置 we-sync 隐私授权时保留钥匙串连接，重新授权后原生冷启动验证。见 [docs/DEPENDENCY_UPGRADES.md](docs/DEPENDENCY_UPGRADES.md) 和 [docs/LOCAL_SIGNING.md](docs/LOCAL_SIGNING.md)。

首次启动的初始化设置先检查本机记录的磁盘访问，再接入原安全连接表单。允许稍后设置，备份和导出记录不依赖完全磁盘访问。旧连接优先自动恢复；权限失效时重新授权后复用钥匙串，见 [docs/FIRST_RUN_SETUP.md](docs/FIRST_RUN_SETUP.md)。

产品首页源文件位于 `website/`。`python3 scripts/build-website.py` 生成三语静态页面及 Cloudflare Pages 部署包，交互预览使用合成会话。V3 布局、部署和线上验收见 [docs/WEBSITE.md](docs/WEBSITE.md)。
