import AppKit
import GreenBubblesHistory
import SwiftUI

@main
struct GreenBubblesHistoryApplication: App {
  @NSApplicationDelegateAdaptor(HistoryApplicationDelegate.self) private var applicationDelegate
  @State private var model = HistoryBrowserModel()
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    WindowGroup("微信聊天记录", id: "history") {
      HistoryRootView(model: model)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
          applicationDelegate.showWindowHandler = { openWindow(id: "history") }
          applicationDelegate.ensureStatusItem()
          applicationDelegate.activateHistoryWindow()
          applicationDelegate.registerOpenURLHandler { [weak model] urls in
            model?.openExternalURLs(urls)
          }
        }
    }
    .defaultSize(width: 1_320, height: 860)
    .commands {
      CommandGroup(after: .toolbar) {
        Button("菜单栏选项") { applicationDelegate.presentStatusMenu() }
          .keyboardShortcut("m", modifiers: [.control, .option])
      }
      CommandGroup(replacing: .newItem) {
        Button("连接微信记录或备份…") {
          model.presentDirectConnection()
        }
        .keyboardShortcut("o")

        Button("打开聊天记录文件夹…") {
          model.chooseBundle()
        }
        .keyboardShortcut("o", modifiers: [.command, .option])

        Divider()

        Button("创建可恢复的加密备份…") {
          model.presentSnapshotCreation()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("关闭当前记录") {
          model.closeBundle()
        }
        .disabled(!model.hasOpenHistory)
        .keyboardShortcut("w", modifiers: [.command, .shift])
      }
    }

  }
}

@MainActor
final class HistoryApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var showWindowHandler: (() -> Void)?
  private var statusItem: NSStatusItem?
  private var dockMenuItem: NSMenuItem?
  private var openURLHandler: (([URL]) -> Void)?
  private var pendingOpenURLs: [URL] = []

  var showDockIcon = UserDefaults.standard.bool(forKey: "history.showDockIcon")

  static var menuIcon: NSImage {
    let image =
      Bundle.main.url(forResource: "GreenBubbles-black", withExtension: "png")
      .flatMap { NSImage(contentsOf: $0) }
      ?? NSImage(
        systemSymbolName: "bubble.left.and.bubble.right.fill",
        accessibilityDescription: "GreenBubbles")!
    image.size = NSSize(width: 22, height: 22)
    image.isTemplate = true
    return image
  }

  func applyDockPolicy() {
    NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
  }

  func activateHistoryWindow() {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first(where: { $0.canBecomeKey && !$0.isSheet })?.makeKeyAndOrderFront(nil)
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    ensureStatusItem()
    activateHistoryWindow()
  }

  func ensureStatusItem() {
    guard statusItem == nil else { return }
    applyDockPolicy()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = Self.menuIcon
    item.button?.toolTip = "GreenBubbles"
    item.button?.setAccessibilityLabel("GreenBubbles 菜单栏")
    let menu = NSMenu(title: "GreenBubbles")
    menu.delegate = self
    func add(_ title: String, _ action: Selector) -> NSMenuItem {
      let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
      entry.target = self
      menu.addItem(entry)
      return entry
    }
    _ = add("打开 GreenBubbles", #selector(showHistory))
    _ = add("隐藏窗口", #selector(hideHistory))
    menu.addItem(.separator())
    dockMenuItem = add("在程序坞中显示", #selector(toggleDock))
    menu.addItem(.separator())
    _ = add("退出 GreenBubbles", #selector(quitHistory))
    item.menu = menu
    statusItem = item
    #if DEBUG
      if Bundle.main.object(forInfoDictionaryKey: "GBOfflineAcceptance") as? Bool == true,
        let root = Bundle.main.resourceURL?.appending(path: "offline-fixture")
      {
        let report: [String: Any] = [
          "statusItemCreated": true, "statusItemVisible": item.isVisible,
          "menuItemCount": menu.items.filter { !$0.isSeparatorItem }.count,
          "dockHidden": NSApp.activationPolicy() == .accessory,
        ]
        if let bytes = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        {
          try? bytes.write(to: root.appending(path: "menu-runtime.json"))
        }
      }
    #endif
    activateHistoryWindow()
  }

  func menuWillOpen(_ menu: NSMenu) { dockMenuItem?.state = showDockIcon ? .on : .off }
  func presentStatusMenu() {
    // Also expose the same menu inside the window when the system menu bar is crowded.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.ensureStatusItem()
      if let view = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible })?.contentView {
        self?.statusItem?.menu?.popUp(
          positioning: nil, at: NSPoint(x: 24, y: view.bounds.height - 24), in: view)
      } else {
        self?.statusItem?.button?.performClick(nil)
      }
    }
  }
  @objc private func showHistory() {
    showWindowHandler?()
    activateHistoryWindow()
  }
  @objc private func hideHistory() {
    NSApp.windows.filter { $0.canBecomeKey }.forEach { $0.orderOut(nil) }
  }
  @objc private func toggleDock() {
    showDockIcon.toggle()
    UserDefaults.standard.set(showDockIcon, forKey: "history.showDockIcon")
    applyDockPolicy()
    activateHistoryWindow()
  }
  @objc private func quitHistory() { NSApp.terminate(nil) }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showWindowHandler?()
    activateHistoryWindow()
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    if let openURLHandler {
      openURLHandler(urls)
    } else {
      pendingOpenURLs.append(contentsOf: urls)
    }
  }

  func registerOpenURLHandler(_ handler: @escaping ([URL]) -> Void) {
    openURLHandler = handler
    guard !pendingOpenURLs.isEmpty else { return }
    let urls = pendingOpenURLs
    pendingOpenURLs.removeAll()
    handler(urls)
  }
}
