import AppKit
import PDFKit
import SwiftUI

enum PDFPreviewError: LocalizedError {
  case unavailable, tooLarge, invalid, locked, openFailed
  var errorDescription: String? {
    switch self {
    case .unavailable: "本地尚未找到此 PDF。请先确认文件已下载，再点重试。"
    case .tooLarge: "此文件超过 64 MB 预览上限，或无法读取文件大小。"
    case .invalid: "此文件不是可读取的 PDF，可能已损坏。"
    case .locked: "此 PDF 已加密，暂不支持应用内预览。"
    case .openFailed: "系统未能打开此 PDF，请重试。"
    }
  }
}

final class HistoryPDFPreview: Identifiable {
  let id = UUID()
  let url: URL
  let document: PDFDocument
  init(url: URL, document: PDFDocument) {
    self.url = url
    self.document = document
  }
  func cleanup() { try? FileManager.default.removeItem(at: url) }
  deinit { cleanup() }

  @MainActor func openExternally() throws {
    // External readers load lazily: retain a separate copy when the sheet closes.
    let folder = HistoryPresentationAssets.shared.root.appending(path: "OpenedPDFs")
    try HistoryPresentationAssets.shared.prepareDirectory(folder)
    for file
      in (try? FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])) ?? []
    {
      let values = try? file.resourceValues(forKeys: [
        .contentModificationDateKey, .isRegularFileKey,
      ])
      if values?.isRegularFile == true, let date = values?.contentModificationDate,
        date < Date().addingTimeInterval(-86400)
      {
        try? FileManager.default.removeItem(at: file)
      }
    }
    let output = folder.appending(path: UUID().uuidString + ".pdf")
    try FileManager.default.copyItem(at: url, to: output)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    guard NSWorkspace.shared.open(output) else {
      try? FileManager.default.removeItem(at: output)
      throw PDFPreviewError.openFailed
    }
  }
}

struct HistoryPDFCard: View {
  let filename: String
  let load: () async throws -> HistoryPDFPreview
  @State private var preview: HistoryPDFPreview?
  @State private var loading = false
  @State private var error: String?
  @State private var task: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Image(systemName: "doc.richtext").font(.system(size: 28)).foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 4) {
          Text(filename).font(.headline).lineLimit(3).textSelection(.enabled)
          Text("PDF 文档").font(.caption).foregroundStyle(.secondary)
        }
      }
      if let error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
      HStack {
        if loading {
          ProgressView().controlSize(.small)
          Text("正在读取本地文件…").font(.caption)
        } else {
          Button(error == nil ? "预览 PDF" : "重试预览") { startLoading() }
            .accessibilityLabel("预览 PDF：\(filename)")
        }
      }
    }
    .frame(minWidth: 240, maxWidth: 360, alignment: .leading)
    .sheet(item: $preview, onDismiss: { preview = nil }) { value in
      HistoryPDFSheet(preview: value, filename: filename)
    }
    .onDisappear {
      task?.cancel()
      task = nil
      loading = false
      preview = nil
    }
  }

  private func startLoading() {
    task?.cancel()
    loading = true
    error = nil
    task = Task { @MainActor in
      defer { loading = false }
      do {
        let value = try await load()
        try Task.checkCancellation()
        preview = value
      } catch is CancellationError {} catch { self.error = historyUserError(error) }
    }
  }
}

struct HistoryPDFSheet: View {
  let preview: HistoryPDFPreview
  let filename: String
  @Environment(\.dismiss) private var dismiss
  @State private var pdfView = PDFView()
  @State private var page = 1
  @State private var error: String?

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(filename).font(.headline).lineLimit(1).help(filename)
        Spacer()
        Button("用系统应用打开") {
          do {
            try preview.openExternally()
            error = nil
          } catch { self.error = historyUserError(error) }
        }
        Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      HStack {
        Button {
          pdfView.goToPreviousPage(nil)
          updatePage()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(page <= 1).accessibilityLabel("上一页")
        Text("第 \(page) / \(preview.document.pageCount) 页").monospacedDigit()
        Button {
          pdfView.goToNextPage(nil)
          updatePage()
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(page >= preview.document.pageCount).accessibilityLabel("下一页")
        Spacer()
        Button {
          pdfView.zoomOut(nil)
        } label: {
          Image(systemName: "minus.magnifyingglass")
        }.accessibilityLabel("缩小")
        Button("适合窗口") { pdfView.autoScales = true }
        Button {
          pdfView.zoomIn(nil)
        } label: {
          Image(systemName: "plus.magnifyingglass")
        }.accessibilityLabel("放大")
      }
      if let error { Text(error).font(.caption).foregroundStyle(.orange) }
      HistoryPDFView(view: pdfView, document: preview.document)
    }
    .padding(18).frame(minWidth: 600, idealWidth: 860, minHeight: 520, idealHeight: 740)
    .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged, object: pdfView)) {
      _ in updatePage()
    }
  }
  private func updatePage() {
    if let current = pdfView.currentPage { page = preview.document.index(for: current) + 1 }
  }
}

private struct HistoryPDFView: NSViewRepresentable {
  let view: PDFView
  let document: PDFDocument
  func makeNSView(context: Context) -> PDFView {
    view.document = document
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    return view
  }
  func updateNSView(_ nsView: PDFView, context: Context) {}
}
