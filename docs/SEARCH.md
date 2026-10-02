# 会话与消息搜索

## 样式及交互

`HistorySearchField` 使用 `HistoryDesign` 的自适应背景和轻边框，32 pt 高、9 pt 圆角、13 pt 字号。内部仍为 `NSSearchField`：保留原生搜索图标、清空按钮、输入法协调和光标位置，不用 SwiftUI TextField 替代。

左侧当前分类的会话搜索保持常驻，输入实时筛选；搜索结果页使用同一输入框样式。

消息页默认只有标题栏中的搜索图标，位于刷新按钮左侧。点击搜索图标，在它左侧展开 120–260 pt 输入框并自动聚焦。输入后按回车打开现有当前会话搜索结果页。空白关键词不提交。Esc 或再次点击搜索图标收起并清空临时输入；切换会话后也收起，避免误用上一会话关键词。标题保持单行，消息区不再留一行搜索框和文字搜索按钮。

## 原生 E2E 复现

1. 构建 `swift build -c release --product greenbubbles-history`，检查 Swift 格式和密钥卫生。
2. `python3 scripts/package-presentation-preview.py --polish`，用原生 UI 打开 `.local-install/GreenBubbles Polish Preview.app`。合成 CLI 运行生产 model；现有 `offline-fixture/acceptance.json` 提供基础链路证据。
3. 在合成预览选择个人会话：默认消息搜索输入框不存在；点击搜索按钮确认输入框在按钮左边、刷新仍在右边。直接输入「合成」验证自动聚焦，按回车检查搜索结果及返回聊天。测试空白回车、Esc 收起、再次点击收起、原生清空、切换会话收起及左侧会话筛选。
4. 按 `LOCAL_SIGNING.md` 使用已安装应用的固定证书，保留查询/发送 helper 字节及 designated requirement；备份旧包后安装。
5. 原生退出并重开 `/Applications/GreenBubbles.app`，无需输入凭据恢复连接；重复搜索交互并检查刷新。再次退出重开确认连接和默认折叠状态。

归档脱敏结果于 `acceptance/search-20261002.json`；只保留合成界面截图，真实聊天截图、搜索词、联系人及凭据不提交仓库。

会话列表搜索与 `CONVERSATION_RANGE.md` 的时间范围取交集，旧会话不会因名称或摘要命中重新进入列表。聊天内消息搜索仍检索当前会话全部历史。
