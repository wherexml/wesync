import AppKit
import GreenBubblesHistory
import SwiftUI

struct HistoryDirectConnectionSheet: View {
  @Bindable var model: HistoryBrowserModel
  @Environment(\.dismiss) private var dismiss
  @State private var secret = ""
  @State private var validationError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text("连接微信记录或备份")
          .font(.title2.weight(.semibold))
        Text(
          "只读取你正在查看的记录，不修改原数据，也无需先恢复全部聊天记录。"
        )
        .foregroundStyle(.secondary)
      }

      Form {
        Section("本机读取工具") {
          pathField(
            title: "读取工具",
            text: $model.liveExecutablePath,
            actionTitle: "选择…",
            action: chooseExecutable
          )
        }

        Section("聊天记录来源") {
          Picker("打开方式", selection: $model.directAccessMode) {
            ForEach(HistoryDirectAccessMode.allCases, id: \.rawValue) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          pathField(
            title: "记录文件夹",
            text: $model.directSourcePath,
            actionTitle: "选择…",
            action: chooseSource
          )
        }

        Section("访问凭据") {
          if model.directAccessMode == .decrypted {
            Label(
              "此方式无需密钥，仅适用于已经解密的数据库文件。",
              systemImage: "exclamationmark.shield"
            )
            .foregroundStyle(.orange)
          } else if model.directAccessMode == .snapshotKeychain {
            Label(
              "使用本机钥匙串中已保存的凭据打开这份备份。",
              systemImage: "key.fill"
            )
            Text(
              "钥匙串保存的是这份备份的快捷解锁凭据。打开期间会使用仅本人可读的临时文件，关闭后清理。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Label(
              "即使电脑丢失或钥匙串条目被删除，也可以用另外保存的 24 个恢复词找回备份。",
              systemImage: "externaldrive.badge.checkmark"
            )
            .font(.caption)
            .foregroundStyle(.green)
          } else if model.directAccessMode == .snapshotLocalCredential {
            pathField(
              title: "本机解锁文件",
              text: $model.directLocalCredentialPath,
              actionTitle: "选择…",
              action: chooseLocalCredential
            )
            Text(
              "选择之前保存的快捷解锁文件。应用只记住文件位置，不将内容写入普通设置。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Label(
              "快捷解锁文件被删除后，仍可使用另行保存的恢复词打开备份。请不要用它代替备份。",
              systemImage: "externaldrive.badge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)
          } else if model.directAccessMode == .snapshotRecoveryKit {
            pathField(
              title: "恢复词文件",
              text: $model.directRecoveryKitPath,
              actionTitle: "选择…",
              action: chooseRecoveryKit
            )
            Text(
              "恢复词文件只在本机读取，用其中的 24 个恢复词解锁备份。恢复词不会写入命令参数或普通设置。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Label(
              "请在其他安全位置另存一份恢复词，不要只保留本机这一份。",
              systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
          } else {
            SecureField(secretTitle, text: $secret)
              .textContentType(.password)
            Text(secretExplanation)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      Toggle("记住此连接，下次启动自动打开", isOn: $model.rememberDirectConnection)
      Text("连接成功后，凭据只保存在本机钥匙串中，不写入普通配置文件。")
        .font(.caption).foregroundStyle(.secondary)
      Button("忘记已保存的连接") { model.forgetRememberedConnection() }
      if let notice = model.connectionPersistenceNotice {
        Text(notice).font(.caption).foregroundStyle(.orange)
      }

      if let validationError {
        Label(validationError, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.red)
      }

      GroupBox {
        Label(
          "加密备份有独立的恢复凭据。以后查看备份时，不需要原来的微信数据库密钥。",
          systemImage: "key.horizontal.fill"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      HStack {
        Button("取消") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("连接并查看", action: connect)
          .buttonStyle(HistoryActionStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .onChange(of: model.directAccessMode) { _, mode in
      if mode == .decrypted || mode == .snapshotRecoveryKit
        || mode == .snapshotLocalCredential || mode == .snapshotKeychain
      {
        secret = ""
      }
      validationError = nil
    }
  }

  private var secretTitle: String {
    switch model.directAccessMode {
    case .liveEncrypted: "微信数据库密钥"
    case .snapshotKeychain: ""
    case .snapshotLocalCredential: ""
    case .snapshotPassphrase: "备份解锁密码"
    case .snapshotRecoveryKit: ""
    case .snapshotEncrypted: "旧版备份恢复密钥"
    case .decrypted: ""
    }
  }

  private var secretExplanation: String {
    switch model.directAccessMode {
    case .liveEncrypted:
      "密钥仅通过本机安全输入通道传给读取工具，不放入命令参数。"
    case .snapshotKeychain:
      ""
    case .snapshotLocalCredential:
      ""
    case .snapshotPassphrase:
      "使用备份创建时设置的密码。勾选下方“记住此连接”后，可保存在本机钥匙串中。"
    case .snapshotRecoveryKit:
      ""
    case .snapshotEncrypted:
      "仅用于旧版备份。请输入备份自己的 32 字节密钥，或 64 位十六进制密钥。"
    case .decrypted:
      ""
    }
  }

  private func pathField(
    title: String,
    text: Binding<String>,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
      Button(actionTitle, action: action)
    }
  }

  private func chooseExecutable() {
    let panel = NSOpenPanel()
    panel.title = "选择本机读取工具"
    panel.prompt = "选择工具"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    if panel.runModal() == .OK, let url = panel.url {
      model.liveExecutablePath = url.path
    }
  }

  private func chooseSource() {
    let panel = NSOpenPanel()
    panel.title = "选择微信记录文件夹或加密备份"
    panel.prompt = "选择记录来源"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    if panel.runModal() == .OK, let url = panel.url {
      model.directSourcePath = url.path
    }
  }

  private func chooseRecoveryKit() {
    let panel = NSOpenPanel()
    panel.title = "选择包含 24 个恢复词的私有文件"
    panel.prompt = "选择恢复词文件"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    if panel.runModal() == .OK, let url = panel.url {
      model.directRecoveryKitPath = url.path
    }
  }

  private func chooseLocalCredential() {
    let panel = NSOpenPanel()
    panel.title = "选择本机备份解锁文件"
    panel.prompt = "选择解锁文件"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    if panel.runModal() == .OK, let url = panel.url {
      model.directLocalCredentialPath = url.path
    }
  }

  private func connect() {
    let executablePath = model.liveExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourcePath = model.directSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !executablePath.isEmpty, !sourcePath.isEmpty else {
      validationError = "请先选择本机读取工具和聊天记录文件夹。"
      return
    }
    let recoveryKitPath = model.directRecoveryKitPath.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let localCredentialPath = model.directLocalCredentialPath.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if model.directAccessMode == .snapshotLocalCredential, localCredentialPath.isEmpty {
      validationError = "请选择这份备份对应的本机解锁文件。"
      return
    }
    if model.directAccessMode == .snapshotRecoveryKit, recoveryKitPath.isEmpty {
      validationError = "请选择这份备份对应的恢复词文件。"
      return
    }
    if model.directAccessMode == .snapshotPassphrase {
      let passphraseBytes = Array(secret.utf8)
      guard (12...1_024).contains(passphraseBytes.count),
        !passphraseBytes.contains(0), !passphraseBytes.contains(10),
        !passphraseBytes.contains(13)
      else {
        validationError =
          "请输入备份密码，长度需为 12–1,024 字节，且不能包含换行。"
        return
      }
    }
    if model.directAccessMode == .liveEncrypted || model.directAccessMode == .snapshotEncrypted,
      secret.isEmpty
    {
      validationError = "请输入这份加密记录对应的密钥。"
      return
    }
    var key =
      model.directAccessMode == .liveEncrypted || model.directAccessMode == .snapshotEncrypted
        || model.directAccessMode == .snapshotPassphrase
      ? Array(secret.utf8) : []
    let recoveryKitURL =
      model.directAccessMode == .snapshotRecoveryKit
      ? URL(fileURLWithPath: recoveryKitPath) : nil
    let localCredentialURL =
      model.directAccessMode == .snapshotLocalCredential
      ? URL(fileURLWithPath: localCredentialPath) : nil
    secret = ""
    defer { key.resetBytes(in: 0..<key.count) }
    model.connectDirectSource(
      executableURL: URL(fileURLWithPath: executablePath),
      sourceURL: URL(fileURLWithPath: sourcePath, isDirectory: true),
      accessMode: model.directAccessMode,
      keyUTF8: key,
      recoveryKitURL: recoveryKitURL,
      localCredentialURL: localCredentialURL
    )
    dismiss()
  }
}

struct HistoryDirectConnectingView: View {
  let cancel: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      ProgressView()
        .controlSize(.large)
      Text("正在打开聊天记录…")
        .font(.title2.weight(.semibold))
      Text(
        "正在验证访问权限、检查记录文件并加载会话列表。"
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 560)
      Label(
        "直接读取本机记录，无需恢复整个数据库", systemImage: "bolt.shield"
      )
      .font(.callout)
      .foregroundStyle(.green)
      Button("取消", action: cancel)
        .keyboardShortcut(.cancelAction)
    }
    .padding(40)
  }
}

struct HistoryDirectLibraryView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    HSplitView {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("聊天").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("GreenBubbles").font(.system(size: 11, weight: .medium)).foregroundStyle(
              .secondary)
          }
          Spacer()
          Menu {
            Button("连接设置…") { model.presentDirectConnection() }
            Button("搜索全部消息") {
              model.directSearchConversationID = nil
              model.directSection = .search
            }
            Button("返回聊天") { model.directSection = .chats }
            Button("查看来源信息") { model.directSection = .overview }
            Button("忘记已保存的连接") { model.forgetRememberedConnection() }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.borderlessButton).frame(width: 24)
        }.padding(16)
        if let notice = model.connectionPersistenceNotice {
          Text(notice).font(.caption).foregroundStyle(.orange).padding(.horizontal)
        }
        HistoryDirectConversationList(model: model)
      }
      .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
      .background(HistoryChatPalette.sidebar)
      Group {
        if model.directSection == .overview {
          HistoryDirectOverviewContents(model: model)
        } else if model.directSection == .search {
          HistoryDirectSearchView(model: model)
        } else {
          detail
        }
      }.frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
        .background(HistoryDesign.canvas)
    }
  }

  private var sidebar: some View {
    List(selection: $model.directSection) {
      Section("当前记录来源") {
        ForEach(HistoryDirectSection.allCases) { section in
          Label(section.title, systemImage: section.systemImage)
            .tag(section)
        }
      }
      if let status = model.directStatus {
        Section("存储占用") {
          LabeledContent("数据库", value: status.databaseCount.formatted())
          LabeledContent("数据库文件", value: directByteCount(status.databaseBytes))
          LabeledContent("WAL", value: directByteCount(status.writeAheadLogBytes))
          LabeledContent("合计", value: directByteCount(status.totalSqliteStorageBytes))
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      VStack(alignment: .leading, spacing: 8) {
        if let notice = model.connectionPersistenceNotice {
          Text(notice).font(.caption).foregroundStyle(.orange)
        }
        Button("忘记已保存的连接") { model.forgetRememberedConnection() }
        Button {
          model.presentDirectConnection()
        } label: {
          Label("打开其他记录…", systemImage: "externaldrive")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
      }.padding(8)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.directSection ?? .overview {
    case .overview:
      HistoryDirectOverviewContents(model: model)
    case .chats:
      HistoryDirectConversationList(model: model)
    case .search:
      HistoryDirectSearchView(model: model)
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch model.directSection ?? .overview {
    case .overview:
      HistoryDirectOverviewDetail(model: model)
    case .chats:
      if let conversationID = model.directSelectedConversationID {
        HistoryDirectTimelineView(model: model, conversationID: conversationID)
      } else {
        HistoryDirectPlaceholder(
          icon: "bubble.left.and.bubble.right",
          title: "选择一个聊天",
          detail: "从左侧选择聊天，按需查看消息。"
        )
      }
    case .search:
      HistoryDirectPlaceholder(
        icon: "text.magnifyingglass",
        title: "搜索本机记录",
        detail: "点击搜索结果，查看对应消息。"
      )
    }
  }
}

private struct HistoryDirectOverviewContents: View {
  let model: HistoryBrowserModel

  var body: some View {
    List {
      if let configuration = model.directConfiguration, let status = model.directStatus {
        Section("打开方式") {
          Label(
            configuration.accessMode.displayName, systemImage: accessIcon(configuration.accessMode))
          LabeledContent("来源标识", value: String(status.source.identity.prefix(16)))
          LabeledContent(
            "检查时间",
            value: Date(
              timeIntervalSince1970: Double(status.observedAtUnixMilliseconds) / 1_000
            ).formatted(date: .abbreviated, time: .shortened)
          )
        }
        Section("加载状态") {
          LabeledContent("已加载会话", value: model.directConversations.count.formatted())
          LabeledContent(
            "更多会话",
            value: model.directConversationCursor == nil ? "否" : "可加载"
          )
          Label("仅以只读方式查询数据库", systemImage: "lock.open.display")
            .foregroundStyle(.green)
        }
      }
      HistoryDirectWarnings(warnings: model.directConversationWarnings)
    }
    .navigationTitle("概览")
  }

  private func accessIcon(_ mode: HistoryDirectAccessMode) -> String {
    switch mode {
    case .liveEncrypted: "waveform.path.ecg"
    case .snapshotKeychain: "key.fill"
    case .snapshotLocalCredential: "lock.laptopcomputer"
    case .snapshotPassphrase: "ellipsis.rectangle"
    case .snapshotRecoveryKit: "key.viewfinder"
    case .snapshotEncrypted: "externaldrive.badge.checkmark"
    case .decrypted: "exclamationmark.lock.open"
    }
  }
}

private struct HistoryDirectOverviewDetail: View {
  let model: HistoryBrowserModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text("直接读取本机记录")
            .font(.largeTitle.weight(.semibold))
          Text(
            "原数据库保持不变。应用按需读取少量记录，关闭来源后释放已加载的数据。"
          )
          .font(.title3)
          .foregroundStyle(.secondary)
        }

        if let consistency = model.directConversationConsistency {
          GroupBox("本次读取状态") {
            VStack(alignment: .leading, spacing: 8) {
              LabeledContent("一致性保障", value: directHumanize(consistency.guarantee))
              LabeledContent("已读取数据库", value: consistency.databaseCount.formatted())
              LabeledContent(
                "跨数据库同步读取",
                value: consistency.crossDatabaseAtomic ? "是" : "否"
              )
              if !consistency.crossDatabaseAtomic {
                Label(
                  "微信记录分散在多个独立数据库中，因此本页各部分可能不是完全同一时刻的数据。",
                  systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
              }
            }
            .padding(6)
          }
        }

        if let status = model.directStatus {
          GroupBox("数据库存储占用") {
            VStack(alignment: .leading, spacing: 8) {
              LabeledContent("数据库文件", value: directByteCount(status.databaseBytes))
              LabeledContent("待写入日志", value: directByteCount(status.writeAheadLogBytes))
              LabeledContent("共享内存文件", value: directByteCount(status.sharedMemoryBytes))
              LabeledContent(
                "恢复日志",
                value: directByteCount(status.rollbackJournalBytes)
              )
              Divider()
              LabeledContent(
                "磁盘占用合计",
                value: directByteCount(status.totalSqliteStorageBytes)
              )
              Text(
                "这里只统计源数据库及其辅助文件，不包含导出记录、临时副本或解码后的附件。"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(6)
          }

          GroupBox("占用空间最多的数据库") {
            VStack(alignment: .leading, spacing: 9) {
              ForEach(largestEntries(status)) { entry in
                HStack {
                  Text(entry.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                  Spacer()
                  Text(directByteCount(directEntryBytes(entry)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
              }
            }
            .padding(6)
          }
        }

        if let mode = model.directConfiguration?.accessMode,
          mode == .snapshotKeychain || mode == .snapshotLocalCredential
            || mode == .snapshotPassphrase || mode == .snapshotRecoveryKit
            || mode == .snapshotEncrypted
        {
          GroupBox("备份恢复方式") {
            Label(
              independentRecoveryExplanation(mode),
              systemImage: "key.radiowaves.forward.fill"
            )
            .padding(6)
          }
        }
      }
      .padding(28)
      .frame(maxWidth: 940, alignment: .leading)
    }
  }

  private func largestEntries(_ status: HistoryDirectSourceStatus) -> [HistoryDirectDatabaseSize] {
    Array(status.entries.sorted { directEntryBytes($0) > directEntryBytes($1) }.prefix(12))
  }

  private func independentRecoveryExplanation(_ mode: HistoryDirectAccessMode) -> String {
    switch mode {
    case .snapshotKeychain:
      "当前使用本机钥匙串解锁备份。钥匙串条目丢失后，仍可使用另外保存的 24 个恢复词打开。"
    case .snapshotLocalCredential:
      "当前使用本机解锁文件。文件丢失后，仍可使用另外保存的 24 个恢复词打开备份。"
    case .snapshotPassphrase:
      "当前使用备份密码解锁。忘记密码后，仍可使用另外保存的 24 个恢复词打开。"
    case .snapshotRecoveryKit:
      "当前使用 24 个恢复词解锁，无需访问微信。请在此电脑以外的安全位置另存一份恢复词。"
    case .snapshotEncrypted:
      "当前使用旧版备份的恢复密钥读取记录，无需访问微信或使用微信原密钥。"
    case .liveEncrypted, .decrypted:
      ""
    }
  }
}

private struct HistoryDirectConversationList: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    VStack(spacing: 0) {
      Picker("会话类型", selection: $model.directChatCategory) {
        Text("个人").tag("personal")
        Text("群聊").tag("group")
        Text("其他").tag("other")
      }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.bottom, 10)
      DirectFilterField(text: $model.conversationFilter, prompt: "搜索当前分类的会话")
      if let error = model.directConversationError {
        DirectInlineError(message: error)
        Button("重试") { model.loadMoreDirectConversations() }
          .buttonStyle(.plain).padding(.bottom, 6)
      }
      List {
        ForEach(model.filteredDirectConversations) { conversation in
          Button {
            model.directSection = .chats
            model.selectDirectConversation(conversation.id)
          } label: {
            HStack(spacing: 10) {
              HistoryPersonAvatar(
                source: model.directStatus?.source.identity ?? "",
                person: conversation.id, name: conversation.displayName,
                embeddedAvatar: conversation.avatarBase64)
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(conversation.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                  Spacer()
                  if let date = conversation.sortDate {
                    HistoryConversationTimestamp(date: date)
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                }
                Text(conversation.summary ?? "")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .contextMenu {
            if model.directCategory(for: conversation) == "other" {
              Button(
                conversation.id.hasSuffix("@chatroom") ? "移回群聊" : "移回个人",
                systemImage: "arrow.uturn.backward"
              ) {
                model.moveDirectConversation(conversation, toOther: false)
              }
            } else {
              Button("移到其他", systemImage: "tray.and.arrow.down") {
                model.moveDirectConversation(conversation, toOther: true)
              }
            }
            if model.hasDirectCategoryOverride(conversation) {
              Divider()
              Button("恢复自动分类", systemImage: "arrow.counterclockwise") {
                model.restoreDirectCategory(conversation)
              }
            }
          }
          .listRowBackground(
            model.directSelectedConversationID == conversation.id
              ? HistoryDesign.selection : Color.clear
          )
        }

        if model.directConversationCursor != nil {
          HStack {
            Spacer()
            if model.isLoadingDirectConversations {
              ProgressView().controlSize(.small)
              Text("正在补齐会话…").font(.caption).foregroundStyle(.secondary)
            } else {
              Text("向下滚动继续浏览").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
          }
          .onAppear {
            if model.directConversationError == nil { model.loadMoreDirectConversations() }
          }
        }

      }
      .listStyle(.inset)
      .scrollContentBackground(.hidden)
      .background(HistoryChatPalette.sidebar)
      .overlay {
        if model.filteredDirectConversations.isEmpty && !model.isLoadingDirectConversations {
          ContentUnavailableView(
            "暂无会话",
            systemImage: "bubble.left",
            description: Text("可调整搜索条件；其余会话会自动补齐。")
          )
        }
      }
    }
    .navigationTitle("聊天")
  }
}

private struct HistoryDirectTimelineView: View {
  @Bindable var model: HistoryBrowserModel
  let conversationID: String
  @State private var chatSearch = ""
  @State private var readingPosition: String?
  @State private var paginationAnchor: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(model.selectedDirectConversation?.displayName ?? conversationID)
            .font(.title2.weight(.semibold))
          Text(
            model.selectedDirectConversation.map { model.directCategory(for: $0) } == "other"
              ? "其他会话" : conversationID.hasSuffix("@chatroom") ? "群聊" : "个人聊天"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          model.returnToLatestDirectMessages()
        } label: {
          Image(systemName: "arrow.clockwise")
        }.help("刷新最新消息")

      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(HistoryChatPalette.timeline)

      HStack(spacing: 10) {
        HistorySearchField(
          prompt: "在当前聊天中搜索", text: $chatSearch,
          onSubmit: {
            guard !chatSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
              return
            }
            model.directSearchConversationID = conversationID
            model.directSearchQuery = chatSearch
            model.directSection = .search
          }
        ).frame(height: 28)
        Button("搜索") {
          model.directSearchConversationID = conversationID
          model.directSearchQuery = chatSearch
          model.directSection = .search
        }.disabled(chatSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.padding(.horizontal, 18).padding(.vertical, 10).background(HistoryChatPalette.timeline)

      if let error = model.directMessageError {
        DirectInlineError(message: error)
      }
      if !model.directMessageWarnings.isEmpty {
        HistoryDirectWarnings(warnings: model.directMessageWarnings)
          .padding(.horizontal, 16)
          .padding(.top, 10)
      }

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            if model.directIsSearchContext {
              Button("返回最新消息") {
                model.returnToLatestDirectMessages()
              }
              .buttonStyle(HistoryActionStyle())
            } else if model.directMessageCursor != nil {
              HStack {
                if model.isLoadingDirectMessages { ProgressView().controlSize(.small) }
                Text(model.isLoadingDirectMessages ? "正在加载更早消息…" : "向上滚动查看更早消息")
                  .font(.caption).foregroundStyle(.secondary)
              }

            }

            let messages = Array(model.directMessages.reversed())
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
              VStack(spacing: 10) {
                if let date = message.createdAt as Date?,
                  HistoryMessageTime.showsSeparator(
                    for: date, after: index > 0 ? messages[index - 1].createdAt : nil)
                {
                  HistoryMessageTimestamp(date: date)
                }
                HistoryDirectMessageBubble(
                  model: model, message: message,
                  highlighted: message.id == model.directHighlightedMessageID
                )
              }
              .id(message.id)
            }

            if model.isLoadingDirectMessages && model.directMessages.isEmpty {
              VStack(spacing: 22) {
                ForEach(0..<4) { index in
                  HStack(alignment: .top, spacing: 10) {
                    if index % 2 == 1 { Spacer(minLength: 80) }
                    RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.05)).frame(
                      width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.045)).frame(
                      width: index % 2 == 0 ? 230 : 170, height: 54)
                    if index % 2 == 0 { Spacer(minLength: 80) }
                  }
                }
                Label("正在加载消息…", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
              }.padding(.vertical, 14).accessibilityLabel("正在加载消息")
            } else if !model.isLoadingDirectMessages && model.directMessages.isEmpty
              && model.directMessageError == nil
            {
              ContentUnavailableView(
                "暂无消息",
                systemImage: "bubble.left",
                description: Text("本次查询未找到消息。")
              )
              .padding(40)
            }
            Color.clear.frame(height: 1).id("latest")
          }
          .scrollTargetLayout()
          .padding(18)
          .background(
            HistoryScrollPrefetch {
              guard !model.isLoadingDirectMessages, model.directMessageCursor != nil else { return }
              paginationAnchor = readingPosition ?? model.directMessages.last?.id
              model.loadOlderDirectMessages()
            })
        }
        .scrollPosition(id: $readingPosition, anchor: .top)
        .onChange(of: model.directMessages.last?.id) { _, _ in
          if let anchor = paginationAnchor {
            proxy.scrollTo(anchor, anchor: .top)
            paginationAnchor = nil
          }
        }
        .onChange(of: model.directMessages.first?.id) { _, _ in
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            proxy.scrollTo("latest", anchor: .bottom)
          }
        }
        .overlay(alignment: .bottomTrailing) {
          Button {
            withAnimation { proxy.scrollTo("latest", anchor: .bottom) }
          } label: {
            Image(systemName: "arrow.down").padding(8)
          }.buttonStyle(.bordered).clipShape(Circle()).padding(16).help("回到最新消息")
        }
      }
    }
    .background(HistoryChatPalette.timeline)
  }
}

struct HistoryDirectMessageBubble: View {
  @Environment(\.colorScheme) private var colorScheme
  let model: HistoryBrowserModel
  let message: HistoryDirectMessage
  let highlighted: Bool
  private var outgoing: Bool { message.isAccountHolder == true }
  private var system: Bool { message.messageTypeLabel == "system" }
  private var imageOnly: Bool { message.messageTypeLabel == "image" }

  private var avatar: some View {
    HistoryPersonAvatar(
      source: model.directStatus?.source.identity ?? "",
      person: message.sender.isEmpty ? "unknown" : message.sender,
      name: outgoing ? "我" : message.senderLabel, embeddedAvatar: message.avatarBase64)
  }

  var body: some View {
    if system {
      Text(message.displayText).font(.caption).foregroundStyle(.secondary)
        .textSelection(.enabled).frame(maxWidth: .infinity).padding(.vertical, 8)
    } else {
      HStack(alignment: .top, spacing: 9) {
        if outgoing { Spacer(minLength: 80) } else { avatar }
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
          if message.conversationID.hasSuffix("@chatroom") && !outgoing {
            Text(message.senderLabel).font(.system(size: 11)).foregroundStyle(.secondary)
          }
          HistoryRichMessageBody(
            message: message,
            localStickerSource: model.directConfiguration?.accessMode == .liveEncrypted
              ? model.directConfiguration?.sourceURL : nil,
            resolveStickerMetadata: { try await model.resolveDirectSticker(message) },
            cachedImage: model.directImagePreviews[message.id],
            loadImage: {
              try await model.previewDirectImage(message)
            },
            loadPDF: {
              try await model.previewDirectPDF(message)
            }
          )
          .font(.system(size: 14))
          .foregroundStyle(
            outgoing ? HistoryChatPalette.outgoingText : Color.primary,
            outgoing ? HistoryChatPalette.outgoingText.opacity(0.85) : Color.secondary,
            outgoing ? HistoryChatPalette.outgoingText.opacity(0.8) : Color.secondary
          )
          .environment(\.colorScheme, outgoing && !imageOnly ? .light : colorScheme)
          .padding(imageOnly ? 0 : 11)
          .background(
            imageOnly
              ? Color.clear
              : outgoing
                ? HistoryChatPalette.outgoing
                : HistoryChatPalette.incoming,
            in: RoundedRectangle(cornerRadius: HistoryDesign.radius, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: HistoryDesign.radius, style: .continuous).strokeBorder(
              highlighted
                ? HistoryDesign.accent : (imageOnly ? .clear : HistoryDesign.border.opacity(0.6)),
              lineWidth: highlighted ? 2 : 0.5)
          }
          .contextMenu {
            Button("复制消息") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(message.displayText, forType: .string)
            }
          }
          if message.contentTruncated {
            Text("内容过长，仅显示部分").font(.caption2).foregroundStyle(.orange)
          }
        }.frame(maxWidth: 570, alignment: outgoing ? .trailing : .leading)
        if outgoing { avatar } else { Spacer(minLength: 80) }
      }.frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
    }
  }
}

private struct HistoryDirectSearchView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("返回聊天") { model.directSection = .chats }
        Spacer()
        Text(model.directSearchConversationID == nil ? "搜索全部消息" : "搜索当前聊天").font(.headline)
      }.padding(12)
      DirectFilterField(text: $model.directSearchQuery, prompt: "搜索消息内容")
      if model.isSearchingDirect && model.directSearchResults.isEmpty {
        ProgressView()
          .controlSize(.small)
          .padding(.top, 8)
      }
      if let error = model.directSearchError {
        DirectInlineError(message: error)
      }
      if !model.directSearchWarnings.isEmpty {
        HistoryDirectWarnings(warnings: model.directSearchWarnings)
          .padding(.horizontal, 10)
          .padding(.bottom, 5)
      }
      List {
        ForEach(model.directSearchResults) { hit in
          Button {
            model.openDirectSearchResult(hit)
          } label: {
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(hit.conversationID)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                Spacer()
                Text(hit.createdAt, format: .dateTime.year().month().day())
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
              Text(HistoryEmojiText.render(hit.snippet))
                .foregroundStyle(.primary)
                .lineLimit(3)
              Text(
                hit.senderLabel.isEmpty
                  ? directHumanize(hit.messageTypeLabel) : hit.senderLabel
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
        if model.directSearchCursor != nil {
          Button {
            model.loadMoreDirectSearchResults()
          } label: {
            HStack {
              Spacer()
              if model.isSearchingDirect {
                ProgressView().controlSize(.small)
              } else {
                Label("加载更多搜索结果", systemImage: "arrow.down.circle")
              }
              Spacer()
            }
          }
          .disabled(model.isSearchingDirect)
        }
      }
      .overlay {
        if model.directSearchQuery.isEmpty {
          ContentUnavailableView(
            "搜索本机聊天记录",
            systemImage: "text.magnifyingglass",
            description: Text(
              "输入关键词，在本机已授权的聊天记录中查找。"
            )
          )
        } else if !model.isSearchingDirect && model.directSearchResults.isEmpty
          && model.directSearchError == nil && model.directSearchCursor == nil
        {
          ContentUnavailableView.search(text: model.directSearchQuery)
        }
      }
    }
    .navigationTitle("搜索")
    .task(id: model.directSearchQuery) {
      await model.performDirectSearch()
    }
  }
}

private struct HistoryDirectWarnings: View {
  let warnings: [HistoryDirectWarning]

  var body: some View {
    if !warnings.isEmpty {
      Section("提示") {
        ForEach(warnings) { warning in
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(historyChineseWarning(warning))
              if let count = warning.count {
                Text("涉及记录：\(count.formatted()) 条")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
        }
      }
    }
  }
}

private struct DirectFilterField: View {
  @Binding var text: String
  let prompt: String
  var body: some View {
    HistorySearchField(prompt: prompt, text: $text)
      .frame(height: 28)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(HistoryChatPalette.sidebar)
  }
}

private struct DirectInlineError: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.red)
      .textSelection(.enabled)
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.07))
  }
}

private struct HistoryDirectPlaceholder: View {
  let icon: String
  let title: String
  let detail: String

  var body: some View {
    ContentUnavailableView(
      title,
      systemImage: icon,
      description: Text(detail)
    )
  }
}

private func directByteCount(_ bytes: UInt64) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
}

private func directEntryBytes(_ entry: HistoryDirectDatabaseSize) -> UInt64 {
  [
    entry.databaseBytes,
    entry.writeAheadLogBytes,
    entry.sharedMemoryBytes,
    entry.rollbackJournalBytes,
  ].reduce(0) { partial, value in
    let (sum, overflow) = partial.addingReportingOverflow(value)
    return overflow ? UInt64.max : sum
  }
}

private func directHumanize(_ value: String) -> String {
  historyChineseStatus(value)
}
