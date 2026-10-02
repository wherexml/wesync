import AppKit
import CryptoKit
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class HistoryPresentationAssets {
  static let shared = HistoryPresentationAssets()
  var revision = 0
  @ObservationIgnored private var images: [String: NSImage] = [:]
  @ObservationIgnored private var missing: Set<String> = []

  var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: Bundle.main.bundleIdentifier ?? "GreenBubbles", directoryHint: .isDirectory)
      .appending(path: "Presentation", directoryHint: .isDirectory)
  }

  func prepareDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }

  func avatarURL(source: String, person: String) -> URL {
    let digest = SHA256.hash(data: Data((source + "\u{0}" + person).utf8))
      .map { String(format: "%02x", $0) }.joined()
    return root.appending(path: "Avatars").appending(path: digest + ".png")
  }

  func avatar(source: String, person: String) -> NSImage? {
    _ = revision
    let url = avatarURL(source: source, person: person)
    if let cached = images[url.path] { return cached }
    if missing.contains(url.path) { return nil }
    if let image = Self.thumbnail(at: url, maxPixel: 128) {
      if images.count > 500 { images.removeAll() }
      images[url.path] = image
      return image
    }
    if missing.count > 2_000 { missing.removeAll() }
    missing.insert(url.path)
    return nil
  }

  func embeddedAvatar(_ value: String?) -> NSImage? {
    guard let value, value.count <= 180_000 else { return nil }
    let cacheKey = "embedded:" + String(SHA256.hash(data: Data(value.utf8)).description)
    if let image = images[cacheKey] { return image }
    guard let data = Data(base64Encoded: value),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cg = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 128,
        ] as CFDictionary)
    else { return nil }
    let image = NSImage(cgImage: cg, size: .zero)
    if images.count > 500 { images.removeAll() }
    images[cacheKey] = image
    return image
  }

  func chooseAvatar(source: String, person: String) throws {
    let panel = NSOpenPanel()
    panel.title = "选择头像图片"
    panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let input = panel.url else { return }
    try importAvatar(from: input, source: source, person: person)
  }

  func importAvatar(from input: URL, source: String, person: String) throws {
    guard let image = Self.thumbnail(at: input, maxPixel: 256),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else { throw PresentationError.invalidImage }
    let output = avatarURL(source: source, person: person)
    try prepareDirectory(output.deletingLastPathComponent())
    try png.write(to: output, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    images.removeValue(forKey: output.path)
    missing.remove(output.path)
    revision += 1
  }

  /// Only receives an explicitly imported file or an integrity-checked GreenBubbles output.
  static func thumbnail(at url: URL, maxPixel: Int) -> NSImage? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 32 * 1_024 * 1_024,
      attrs[.type] as? FileAttributeType == .typeRegular,
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    else { return nil }
    return NSImage(cgImage: image, size: .zero)
  }
}

enum PresentationError: Error, LocalizedError {
  case unavailable, invalidImage, invalidIntegrity, sourceChanged, codecUnavailable,
    conversionFailed
  var errorDescription: String? {
    switch self {
    case .unavailable: "这个来源没有可用的图片附件。可以稍后重试。"
    case .invalidImage: "图片格式不受支持或文件超过预览限制。"
    case .codecUnavailable: "本机缺少此图片所需的解码工具，暂时无法预览。"
    case .conversionFailed: "微信图片转换失败，可重试或查看其他图片。"
    case .invalidIntegrity: "附件校验未通过，未显示内容。请重试。"
    case .sourceChanged: "来源已切换，请在当前会话重新加载。"
    }
  }
}
