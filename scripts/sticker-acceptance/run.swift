import AppKit
import Foundation
import GreenBubblesHistory
import ImageIO

@main struct StickerAcceptance {
  static func main() async {
    do { try await run() }
    catch {
      let report: [String: Any] = ["passed": false, "error": "resource-unavailable-or-invalid"]
      if CommandLine.arguments.count > 3, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
        try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
      }
      exit(1)
    }
  }
  static func run() async throws {
    let args = CommandLine.arguments
    let message = try JSONDecoder().decode(HistoryDirectMessage.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    guard let sticker = message.sticker else { throw StickerLoadError.invalidResource }
    let loader = HistoryStickerLoader(cacheDirectory: URL(fileURLWithPath: args[2]), networkEnabled: !args.contains("--cache-only"))
    let result = try await loader.load(sticker)
    let source = CGImageSourceCreateWithData(result.data as CFData, nil)!
    let checks: [String: Any] = ["passed": true, "xmlRedacted": message.displayText == "[表情]", "resource": result.kind.rawValue,
      "frames": CGImageSourceGetCount(source), "bytes": result.data.count, "cacheHit": result.fromCache,
      "cacheOnly": args.contains("--cache-only"), "imageDecoded": NSImage(data: result.data) != nil]
    try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
    if let index = args.firstIndex(of: "--image"), args.count > index + 1 {
      try result.data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
    }
  }
}
