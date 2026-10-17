# 合并转发聊天记录

## 实时聊天展示

`MergedMessages` 不再退化为普通标题文字。`HistoryRichMessageBody` 显示聊天记录卡片，包含标题、最多三条预览及打开入口；点击后在原生 sheet 中按原顺序显示发送者、来源时间和可选择复制的正文。关闭后保留当前聊天。

`HistoryMergedRecord` 仅解析已获得的 `raw_xml`，支持直接嵌套和 CDATA/转义的 `recorditem`、`recordxml`。保持原始内容和原有复制行为，不修改数据库或消息缓存。拒绝 DTD/实体；单份 XML 最多 2 MiB、30000 个节点、48 层元素、4 层嵌入文档和 500 条预览。损坏、缺失或超限内容明确显示提示，不把部分结果声称为全部消息。

当前范围：实时聊天中的合并转发文字。本机可定位的内嵌图片自动加载并可点击放大；语音、视频、文件等附件仍显示类型占位，不读取 XML 中的 CDN 地址或密钥。嵌套转发显示聊天记录占位；导入档案仍沿用其原有视图。这些占位不代表附件已恢复或可播放。

## 可重复验收

1. `python3 scripts/package-presentation-preview.py`，使用干净的 offline-fixture（旧 marker 和该合成应用专用的 History-v1 缓存需移入备份目录，不能清理生产缓存）。
2. 原生启动预览，合成 CLI 经生产连接、分页与渲染路径加载 15 条消息，检查 `acceptance.json` 中 `merged-record-ordered-text-and-media`、`merged-record-malformed-and-entity-safe` 为 true；`presentation.png` 为可核查合成图。
3. 打开合成会话，点击“合成群聊的聊天记录”，核对两条消息的顺序、发送者、时间、实体解码后的正文和图片占位，点击“完成”返回。
4. 按 `LOCAL_SIGNING.md` 沿用当前 Apple Development 身份，通过工具更新脚本同时暂存主程序和读取工具；校验 designated requirement 不变、读取工具精确摘要迁移、发送 helper 字节不变。
5. 原生退出安装版后更新、重开，确认自动连接且无需密钥，打开用户指定的转发记录，核对文字明细；关闭后再次退出重开复验。只保存脱敏结论，不提交私聊截图或原文。

本次合成、签名和原生结果见 `acceptance/merged-records-20261013/`。后续图片恢复结果见 `acceptance/merged-images-20261013/`。


## 本机图片恢复

打开记录后自动加载图片，点击缩略图可放大，完成后返回记录；失败显示本机图片暂不可用及重试入口。保持两路图片并发、32 MiB 前端限制、临时文件清理、SHA-256 回执校验及连接切换隔离。

读取工具接受 `<parent-message-id>~merged-image~<zero-based-index>` 作为 image 请求的精确子消息标识。每次 inspect/materialize 重新读取并授权父消息，只允许 0...499 的顶层图片条目，从来源 XML 获取 fullmd5，不接受界面自报 MD5 或远端凭据。父消息内容、选中会话及附件候选保持身份绑定。

部分转发 fullmd5 与本地文件名索引不一致。如果 XML 有 fromnewmsgid 和 srcMsgCreateTime，则只在父会话对应的一秒内有界查询最多 100 条，唯一匹配的原始图片提供本地索引；不存在或不唯一时使用转发 fullmd5 查找该会话附件。不会跨会话扫描、忽略黑名单或访问 CDN。跨会话转发且本机缺少可定位副本时仍显示不可用。

Rust CLI E2E 先定义失败契约，实际启动查询/附件命令验证父消息绑定、来源索引不同的恢复、非图片与越界拒绝和导出字节；`cargo test --manifest-path Native/GreenBubbles/Cargo.toml --test live_attachment_cli` 可重复运行。Swift 合成验收包含 `merged-image-production-load-and-decode`，原生验收包括用户指定记录的真实图像和放大返回。更新 CLI 必须使用 `stage-local-tool-update.py` 的精确摘要迁移，不能只替换工具文件。
