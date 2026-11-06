import AppKit
import SwiftUI

/// Observe actual user movement, not LazyVStack construction or initial layout.
struct HistoryScrollPrefetch: NSViewRepresentable {
  var load: () -> Void
  var bottomDistance: ((CGFloat) -> Void)?

  init(bottomDistance: ((CGFloat) -> Void)? = nil, load: @escaping () -> Void) {
    self.bottomDistance = bottomDistance
    self.load = load
  }

  func makeNSView(context: Context) -> Probe {
    let view = Probe()
    view.load = load
    view.bottomDistance = bottomDistance
    return view
  }

  func updateNSView(_ view: Probe, context: Context) {
    view.load = load
    view.bottomDistance = bottomDistance
  }

  final class Probe: NSView {
    var load: (() -> Void)?
    var bottomDistance: ((CGFloat) -> Void)?
    private var previousY: CGFloat?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      NotificationCenter.default.removeObserver(self)
      previousY = nil
      guard window != nil else { return }
      DispatchQueue.main.async { [weak self] in self?.observeScroll() }
    }

    private func observeScroll() {
      guard let scrollView = enclosingScrollView else { return }
      HistoryQuietScroller.apply(to: scrollView)
      let clip = scrollView.contentView
      previousY = clip.bounds.minY
      clip.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(scrolled(_:)),
        name: NSView.boundsDidChangeNotification, object: clip)
      if let document = clip.documentView {
        document.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
          self, selector: #selector(layoutChanged(_:)),
          name: NSView.frameDidChangeNotification, object: document)
      }
      clip.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(layoutChanged(_:)),
        name: NSView.frameDidChangeNotification, object: clip)
      reportBottomDistance()
    }

    @objc private func scrolled(_ notification: Notification) {
      guard let clip = notification.object as? NSClipView else { return }
      let y = clip.bounds.minY
      defer { previousY = y }
      if let previous = previousY, y < previous - 0.5, y < 600 { load?() }
      reportBottomDistance()
    }

    @objc private func layoutChanged(_ notification: Notification) { reportBottomDistance() }

    private func reportBottomDistance() {
      guard bottomDistance != nil, let clip = enclosingScrollView?.contentView,
        let document = clip.documentView
      else { return }
      let visible = document.convert(clip.bounds, from: clip)
      let distance = max(
        0,
        document.isFlipped
          ? document.bounds.maxY - visible.maxY : visible.minY - document.bounds.minY)
      // AppKit may notify during layout; publish after SwiftUI's update finishes.
      DispatchQueue.main.async { [weak self] in
        guard let self, window != nil else { return }
        bottomDistance?(distance)
      }
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}
