# 联系人和群聊时间范围

聊天栏齿轮“高级设置”顶部新增“会话显示 → 联系人和群聊时间范围”。选项为 **1 周、1 个月、3 个月、1 年、所有**，首次默认 **1 个月**。选中立即生效并自动保存；底部“取消”仅关闭连接表单，不回退已经保存的显示范围，无需提交“连接并查看”。

按会话最近消息时间筛选，而不是联系人创建时间。个人、群聊和其他分类遵循同一范围；导入记录会话使用最新消息统计，导入联系人至少有一个范围内的关联会话才显示。导入列表在实现上共用规则，本次原生验收使用实时界面。

1 周是向前 7 个日历日；月和年使用本机日历向前减 1 月、3 月、1 年，包含恰好落在边界的会话。截止时间每分钟更新，重开重新计算。没有有效最近消息时间的会话仅在“所有”中显示；实时秒/毫秒时间沿用现有 `sortDate` 归一化。

显示范围只过滤视图，不删除源记录、加密缓存、分页游标或加载中的会话。搜索列表与时间范围取交集；历史消息内容不受列表范围裁剪。缩小范围导致当前聊天被隐藏时，清空该聊天的可见选择并取消未完成的消息读取；扩大范围后仍可选择旧聊天。空列表提示可在高级设置扩大范围。

实现：`HistoryConversationRange.swift` 定义选项、日历边界和普通偏好键 `history.conversationRange.v1`；`HistoryBrowserModel` 保存偏好并筛选；`HistoryDirectConnectionSheet` 提供原生 Picker。范围偏好不包含联系人或凭据。

## 重复 E2E

1. `python3 scripts/package-presentation-preview.py --polish` 构建隔离预览，不读取微信。
2. 在 `.local-install/GreenBubbles Polish Preview.app/Contents/Resources/offline-fixture/` 创建空文件 `conversation-range-acceptance`。此模式优先于其他既有验收标记，不更改安装版连接。
3. 原生退出旧预览并重新打开；真实 CLI transport 返回固定 2026-10-02 12:00 UTC 下的 21 个合成会话，生产 model 校验五档范围、分类、搜索交集、毫秒时间、未知时间、边界、自然月末、选择清空、扩大恢复及新 model 偏好读取。
4. 检查 `offline-fixture/conversation-range-acceptance.json`：`passed: true`，48 项检查全部通过。固定时钟用于自动验收；自动流程结束后每分钟时钟会恢复真实当前时间。
5. 按 `LOCAL_SIGNING.md` 沿用安装版固定证书暂存主程序更新，确认 helper 字节与 designated requirement 不变，保留旧包；原生退出、安装、原生重开，不输入凭据自动连接。
6. 点击齿轮检查默认 1 个月和五档菜单，逐项选择并关闭设置检查个人/群聊。选择一周，核对列表最近消息日期；扩大范围确认列表恢复。最终设置 1 个月，完整退出重开，检查自动连接和选项仍为 1 个月。

脱敏证据：`acceptance/conversation-range-20261002/{PLAN.md,synthetic.json,signing.json,native.json}`。已安装 build 17 → 18，固定签名与 helper 字节校验通过；重启后自动连接、范围保存均通过。列表超过可视行时 AX 会虚拟化，记录的 rendered rows 不代表全量会话总数。未新增单元测试，未归档真实联系人、消息内容或截图。
