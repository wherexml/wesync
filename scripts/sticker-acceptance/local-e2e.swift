import AppKit
import CryptoKit
import Foundation
import GreenBubblesHistory

@main struct LocalStickerE2E {
  static func main() async throws {
    let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = base.appending(path: "account/db_storage")
    let store = base.appending(path: "account/business/emoticon/nested")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9xkAAAAASUVORK5CYII=")!
    let digest = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
    var checks = [String: Bool]()
    func record(_ name: String, _ condition: Bool) throws {
      checks[name] = condition
      if !condition { throw NSError(domain: name, code: 1) }
    }
    let file = store.appending(path: digest + ".pic")
    try png.write(to: file)
    try record("local-original", try HistoryLocalStickerStore.load(md5: digest, sourceRoot: source) == png)
    try record("wrong-source", (try? HistoryLocalStickerStore.load(md5: digest, sourceRoot: base)) == nil)
    try record("traversal-rejected", (try? HistoryLocalStickerStore.load(md5: "../payload", sourceRoot: source)) == nil)
    try Data("not the image".utf8).write(to: file)
    try record("digest-mismatch", (try? HistoryLocalStickerStore.load(md5: digest, sourceRoot: source)) == nil)
    try FileManager.default.removeItem(at: file)
    let outside = base.appending(path: "outside.png"); try png.write(to: outside)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    try record("file-symlink-rejected", (try? HistoryLocalStickerStore.load(md5: digest, sourceRoot: source)) == nil)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: store.appending(path: "escape"), withDestinationURL: base)
    try record("directory-symlink-rejected", (try? HistoryLocalStickerStore.load(md5: digest, sourceRoot: source)) == nil)
    try record("text-tears", HistoryEmojiText.render("[流泪]原来如此") == "😢原来如此")
    try record("text-repeated-alias", HistoryEmojiText.render("[流泪][Tears]😂") == "😢😢😂")
    try record("unknown-preserved", HistoryEmojiText.render("[未知]普通文字 https://a.test/[流泪]") == "[未知]普通文字 https://a.test/[流泪]")
    try record("legacy-cdn-valid-tls-host", HistoryDirectMessage.stickerURL("http://vweixinf.tc.qq.com/synthetic")?.host == "wxapp.tc.qq.com")
    try record("cdn-untrusted-host-rejected", HistoryDirectMessage.stickerURL("https://wxapp.tc.qq.com.attacker.test/synthetic") == nil)
    let report: [String: Any] = ["passed": true, "checks": checks, "privateDataRecorded": false]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys])
      .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
  }
}
