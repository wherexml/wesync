import AppKit
import GreenBubblesHistory
import SwiftUI

struct HistoryMergedRecordView: View {
  let record: HistoryMergedRecord
  var loadImage: (@MainActor (Int) async throws -> NSImage)? = nil
  var loadPDF: (@MainActor (Int) async throws -> HistoryPDFPreview)? = nil
  var loadFile: (@MainActor (Int) async throws -> URL)? = nil
  @State private var opened = false

  var body: some View {
    Button {
      opened = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        Text(record.title).font(.headline).lineLimit(2)
        ForEach(Array(record.entries.prefix(3).enumerated()), id: \.offset) { _, entry in
          Text("\(entry.sender)：\(entry.text)").font(.callout).foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if record.entries.isEmpty {
          Text("记录内容暂不可用").font(.callout).foregroundStyle(.secondary)
        }
        Divider()
        HStack {
          Label("聊天记录", systemImage: "text.bubble")
          Spacer()
          Image(systemName: "chevron.right")
        }.font(.caption).foregroundStyle(.secondary)
      }.frame(width: 260, alignment: .leading).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("打开聊天记录：\(record.title)")
    .sheet(isPresented: $opened) {
      VStack(spacing: 0) {
        HStack {
          Text(record.title).font(.headline)
          Spacer()
          Button("完成") { opened = false }.keyboardShortcut(.cancelAction)
        }.padding(20)
        Divider()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(record.entries.enumerated()), id: \.offset) { index, entry in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(entry.sender).fontWeight(.semibold)
                  Spacer()
                  Text(entry.time).font(.caption).foregroundStyle(.secondary)
                }
                if entry.isImage, let loadImage {
                  HistoryMergedImageView(load: { try await loadImage(index) })
                } else if let filename = entry.filename, filename.lowercased().hasSuffix(".pdf"),
                  let loadPDF
                {
                  HistoryPDFCard(filename: filename, load: { try await loadPDF(index) })
                } else if let filename = entry.filename, let loadFile {
                  HistoryMergedFileCard(filename: filename, load: { try await loadFile(index) })
                } else {
                  Text(HistoryEmojiText.render(entry.text)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }.padding(12).background(
                .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if record.incomplete {
              Text("部分记录未能读取，来源内容可能缺失或超出预览范围。")
                .font(.callout).foregroundStyle(.secondary)
            }
          }.padding(20)
        }
      }.frame(width: 620, height: 560)
    }
  }
}

private struct HistoryMergedImageView: View {
  let load: @MainActor () async throws -> NSImage
  @State private var image: NSImage?
  @State private var failed = false
  @State private var attempt = 0
  @State private var expanded = false
  var body: some View {
    Group {
      if let image {
        Button {
          expanded = true
        } label: {
          Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 360, maxHeight: 240)
        }.buttonStyle(.plain).accessibilityLabel("打开转发图片预览")
          .sheet(isPresented: $expanded) {
            VStack {
              HStack {
                Text("转发图片").font(.headline)
                Spacer()
                Button("完成") { expanded = false }
              }
              Image(nsImage: image).resizable().scaledToFit()
            }.padding(20).frame(width: 800, height: 600)
          }
      } else if failed {
        VStack(alignment: .leading, spacing: 8) {
          Text("本机图片暂不可用").foregroundStyle(.secondary)
          Button("重试加载图片") {
            failed = false
            attempt += 1
          }
        }
      } else {
        ProgressView("正在加载转发图片…")
      }
    }
    .task(id: attempt) {
      guard image == nil else { return }
      do { image = try await load() } catch is CancellationError {} catch { failed = true }
    }
  }
}

private struct HistoryMergedFileCard: View {
  let filename: String
  let load: @MainActor () async throws -> URL
  @State private var loading = false
  @State private var error: String?
  @State private var task: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(filename, systemImage: "doc").textSelection(.enabled)
      if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
      if loading {
        ProgressView().controlSize(.small)
      } else {
        Button("存储文件…") {
          loading = true
          error = nil
          task = Task { @MainActor in
            defer { loading = false }
            do {
              let url = try await load()
              defer { try? FileManager.default.removeItem(at: url) }
              try Task.checkCancellation()
              let panel = NSSavePanel()
              panel.nameFieldStringValue = (filename as NSString).lastPathComponent
              guard panel.runModal() == .OK, let destination = panel.url else { return }
              try Data(contentsOf: url).write(to: destination, options: .atomic)
            } catch is CancellationError {} catch { self.error = historyUserError(error) }
          }
        }
      }
    }
    .onDisappear { task?.cancel() }
  }
}
