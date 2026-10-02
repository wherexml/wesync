import Foundation

/// Presentation of an already decoded message. Does not access files, databases or the network.
public struct HistoryQuote: Sendable {
  public let reply: String?
  public let sender: String?
  public let text: String?
  public var isEmpty: Bool { reply == nil && sender == nil && text == nil }
}

extension HistoryDirectJSONValue {
  public var fields: [String: HistoryDirectJSONValue] {
    if case .object(let values) = self { return values }
    return [:]
  }
  public var string: String? {
    guard case .string(let value) = self else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
  public var quote: HistoryQuote? {
    guard let value = fields["Quote"] else { return nil }
    let fields = value.fields
    var reply = fields["reply_text"]?.string
    var sender = fields["refer_sender"]?.string
    var text = fields["refer_content"]?.string
    if let xml = fields["raw_xml"]?.string, xml.utf8.count <= 256 * 1_024,
      !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY")
    {
      let reader = QuoteXMLReader()
      let parser = XMLParser(data: Data(xml.utf8))
      parser.shouldResolveExternalEntities = false
      parser.delegate = reader
      if parser.parse() {
        reply = reply ?? reader.values["title"]
        sender = sender ?? reader.values["displayname"] ?? reader.values["fromusr"]
        text = text ?? reader.values["content"]
      }
    }
    return HistoryQuote(reply: reply, sender: sender, text: text)
  }
}

private final class QuoteXMLReader: NSObject, XMLParserDelegate {
  var values: [String: String] = [:]
  private var path: [String] = []
  private var buffers: [String] = []
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    path.append(name)
    buffers.append("")
    if path.count > 32 { parser.abortParsing() }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if !buffers.isEmpty { buffers[buffers.count - 1] += string }
  }
  func parser(_ parser: XMLParser, foundCDATA data: Data) {
    self.parser(parser, foundCharacters: String(decoding: data, as: UTF8.self))
  }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    let text = (buffers.popLast() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let parent = path.dropLast().last
    if !text.isEmpty,
      (name == "title" && parent == "appmsg")
        || (["displayname", "fromusr", "content"].contains(name) && parent == "refermsg")
    {
      values[name] = text
    }
    _ = path.popLast()
  }
}

public struct HistoryStickerResource: Sendable {
  public enum Kind: String, Sendable { case original, encrypted, thumbnail }
  public let url: URL
  public let kind: Kind
  public let md5: String?
  public let aesKey: Data?
}

public struct HistorySticker: Sendable {
  public let resources: [HistoryStickerResource]
  public var previewURLs: [URL] { resources.filter { $0.aesKey == nil }.map(\.url) }
  public init(previewURLs: [URL]) {
    resources = previewURLs.map {
      HistoryStickerResource(url: $0, kind: .original, md5: nil, aesKey: nil)
    }
  }
  init(resources: [HistoryStickerResource]) { self.resources = resources }
}

extension HistoryDirectMessage {
  public var isSticker: Bool {
    messageType == 47 || messageTypeLabel == "emoji" || content.fields["Emoji"] != nil
  }
  public var sticker: HistorySticker? {
    guard isSticker else { return nil }
    let raw =
      content.fields["Emoji"]?.string ?? content.fields["Text"]?.string ?? content.string ?? ""
    guard raw.utf8.count <= 256 * 1_024, !raw.uppercased().contains("<!DOCTYPE"),
      !raw.uppercased().contains("<!ENTITY")
    else { return HistorySticker(previewURLs: []) }
    let reader = StickerXMLReader()
    let parser = XMLParser(data: Data(raw.utf8))
    parser.shouldResolveExternalEntities = false
    parser.delegate = reader
    guard parser.parse() else { return HistorySticker(previewURLs: []) }
    let md5 =
      Self.stickerHex(reader.attributes["md5"], bytes: 16) == nil
      ? nil : reader.attributes["md5"]?.lowercased()
    var resources: [HistoryStickerResource] = []
    for (attribute, kind) in [
      ("cdnurl", HistoryStickerResource.Kind.original), ("encrypturl", .encrypted),
      ("thumburl", .thumbnail),
    ] {
      guard let value = reader.attributes[attribute], let url = Self.stickerURL(value) else {
        continue
      }
      let key = kind == .encrypted ? Self.stickerHex(reader.attributes["aeskey"], bytes: 16) : nil
      if kind == .encrypted && key == nil { continue }
      resources.append(
        HistoryStickerResource(
          url: url, kind: kind, md5: kind == .thumbnail ? nil : md5, aesKey: key))
    }
    return HistorySticker(resources: resources)
  }
  private static func stickerHex(_ text: String?, bytes: Int) -> Data? {
    guard let text, text.utf8.count == bytes * 2,
      text.utf8.allSatisfy({
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      })
    else { return nil }
    var data = Data()
    var index = text.startIndex
    while index < text.endIndex {
      let end = text.index(index, offsetBy: 2)
      guard let byte = UInt8(text[index..<end], radix: 16) else { return nil }
      data.append(byte)
      index = end
    }
    return data
  }
  public static func stickerURL(_ value: String) -> URL? {
    guard var parts = URLComponents(string: value), allowedStickerHost(parts.host),
      parts.user == nil, parts.password == nil, parts.port == nil,
      ["http", "https"].contains(parts.scheme?.lowercased() ?? "")
    else { return nil }
    parts.scheme = "https"
    return parts.url
  }

  public static func allowedStickerHost(_ host: String?) -> Bool {
    ["wxapp.tc.qq.com", "emoji.qpic.cn", "mmbiz.qpic.cn", "vweixinf.tc.qq.com"].contains(
      host?.lowercased() ?? "")
  }
}

private final class StickerXMLReader: NSObject, XMLParserDelegate {
  var attributes: [String: String] = [:]
  private var depth = 0
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    depth += 1
    if depth > 32 { parser.abortParsing() }
    if name == "emoji" && self.attributes.isEmpty { self.attributes = attributes }
  }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) { depth -= 1 }
}

// A filename alone in ordinary text is not an attachment.
extension HistoryDirectMessage {
  public var pdfFilename: String? {
    guard messageType == 49, messageSubtype == 6 else { return nil }
    let title = content.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard title.lowercased().hasSuffix(".pdf"), !title.contains("\n"), title.utf8.count <= 1024
    else { return nil }
    return title
  }
}
