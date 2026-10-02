import AppKit
import GreenBubblesHistory
import SwiftUI

struct HistoryOverviewView: View {
  let model: HistoryBrowserModel

  var body: some View {
    ScrollView {
      if let manifest = model.session?.manifest {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 6) {
            Text("聊天记录概览")
              .font(.largeTitle.weight(.semibold))
            Text("查看已检查、在授权范围内的本机微信记录。")
              .font(.title3)
              .foregroundStyle(.secondary)
          }
          CoverageBanner(context: manifest.context) {
            model.showsCoverageDetails = true
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14
          ) {
            MetricCard(
              title: "会话", value: manifest.enabledConversationCount.formatted(),
              icon: "bubble.left.and.bubble.right.fill", color: .blue)
            MetricCard(
              title: "联系人", value: manifest.exportedContactCount.formatted(),
              icon: "person.2.fill", color: .purple)
            MetricCard(
              title: "消息", value: manifest.exportedMessageCount.formatted(),
              icon: "text.bubble.fill", color: .green)
            MetricCard(
              title: "附件引用", value: manifest.exportedArtifactCount.formatted(),
              icon: "photo.on.rectangle.angled", color: .orange)
          }
          GroupBox("记录完整程度") {
            HStack(spacing: 32) {
              CoverageMetric(label: "合计", value: manifest.context.totalDatabaseCount)
              CoverageMetric(
                label: "最新记录", value: manifest.context.freshDatabaseCount, color: .green)
              CoverageMetric(
                label: "暂不可用", value: manifest.context.unavailableDatabaseCount,
                color: .orange)
              CoverageMetric(
                label: "此前保留的记录", value: manifest.context.preservedStaleDatabaseCount,
                color: .yellow)
              Spacer()
            }
            .padding(8)
          }
          GroupBox("记录文件信息") {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
              EvidenceRow(
                label: "创建时间",
                value: manifest.createdAt.formatted(date: .long, time: .shortened))
              EvidenceRow(
                label: "导出进度标记", value: shortHistoryID(manifest.context.checkpointRevision))
              EvidenceRow(
                label: "来源客户端",
                value: historyHumanize(manifest.context.clientBuildCompatibility ?? "unknown"))
              EvidenceRow(
                label: "访问范围", value: historyHumanize(manifest.context.archiveScope ?? "unknown"))
              EvidenceRow(
                label: "搜索索引",
                value: model.session?.reusedIndex == true
                  ? "已复用检查通过的索引" : "已建立并检查")
            }
            .padding(8)
            .textSelection(.enabled)
          }
        }
        .padding(28)
        .frame(maxWidth: 1_050, alignment: .leading)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

struct ConversationTimelineView: View {
  @Bindable var model: HistoryBrowserModel
  let conversation: HistoryConversation
  @State private var readingPosition: String?
  @State private var paginationAnchor: String?

  var body: some View {
    VStack(spacing: 0) {
      conversationHeader
      Divider()
      if let context = model.session?.manifest.context,
        !context.sourceCoverageComplete || historyIsStale(conversation.sourceDatabaseFreshness)
      {
        CoverageBanner(context: context, compact: true) {
          model.showsCoverageDetails = true
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
      }
      if let timelineError = model.timelineError {
        Label(timelineError, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .padding()
      }
      timeline
    }
    .background(HistoryChatPalette.timeline)
  }

  private var conversationHeader: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text(conversation.humanLabel)
          .font(.title2.weight(.semibold))
        Text(
          "\(conversation.participantCount) 位参与者 · \(model.session?.conversationStatistics[conversation.conversationID]?.messageCount ?? 0) 条消息"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      if historyIsStale(conversation.sourceDatabaseFreshness) {
        FreshnessBadge(value: conversation.sourceDatabaseFreshness)
      }
      Menu {
        ForEach(conversation.participants) { participant in
          Text("\(participant.displayName) — \(historyHumanize(participant.role))")
        }
      } label: {
        Label("参与者", systemImage: "person.2")
      }
      .menuStyle(.borderlessButton)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(HistoryChatPalette.timeline)
  }

  private var timeline: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10) {
          if model.isSearchContext {
            Button("返回最新消息") {
              model.returnToLatestMessages()
            }
            .buttonStyle(HistoryActionStyle())
            .padding(.vertical, 8)
          } else if model.timelineCursor != nil {
            HStack {
              if model.isLoadingTimeline { ProgressView().controlSize(.small) }
              Text(model.isLoadingTimeline ? "正在加载更早消息…" : "向上滚动查看更早消息")
                .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)

          }

          let messages = Array(model.timelineMessages.reversed())
          ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            VStack(spacing: 10) {
              if let date = message.createdAt as Date?,
                HistoryMessageTime.showsSeparator(
                  for: date, after: index > 0 ? messages[index - 1].createdAt : nil)
              {
                HistoryMessageTimestamp(date: date)
              }
              MessageBubble(
                model: model,
                message: message,
                highlighted: message.canonicalID == model.highlightedMessageID
              )
            }
            .id(message.canonicalID)
          }

          if model.isLoadingTimeline && model.timelineMessages.isEmpty {
            ProgressView("正在加载消息…")
              .padding(40)
          }
          if !model.isLoadingTimeline && model.timelineMessages.isEmpty
            && model.timelineError == nil
          {
            ContentUnavailableView(
              "暂无可查看的消息",
              systemImage: "bubble.left",
              description: Text(
                "在这份导出记录允许查看的时间范围内，此会话没有消息。")
            )
            .padding(40)
          }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
          HistoryScrollPrefetch {
            guard !model.isLoadingTimeline, model.timelineCursor != nil else { return }
            paginationAnchor = readingPosition ?? model.timelineMessages.last?.canonicalID
            model.loadOlderMessages()
          })
      }
      .scrollPosition(id: $readingPosition, anchor: .top)
      .onChange(of: model.timelineMessages.last?.canonicalID) { _, _ in
        if let anchor = paginationAnchor {
          proxy.scrollTo(anchor, anchor: .top)
          paginationAnchor = nil
        }
      }
      .onChange(of: model.timelineMessages.count) { previousCount, currentCount in
        guard currentCount > 0 else { return }
        if let highlighted = model.highlightedMessageID {
          proxy.scrollTo(highlighted, anchor: .center)
        } else if previousCount == 0, let newest = model.timelineMessages.first {
          proxy.scrollTo(newest.canonicalID, anchor: .bottom)
        }
      }
    }
  }
}

private struct MessageBubble: View {
  @Environment(\.colorScheme) private var colorScheme
  let model: HistoryBrowserModel
  let message: HistoryMessage
  let highlighted: Bool

  var body: some View {
    HStack {
      if resolvedDirection == "outgoing" { Spacer(minLength: 90) }
      bubbleContent
        .foregroundStyle(
          resolvedDirection == "outgoing" ? HistoryChatPalette.outgoingText : Color.primary
        )
        .environment(\.colorScheme, resolvedDirection == "outgoing" ? .light : colorScheme)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: 650, alignment: .leading)
        .background(
          bubbleColor, in: RoundedRectangle(cornerRadius: HistoryDesign.radius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: HistoryDesign.radius, style: .continuous)
            .strokeBorder(
              highlighted ? HistoryDesign.accent : HistoryDesign.border.opacity(0.6),
              lineWidth: highlighted ? 2 : 0.5)
        }
        .contextMenu {
          Button("复制消息文字") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.displayText, forType: .string)
          }
          Button("复制消息标识") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.canonicalID, forType: .string)
          }
        }
      if resolvedDirection != "outgoing" { Spacer(minLength: 90) }
    }
  }

  private var bubbleContent: some View {
    VStack(alignment: .leading, spacing: 7) {
      senderHeader
      Text(HistoryEmojiText.render(message.displayText))
        .font(.body)
        .textSelection(.enabled)
      if message.payloadSummaryTruncated == true {
        Label("摘要已按访问规则截短", systemImage: "scissors")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      relationshipLinks
      artifactLinks
      messageMetadata
    }
  }

  private var senderHeader: some View {
    HStack(spacing: 7) {
      if let sender = message.senderDisplayName, resolvedDirection != "outgoing" {
        Text(sender)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      if message.sourceDatabaseFreshness == "preservedStale" {
        FreshnessBadge(value: message.sourceDatabaseFreshness)
      }
    }
  }

  private var relationshipLinks: some View {
    ForEach(Array(message.relationships.enumerated()), id: \.offset) { _, relationship in
      RelationshipButton(model: model, message: message, relationship: relationship)
    }
  }

  private var artifactLinks: some View {
    ForEach(Array(message.artifactReferences.enumerated()), id: \.offset) { _, reference in
      ArtifactReferenceView(model: model, reference: reference)
    }
  }

  private var messageMetadata: some View {
    HStack(spacing: 7) {
      if message.createdAt == nil {
        Text("时间未知")
      }
      if let payloadKind = message.payloadKind {
        Text(historyHumanize(payloadKind))
      }
      if resolvedDirection == "unknown" {
        Text("· 收发方向未知")
          .foregroundStyle(.orange)
      }
    }
    .font(.caption2.monospacedDigit())
    .foregroundStyle(.tertiary)
  }

  private var bubbleColor: Color {
    switch resolvedDirection {
    case "outgoing": HistoryChatPalette.outgoing
    case "incoming": HistoryChatPalette.incoming
    default: .orange.opacity(0.10)
    }
  }

  private var resolvedDirection: String? {
    model.resolvedDirection(for: message)
  }
}

private struct RelationshipButton: View {
  let model: HistoryBrowserModel
  let message: HistoryMessage
  let relationship: HistoryRelationshipReference

  var body: some View {
    Button {
      if let target = relationship.targetCanonicalID {
        model.selectConversation(message.conversationID, around: target)
      }
    } label: {
      Label(title, systemImage: icon)
    }
    .buttonStyle(.plain)
    .font(.caption)
    .foregroundStyle(relationship.resolved ? Color.secondary : Color.orange)
    .disabled(!relationship.resolved || relationship.targetCanonicalID == nil)
  }

  private var title: String {
    relationship.resolved
      ? historyHumanize(relationship.kind)
      : "未能识别：\(historyHumanize(relationship.kind))"
  }

  private var icon: String {
    relationship.resolved ? "arrowshape.turn.up.left" : "questionmark.diamond"
  }
}

private struct ArtifactReferenceView: View {
  let model: HistoryBrowserModel
  let reference: HistoryArtifactReference
  @State private var artifact: HistoryArtifact?
  @State private var loaded = false
  @State private var loadError: String?

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: artifactIcon)
        .font(.title2)
        .frame(width: 30)
        .foregroundStyle(artifactColor)
      VStack(alignment: .leading, spacing: 3) {
        Text(artifactTitle)
          .font(.callout.weight(.medium))
        Text(artifactDetail)
          .font(.caption)
          .foregroundStyle(
            artifact?.error == nil && loadError == nil ? Color.secondary : Color.red
          )
          .lineLimit(2)
      }
      Spacer()
      if !loaded {
        ProgressView().controlSize(.small)
      } else if artifact?.detail != nil {
        Image(systemName: "checkmark.shield.fill")
          .foregroundStyle(.green)
          .help("导出时已检查文件完整性")
        if canPreview, let artifact {
          Button("预览") {
            model.requestMediaPreview(artifact)
          }
          .buttonStyle(HistoryActionStyle())
          .controlSize(.small)
        }
      }
    }
    .padding(9)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
    .task(id: reference.artifactID) {
      artifact = nil
      loadError = nil
      loaded = false
      do {
        artifact = try await model.artifact(reference.artifactID)
        loaded = true
      } catch is CancellationError {
        return
      } catch {
        loadError = historyUserError(error)
        loaded = true
      }
    }
  }

  private var artifactIcon: String {
    switch artifact?.detail?.kind {
    case "image", "animatedImage", "thumbnail": "photo.fill"
    case "voice": "waveform"
    case "video": "play.rectangle.fill"
    case "document": "doc.fill"
    case "richMedia": "rectangle.stack.fill"
    default: "paperclip"
    }
  }

  private var artifactColor: Color {
    artifact?.error == nil && loadError == nil ? .blue : .red
  }

  private var artifactTitle: String {
    if let detail = artifact?.detail { return historyHumanize(detail.kind) }
    if artifact?.error != nil || loadError != nil { return "附件暂不可用" }
    return historyHumanize(reference.role)
  }

  private var artifactDetail: String {
    if let loadError { return loadError }
    if let error = artifact?.error { return error.message }
    guard let detail = artifact?.detail else {
      return loaded ? "无法读取附件信息" : "正在读取附件信息…"
    }
    let file = detail.decoded ?? detail.source
    let size = file.map {
      ByteCountFormatter.string(
        fromByteCount: Int64(clamping: $0.byteCount), countStyle: .file)
    }
    return [
      historyHumanize(detail.availability),
      "解析状态：\(historyHumanize(detail.decodeState))",
      file?.format.uppercased(),
      size,
    ]
    .compactMap { $0 }
    .joined(separator: " • ")
  }

  private var canPreview: Bool {
    guard let availability = artifact?.detail?.availability else { return false }
    return availability == "downloaded" || availability == "materializedFromDatabase"
  }
}

struct ContactDetailView: View {
  let model: HistoryBrowserModel
  let contact: HistoryContact

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 16) {
          HistoryAvatarView(name: contact.displayName, size: 64)
          VStack(alignment: .leading, spacing: 5) {
            Text(contact.displayName)
              .font(.largeTitle.weight(.semibold))
            HStack {
              Text(
                contact.localProfileAvailable
                  ? "本机有联系人资料" : "资料来自会话记录")
              FreshnessBadge(value: contact.sourceDatabaseFreshness)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
          }
        }
        GroupBox("共同会话") {
          VStack(spacing: 0) {
            ForEach(contact.conversationProfiles) { profile in
              Button {
                model.selectConversation(profile.conversationID)
              } label: {
                HStack {
                  Image(systemName: "bubble.left.fill")
                    .foregroundStyle(.green)
                  VStack(alignment: .leading) {
                    Text(profile.conversationLabel)
                    Text(
                      "会话中显示为 \(profile.displayName) · \(historyHumanize(profile.role))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 9)
              }
              .buttonStyle(.plain)
              if profile.id != contact.conversationProfiles.last?.id {
                Divider()
              }
            }
          }
          .padding(.horizontal, 8)
        }
        DisclosureGroup("内部标识") {
          LabeledContent("参与者标识", value: contact.participantID)
            .textSelection(.enabled)
            .padding(.top, 8)
        }
      }
      .padding(28)
      .frame(maxWidth: 860, alignment: .leading)
    }
  }
}

struct CoverageBanner: View {
  let context: HistoryContextHealth
  var compact = false
  var showDetails: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(
        systemName: context.sourceCoverageComplete
          ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
      )
      .font(.title3)
      .foregroundStyle(context.sourceCoverageComplete ? .green : .orange)
      VStack(alignment: .leading, spacing: 3) {
        Text(
          context.sourceCoverageComplete
            ? "记录来源完整" : "部分记录来源暂不可用"
        )
        .font(.callout.weight(.semibold))
        if !compact || !context.sourceCoverageComplete {
          Text(context.coverageNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(compact ? 2 : nil)
        }
      }
      Spacer()
      if let showDetails {
        Button("详情", action: showDetails)
          .buttonStyle(.borderless)
      }
    }
    .padding(12)
    .background(
      (context.sourceCoverageComplete ? Color.green : Color.orange).opacity(0.09),
      in: RoundedRectangle(cornerRadius: 11)
    )
  }
}

struct CoverageDetailsView: View {
  let context: HistoryContextHealth
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("记录完整程度")
          .font(.title2.weight(.semibold))
        Spacer()
        Button("完成") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      CoverageBanner(context: context)
      GroupBox("数据库") {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
          EvidenceRow(label: "合计", value: context.totalDatabaseCount?.formatted() ?? "未知")
          EvidenceRow(label: "最新记录", value: context.freshDatabaseCount?.formatted() ?? "未知")
          EvidenceRow(
            label: "暂不可用", value: context.unavailableDatabaseCount?.formatted() ?? "未知")
          EvidenceRow(
            label: "此前保留的记录",
            value: context.preservedStaleDatabaseCount?.formatted() ?? "未知")
        }
        .padding(8)
      }
      if !context.limitationCodes.isEmpty {
        GroupBox("当前限制") {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(context.limitationCodes, id: \.self) { code in
              Label(historyHumanize(code), systemImage: "exclamationmark.circle")
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
        }
      }
      Text(
        "部分数据库不可用时，可能无法显示其中的消息、联系人或附件。这不代表它们已被删除或从未存在。"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(24)
  }
}

struct HistoryFilterField: View {
  @Binding var text: String
  let prompt: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(prompt, text: $text)
        .textFieldStyle(.plain)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
    )
    .padding(10)
  }
}

struct HistoryAvatarView: View {
  let name: String
  var size: CGFloat = 38

  var body: some View {
    ZStack {
      Circle().fill(color.gradient)
      Text(initials)
        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
    .accessibilityLabel(name)
  }

  private var initials: String {
    let components = name.split(separator: " ").prefix(2)
    let value = components.compactMap(\.first).map(String.init).joined()
    return value.isEmpty ? "?" : value.uppercased()
  }

  private var color: Color {
    let value = name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
    let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal]
    return colors[Int(value.magnitude % UInt(colors.count))]
  }
}

private struct MetricCard: View {
  let title: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 36, height: 36)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.title2.monospacedDigit().weight(.semibold))
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(14)
    .background(
      Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct CoverageMetric: View {
  let label: String
  let value: Int?
  var color: Color = .primary

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value?.formatted() ?? "—")
        .font(.title2.monospacedDigit().weight(.semibold))
        .foregroundStyle(color)
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

private struct EvidenceRow: View {
  let label: String
  let value: String

  var body: some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value)
    }
  }
}

private struct FreshnessBadge: View {
  let value: String

  var body: some View {
    Text(historyHumanize(value))
      .font(.caption2.weight(.semibold))
      .foregroundStyle(historyIsStale(value) ? .orange : .secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        (historyIsStale(value) ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
  }
}

struct DetailPlaceholder: View {
  let icon: String
  let title: String
  let detail: String

  var body: some View {
    ContentUnavailableView(title, systemImage: icon, description: Text(detail))
  }
}

func historyIsStale(_ value: String) -> Bool {
  value == "preservedStale" || value == "mixed"
}

func shortHistoryID(_ value: String) -> String {
  value.count > 18 ? "\(value.prefix(9))…\(value.suffix(8))" : value
}

func historyHumanize(_ value: String) -> String {
  historyChineseStatus(value)
}
