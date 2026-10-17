import AppKit
import GreenBubblesHistory
import SwiftUI

struct HistoryPersonAvatar: View {
  let source: String
  let person: String
  let name: String
  var size: CGFloat = 34
  var embeddedAvatar: String? = nil
  @State private var assets = HistoryPresentationAssets.shared
  @State private var error: String?

  var body: some View {
    Group {
      if let image = assets.embeddedAvatar(embeddedAvatar)
        ?? assets.avatar(source: source, person: person)
      {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        HistoryAvatarView(name: name, size: size)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    .accessibilityLabel("\(name)的头像")
    .help("右键选择本机头像图片")
    .contextMenu {
      Button("选择头像图片…") {
        do { try assets.chooseAvatar(source: source, person: person) } catch {
          self.error = historyUserError(error)
        }
      }
    }
    .alert("头像未更新", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
      Button("好") { error = nil }
    } message: {
      Text(error ?? "")
    }
  }
}

struct HistoryRichMessageBody: View {
  let message: HistoryDirectMessage
  var localStickerSource: URL? = nil
  var resolveStickerMetadata: (@MainActor () async throws -> HistorySticker)? = nil
  var cachedImage: NSImage? = nil
  let loadImage: @MainActor () async throws -> NSImage
  var loadMergedImage: (@MainActor (Int) async throws -> NSImage)? = nil
  var loadPDF: (@MainActor () async throws -> HistoryPDFPreview)? = nil
  @State private var image: NSImage?
  @State private var error: String?
  @State private var loading = false
  @State private var expanded = false
  @State private var imageTask: Task<Void, Never>?

  var body: some View {
    Group {
      if let record = message.content.mergedRecord {
        HistoryMergedRecordView(record: record, loadImage: loadMergedImage)
      } else if let sticker = message.sticker {
        HistoryStickerView(
          sticker: sticker, localSource: localStickerSource, resolveMetadata: resolveStickerMetadata
        )
      } else if let quote = message.content.quote {
        VStack(alignment: .leading, spacing: 10) {
          if let reply = quote.reply {
            Text(HistoryEmojiText.render(reply)).textSelection(.enabled)
          }
          HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(.green.opacity(0.65)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
              Label(quote.sender ?? "引用消息", systemImage: "quote.opening")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              Text(HistoryEmojiText.render(quote.text ?? "引用原文未能解析"))
                .foregroundStyle(quote.text == nil ? .secondary : .primary)
                .textSelection(.enabled)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          .padding(10)
          .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
          if quote.isEmpty {
            Text("已识别为引用回复，但来源未提供可用正文。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      } else if let filename = message.pdfFilename, let loadPDF {
        HistoryPDFCard(filename: filename, load: loadPDF)
          .id(message.conversationID + message.id)
      } else if message.messageTypeLabel == "image" {
        imageBody
      } else if message.messageTypeLabel == "system" {
        Label(message.displayText, systemImage: "info.circle")
          .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
      } else {
        Text(HistoryEmojiText.render(message.displayText)).textSelection(.enabled)
      }
    }
    .task(id: message.id) {
      guard message.messageTypeLabel == "image", cachedImage == nil, image == nil, error == nil,
        Bundle.main.object(forInfoDictionaryKey: "GBOfflineAcceptance") as? Bool != true
      else { return }
      loading = true
      defer { loading = false }
      do { image = try await loadImage() } catch is CancellationError {} catch {
        self.error = historyUserError(error)
      }
    }
    .onDisappear {
      imageTask?.cancel()
      loading = false
    }
  }

  @ViewBuilder private var imageBody: some View {
    if let image = image ?? cachedImage {
      // A flexible frame centers portrait pixels inside unused horizontal space.
      // Give the button the fitted image bounds so the row owns its alignment.
      let size = image.size
      let scale = min(300 / max(size.width, 1), 240 / max(size.height, 1))
      Button {
        expanded = true
      } label: {
        Image(nsImage: image).resizable().scaledToFit()
          .frame(width: max(size.width, 1) * scale, height: max(size.height, 1) * scale)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("打开图片预览")
      .sheet(isPresented: $expanded) {
        VStack {
          HStack {
            Text("图片预览").font(.headline)
            Spacer()
            Button("完成") { expanded = false }
          }
          Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 960, maxHeight: 720)
        }.padding(20).frame(minWidth: 480, minHeight: 360)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(.secondary)
        Text(loading ? "正在加载图片" : "图片预览").font(.caption).foregroundStyle(.secondary)
        if let error { Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        Button {
          loading = true
          error = nil
          imageTask?.cancel()
          imageTask = Task { @MainActor in
            defer { loading = false }
            do {
              let value = try await loadImage()
              try Task.checkCancellation()
              image = value
            } catch is CancellationError {} catch {
              self.error = historyUserError(error)
            }
          }
        } label: {
          if loading {
            ProgressView().controlSize(.small)
          } else {
            Label(error == nil ? "加载图片" : "重试", systemImage: "arrow.down.circle")
          }
        }.disabled(loading)
      }
      .padding(14).frame(width: 190, alignment: .leading)
      .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
  }
}
