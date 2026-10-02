import AppKit
import Foundation
import GreenBubblesHistory
import SwiftUI

@main struct StickerNativeAcceptance {
  @MainActor static func main() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Sticker Acceptance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
    let fixture = Bundle.main.resourceURL!.appending(path: "message.json")
    let message = try JSONDecoder().decode(HistoryDirectMessage.self, from: Data(contentsOf: fixture))
    guard let sticker = message.sticker else { return }
    let content = VStack(spacing: 20) {
      Text("GreenBubbles 表情恢复验收").font(.title2)
      HStack(spacing: 30) {
        VStack { HistoryStickerView(sticker: sticker); Text("截图对应表情 · 原始资源") }
        VStack { HistoryStickerView(sticker: HistorySticker(previewURLs: [])); Text("无资源 · 不显示 XML") }
        VStack { HistoryStickerView(sticker: HistorySticker(previewURLs: [URL(string: "https://emoji.qpic.cn/greenbubbles-unavailable-acceptance")!])); Text("失效资源 · 可重试") }
      }
    }.padding(30)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 330), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "GreenBubbles Sticker Acceptance"
    window.contentView = NSHostingView(rootView: content)
    window.center(); window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
  }
}
