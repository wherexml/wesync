# 聊天消息时间分隔

实时聊天与导入记录共用 `HistoryMessageTime` / `HistoryMessageTimestamp`，时间从消息气泡移到聊天内容区域中间，以 12pt 次级文字独立显示。

## 规则

- 当前已加载序列的第一条有效时间显示分隔。
- 与相邻上一条消息间隔达到 15 分钟（包含 15:00）显示；持续聊天不会按上一个时间标签累计重新计时。
- 跨本地日历日始终显示，即使不足 15 分钟；同秒消息不重复显示。
- 系统消息也参与时间间隔；缺失时间不伪造日期，下一条有时间的消息重新显示分隔。
- 今天 `HH:mm`；昨天 `昨天 HH:mm`；昨天之前且同一自然周 `星期X HH:mm`；更早 `M 月 d 日 HH:mm`；跨年补 `yyyy 年`。
- 自然周为周一至周日；使用本机时区、公历、24 小时制，每分钟更新日期标签。
- 分页加载后按合并序列重新计算边界，不把每页首条强行当成新分组。搜索上下文首条仍提供时间定位。
- 会话列表右上角保持其独立规则，见 [CONVERSATION_TIMESTAMPS.md](CONVERSATION_TIMESTAMPS.md)。

## 复验

运行 `bash scripts/verify-message-timestamps.sh`，输出 `.build/message-timestamps-acceptance/rendering.json` 与 `synthetic-timeline.png`。原生渲染使用生产时间组件，固定日期断言包含 14:59 / 15:00、同秒、周边界、跨年和缺失日期。截图日期相对于运行当天显示。

安装版必须使用现有稳定证书，退出再重开确认记住的连接自动恢复，检查消息间居中时间以及连续消息无重复时间。仅记录时间标签和验证结论，不保存真实消息内容。此次证据见 [acceptance/message-timestamps-20261002](acceptance/message-timestamps-20261002)。
