import AppKit
import SwiftUI

/// Explicitly activates the window before editing; preserves the native IME field editor.
struct HistorySearchField: NSViewRepresentable {
  let prompt: String
  @Binding var text: String
  var onSubmit: () -> Void = {}
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSSearchField {
    let field = ActivatingSearchField()
    field.placeholderString = prompt
    field.setAccessibilityLabel(prompt)
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.submit)
    field.sendsWholeSearchString = true
    field.sendsSearchStringImmediately = false
    field.focusRingType = .none
    field.bezelStyle = .roundedBezel
    field.font = .systemFont(ofSize: 14)
    return field
  }
  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
    // Never replace in-progress composition or reset the caret on normal SwiftUI updates.
    if field.stringValue != text
      && !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false)
    {
      field.stringValue = text
    }
  }
  @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: HistorySearchField
    init(_ parent: HistorySearchField) { self.parent = parent }
    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSSearchField else { return }
      parent.text = field.stringValue
    }
    @objc func submit() { parent.onSubmit() }
  }
}
private final class ActivatingSearchField: NSSearchField {
  override func mouseDown(with event: NSEvent) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    super.mouseDown(with: event)
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
