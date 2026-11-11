import AppKit
import Foundation
import SwiftUI

@MainActor
final class UpdatePreviewDelegate: NSObject, NSApplicationDelegate {
  let updater = HistoryUpdater()
  private var window: NSWindow?

  private func record(_ kind: String, code: Int? = nil) {
    guard
      let directory = Bundle.main.object(forInfoDictionaryKey: "GBUpdateEvidenceDirectory")
        as? String
    else { return }
    let url = URL(fileURLWithPath: directory).appending(path: "events.jsonl")
    let row: [String: Any] = [
      "event": kind, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "",
      "code": code as Any? ?? NSNull(),
    ]
    guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    else { return }
    data.append(10)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(
        atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    guard let file = try? FileHandle(forWritingTo: url) else { return }
    defer { try? file.close() }
    _ = try? file.seekToEnd()
    try? file.write(contentsOf: data)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    updater.diagnosticHandler = { [weak self] kind, code in self?.record(kind, code: code) }
    updater.start()
    record("launched")
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "we-sync"
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    window.contentView = NSHostingView(
      rootView:
        VStack(alignment: .leading, spacing: 18) {
          HStack {
            Text("we-sync").font(.system(size: 18, weight: .semibold))
            Spacer()
            Text("0.10.0（\(version)）").foregroundStyle(.secondary)
            Button("检查更新…") { self.updater.check() }
          }
          Divider()
          Spacer()
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HistoryDesign.canvas)
        .overlay(alignment: .bottomTrailing) {
          HistoryUpdateNotice(updater: updater).padding(24)
        })
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    let menu = NSMenu()
    let application = NSMenuItem()
    menu.addItem(application)
    let entries = NSMenu()
    entries.addItem(withTitle: "检查更新…", action: #selector(check), keyEquivalent: "u").target = self
    entries.addItem(
      withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    application.submenu = entries
    NSApp.mainMenu = menu
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func check() { updater.check() }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum UpdatePreviewMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = UpdatePreviewDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
