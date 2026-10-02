import AppKit
import GreenBubblesHistory
import SwiftUI

/// NSImageView preserves GIF animation; a SwiftUI Image would flatten it to a still.
struct AnimatedStickerImage: NSViewRepresentable {
  let image: NSImage
  func makeNSView(context: Context) -> NSImageView {
    let view = NSImageView()
    view.imageScaling = .scaleProportionallyUpOrDown
    view.clipsToBounds = true
    view.animates = true
    view.setAccessibilityLabel("表情预览")
    return view
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize?
  {
    CGSize(width: proposal.width ?? 160, height: proposal.height ?? 160)
  }
  func updateNSView(_ view: NSImageView, context: Context) {
    if view.image !== image { view.image = image }
    view.animates = true
  }
  static func dismantleNSView(_ view: NSImageView, coordinator: ()) {
    view.animates = false
    view.image = nil
  }
}

struct HistoryStickerView: View {
  let sticker: HistorySticker
  @State private var image: NSImage?
  @State private var failed = false
  @State private var attempt = 0
  private var identity: String {
    sticker.resources.map { $0.url.absoluteString }.joined(separator: "\n")
  }
  var body: some View {
    Group {
      if let image {
        AnimatedStickerImage(image: image).frame(width: 160, height: 160).clipped()
      } else {
        VStack(spacing: 8) {
          Image(systemName: "face.smiling").font(.system(size: 28)).foregroundStyle(.secondary)
          Text(failed || sticker.resources.isEmpty ? "表情暂不可用" : "正在加载表情").font(.caption)
            .foregroundStyle(.secondary)
          if failed && !sticker.resources.isEmpty {
            Button("重试") { attempt += 1 }.buttonStyle(.plain).font(.caption)
          }
        }.frame(width: 144, height: 112).background(
          .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
      }
    }.task(id: identity + "#\(attempt)") {
      image = nil
      failed = false
      guard !sticker.resources.isEmpty else { return }
      guard Bundle.main.object(forInfoDictionaryKey: "GBOfflineAcceptance") as? Bool != true else {
        failed = true
        return
      }
      do {
        let result = try await HistoryStickerLoader.shared.load(sticker)
        try Task.checkCancellation()
        guard let decoded = NSImage(data: result.data), decoded.isValid else {
          throw StickerLoadError.invalidResource
        }
        image = decoded
      } catch is CancellationError {} catch { failed = true }
    }
  }
}
