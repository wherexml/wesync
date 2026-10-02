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
  var localSource: URL? = nil
  var resolveMetadata: (@MainActor () async throws -> HistorySticker)? = nil
  @State private var image: NSImage?
  @State private var failed = false
  @State private var attempt = 0
  private var identity: String {
    (localSource?.path ?? "") + (sticker.md5 ?? "")
      + sticker.resources.map {
        $0.url.absoluteString + ($0.md5 ?? "") + ($0.aesKey?.base64EncodedString() ?? "")
      }.joined(separator: "\n")
  }
  private var canLoad: Bool {
    !sticker.resources.isEmpty
      || (sticker.md5 != nil && (localSource != nil || resolveMetadata != nil))
  }
  var body: some View {
    Group {
      if let image {
        AnimatedStickerImage(image: image).frame(width: 160, height: 160).clipped()
      } else {
        VStack(spacing: 8) {
          Image(systemName: "face.smiling").font(.system(size: 28)).foregroundStyle(.secondary)
          Text(failed || !canLoad ? "表情暂不可用" : "正在加载表情").font(.caption)
            .foregroundStyle(.secondary)
          if failed && canLoad {
            Button("重试") { attempt += 1 }.buttonStyle(.plain).font(.caption)
          }
        }.frame(width: 144, height: 112).background(
          .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
      }
    }.task(id: identity + "#\(attempt)") {
      image = nil
      failed = false
      guard canLoad else { return }
      guard Bundle.main.object(forInfoDictionaryKey: "GBOfflineAcceptance") as? Bool != true else {
        failed = true
        return
      }
      do {
        let result: LoadedSticker
        do {
          result = try await HistoryStickerLoader.shared.load(sticker, localSource: localSource)
        } catch is CancellationError { throw CancellationError() } catch {
          guard let resolveMetadata else { throw error }
          let recovered = try await resolveMetadata()
          result = try await HistoryStickerLoader.shared.load(recovered, localSource: localSource)
        }
        try Task.checkCancellation()
        guard let decoded = NSImage(data: result.data), decoded.isValid else {
          throw StickerLoadError.invalidResource
        }
        image = decoded
      } catch is CancellationError {} catch { failed = true }
    }
  }
}
