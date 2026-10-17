import CommonCrypto
import CryptoKit
import Foundation
import GreenBubblesHistory
import ImageIO

private final class StickerRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let url = request.url, url.scheme == "https",
      HistoryDirectMessage.stickerURL(url.absoluteString) == url
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}

enum StickerLoadError: Error { case unavailable, invalidResource }

struct LoadedSticker: Sendable {
  let data: Data
  let kind: HistoryStickerResource.Kind
  let fromCache: Bool
}

actor HistoryStickerLoader {
  static let shared = HistoryStickerLoader()
  private let cacheDirectory: URL
  private let networkEnabled: Bool
  private let session: URLSession
  private let maxBytes = 8 * 1_024 * 1_024

  init(cacheDirectory: URL? = nil, networkEnabled: Bool = true) {
    self.cacheDirectory =
      cacheDirectory
      ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "me.greenbubbles/stickers-v1", directoryHint: .isDirectory)
    self.networkEnabled = networkEnabled
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 8
    config.timeoutIntervalForResource = 12
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.urlCache = nil
    session = URLSession(
      configuration: config, delegate: StickerRedirectPolicy(), delegateQueue: nil)
  }

  func load(_ sticker: HistorySticker, localSource: URL? = nil) async throws -> LoadedSticker {
    if let source = localSource, let md5 = sticker.md5 {
      do {
        let data = try HistoryLocalStickerStore.load(md5: md5, sourceRoot: source)
        try validate(data, expectedMD5: md5)
        return LoadedSticker(data: data, kind: .original, fromCache: true)
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
      }
    }
    for resource in sticker.resources {
      try Task.checkCancellation()
      guard resource.url.scheme == "https",
        HistoryDirectMessage.stickerURL(resource.url.absoluteString) == resource.url
      else { continue }
      let file = cacheFile(resource)
      if let data = cached(file, resource: resource) {
        return LoadedSticker(data: data, kind: resource.kind, fromCache: true)
      }
      guard networkEnabled else { continue }
      do {
        var data = try await download(resource.url)
        if let key = resource.aesKey { data = try decrypt(data, key: key) }
        try validate(data, expectedMD5: resource.md5)
        try Task.checkCancellation()
        // Cache failure must not prevent displaying a successfully decoded resource.
        try? persist(data, at: file)
        return LoadedSticker(data: data, kind: resource.kind, fromCache: false)
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
      }
    }
    throw StickerLoadError.unavailable
  }

  private func download(_ url: URL) async throws -> Data {
    let (stream, response) = try await session.bytes(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      response.expectedContentLength <= maxBytes
    else { throw StickerLoadError.invalidResource }
    var data = Data()
    for try await byte in stream {
      data.append(byte)
      if data.count % 65536 == 0 { try Task.checkCancellation() }
      if data.count > maxBytes { throw StickerLoadError.invalidResource }
    }
    return data
  }

  private func decrypt(_ data: Data, key: Data) throws -> Data {
    guard key.count == kCCKeySizeAES128, !data.isEmpty, data.count % kCCBlockSizeAES128 == 0 else {
      throw StickerLoadError.invalidResource
    }
    var output = Data(count: data.count + kCCBlockSizeAES128)
    let capacity = output.count
    var written = 0
    let status = output.withUnsafeMutableBytes { out in
      data.withUnsafeBytes { input in
        key.withUnsafeBytes { secret in
          CCCrypt(
            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
            secret.baseAddress, key.count, secret.baseAddress, input.baseAddress, data.count,
            out.baseAddress, capacity, &written)
        }
      }
    }
    guard status == kCCSuccess else { throw StickerLoadError.invalidResource }
    output.count = written
    return output
  }

  private func validate(_ data: Data, expectedMD5: String?) throws {
    guard !data.isEmpty, data.count <= maxBytes else { throw StickerLoadError.invalidResource }
    if let expected = expectedMD5 {
      let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard digest == expected else { throw StickerLoadError.invalidResource }
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetStatus(source) == .statusComplete,
      (1...200).contains(CGImageSourceGetCount(source))
    else { throw StickerLoadError.invalidResource }
    var pixels = 0
    for index in 0..<CGImageSourceGetCount(source) {
      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        (1...4096).contains(width), (1...4096).contains(height)
      else { throw StickerLoadError.invalidResource }
      pixels += width * height
      guard pixels <= 64 * 1_024 * 1_024 else { throw StickerLoadError.invalidResource }
    }
    guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
      throw StickerLoadError.invalidResource
    }
  }

  private func cacheFile(_ resource: HistoryStickerResource) -> URL {
    // The filename contains no resource URL, sender identity or decryption key.
    let material =
      Data(resource.url.absoluteString.utf8) + Data((resource.md5 ?? "").utf8)
      + (resource.aesKey ?? Data())
    let name = SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    return cacheDirectory.appending(path: name)
  }

  private func cached(_ file: URL, resource: HistoryStickerResource) -> Data? {
    do {
      let values = try file.resourceValues(forKeys: [
        .fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey,
      ])
      let age = Date().timeIntervalSince(values.contentModificationDate ?? .distantPast)
      guard values.isRegularFile == true, values.isSymbolicLink != true,
        (values.fileSize ?? Int.max) <= maxBytes,
        age < (resource.kind == .thumbnail ? 300 : 30 * 86400)
      else { return nil }
      let data = try Data(contentsOf: file)
      try validate(data, expectedMD5: resource.md5)
      return data
    } catch {
      try? FileManager.default.removeItem(at: file)
      return nil
    }
  }

  private func persist(_ data: Data, at file: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(
      at: cacheDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try data.write(to: file, options: [.atomic])
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let entries = try fm.contentsOfDirectory(
      at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
    )
    .filter { $0.lastPathComponent.count == 64 }
    .compactMap { url -> (URL, Int, Date)? in
      guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      else { return nil }
      return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var total = entries.reduce(0) { $0 + $1.1 }
    for (url, size, date) in entries where url != file {
      if total > 32 * 1_024 * 1_024 || Date().timeIntervalSince(date) > 30 * 86400 {
        try? fm.removeItem(at: url)
        total -= size
      }
    }
  }
}
