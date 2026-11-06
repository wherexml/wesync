import AppKit
import SwiftUI

/// Draw only the thumb; AppKit retains its normal hit area, tracking and fades.
final class HistoryQuietScroller: NSScroller {
  override class var isCompatibleWithOverlayScrollers: Bool { true }

  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

  override func drawKnob() {
    var knob = rect(for: .knob)
    guard !knob.isEmpty else { return }
    if bounds.height >= bounds.width {
      knob.origin.x = bounds.maxX - 5
      knob.size.width = 3
    } else {
      knob.origin.y = bounds.maxY - 5
      knob.size.height = 3
    }
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.26 : 0.20).setFill()
    NSBezierPath(roundedRect: knob, xRadius: 1.5, yRadius: 1.5).fill()
  }

  static func apply(to scrollView: NSScrollView) {
    if let original = scrollView.verticalScroller, !(original is HistoryQuietScroller) {
      let scroller = HistoryQuietScroller(frame: original.frame)
      scroller.target = original.target
      scroller.action = original.action
      scroller.doubleValue = original.doubleValue
      scroller.knobProportion = original.knobProportion
      scroller.controlSize = .small
      scrollView.verticalScroller = scroller
    }
    if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
    if scrollView.borderType != .noBorder { scrollView.borderType = .noBorder }
  }
}

/// A List's background may be beside its NSScrollView rather than inside it.
struct HistoryScrollAppearance: NSViewRepresentable {
  func makeNSView(context: Context) -> Probe { Probe() }
  func updateNSView(_ view: Probe, context: Context) { view.scheduleAppearance() }

  final class Probe: NSView {
    private var scheduled = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      scheduleAppearance()
    }

    override func layout() {
      super.layout()
      scheduleAppearance()
    }

    func scheduleAppearance() {
      guard !scheduled else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        scheduled = false
        guard window != nil else { return }
        if let scrollView = enclosingScrollView {
          HistoryQuietScroller.apply(to: scrollView)
          return
        }
        var ancestor = superview
        while let container = ancestor {
          if let scrollView = firstScrollView(in: container) {
            HistoryQuietScroller.apply(to: scrollView)
            return
          }
          ancestor = container.superview
        }
      }
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
      if let scrollView = view as? NSScrollView { return scrollView }
      for child in view.subviews {
        if let scrollView = firstScrollView(in: child) { return scrollView }
      }
      return nil
    }
  }
}
