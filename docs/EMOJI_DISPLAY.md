# 正文表情与无网址图片表情

## 实现前失败清单与验收约定

- `[流泪]原来如此`、相邻/重复表情、中英文别名应显示对应 Unicode 表情；未知方括号内容、普通文字、链接和已有 Unicode 不变。正文及引用使用同一转换；复制消息保留原文。Unicode 字形不是微信专用素材。
- type 47 XML 只有 MD5 时，不能因无 CDN URL 提前结束。只从当前已授权 live connection 的 account/business/emoticon 查找摘要对应文件；快照和其他账户不能借用本机文件。
- 本机查找限制 20,000 条目录项、12 层、单文件 8 MiB；拒绝路径穿越、符号链接、非普通文件、摘要不符及无效图片。通过目录文件描述符访问；不打开或解密数据库。
- 本机失败后尝试既有网络候选；所有候选失败显示可重试占位。切换源/消息取消旧任务；动图保持动画。
- 先运行合成端到端程序，覆盖临时账户目录、文件命中、缺失、错误摘要、符号链接、非法摘要、错误源及正文转换，输出脱敏 JSON；再安装同证书签名包，原生退出/重开，确认自动连接，检查用户指定的两条消息。

## 加密本机资源补充失败清单（实机发现后，元数据实现前）

- 部分本机表情文件为加密数据，不能绕过摘要或图片验证展示。仅对用户已打开的单条 type 47 消息，按 XML 中的 32 位摘要从当前 source 的 `emoticon/emoticon.db` 查询 `kNonStoreEmoticonTable` 一行，最多八个固定字段，每字段 4096 字节。
- 没有表、没有行、字段缺失应保留原消息；元数据摘要必须与消息摘要一致。禁止将其他消息、其他账号或整个表作为回退。
- 增加独立签名的 bundled `greenbubbles-sticker-query`，复用现有 message get 和 stdin 密钥通道；原记住连接所绑定的 `greenbubbles` 字节保持不变。不得放宽已记住工具的 digest 验证。
- 单条查询统计包含额外元数据库；网络加载仍经过 HTTPS 域名、摘要和图片边界校验。原始消息、网址和密钥不写入公开报告。

## 实现与验证

- `HistoryEmojiText` 只转换展示层的已知别名，应用于 live/imported 正文、引用和搜索结果；不修改消息数据与右键复制原文。未知编码及 URL 保留。当前采用系统 Unicode 字形，未声称与微信专用图形完全一致。
- `HistorySticker` 保留消息 MD5。`HistoryLocalStickerStore` 用目录描述符及 `O_NOFOLLOW` 在本账号下载目录有界查找，仍需通过全文 MD5 和图片解码；加密本机文件不会当作图片展示。
- `message get` 对选定 type 47 消息补充 `content.StickerResource`；原 `content.Emoji` 保留。元数据库读取计入 consistency，查询设 SQLite VM 步数上限，缺失或不兼容不阻断正文。
- App 仅在原资源失败时按消息身份补充元数据，检查 source/message/MD5 一致。专用 bundled helper 的最终签名字节 SHA-256 固定在外层签名覆盖的 Info.plist `GBStickerQuerySHA256` 中；应用调用前校验。原始连接工具及记住连接的摘要校验保持不变。
- 旧 `vweixinf.tc.qq.com` 在当前环境发生 TLS 主机名证书不匹配。将该明确旧别名改为 `wxapp.tc.qq.com`，保留路径和查询参数并坚持 HTTPS。已验证用户指定图片返回 HTTP 200、MD5 完全一致；没有关闭证书校验或降级 HTTP。
- 原图验证：74,707 字节、1 帧、ImageIO/AppKit 成功解码；新进程 cache-only 成功。脱敏报告见 `docs/acceptance/emoji-fix-20261002/`。
- build 13 原生重启自动连接成功，正文 `流泪` 已显示。build 14 包含元数据补全和 CDN 兼容，签名完整且 designated requirement 与旧包一致，原查询/发送工具字节保持一致。最终原生验收暂待系统钥匙串确认；不可将资源/合成通过等同于安装后验收通过。

## 可重复验收

```sh
scripts/sticker-acceptance/local-e2e.sh
cargo build --manifest-path Native/GreenBubbles/Cargo.toml --release
python3 scripts/sticker-acceptance/metadata-e2e.py Native/GreenBubbles/target/release/greenbubbles docs/acceptance/emoji-fix-20261002/metadata.json
```

本机资源及正文转换 11 项、元数据 CLI 6 项 E2E 全部通过。测试创建临时合成账户，退出清理；报告不含私人消息、联系人、网址或密钥。已授权的实际单条消息可用 `scripts/sticker-acceptance/run.sh` 复现加载并用 `--cache-only` 复验，私有输入不得提交。

安装后：原生 Cmd-Q → 确认进程退出 → 同证书更新 → 原生重开 → 无需输入数据库密钥自动连接 → 打开原问题群 → 加载至原问题消息，确认正文表情及原图都显示；再退出重开复验。仅在系统安全窗口由用户确认钥匙串，不经聊天收集密码。

CI 的 Swift/Rust jobs 分别运行上述 E2E，输出脱敏 JSON；既有测试保持。当前本机 `cargo clippy -D warnings` 被三个未修改文件中的四条 `nonminimal_bool` 既有告警阻断；仅在本机临时允许该告警后，其余严格检查通过，未在项目或 CI 中关闭此检查。云端结果单独记录。
