# 主窗口复用

WeSync 只保留一个聊天主窗口。Dock 点击、Finder 再次打开和菜单栏“打开 WeSync”均恢复该窗口，不创建第二个聊天窗口；最小化时还原，隐藏时前置，关闭后重新显示。连接模型与会话状态继续由 App 持有。

## 实现约束

`GreenBubblesHistoryApp.swift` 使用 `Window("微信聊天记录", id: "history")`，不要恢复为 `WindowGroup`。`openWindow(id:)` 由 SwiftUI 按单窗口语义复用；重开代理调用统一入口并返回 false，避免 AppKit 再执行默认重开。前置时显式解除最小化。菜单栏保持可用，关闭主窗口不退出应用。

## 2026-10-16 原生验收

旧版“窗口”菜单出现两个“聊天”项。修复版从已提交源码加本次主窗口修改构建，保持原 Apple Development 身份及全部 helper 字节，完整退出后安装。两次 Finder 冷启动自动连接、消息加载与刷新通过；Finder 连续五次重开、菜单三次打开、最小化/隐藏/关闭后恢复通过。未输入凭据或修改 TCC/ACL。

直接 Dock 点击验收受原生 Dock 自动化接口超时阻塞；Finder 的原生应用重开入口用于覆盖相同的 applicationShouldHandleReopen 流程，不将其记录为直接 Dock 点击通过。

脱敏记录及复验步骤：[single-window-20261016.json](acceptance/single-window-20261016.json)。本地回滚包位于 `.build/single-window-install-20261016/installed-backup.app`，须完整退出后恢复。工作区已有搜索框修改未混入本次构建和提交。
