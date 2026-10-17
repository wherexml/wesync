import AppKit
import SwiftUI

/// Keep the mouse event in window coordinates instead of asking a virtualized
/// SwiftUI List row to focus/scroll itself before presenting its context menu.
struct HistoryConversationContextMenu: NSViewRepresentable {
  struct Action {
    let title: String
    let symbol: String
    let perform: () -> Void
  }

  var actions: () -> [Action]

  func makeNSView(context: Context) -> MenuView { MenuView() }

  func updateNSView(_ nsView: MenuView, context: Context) {
    nsView.actions = actions
  }

  final class MenuView: NSView {
    var actions: (() -> [Action])?
    private var presentedActions: [Action] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard let event = NSApp.currentEvent,
        event.type == .rightMouseDown || event.type == .rightMouseUp
          || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
      else { return nil }
      return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(for: event) }
    override func mouseDown(with event: NSEvent) { showMenu(for: event) }

    private func showMenu(for event: NSEvent) {
      presentedActions = actions?() ?? []
      let menu = NSMenu()
      for (index, action) in presentedActions.enumerated() {
        if index > 0 { menu.addItem(.separator()) }
        let item = NSMenuItem(title: action.title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
        menu.addItem(item)
      }
      NSMenu.popUpContextMenu(menu, with: event, for: self)
      presentedActions = []
    }

    @objc private func invoke(_ sender: NSMenuItem) {
      guard presentedActions.indices.contains(sender.tag) else { return }
      presentedActions[sender.tag].perform()
    }
  }
}
