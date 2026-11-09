import AppKit
import GreenBubblesCore
import SwiftUI

struct HistorySetupGuide: View {
  let model: HistoryBrowserModel
  @State private var access: WeChatLocalDatabaseAccess?
  @State private var checkID = 0

  private var permissionRequired: Bool { access == .permissionRequired }
  private var accessReady: Bool {
    if case .readable = access { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("初始化设置")
        .font(HistoryDesign.title)

      HistorySettingsGroup {
        HStack(spacing: 12) {
          Image(systemName: "externaldrive")
            .font(.system(size: 19))
            .frame(width: 24)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text("完全磁盘访问权限").font(.headline)
            Text("读取本机微信记录")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Label(status, systemImage: accessReady ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(accessReady ? HistoryDesign.accent : .secondary)
            .accessibilityIdentifier("setup-access-status")
        }
        if permissionRequired {
          Text("在系统设置中添加并开启 we-sync。如系统提示重开应用，请按提示操作。")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 12) {
            Button("打开系统设置") { openPrivacySettings() }
              .buttonStyle(HistoryActionStyle(prominent: true))
              .accessibilityIdentifier("setup-open-settings")
            Button("在 Finder 中显示 we-sync") {
              NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            .buttonStyle(HistoryActionStyle())
          }
        }
      }

      HStack(spacing: 10) {
        Button("稍后设置") { model.deferSetupGuide() }
          .buttonStyle(HistoryActionStyle())
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("重新检查") { checkID += 1 }
          .buttonStyle(HistoryActionStyle())
          .accessibilityIdentifier("setup-recheck")
        Button(continueTitle) {
          guard let access else { return }
          model.continueSetupGuide(access: access)
        }
        .buttonStyle(HistoryActionStyle(prominent: !permissionRequired))
        .keyboardShortcut(.defaultAction)
        .disabled(access == nil || permissionRequired)
        .accessibilityIdentifier("setup-continue")
      }
    }
    .padding(24)
    .frame(width: 540)
    .background(HistoryDesign.canvas)
    .task(id: checkID) {
      let source = model.setupGuideSource
      let result = await Task.detached(priority: .utility) {
        WeChatAccountDiscovery().localDatabaseAccess(preferredRoot: source)
      }.value
      if !Task.isCancelled { access = result }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in checkID += 1 }
  }

  private var status: String {
    switch access {
    case .readable: "可读取"
    case .permissionRequired: "需要授权"
    case .sourceUnavailable: "未找到本机记录"
    case nil: "检查中…"
    }
  }

  private var continueTitle: String {
    if access == .sourceUnavailable { return "选择记录…" }
    return model.setupGuideWillRestoreConnection ? "重新连接" : "继续连接"
  }

  private func openPrivacySettings() {
    let privacy = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    if !NSWorkspace.shared.open(privacy) {
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
  }
}
