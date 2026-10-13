# 合并转发聊天记录

## 实时聊天展示

`MergedMessages` 不再退化为普通标题文字。`HistoryRichMessageBody` 显示聊天记录卡片，包含标题、最多三条预览及打开入口；点击后在原生 sheet 中按原顺序显示发送者、来源时间和可选择复制的正文。关闭后保留当前聊天。

`HistoryMergedRecord` 仅解析已获得的 `raw_xml`，支持直接嵌套和 CDATA/转义的 `recorditem`、`recordxml`。保持原始内容和原有复制行为，不修改数据库或消息缓存。拒绝 DTD/实体；单份 XML 最多 2 MiB、30000 个节点、48 层元素、4 层嵌入文档和 500 条预览。损坏、缺失或超限内容明确显示提示，不把部分结果声称为全部消息。

当前范围：实时聊天中的合并转发文字。图片、语音、视频、文件等内嵌附件显示类型占位，不读取 XML 中的 CDN 地址或密钥。嵌套转发显示聊天记录占位；导入档案仍沿用其原有视图。这些占位不代表附件已恢复或可播放。

## 可重复验收

1. `python3 scripts/package-presentation-preview.py --polish`，使用干净的 offline-fixture（旧 marker 需移入备份目录）。
2. 原生启动预览，合成 CLI 经生产连接、分页与渲染路径加载 15 条消息，检查 `acceptance.json` 中 `merged-record-ordered-text-and-media`、`merged-record-malformed-and-entity-safe` 为 true；`presentation.png` 为可核查合成图。
3. 打开合成会话，点击“合成群聊的聊天记录”，核对两条消息的顺序、发送者、时间、实体解码后的正文和图片占位，点击“完成”返回。
4. 按 `LOCAL_SIGNING.md` 沿用当前 Apple Development 身份，仅替换主程序；校验 designated requirement、全部 helper 字节不变。
5. 原生退出安装版后更新、重开，确认自动连接且无需密钥，打开用户指定的转发记录，核对文字明细；关闭后再次退出重开复验。只保存脱敏结论，不提交私聊截图或原文。

本次合成、签名和原生结果见 `acceptance/merged-records-20261013/`。图片恢复不在本次通过项内。
