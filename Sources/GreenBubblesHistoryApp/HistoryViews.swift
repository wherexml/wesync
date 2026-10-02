import AppKit
import GreenBubblesHistory
import SwiftUI

struct HistoryRootView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    Group {
      if model.isDirectConnecting {
        HistoryDirectConnectingView {
          model.closeBundle()
        }
      } else if model.isLoading {
        HistoryLoadingView(progress: model.loadProgress) {
          model.closeBundle()
        }
      } else if model.isDirectHistoryOpen {
        HistoryDirectLibraryView(model: model)
      } else if model.session != nil {
        HistoryLibraryView(model: model)
      } else {
        HistoryWelcomeView(
          errorMessage: model.libraryError,
          browseDirect: { model.presentDirectConnection() },
          createSnapshot: { model.presentSnapshotCreation() },
          openBundle: { model.chooseBundle() }
        )
      }
    }
    .tint(HistoryDesign.accent)
    .background(HistoryDesign.canvas)
    .task {
      #if DEBUG
        if [
          "me.greenbubbles.PresentationPreview", "me.greenbubbles.PolishPreview",
          "me.greenbubbles.ChinesePreview", "me.greenbubbles.DarkModePreview",
        ].contains(Bundle.main.bundleIdentifier ?? ""),
          Bundle.main.object(forInfoDictionaryKey: "GBOfflineAcceptance") as? Bool == true
        {
          await runOfflinePresentationAcceptance(model: model)
          return
        }
      #endif
      model.openStartupBundleIfNeeded()
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let directory = urls.first,
        (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      else { return false }
      model.openBundle(directory)
      return true
    }
    .sheet(isPresented: $model.showsDirectConnection) {
      HistoryDirectConnectionSheet(model: model)
        .frame(minWidth: 680, minHeight: 560)
    }
    .sheet(isPresented: $model.showsSnapshotCreation) {
      HistorySnapshotCreationSheet(model: model)
        .frame(minWidth: 820, minHeight: 720)
    }
  }
}

private struct HistoryWelcomeView: View {
  let errorMessage: String?
  let browseDirect: () -> Void
  let createSnapshot: () -> Void
  let openBundle: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(nsImage: HistoryApplicationDelegate.menuIcon)
        .resizable().scaledToFit().frame(width: 112, height: 112)
        .foregroundStyle(.primary).accessibilityLabel("GreenBubbles")
      VStack(spacing: 8) {
        Text("查看你的微信聊天记录")
          .font(.system(size: 28, weight: .semibold, design: .rounded))
        Text(
          "查看本机微信记录、打开加密备份，或浏览已导出的聊天记录。"
        )
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 660)
      }
      Button(action: browseDirect) {
        Label("连接微信记录或备份…", systemImage: "externaldrive.badge.magnifyingglass")
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
      }
      .buttonStyle(HistoryActionStyle(prominent: true))
      .controlSize(.large)

      Button(action: createSnapshot) {
        Label("创建可恢复的加密备份…", systemImage: "externaldrive.badge.plus")
      }
      .buttonStyle(HistoryActionStyle())

      Button(action: openBundle) {
        Label("打开已导出的聊天记录…", systemImage: "folder.badge.plus")
      }
      .buttonStyle(HistoryActionStyle())

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .font(.callout)
          .textSelection(.enabled)
          .padding(14)
          .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
          .frame(maxWidth: 680)
      }

      HStack(spacing: 24) {
        WelcomePromise(icon: "lock.shield", text: "仅在本机读取，不修改原记录")
        WelcomePromise(icon: "list.number", text: "按需加载，浏览更轻快")
        WelcomePromise(icon: "externaldrive.badge.checkmark", text: "直接查看，无需先恢复全部数据")
      }
      Spacer()
      Text("也可以将已导出的聊天记录文件夹直接拖入此窗口。")
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 24)
    }
    .padding(40)
  }
}

private struct WelcomePromise: View {
  let icon: String
  let text: String

  var body: some View {
    Label(text, systemImage: icon)
      .font(.callout)
      .foregroundStyle(.secondary)
  }
}

private struct HistoryLoadingView: View {
  let progress: HistoryLoadProgress?
  let cancel: () -> Void

  var body: some View {
    VStack(spacing: 22) {
      ProgressView(value: progress?.overallFraction ?? 0)
        .progressViewStyle(.linear)
        .frame(width: 480)
      VStack(spacing: 7) {
        Text(progress.map(phaseTitle) ?? "正在准备聊天记录…")
          .font(.title2.weight(.semibold))
        if let progress {
          HStack(spacing: 8) {
            Text(
              "总进度 \(progress.overallFraction.formatted(.percent.precision(.fractionLength(1))))"
            )
            Text("•")
            Text(
              "当前步骤 \(progress.phaseFraction.formatted(.percent.precision(.fractionLength(1))))"
            )
          }
          .font(.system(.title3, design: .rounded, weight: .medium))
          .foregroundStyle(.green)
          Text(progressDetail(progress))
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
          if progress.phase == .finalizingIndex, progress.phaseFraction < 1 {
            ProgressView()
              .controlSize(.small)
          }
          if progress.bundleByteCount > 0 || progress.bundleRecordCount > 0 {
            Label(bundleDetail(progress), systemImage: "shippingbox")
              .font(.footnote.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          if progress.usingCachedIndex {
            Label(
              "正在重新检查文件，检查通过后将复用已有搜索索引",
              systemImage: "bolt.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        }
      }
      Label(
        "显示内容前，会检查文件权限、完整性和记录数量，确保数据可读取。",
        systemImage: "checkmark.shield"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .frame(maxWidth: 560)
      .multilineTextAlignment(.center)
      Button("取消", action: cancel)
        .keyboardShortcut(.cancelAction)
    }
    .padding(40)
  }

  private func phaseTitle(_ progress: HistoryLoadProgress) -> String {
    switch progress.phase {
    case .validatingManifest: "正在检查记录文件清单"
    case .verifyingConversations: "正在检查会话"
    case .verifyingContacts: "正在检查联系人"
    case .indexingMessages: progress.usingCachedIndex ? "正在检查消息" : "正在建立消息搜索索引"
    case .indexingArtifacts: progress.usingCachedIndex ? "正在检查附件" : "正在建立附件索引"
    case .finalizingIndex: "正在完成本机搜索索引"
    case .ready: "聊天记录已就绪"
    }
  }

  private func progressDetail(_ progress: HistoryLoadProgress) -> String {
    if progress.phase == .finalizingIndex {
      return "正在检查数据库和搜索索引是否完整"
    }
    if progress.phase == .validatingManifest {
      return "正在检查文件清单、导出进度、访问范围和文件完整性"
    }
    let bytes = ByteCountFormatter.string(
      fromByteCount: Int64(clamping: progress.completedBytes), countStyle: .file)
    let totalBytes = ByteCountFormatter.string(
      fromByteCount: Int64(clamping: progress.totalBytes), countStyle: .file)
    let role = progress.fileRole.map(historyHumanize) ?? "当前文件"
    return
      "\(historyChineseStatus(role))：\(progress.completedRecords.formatted()) / \(progress.totalRecords.formatted()) 条 · \(bytes) / \(totalBytes)"
  }

  private func bundleDetail(_ progress: HistoryLoadProgress) -> String {
    let bytes = ByteCountFormatter.string(
      fromByteCount: Int64(clamping: progress.bundleByteCount), countStyle: .file)
    return "记录大小：\(bytes)，共 \(progress.bundleRecordCount.formatted()) 条"
  }
}

private struct HistoryLibraryView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 260)
    } content: {
      contentColumn
        .scrollContentBackground(.hidden)
        .background(HistoryChatPalette.sidebar)
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 450)
    } detail: {
      detailColumn
    }
    .sheet(isPresented: $model.showsCoverageDetails) {
      if let context = model.session?.manifest.context {
        CoverageDetailsView(context: context)
          .frame(minWidth: 560, minHeight: 510)
      }
    }
    .sheet(item: $model.pendingMediaRequest) { request in
      LiveMediaAccessView(model: model, request: request)
        .frame(minWidth: 760, minHeight: 620)
    }
  }

  private var sidebar: some View {
    List(selection: $model.selectedSection) {
      Section("记录库") {
        ForEach(HistorySection.allCases) { section in
          Label(section.title, systemImage: section.systemImage)
            .tag(section)
        }
      }
      if let session = model.session {
        Section("记录来源") {
          LabeledContent("聊天", value: session.conversations.count.formatted())
          LabeledContent("消息", value: session.manifest.exportedMessageCount.formatted())
          HStack {
            Circle()
              .fill(session.manifest.context.sourceCoverageComplete ? .green : .orange)
              .frame(width: 7, height: 7)
            Text(
              session.manifest.context.sourceCoverageComplete
                ? "记录完整" : "部分记录可用"
            )
            .font(.caption)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(HistoryChatPalette.sidebar)
    .safeAreaInset(edge: .bottom) {
      Button {
        model.chooseBundle()
      } label: {
        Label("打开其他记录…", systemImage: "folder")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
    }
  }

  @ViewBuilder
  private var contentColumn: some View {
    switch model.selectedSection ?? .overview {
    case .overview:
      OverviewContents(model: model)
    case .chats:
      ConversationListView(model: model)
    case .contacts:
      ContactListView(model: model)
    case .search:
      SearchResultsView(model: model)
    }
  }

  @ViewBuilder
  private var detailColumn: some View {
    switch model.selectedSection ?? .overview {
    case .overview:
      HistoryOverviewView(model: model)
    case .chats:
      if let conversation = model.selectedConversation {
        ConversationTimelineView(model: model, conversation: conversation)
      } else {
        DetailPlaceholder(
          icon: "bubble.left.and.bubble.right",
          title: "选择一个聊天",
          detail: "从左侧选择聊天，查看消息记录。"
        )
      }
    case .contacts:
      if let contact = model.selectedContact {
        ContactDetailView(model: model, contact: contact)
      } else {
        DetailPlaceholder(
          icon: "person.crop.circle",
          title: "选择一个联系人",
          detail: "选择联系人，查看备注、身份和共同会话。"
        )
      }
    case .search:
      DetailPlaceholder(
        icon: "text.magnifyingglass",
        title: "搜索可访问的消息",
        detail: "点击搜索结果，即可查看消息及前后对话。"
      )
    }
  }
}

private struct OverviewContents: View {
  let model: HistoryBrowserModel

  var body: some View {
    List {
      if let manifest = model.session?.manifest {
        Section("记录文件夹") {
          Label("已检查并建立索引", systemImage: "checkmark.seal.fill")
            .foregroundStyle(.green)
          LabeledContent(
            "创建时间",
            value: manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
          LabeledContent(
            "使用范围", value: manifest.destination == "local" ? "本机" : "远程模型")
          LabeledContent("导出进度标记", value: shortHistoryID(manifest.context.checkpointRevision))
        }
        Section("数据") {
          LabeledContent("会话", value: manifest.enabledConversationCount.formatted())
          LabeledContent("联系人", value: manifest.exportedContactCount.formatted())
          LabeledContent("消息", value: manifest.exportedMessageCount.formatted())
          LabeledContent("附件记录", value: manifest.exportedArtifactCount.formatted())
        }
      }
    }
    .navigationTitle("概览")
  }
}

private struct ConversationListView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    VStack(spacing: 0) {
      HistoryFilterField(text: $model.conversationFilter, prompt: "搜索会话")
      List(selection: $model.selectedConversationID) {
        ForEach(model.filteredConversations) { conversation in
          ConversationRow(
            conversation: conversation,
            statistics: model.session?.conversationStatistics[conversation.conversationID]
          )
          .tag(conversation.conversationID)
        }
      }
      .overlay {
        if model.filteredConversations.isEmpty {
          ContentUnavailableView.search(text: model.conversationFilter)
        }
      }
    }
    .navigationTitle("聊天")
    .onChange(of: model.selectedConversationID) { _, value in
      if let value { model.selectConversation(value) }
    }
  }
}

private struct ConversationRow: View {
  let conversation: HistoryConversation
  let statistics: HistoryConversationStatistics?

  var body: some View {
    HStack(spacing: 11) {
      ZStack {
        Circle()
          .fill(iconColor.opacity(0.16))
          .frame(width: 38, height: 38)
        Image(systemName: icon)
          .foregroundStyle(iconColor)
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(conversation.humanLabel)
            .font(.body.weight(.medium))
            .lineLimit(1)
          Spacer()
          if let date = statistics?.latestMessageDate {
            HistoryConversationTimestamp(date: date)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        HStack(spacing: 6) {
          Text("\(statistics?.messageCount ?? 0) 条消息")
          Text("•")
          Text("\(conversation.participantCount) 人")
          if historyIsStale(conversation.sourceDatabaseFreshness) {
            Image(systemName: "clock.badge.exclamationmark")
              .foregroundStyle(.orange)
              .help("包含此前保留的记录，其原数据库目前不可用")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var icon: String {
    switch conversation.kind {
    case "group": "person.3.fill"
    case "business": "building.2.fill"
    case "chatbot": "cpu.fill"
    case "system": "gearshape.fill"
    default: "person.fill"
    }
  }

  private var iconColor: Color {
    conversation.kind == "group" ? .blue : .green
  }
}

private struct ContactListView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    VStack(spacing: 0) {
      HistoryFilterField(text: $model.contactFilter, prompt: "搜索联系人")
      List(selection: $model.selectedContactID) {
        ForEach(model.filteredContacts) { contact in
          HStack(spacing: 10) {
            HistoryAvatarView(name: contact.displayName)
            VStack(alignment: .leading, spacing: 3) {
              Text(contact.displayName)
                .lineLimit(1)
              Text("\(contact.enabledConversationIDs.count) 个共同会话")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if historyIsStale(contact.sourceDatabaseFreshness) {
              Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            }
          }
          .tag(contact.participantID)
        }
      }
      .overlay {
        if model.filteredContacts.isEmpty {
          ContentUnavailableView.search(text: model.contactFilter)
        }
      }
    }
    .navigationTitle("联系人")
    .onChange(of: model.selectedContactID) { _, value in
      if let value { model.selectContact(value) }
    }
  }
}

private struct SearchResultsView: View {
  @Bindable var model: HistoryBrowserModel

  var body: some View {
    VStack(spacing: 0) {
      HistoryFilterField(text: $model.searchQuery, prompt: "搜索消息内容")
      if model.isSearching {
        ProgressView()
          .controlSize(.small)
          .padding(.top, 8)
      } else if model.searchResults.count == 150 {
        Text("当前显示最相关的前 150 条结果。可输入更具体的关键词缩小范围。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.bottom, 4)
      }
      if let error = model.searchError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(8)
      }
      List(model.searchResults) { message in
        Button {
          model.openSearchResult(message)
        } label: {
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(message.conversationLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Spacer()
              if let date = message.createdAt {
                Text(date, format: .dateTime.year().month().day())
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
            Text(message.displayText)
              .foregroundStyle(.primary)
              .lineLimit(3)
            if let sender = message.senderDisplayName {
              Text(sender)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
      }
      .overlay {
        if model.searchQuery.isEmpty {
          ContentUnavailableView(
            "搜索聊天记录",
            systemImage: "text.magnifyingglass",
            description: Text("可以搜索消息内容、发送者姓名或会话名称。"))
        } else if !model.isSearching && model.searchResults.isEmpty && model.searchError == nil {
          ContentUnavailableView.search(text: model.searchQuery)
        }
      }
    }
    .navigationTitle("搜索")
    .task(id: model.searchQuery) {
      await model.performSearch()
    }
  }
}
