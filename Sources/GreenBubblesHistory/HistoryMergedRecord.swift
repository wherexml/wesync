import Foundation

/// Local presentation only: embedded attachments never trigger remote downloads.
public struct HistoryMergedRecord: Sendable {
  public struct Entry: Sendable {
    public let isImage: Bool
    public let filename: String?
    public let sender: String
    public let time: String
    public let text: String
  }
  public let title: String
  public let entries: [Entry]
  public let incomplete: Bool
}

extension HistoryDirectJSONValue {
  public var mergedRecord: HistoryMergedRecord? {
    guard let fields = fields["MergedMessages"]?.fields else { return nil }
    let title = fields["title"]?.string ?? "聊天记录"
    guard let raw = fields["raw_xml"]?.string,
      let root = RecordXMLNode.parse(raw)
    else { return HistoryMergedRecord(title: title, entries: [], incomplete: true) }
    var entries: [HistoryMergedRecord.Entry] = []
    var incomplete = false
    func walk(_ node: RecordXMLNode, embeddedDepth: Int) {
      guard entries.count < 500 else {
        incomplete = true
        return
      }
      if node.name == "dataitem" {
        let kind = node.attributes["datatype"] ?? ""
        let fallback = [
          "2": "[图片]", "3": "[语音]", "4": "[视频]", "5": "[链接]",
          "6": "[位置]", "7": "[音乐]", "8": "[文件]", "17": "[聊天记录]",
        ]
        let text =
          node.value("datadesc") ?? node.value("datatitle") ?? fallback[kind] ?? "[暂不支持的消息]"
        entries.append(
          .init(
            isImage: kind == "2", filename: kind == "8" ? (node.value("datatitle") ?? "附件") : nil,
            sender: node.value("sourcename") ?? "未知发送者",
            time: node.value("sourcetime") ?? "", text: text))
        return
      }
      if ["recorditem", "recordxml"].contains(node.name),
        !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        if embeddedDepth < 4, let embedded = RecordXMLNode.parse(node.text) {
          walk(embedded, embeddedDepth: embeddedDepth + 1)
        } else {
          incomplete = true
        }
      }
      for child in node.children { walk(child, embeddedDepth: embeddedDepth) }
    }
    walk(root, embeddedDepth: 0)
    return HistoryMergedRecord(
      title: title, entries: entries, incomplete: incomplete || entries.isEmpty)
  }
}

private final class RecordXMLNode: NSObject, XMLParserDelegate {
  var name = ""
  var attributes: [String: String] = [:]
  var text = ""
  var children: [RecordXMLNode] = []
  private var stack: [RecordXMLNode] = []
  private var count = 0

  func value(_ name: String) -> String? {
    guard
      let text = children.first(where: { $0.name == name })?.text
        .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
    else { return nil }
    return text
  }
  static func parse(_ raw: String) -> RecordXMLNode? {
    guard raw.utf8.count <= 2 * 1_024 * 1_024,
      !raw.uppercased().contains("<!DOCTYPE"), !raw.uppercased().contains("<!ENTITY"),
      let start = raw.firstIndex(of: "<")
    else { return nil }
    let reader = RecordXMLNode()
    let parser = XMLParser(data: Data(raw[start...].utf8))
    parser.shouldResolveExternalEntities = false
    parser.delegate = reader
    return parser.parse() ? reader.children.first : nil
  }
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    count += 1
    guard stack.count < 48, count <= 30_000 else {
      parser.abortParsing()
      return
    }
    let node = RecordXMLNode()
    node.name = name
    node.attributes = attributes
    (stack.last ?? self).children.append(node)
    stack.append(node)
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
  func parser(_ parser: XMLParser, foundCDATA data: Data) {
    stack.last?.text += String(decoding: data, as: UTF8.self)
  }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    _ = stack.popLast()
  }
}
