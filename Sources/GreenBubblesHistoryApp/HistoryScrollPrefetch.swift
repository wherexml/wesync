import AppKit
import SwiftUI

/// Observe actual user movement, not LazyVStack construction or initial layout.
struct HistoryScrollPrefetch: NSViewRepresentable {
  var load: () -> Void

  func makeNSView(context: Context) -> Probe {
    let view = Probe()
    view.load = load
    return view
  }

  func updateNSView(_ view: Probe, context: Context) { view.load = load }

  final class Probe: NSView {
    var load: (() -> Void)?
    private var previousY: CGFloat?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      NotificationCenter.default.removeObserver(self)
      previousY = nil
      guard window != nil else { return }
      DispatchQueue.main.async { [weak self] in self?.observeScroll() }
    }

    private func observeScroll() {
      guard let clip = enclosingScrollView?.contentView else { return }
      previousY = clip.bounds.minY
      clip.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(scrolled(_:)),
        name: NSView.boundsDidChangeNotification, object: clip)
    }

    @objc private func scrolled(_ notification: Notification) {
      guard let clip = notification.object as? NSClipView else { return }
      let y = clip.bounds.minY
      defer { previousY = y }
      if let previous = previousY, y < previous - 0.5, y < 600 { load?() }
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}
