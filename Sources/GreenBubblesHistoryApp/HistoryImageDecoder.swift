import AppKit
import Foundation

/// Converts only an integrity-verified local GreenBubbles output. No source DB or networking.
@MainActor
enum HistoryImageDecoder {
  static func preview(at input: URL) async throws -> NSImage {
    if let image = HistoryPresentationAssets.thumbnail(at: input, maxPixel: 1440) { return image }
    let bytes = try Data(contentsOf: input)
    guard bytes.count <= 32 * 1024 * 1024, bytes.count > 15,
      bytes.prefix(4) == Data("wxgf".utf8)
    else { throw PresentationError.invalidImage }
    let hevc = try extractHEVC(bytes)
    let parent = input.deletingLastPathComponent()
    let bitstream = parent.appending(path: UUID().uuidString + ".hevc")
    let output = parent.appending(path: UUID().uuidString + ".jpg")
    defer {
      try? FileManager.default.removeItem(at: bitstream)
      try? FileManager.default.removeItem(at: output)
    }
    try hevc.write(to: bitstream, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bitstream.path)
    guard
      let executable = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else {
      throw PresentationError.codecUnavailable
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = [
      "-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe",
      "-threads", "2", "-f", "hevc", "-i", bitstream.path, "-frames:v", "1", "-an",
      "-vf", "scale=1440:1440:force_original_aspect_ratio=decrease", "-c:v", "mjpeg", "-q:v", "2",
      "-fs", "8388608", output.path,
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    let deadline = Date().addingTimeInterval(20)
    do {
      while process.isRunning {
        try Task.checkCancellation()
        guard Date() < deadline else { throw PresentationError.conversionFailed }
        try await Task.sleep(for: .milliseconds(50))
      }
    } catch {
      if process.isRunning { process.terminate() }
      throw error
    }
    guard process.terminationStatus == 0,
      let image = HistoryPresentationAssets.thumbnail(at: output, maxPixel: 1440)
    else {
      throw PresentationError.conversionFailed
    }
    return image
  }

  private static func extractHEVC(_ data: Data) throws -> Data {
    let start = Int(data[4])
    guard start >= 5 && start < data.count else { throw PresentationError.conversionFailed }
    for marker: [UInt8] in [[0, 0, 0, 1], [0, 0, 1]] {
      var best: Range<Int>?
      var index = max(start, 4)
      while index + marker.count < data.count {
        if data[index..<(index + marker.count)].elementsEqual(marker) {
          let size = data[(index - 4)..<index].reduce(0) { ($0 << 8) | Int($1) }
          if size > marker.count && size <= data.count - index {
            if size > (best?.count ?? 0) { best = index..<(index + size) }
            index += size
            continue
          }
        }
        index += 1
      }
      if let best { return data.subdata(in: best) }
    }
    throw PresentationError.conversionFailed
  }
}
