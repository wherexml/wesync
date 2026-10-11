import AppKit
import SwiftUI

/// Shared with the Rust CLI. Contains IDs only, never message bodies or credentials.
enum HistoryAIReadPolicy {
  struct Document: Codable {
    var version = 1
    var conversationIds: [String]
  }

  static var url: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/GreenBubbles/ai-read-policy.json")
  }

  static func load() throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 4 * 1024 * 1024
    else { throw CocoaError(.fileReadNoPermission) }
    let value = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    guard value.version == 1, !value.conversationIds.contains("") else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return Set(value.conversationIds)
  }

  static func save(_ ids: Set<String>) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    // A private temporary file and atomic rename never expose a partial/empty policy.
    let temporary = parent.appending(path: ".ai-read-policy-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let data = try JSONEncoder().encode(Document(conversationIds: ids.sorted()))
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }
    guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
  }
}

struct HistoryAIReadBlacklistSection: View {
  @Bindable var model: HistoryBrowserModel
  @State private var selected: Set<String> = []
  @State private var error: String?
  @State private var showsPicker = false

  var body: some View {
    Section("AI 读取黑名单") {
      HStack {
        Label("禁止 AI 读取的会话", systemImage: "hand.raised.fill")
        Spacer()
        Text("已选 \(selected.count) 个").foregroundStyle(.secondary)
        Button("选择个人和群聊…") { showsPicker = true }
          .accessibilityIdentifier("ai-read-blacklist-picker")
          .disabled(error != nil)
      }
      Text("支持多选。保存后禁止 AI 读取所选会话，你仍可在应用中查看。")
        .font(.caption).foregroundStyle(.secondary)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .onAppear(perform: reload)
    .sheet(isPresented: $showsPicker, onDismiss: reload) {
      HistoryAIReadBlacklistPicker(model: model, selected: selected)
    }
  }

  private func reload() {
    do {
      selected = try HistoryAIReadPolicy.load()
      error = nil
    } catch { self.error = "黑名单无法读取，AI 读取已暂停。请检查本机策略文件权限或内容。" }
  }
}

private struct HistoryAIReadBlacklistPicker: View {
  @Bindable var model: HistoryBrowserModel
  @State var selected: Set<String>
  @State private var category = "personal"
  @State private var search = ""
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  private struct Candidate: Identifiable {
    let id: String
    let name: String
    let avatar: String?
    let available: Bool
  }

  private var candidates: [Candidate] {
    var items = Dictionary(
      model.directConversations.map {
        (
          $0.id,
          Candidate(id: $0.id, name: $0.displayName, avatar: $0.avatarBase64, available: true)
        )
      }, uniquingKeysWith: { first, _ in first })
    for id in selected where items[id] == nil {
      items[id] = Candidate(
        id: id,
        name: id.hasSuffix("@chatroom") ? "暂未载入的群聊" : "暂未载入的个人会话",
        avatar: nil, available: false)
    }
    return items.values.filter {
      (category == "selected"
        ? selected.contains($0.id) : ($0.id.hasSuffix("@chatroom") == (category == "groups")))
        && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
          || $0.id.localizedCaseInsensitiveContains(search))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("AI 读取黑名单").font(.title2.weight(.semibold))
      Text("勾选不允许 AI 读取的个人或群聊，可跨分类多选。")
        .foregroundStyle(.secondary)
      Picker("会话类型", selection: $category) {
        Text("个人").tag("personal")
        Text("群聊").tag("groups")
        Text("已选 \(selected.count)").tag("selected")
      }.pickerStyle(.segmented)
      HistorySearchField(prompt: "搜索个人或群聊", text: $search)
      List {
        ForEach(candidates, id: \.id) { item in
          Toggle(
            isOn: Binding(
              get: { selected.contains(item.id) },
              set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }
            )
          ) {
            HStack(spacing: 10) {
              HistoryPersonAvatar(
                source: model.directStatus?.source.identity ?? "",
                person: item.id, name: item.name, size: 36, embeddedAvatar: item.avatar)
              VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text(
                  item.available ? (item.id.hasSuffix("@chatroom") ? "群聊" : "个人") : "请连接原聊天记录确认名称"
                )
                .font(.caption).foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }.padding(.vertical, 3)
          }
        }
      }
      .overlay {
        if candidates.isEmpty { Text("没有匹配的会话").foregroundStyle(.secondary) }
      }
      if model.directConfiguration == nil {
        Text("连接聊天记录后可选择会话；已保存的黑名单仍然生效。")
          .font(.caption).foregroundStyle(.secondary)
      } else if model.directConversationCursor != nil {
        HStack {
          Text("会话目录尚未加载完整").font(.caption).foregroundStyle(.secondary)
          Button("加载更多会话") { model.loadMoreDirectConversations() }
            .disabled(model.isLoadingDirectConversations)
        }
      }
      Text("启用后，跨会话搜索、排名及旧版批量导出会暂停；可继续读取未勾选的指定会话。")
        .font(.caption).foregroundStyle(.secondary)
      if let error { Text(error).foregroundStyle(.red) }
      HStack {
        Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Text("已选 \(selected.count) 个").foregroundStyle(.secondary)
        Button("保存") {
          do {
            try HistoryAIReadPolicy.save(selected)
            dismiss()
          } catch { self.error = "保存失败，原黑名单仍然保留。请检查本机文件权限后重试。" }
        }
        .buttonStyle(HistoryActionStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 560, height: 570)
  }
}
