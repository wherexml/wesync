import AppKit
import SwiftUI

/// Explicitly activates the window before editing; preserves the native IME field editor.
struct HistorySearchField: View {
  let prompt: String
  @Binding var text: String
  var focusOnAppear = false
  var onSubmit: () -> Void = {}
  var onCancel: (() -> Void)?

  var body: some View {
    HistoryNativeSearchField(
      prompt: prompt, text: $text, focusOnAppear: focusOnAppear,
      onSubmit: onSubmit, onCancel: onCancel
    )
    .padding(.horizontal, 8)
    .frame(height: 32)
    .background(HistoryDesign.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .strokeBorder(HistoryDesign.border.opacity(0.65), lineWidth: 0.5)
    }
  }
}

private struct HistoryNativeSearchField: NSViewRepresentable {
  let prompt: String
  @Binding var text: String
  let focusOnAppear: Bool
  let onSubmit: () -> Void
  let onCancel: (() -> Void)?

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
    field.isBezeled = false
    field.drawsBackground = false
    field.font = .systemFont(ofSize: 13)
    field.focusOnAttach = focusOnAppear
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
    var parent: HistoryNativeSearchField
    init(_ parent: HistoryNativeSearchField) { self.parent = parent }
    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSSearchField else { return }
      parent.text = field.stringValue
    }
    @objc func submit(_ field: NSSearchField) {
      // AppKit also sends the action when its clear button is clicked, before
      // SwiftUI has necessarily received the text-change notification.
      parent.text = field.stringValue
      guard !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
      }
      parent.onSubmit()
    }
    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
      guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
        let onCancel = parent.onCancel
      else { return false }
      onCancel()
      return true
    }
  }
}
private final class ActivatingSearchField: NSSearchField {
  var focusOnAttach = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard focusOnAttach, window != nil else { return }
    focusOnAttach = false
    DispatchQueue.main.async { [weak self] in
      guard let self, let window = self.window else { return }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.makeFirstResponder(self)
    }
  }

  override func mouseDown(with event: NSEvent) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    super.mouseDown(with: event)
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
