import AppKit
import Foundation

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
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "we-sync 更新验收"
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let label = NSTextField(labelWithString: "we-sync 0.10.0（\(version)）")
    label.font = .systemFont(ofSize: 24, weight: .semibold)
    let button = NSButton(title: "检查更新…", target: self, action: #selector(check))
    button.bezelStyle = .rounded
    let stack = NSStackView(views: [label, button])
    stack.orientation = .vertical
    stack.spacing = 24
    window.contentView = stack
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
