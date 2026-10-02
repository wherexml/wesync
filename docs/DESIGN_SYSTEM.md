# GreenBubbles 原生桌面设计系统

## 方向

保留 SwiftUI / AppKit 与 macOS 14 支持。参考 ChunUI 的灰阶层次、单一品牌色、连续圆角和轻微按钮质感；不引入其 iOS 包、UIKit 呈现层或手机尺寸。实现为原创桌面样式，不复制上游源码。

参考：https://github.com/liseami/ChunUI

## 组件边界

- `HistoryDesign.swift`：语义背景、品牌绿、选中态、边框、12 pt 气泡圆角；`HistoryActionStyle` 只显式用于操作按钮，提供按压和禁用反馈。
- `HistoryChatPalette.swift`：聊天区、收发气泡和文字对比度以 `DARK_MODE.md` 为准，不在设计层重复定义。
- 实时浏览保持双栏，导入浏览保留原生分栏；搜索保留 NSSearchField 的输入法协调，分类保留系统 segmented picker，列表和菜单保留原生键盘交互。
- 欢迎页采用 28 pt 标题，实时聊天栏采用 22 pt 标题；正文及列表保留桌面密度，不套用手机三档字号。
- 轻阴影只用于按钮，不在长消息列表加入持续动画。保留橙色警告和红色错误语义。
- 图片消息保持透明背景、原有缩略图尺寸与同侧对齐；不变更分页、缓存、连接与凭据处理。
- 聊天栏右上角仅保留 32 × 32 pt 的齿轮“高级设置”按钮，直接打开连接设置，使用悬浮提示和辅助功能名称，不叠加下拉箭头。旧菜单的全局搜索、返回聊天、来源信息和忘记连接入口移除；会话筛选、聊天内搜索及搜索结果页返回按钮保留，忘记连接只在设置中操作。

## 高级设置入口验收

原生退出并重开安装版，确认无需输入密钥即恢复聊天列表；右上角应仅显示一个齿轮，无菜单箭头。点击“高级设置”应直接打开连接设置，取消后保持会话列表可用，再退出重开复验。不要点击“忘记已保存的连接”或提交新凭据。脱敏结果见 `acceptance/advanced-settings-20261002.json`。

## 重复验收

1. `swift build -c release --product greenbubbles-history`。
2. `python3 scripts/package-presentation-preview.py --polish`；用原生 UI 打开 `.local-install/GreenBubbles Polish Preview.app`。现有端到端流程经合成 CLI 驱动生产 model，输出 `Contents/Resources/offline-fixture/acceptance.json` 与 `presentation.png`。
3. 在预览检查欢迎/连接入口、会话分类及搜索、气泡层次和图像对齐。只归档合成图或脱敏结论。
4. 按 `LOCAL_SIGNING.md` 使用同一证书暂存应用更新，仅替换主界面程序，验证 helper 字节与 designated requirement 不变。
5. 原生退出安装版、安装、原生重开，确认不输入密钥自动连接，检查会话选择、搜索、时间分隔、附件，退出重开再复验。此步骤未通过时，不声明安装交付完成。
