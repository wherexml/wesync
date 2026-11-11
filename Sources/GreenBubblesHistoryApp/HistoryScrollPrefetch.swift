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
    private var pendingDistance: CGFloat?
    private var distanceScheduled = false
    private var previousDistance: CGFloat?

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
      HistoryInteractionTrace.shared.scrollBoundsChanged()
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
      guard distanceScheduled || (previousDistance.map({ abs($0 - distance) > 0.5 }) ?? true)
      else { return }
      pendingDistance = distance
      guard !distanceScheduled else { return }
      distanceScheduled = true
      // AppKit may notify several times during one layout pass. Publish only its final geometry.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        distanceScheduled = false
        guard window != nil, let latest = pendingDistance else { return }
        pendingDistance = nil
        previousDistance = latest
        bottomDistance?(latest)
      }
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}
