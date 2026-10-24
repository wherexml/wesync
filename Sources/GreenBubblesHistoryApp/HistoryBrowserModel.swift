import AppKit
import CryptoKit
import Foundation
import GreenBubblesHistory
import Observation
import PDFKit

enum HistorySection: String, CaseIterable, Identifiable {
  case overview
  case chats
  case contacts
  case search

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "概览"
    case .chats: "聊天"
    case .contacts: "联系人"
    case .search: "搜索"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "chart.bar.xaxis"
    case .chats: "bubble.left.and.bubble.right"
    case .contacts: "person.2"
    case .search: "text.magnifyingglass"
    }
  }
}

enum HistoryDirectSection: String, CaseIterable, Identifiable {
  case overview
  case chats
  case search

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "概览"
    case .chats: "聊天"
    case .search: "搜索"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "externaldrive.badge.checkmark"
    case .chats: "bubble.left.and.bubble.right"
    case .search: "text.magnifyingglass"
    }
  }
}

struct HistoryMediaRequest: Identifiable {
  let conversationID: String
  let artifact: HistoryArtifact
  var id: String { "\(conversationID):\(artifact.artifactID)" }
}

@MainActor
@Observable
final class HistoryBrowserModel {
  var session: HistoryBundleSession?
  var loadProgress: HistoryLoadProgress?
  var isLoading = false
  var libraryError: String?
  var selectedSection: HistorySection? = .overview
  var selectedConversationID: String?
  var selectedContactID: String?
  var conversationRangeReferenceDate = Date()
  var conversationRange: HistoryConversationRange = .month {
    didSet {
      UserDefaults.standard.set(
        conversationRange.rawValue, forKey: HistoryConversationRange.defaultsKey)
      clearConversationOutsideRange()
    }
  }
  var conversationFilter = ""
  var contactFilter = ""
  var searchQuery = ""
  var searchResults: [HistoryMessage] = []
  var isSearching = false
  var searchError: String?
  var timelineMessages: [HistoryMessage] = []
  var timelineCursor: HistoryMessageCursor?
  var isLoadingTimeline = false
  var timelineError: String?
  var isSearchContext = false
  var highlightedMessageID: String?
  var showsCoverageDetails = false
  var pendingMediaRequest: HistoryMediaRequest?
  var liveExecutablePath = ""
  var liveReplicaPath = ""
  var livePolicyPath = ""
  var liveAuditPath = ""
  var showsDirectConnection = false
  var showsSnapshotCreation = false
  var directCategoryOverrides: [String: String] = [:]
  var directChatCategory = "personal"
  var rememberDirectConnection = true
  var connectionPersistenceNotice: String?
  var directSourcePath = ""
  var directAccessMode: HistoryDirectAccessMode = .liveEncrypted
  var directLocalCredentialPath = ""
  var directRecoveryKitPath = ""
  var directConfiguration: HistoryDirectConfiguration?
  var directStatus: HistoryDirectSourceStatus?
  var directSection: HistoryDirectSection? = .overview
  var directConversations: [HistoryDirectConversation] = []
  var directConversationCursor: String?
  var directConversationWarnings: [HistoryDirectWarning] = []
  var directConversationConsistency: HistoryDirectConsistency?
  var directSelectedConversationID: String?
  var directMessages: [HistoryDirectMessage] = []
  var directImagePreviews: [String: NSImage] = [:]
  private var directImagePreviewOrder: [String] = []
  private struct CachedTimeline: Codable {
    let messages: [HistoryDirectMessage]
    let cursor: String?
    let warnings: [HistoryDirectWarning]
    let consistency: HistoryDirectConsistency?
    let refreshedAt: Date
    var accessedAt: Date
  }
  private var directMessagePageCache: [String: CachedTimeline] = [:]
  private struct DiskHistory: Codable {
    var conversations: [HistoryDirectConversation]
    var cursor: String?
    var timelines: [String: CachedTimeline]
  }
  @ObservationIgnored private var persistentHistory: HistoryPersistentCache?
  private var conversationRefreshItems: [HistoryDirectConversation] = []
  private var conversationRefreshCursors: Set<String> = []
  private var pendingFullConversationRefresh = false
  @ObservationIgnored private var conversationChangeMonitor: HistoryConversationChangeMonitor?
  private var conversationChangeTask: Task<Void, Never>?
  private var conversationSourceChanged = false
  private var conversationSceneActive = false
  private let conversationRefreshClock = ContinuousClock()
  private var lastDirectConversationRead: ContinuousClock.Instant?

  var isMonitoringDirectConversationChanges: Bool { conversationChangeMonitor != nil }

  private func saveHistoryCache() {
    guard let persistentHistory else { return }
    do {
      try persistentHistory.write(
        DiskHistory(
          conversations: directConversations,
          cursor: directConversationCursor, timelines: directMessagePageCache))
    } catch {
      connectionPersistenceNotice = "本地缓存暂时无法保存，下次打开将重新加载。"
    }
  }

  var directMessageCursor: String?
  var directMessageWarnings: [HistoryDirectWarning] = []
  var directMessageConsistency: HistoryDirectConsistency?
  var directSearchConversationID: String?
  var directImageLoads = 0
  var directSearchQuery = ""
  var directSearchResults: [HistoryDirectSearchHit] = []
  var directSearchCursor: String?
  var directSearchWarnings: [HistoryDirectWarning] = []
  var isDirectConnecting = false
  var isLoadingDirectConversations = false
  var isRefreshingDirectConversations = false
  var isLoadingDirectMessages = false
  var isSearchingDirect = false
  var directConversationError: String?
  var directMessageError: String?
  var directSearchError: String?
  var directIsSearchContext = false
  var directHighlightedMessageID: String?

  private var store: HistoryStore?
  private var loadTask: Task<Void, Never>?
  private var timelineTask: Task<Void, Never>?
  private var artifactCache: [String: HistoryArtifact] = [:]
  private var activeLoadID = UUID()
  private var activeTimelineID = UUID()
  private var activeSearchID = UUID()
  private var activeArtifactID = UUID()
  private var directLoadTask: Task<Void, Never>?
  private var directConversationTask: Task<Void, Never>?
  private var directConversationRefreshTask: Task<Void, Never>?
  private var directMessageTask: Task<Void, Never>?
  private var directSearchTask: Task<Void, Never>?
  private var activeDirectLoadID = UUID()
  private var activeDirectConversationID = UUID()
  private var activeDirectConversationRefreshID = UUID()
  private var activeDirectMessageID = UUID()
  private var activeDirectSearchID = UUID()
  @ObservationIgnored private var directKeyUTF8: [UInt8] = []
  @ObservationIgnored private let directClient = HistoryDirectQueryClient()
  @ObservationIgnored private let snapshotKeychain = SnapshotKeychainStore()
  private var pendingStartupBundleURL: URL?
  private var processedStartupBundle = false
  private let mediaSessionURL = FileManager.default.temporaryDirectory.appending(
    path: "greenbubbles-history-media-\(UUID().uuidString)", directoryHint: .isDirectory)
  private let snapshotUnlockSessionURL = FileManager.default.temporaryDirectory.appending(
    path: "greenbubbles-history-unlock-\(UUID().uuidString)", directoryHint: .isDirectory)

  init(
    arguments: [String] = Array(CommandLine.arguments.dropFirst()),
    currentDirectoryURL: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true)
  ) {
    let candidates = [
      Bundle.main.executableURL?.deletingLastPathComponent().appending(
        path: "greenbubbles"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appending(path: "Native/GreenBubbles/target/debug/greenbubbles"),
    ].compactMap { $0 }
    if let executable = candidates.first(where: {
      FileManager.default.isExecutableFile(atPath: $0.path)
    }) {
      liveExecutablePath = executable.path
    }
    let defaults = UserDefaults.standard
    conversationRange =
      defaults.string(forKey: HistoryConversationRange.defaultsKey)
      .flatMap(HistoryConversationRange.init(rawValue:)) ?? .month
    directCategoryOverrides =
      defaults.dictionary(forKey: "history.direct.categoryOverrides.v1") as? [String: String] ?? [:]
    rememberDirectConnection = defaults.object(forKey: "history.direct.remember") as? Bool ?? true
    if let rememberedCLI = defaults.string(forKey: "history.direct.executablePath"),
      FileManager.default.isExecutableFile(atPath: rememberedCLI)
    {
      liveExecutablePath = rememberedCLI
    }
    if let rememberedSource = defaults.string(forKey: "history.direct.sourcePath") {
      directSourcePath = rememberedSource
    }
    if let rememberedKit = defaults.string(forKey: "history.direct.recoveryKitPath") {
      directRecoveryKitPath = rememberedKit
    }
    if let rememberedLocal = defaults.string(forKey: "history.direct.localCredentialPath") {
      directLocalCredentialPath = rememberedLocal
    }
    if let rememberedMode = defaults.string(forKey: "history.direct.accessMode"),
      let mode = HistoryDirectAccessMode(rawValue: rememberedMode)
    {
      directAccessMode = mode
    }
    do {
      pendingStartupBundleURL = try HistoryBrowserLaunchOptions(
        arguments: arguments,
        currentDirectoryURL: currentDirectoryURL
      ).bundleURL
    } catch {
      libraryError = historyUserError(error)
    }
  }

  deinit {
    directKeyUTF8.resetBytes(in: 0..<directKeyUTF8.count)
    try? FileManager.default.removeItem(at: mediaSessionURL)
    try? FileManager.default.removeItem(at: snapshotUnlockSessionURL)
  }

  var hasOpenHistory: Bool {
    session != nil || directConfiguration != nil
  }

  var isDirectHistoryOpen: Bool {
    directConfiguration != nil && (directStatus != nil || !directConversations.isEmpty)
  }

  var selectedConversation: HistoryConversation? {
    guard let selectedConversationID else { return nil }
    return session?.conversations.first { $0.conversationID == selectedConversationID }
  }

  var selectedContact: HistoryContact? {
    guard let selectedContactID else { return nil }
    return session?.contacts.first { $0.participantID == selectedContactID }
  }

  var filteredConversations: [HistoryConversation] {
    guard let session else { return [] }
    let query = conversationFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    let visible = session.conversations.filter {
      conversationRange.includes(
        session.conversationStatistics[$0.id]?.latestMessageDate,
        relativeTo: conversationRangeReferenceDate)
    }
    guard !query.isEmpty else { return visible }
    return visible.filter { conversation in
      conversation.humanLabel.localizedCaseInsensitiveContains(query)
        || conversation.participants.contains {
          $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }
  }

  var filteredContacts: [HistoryContact] {
    guard let session else { return [] }
    let query = contactFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    let visible = session.contacts.filter { contact in
      conversationRange == .all
        || contact.enabledConversationIDs.contains {
          conversationRange.includes(
            session.conversationStatistics[$0]?.latestMessageDate,
            relativeTo: conversationRangeReferenceDate)
        }
    }
    guard !query.isEmpty else { return visible }
    return visible.filter { contact in
      contact.displayName.localizedCaseInsensitiveContains(query)
        || contact.conversationProfiles.contains {
          $0.conversationLabel.localizedCaseInsensitiveContains(query)
        }
    }
  }

  private func directCategoryKey(_ id: String) -> String {
    let source = URL(fileURLWithPath: directSourcePath).standardizedFileURL.path
    return SHA256.hash(data: Data((source + "\u{0}" + id).utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func directCategory(for conversation: HistoryDirectConversation) -> String? {
    guard conversation.chatCategory != nil else { return nil }
    let saved = directCategoryOverrides[directCategoryKey(conversation.id)]
    return ["personal", "group", "other"].contains(saved ?? "") ? saved : conversation.chatCategory
  }

  func hasDirectCategoryOverride(_ conversation: HistoryDirectConversation) -> Bool {
    directCategoryOverrides[directCategoryKey(conversation.id)] != nil
  }

  func moveDirectConversation(_ conversation: HistoryDirectConversation, toOther: Bool) {
    guard conversation.chatCategory != nil else { return }
    directCategoryOverrides[directCategoryKey(conversation.id)] =
      toOther
      ? "other"
      : conversation.id.hasSuffix("@chatroom") ? "group" : "personal"
    saveDirectCategoryOverrides(conversation)
  }

  func restoreDirectCategory(_ conversation: HistoryDirectConversation) {
    directCategoryOverrides.removeValue(forKey: directCategoryKey(conversation.id))
    saveDirectCategoryOverrides(conversation)
  }

  private func saveDirectCategoryOverrides(_ conversation: HistoryDirectConversation) {
    UserDefaults.standard.set(
      directCategoryOverrides, forKey: "history.direct.categoryOverrides.v1")
    if directSelectedConversationID == conversation.id
      && directCategory(for: conversation) != directChatCategory
    {
      directMessageTask?.cancel()
      activeDirectMessageID = UUID()
      isLoadingDirectMessages = false
      directSelectedConversationID = nil
      directMessages = []
    }
  }

  var filteredDirectConversations: [HistoryDirectConversation] {
    let query = conversationFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    let visible = directConversations.filter { item in
      directCategory(for: item) == directChatCategory
        && conversationRange.includes(item.sortDate, relativeTo: conversationRangeReferenceDate)
    }
    guard !query.isEmpty else { return visible }
    return visible.filter { conversation in
      conversation.displayName.localizedCaseInsensitiveContains(query)
        || (conversation.summary?.localizedCaseInsensitiveContains(query) == true)
        || (conversation.lastSenderDisplayName?.localizedCaseInsensitiveContains(query) == true)
    }
  }

  func refreshConversationRangeClock() {
    conversationRangeReferenceDate = Date()
    clearConversationOutsideRange()
    if conversationSceneActive { conversationChangeMonitor?.checkForChanges() }
  }

  private func clearConversationOutsideRange() {
    if let conversation = selectedDirectConversation,
      !conversationRange.includes(conversation.sortDate, relativeTo: conversationRangeReferenceDate)
    {
      directMessageTask?.cancel()
      activeDirectMessageID = UUID()
      isLoadingDirectMessages = false
      directSelectedConversationID = nil
      directMessages = []
      directMessageCursor = nil
      directMessageError = nil
      directIsSearchContext = false
    }
    if let id = selectedConversationID, let session,
      !conversationRange.includes(
        session.conversationStatistics[id]?.latestMessageDate,
        relativeTo: conversationRangeReferenceDate)
    {
      timelineTask?.cancel()
      activeTimelineID = UUID()
      isLoadingTimeline = false
      selectedConversationID = nil
      timelineMessages = []
      timelineCursor = nil
    }
    if let id = selectedContactID, !filteredContacts.contains(where: { $0.id == id }) {
      selectedContactID = nil
    }
  }

  var selectedDirectConversation: HistoryDirectConversation? {
    guard let directSelectedConversationID else { return nil }
    return directConversations.first { $0.id == directSelectedConversationID }
  }

  func resolvedDirection(for message: HistoryMessage) -> String? {
    message.resolvedDirection(
      selfParticipantID: session?.manifest.context.selfParticipantID
    )
  }

  func presentDirectConnection() {
    libraryError = nil
    showsDirectConnection = true
  }

  func presentSnapshotCreation() {
    libraryError = nil
    showsSnapshotCreation = true
  }

  func rememberCreatedSnapshot(
    _ result: HistorySnapshotCreationResult,
    keychainProtected: Bool,
    hiddenCredentialURL: URL?,
    recoveryKitURL: URL,
    passphraseProtected: Bool
  ) {
    directSourcePath = result.outputURL.standardizedFileURL.path
    directRecoveryKitPath = recoveryKitURL.standardizedFileURL.path
    if keychainProtected {
      directAccessMode = .snapshotKeychain
    } else if let hiddenCredentialURL {
      directAccessMode = .snapshotLocalCredential
      directLocalCredentialPath = hiddenCredentialURL.standardizedFileURL.path
    } else if passphraseProtected {
      directAccessMode = .snapshotPassphrase
    } else {
      directAccessMode = .snapshotRecoveryKit
    }
    UserDefaults.standard.set(directSourcePath, forKey: "history.direct.sourcePath")
    UserDefaults.standard.set(directAccessMode.rawValue, forKey: "history.direct.accessMode")
    UserDefaults.standard.set(
      directRecoveryKitPath,
      forKey: "history.direct.recoveryKitPath"
    )
  }

  func connectDirectSource(
    executableURL: URL,
    sourceURL: URL,
    accessMode: HistoryDirectAccessMode,
    keyUTF8: [UInt8],
    recoveryKitURL: URL? = nil,
    localCredentialURL: URL? = nil,
    restoring: Bool = false,
    migratingTool: Bool = false
  ) {
    connectionPersistenceNotice = nil
    let shouldRemember = rememberDirectConnection
    UserDefaults.standard.set(shouldRemember, forKey: "history.direct.remember")
    if !shouldRemember {
      do { try HistoryConnectionVault().remove() } catch {
        connectionPersistenceNotice = historyUserError(error)
      }
    }
    closeBundle()
    let effectiveLocalCredentialURL: URL?
    if accessMode == .snapshotKeychain {
      do {
        effectiveLocalCredentialURL = try snapshotKeychain.materialize(
          snapshotURL: sourceURL,
          sessionDirectory: snapshotUnlockSessionURL
        )
      } catch {
        libraryError = historyUserError(error)
        showsDirectConnection = false
        return
      }
    } else {
      effectiveLocalCredentialURL = localCredentialURL
    }
    liveExecutablePath = executableURL.standardizedFileURL.path
    directSourcePath = sourceURL.standardizedFileURL.path
    directAccessMode = accessMode
    directRecoveryKitPath = recoveryKitURL?.standardizedFileURL.path ?? directRecoveryKitPath
    if accessMode != .snapshotKeychain {
      directLocalCredentialPath =
        localCredentialURL?.standardizedFileURL.path ?? directLocalCredentialPath
    }
    let configuration = HistoryDirectConfiguration(
      executableURL: executableURL,
      sourceURL: sourceURL,
      accessMode: accessMode,
      recoveryKitURL: recoveryKitURL,
      localCredentialURL: effectiveLocalCredentialURL
    )
    let defaults = UserDefaults.standard
    defaults.set(liveExecutablePath, forKey: "history.direct.executablePath")
    defaults.set(directSourcePath, forKey: "history.direct.sourcePath")
    defaults.set(accessMode.rawValue, forKey: "history.direct.accessMode")
    if let recoveryKitURL {
      defaults.set(
        recoveryKitURL.standardizedFileURL.path,
        forKey: "history.direct.recoveryKitPath"
      )
    }
    if let localCredentialURL, accessMode != .snapshotKeychain {
      defaults.set(
        localCredentialURL.standardizedFileURL.path,
        forKey: "history.direct.localCredentialPath"
      )
    }
    directConfiguration = configuration
    replaceDirectKey(with: keyUTF8)
    persistentHistory = HistoryPersistentCache(
      configuration: configuration,
      secret: keyUTF8, enabled: shouldRemember)
    if let cached = persistentHistory?.read(DiskHistory.self) {
      directConversations = cached.conversations
      directMessagePageCache = cached.timelines
      directSection = .chats
    }
    showsDirectConnection = false
    isDirectConnecting = true
    libraryError = nil
    let loadID = UUID()
    activeDirectLoadID = loadID
    startDirectConversationChangeMonitor(configuration: configuration, sessionID: loadID)
    directLoadTask = Task { [weak self] in
      guard let self else { return }
      var key = directKeyUTF8
      defer { key.resetBytes(in: 0..<key.count) }
      do {
        let status = try await directClient.status(
          configuration: configuration,
          keyUTF8: key
        )
        try Task.checkCancellation()
        lastDirectConversationRead = conversationRefreshClock.now
        let page = try await directClient.conversations(
          configuration: configuration,
          keyUTF8: key,
          limit: 100
        )
        try Task.checkCancellation()
        guard activeDirectLoadID == loadID, directConfiguration == configuration else { return }
        directStatus = status
        conversationRefreshItems = page.items
        let freshIDs = Set(page.items.map(\.id))
        directConversations = page.items + directConversations.filter { !freshIDs.contains($0.id) }
        if page.page.nextCursor == nil { directConversations = page.items }
        directConversationCursor = page.page.nextCursor
        directConversationWarnings = page.warnings
        directConversationConsistency = page.consistency
        directSection = .chats
        isDirectConnecting = false
        saveHistoryCache()
        loadMoreDirectConversations()
        refreshDirectConversationsIfNeeded()
        if shouldRemember && rememberDirectConnection && (!restoring || migratingTool) {
          do {
            let record = HistoryRememberedConnection(
              executablePath: configuration.executableURL.path,
              executableDigest: try HistoryRememberedConnection.digest(configuration.executableURL),
              sourcePath: configuration.sourceURL.path, accessMode: accessMode.rawValue,
              recoveryKitPath: recoveryKitURL?.path, localCredentialPath: localCredentialURL?.path,
              secret: Data(key))
            try HistoryConnectionVault().save(record)
          } catch { connectionPersistenceNotice = "已连接，但未能记住：" + historyUserError(error) }
        }
      } catch is CancellationError {
        if activeDirectLoadID == loadID { isDirectConnecting = false }
      } catch {
        guard activeDirectLoadID == loadID else { return }
        isDirectConnecting = false
        libraryError = historyUserError(error)
        if directConversations.isEmpty {
          clearDirectState()
        } else {
          directConversationError = "连接暂不可用，显示本地缓存。"
        }
      }
    }
  }

  func previewDirectPDF(_ message: HistoryDirectMessage, mergedIndex: Int? = nil) async throws
    -> HistoryPDFPreview
  {
    guard message.pdfFilename != nil || mergedIndex != nil else {
      throw PDFPreviewError.unavailable
    }
    let output = try await materializeDirectDocument(message, mergedIndex: mergedIndex)
    var retained = false
    defer { if !retained { try? FileManager.default.removeItem(at: output) } }
    let bytes = try Data(contentsOf: output)
    guard bytes.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: bytes) else {
      throw PDFPreviewError.invalid
    }
    guard !document.isLocked else { throw PDFPreviewError.locked }
    guard document.pageCount > 0 else { throw PDFPreviewError.invalid }
    try Task.checkCancellation()
    retained = true
    return HistoryPDFPreview(url: output, document: document)
  }

  func materializeDirectDocument(_ message: HistoryDirectMessage, mergedIndex: Int? = nil)
    async throws -> URL
  {
    let attachmentID =
      mergedIndex.map { message.id + "~merged-document~" + String($0) } ?? message.id
    guard let configuration = directConfiguration else {
      throw PDFPreviewError.unavailable
    }
    let sessionID = activeDirectLoadID
    var key = directKeyUTF8
    defer { key.resetBytes(in: 0..<key.count) }
    let inspection = try await directClient.inspectDocument(
      configuration: configuration, keyUTF8: key, message: message,
      attachmentMessageID: attachmentID)
    try Task.checkCancellation()
    guard directConfiguration == configuration, activeDirectLoadID == sessionID else {
      throw PresentationError.sourceChanged
    }
    guard inspection.kind == "document", let attachment = inspection.preferredAttachmentId else {
      throw PDFPreviewError.unavailable
    }
    guard let size = inspection.preferredSourceByteCount, size > 0, size <= 64 * 1_024 * 1_024
    else { throw PDFPreviewError.tooLarge }
    let folder = HistoryPresentationAssets.shared.root.appending(path: "Previews")
    try HistoryPresentationAssets.shared.prepareDirectory(folder)
    let output = folder.appending(path: UUID().uuidString)
    var retained = false
    defer { if !retained { try? FileManager.default.removeItem(at: output) } }
    let report = try await directClient.materializeDocument(
      configuration: configuration, keyUTF8: key,
      message: message, attachmentID: attachment, output: output, attachmentMessageID: attachmentID)
    try Task.checkCancellation()
    guard directConfiguration == configuration, activeDirectLoadID == sessionID else {
      throw PresentationError.sourceChanged
    }
    guard report.decodedByteCount <= 64 * 1_024 * 1_024 else { throw PDFPreviewError.tooLarge }
    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.uint64Value == report.decodedByteCount,
      report.attachmentId == attachment, report.kind == "document"
    else { throw PresentationError.invalidIntegrity }
    let bytes = try Data(contentsOf: output)
    guard
      SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined()
        == report.decodedSha256.lowercased()
    else { throw PresentationError.invalidIntegrity }
    retained = true
    return output
  }

  func resolveDirectSticker(_ message: HistoryDirectMessage) async throws -> HistorySticker {
    guard message.isSticker, let configuration = directConfiguration,
      let executable = Bundle.main.executableURL?.deletingLastPathComponent()
        .appending(path: "greenbubbles-sticker-query"),
      FileManager.default.isExecutableFile(atPath: executable.path),
      let expected = Bundle.main.object(forInfoDictionaryKey: "GBStickerQuerySHA256") as? String,
      try HistoryRememberedConnection.digest(executable) == expected
    else { throw StickerLoadError.unavailable }
    let sessionID = activeDirectLoadID
    var key = directKeyUTF8
    defer { key.resetBytes(in: 0..<key.count) }
    let metadataConfiguration = HistoryDirectConfiguration(
      executableURL: executable,
      sourceURL: configuration.sourceURL, accessMode: configuration.accessMode,
      recoveryKitURL: configuration.recoveryKitURL,
      localCredentialURL: configuration.localCredentialURL)
    let resource = try await directClient.message(
      configuration: metadataConfiguration, keyUTF8: key,
      conversationID: message.conversationID, messageID: message.id)
    try Task.checkCancellation()
    guard directConfiguration == configuration, activeDirectLoadID == sessionID,
      resource.source.identity == directStatus?.source.identity,
      resource.item.id == message.id, let sticker = resource.item.sticker,
      sticker.md5 == message.sticker?.md5
    else { throw StickerLoadError.unavailable }
    return sticker
  }

  func previewDirectImage(_ message: HistoryDirectMessage, mergedIndex: Int? = nil) async throws
    -> NSImage
  {
    let imageID = mergedIndex.map { message.id + "~merged-image~" + String($0) } ?? message.id
    guard let configuration = directConfiguration else { throw PresentationError.sourceChanged }
    let sessionID = activeDirectLoadID
    while directImageLoads >= 2 {
      try Task.checkCancellation()
      try await Task.sleep(for: .milliseconds(50))
    }
    directImageLoads += 1
    defer { directImageLoads -= 1 }
    guard directConfiguration == configuration, activeDirectLoadID == sessionID else {
      throw PresentationError.sourceChanged
    }
    var key = directKeyUTF8
    defer { key.resetBytes(in: 0..<key.count) }
    let inspection = try await directClient.inspectImage(
      configuration: configuration, keyUTF8: key, message: message, attachmentMessageID: imageID)
    guard inspection.kind == "image", let attachment = inspection.preferredAttachmentId,
      (inspection.preferredSourceByteCount ?? 0) <= 32 * 1_024 * 1_024
    else { throw PresentationError.unavailable }
    try Task.checkCancellation()
    guard directConfiguration == configuration, activeDirectLoadID == sessionID else {
      throw PresentationError.sourceChanged
    }
    let folder = HistoryPresentationAssets.shared.root.appending(path: "Previews")
    try HistoryPresentationAssets.shared.prepareDirectory(folder)
    let output = folder.appending(path: UUID().uuidString + ".image")
    defer { try? FileManager.default.removeItem(at: output) }
    let report = try await directClient.materializeImage(
      configuration: configuration, keyUTF8: key,
      message: message, attachmentMessageID: imageID, attachmentID: attachment, output: output)
    try Task.checkCancellation()
    guard directConfiguration == configuration, activeDirectLoadID == sessionID else {
      throw PresentationError.sourceChanged
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.uint64Value == report.decodedByteCount,
      report.decodedByteCount <= 32 * 1_024 * 1_024,
      report.attachmentId == attachment, report.kind == "image"
    else { throw PresentationError.invalidIntegrity }
    let bytes = try Data(contentsOf: output)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    guard digest == report.decodedSha256.lowercased() else {
      throw PresentationError.invalidIntegrity
    }
    let image = try await HistoryImageDecoder.preview(at: output)
    try Task.checkCancellation()
    guard directConfiguration == configuration, activeDirectLoadID == sessionID else {
      throw PresentationError.sourceChanged
    }
    directImagePreviewOrder.removeAll { $0 == imageID }
    directImagePreviewOrder.append(imageID)
    while directImagePreviewOrder.count > 20 {
      directImagePreviews.removeValue(forKey: directImagePreviewOrder.removeFirst())
    }
    directImagePreviews[imageID] = image
    return image
  }

  /// Refresh only the bounded latest page automatically; a user refresh also
  /// reconciles the complete catalog so removed source conversations disappear.
  func refreshDirectConversations(reloadAll: Bool = false) {
    guard let configuration = directConfiguration, !isDirectConnecting
    else { return }
    if isRefreshingDirectConversations {
      if reloadAll { pendingFullConversationRefresh = true }
      return
    }
    if !reloadAll {
      guard directConversationCursor == nil, !isLoadingDirectConversations else { return }
    } else {
      directConversationTask?.cancel()
      activeDirectConversationID = UUID()
      isLoadingDirectConversations = false
    }
    let requestID = UUID()
    activeDirectConversationRefreshID = requestID
    conversationChangeTask?.cancel()
    conversationChangeTask = nil
    conversationSourceChanged = false
    lastDirectConversationRead = conversationRefreshClock.now
    isRefreshingDirectConversations = true
    directConversationError = nil
    directConversationRefreshTask = Task { [weak self] in
      guard let self else { return }
      var key = directKeyUTF8
      defer {
        key.resetBytes(in: 0..<key.count)
        if activeDirectConversationRefreshID == requestID && pendingFullConversationRefresh {
          pendingFullConversationRefresh = false
          refreshDirectConversations(reloadAll: true)
        } else if activeDirectConversationRefreshID == requestID {
          refreshDirectConversationsIfNeeded()
        }
      }
      do {
        let page = try await directClient.conversations(
          configuration: configuration, keyUTF8: key, limit: 100)
        try Task.checkCancellation()
        guard activeDirectConversationRefreshID == requestID,
          directConfiguration == configuration
        else { return }
        let freshIDs = Set(page.items.map(\.id))
        let refreshedCatalog: [HistoryDirectConversation]
        if page.page.nextCursor == nil {
          refreshedCatalog = page.items
        } else {
          refreshedCatalog =
            (page.items + directConversations.filter { !freshIDs.contains($0.id) }).sorted {
              let left = $0.sortDate ?? .distantPast
              let right = $1.sortDate ?? .distantPast
              return left == right ? $0.id < $1.id : left > right
            }
        }
        let catalogChanged = refreshedCatalog != directConversations
        if catalogChanged { directConversations = refreshedCatalog }
        directConversationWarnings = page.warnings
        directConversationConsistency = page.consistency
        isRefreshingDirectConversations = false
        if reloadAll {
          conversationRefreshItems = page.items
          conversationRefreshCursors = []
          directConversationCursor = page.page.nextCursor
          loadMoreDirectConversations()
        }
        if reloadAll || catalogChanged { saveHistoryCache() }
      } catch is CancellationError {
        if activeDirectConversationRefreshID == requestID {
          isRefreshingDirectConversations = false
        }
      } catch {
        if activeDirectConversationRefreshID == requestID {
          isRefreshingDirectConversations = false
          directConversationError = historyUserError(error)
        }
      }
    }
  }

  func refreshDirectConversationsIfNeeded() {
    guard conversationSceneActive, conversationSourceChanged,
      directConfiguration != nil, conversationChangeMonitor != nil,
      directConversationError == nil, !isDirectConnecting,
      directConversationCursor == nil, !isLoadingDirectConversations,
      !isRefreshingDirectConversations, conversationChangeTask == nil
    else { return }
    var delay: Duration = .seconds(2)
    if let lastDirectConversationRead {
      delay = max(
        delay, .seconds(60) - lastDirectConversationRead.duration(to: conversationRefreshClock.now))
    }
    let sessionID = activeDirectLoadID
    conversationChangeTask = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard let self, activeDirectLoadID == sessionID else { return }
      conversationChangeTask = nil
      guard conversationSceneActive, conversationSourceChanged,
        directConversationError == nil, !isDirectConnecting,
        directConversationCursor == nil, !isLoadingDirectConversations,
        !isRefreshingDirectConversations
      else { return }
      refreshDirectConversations()
    }
  }

  func setDirectConversationMonitoringActive(_ active: Bool) {
    conversationSceneActive = active
    if active {
      conversationChangeMonitor?.checkForChanges()
      refreshDirectConversationsIfNeeded()
    } else {
      conversationChangeTask?.cancel()
      conversationChangeTask = nil
    }
  }

  private func startDirectConversationChangeMonitor(
    configuration: HistoryDirectConfiguration, sessionID: UUID
  ) {
    guard configuration.accessMode == .liveEncrypted || configuration.accessMode == .decrypted
    else { return }
    do {
      conversationChangeMonitor = try HistoryConversationChangeMonitor(
        sourceRoot: configuration.sourceURL
      ) { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, self.activeDirectLoadID == sessionID,
            self.directConfiguration == configuration
          else { return }
          self.conversationSourceChanged = true
          self.refreshDirectConversationsIfNeeded()
        }
      }
    } catch {
      connectionPersistenceNotice = "暂时无法自动检测会话变化，请使用刷新按钮更新。"
    }
  }

  func refreshDirectHistory() {
    refreshDirectConversations(reloadAll: true)
    returnToLatestDirectMessages()
  }

  func retryDirectConversations() {
    if directConversationCursor != nil {
      loadMoreDirectConversations()
    } else {
      refreshDirectConversations(reloadAll: true)
    }
  }

  func loadMoreDirectConversations() {
    guard let configuration = directConfiguration, let cursor = directConversationCursor,
      !isLoadingDirectConversations, !isRefreshingDirectConversations
    else { return }
    directConversationTask?.cancel()
    let requestID = UUID()
    activeDirectConversationID = requestID
    isLoadingDirectConversations = true
    directConversationError = nil
    directConversationTask = Task { [weak self] in
      guard let self else { return }
      var key = directKeyUTF8
      defer { key.resetBytes(in: 0..<key.count) }
      do {
        let page = try await directClient.conversations(
          configuration: configuration,
          keyUTF8: key,
          limit: 100,
          cursor: cursor
        )
        try Task.checkCancellation()
        guard activeDirectConversationID == requestID,
          directConfiguration == configuration,
          directConversationCursor == cursor
        else { return }
        guard !conversationRefreshCursors.contains(cursor), page.page.nextCursor != cursor else {
          isLoadingDirectConversations = false
          directConversationError = "会话分页未前进，请重新连接后重试。"
          return
        }
        conversationRefreshCursors.insert(cursor)
        let existing = Set(conversationRefreshItems.map(\.id))
        conversationRefreshItems.append(contentsOf: page.items.filter { !existing.contains($0.id) })
        let freshIDs = Set(conversationRefreshItems.map(\.id))
        directConversations =
          conversationRefreshItems + directConversations.filter { !freshIDs.contains($0.id) }
        directConversationCursor = page.page.nextCursor
        if directConversationCursor == nil { directConversations = conversationRefreshItems }
        directConversationWarnings = mergeDirectWarnings(
          directConversationWarnings,
          page.warnings
        )
        directConversationConsistency = page.consistency
        isLoadingDirectConversations = false
        saveHistoryCache()
        // One bounded page at a time; yield between pages so chat reads remain responsive.
        try await Task.sleep(for: .milliseconds(150))
        guard activeDirectConversationID == requestID, directConfiguration == configuration else {
          return
        }
        loadMoreDirectConversations()
        refreshDirectConversationsIfNeeded()
      } catch is CancellationError {
        if activeDirectConversationID == requestID { isLoadingDirectConversations = false }
      } catch {
        if activeDirectConversationID == requestID {
          isLoadingDirectConversations = false
          directConversationError = historyUserError(error)
        }
      }
    }
  }

  func selectDirectConversation(_ conversationID: String) {
    directSection = .chats
    // Re-selecting the visible conversation must not restart a query or discard history.
    if directSelectedConversationID == conversationID && !directIsSearchContext
      && directMessageError == nil && (isLoadingDirectMessages || !directMessages.isEmpty)
    {
      return
    }
    directSelectedConversationID = conversationID
    if var cached = directMessagePageCache[conversationID] {
      cached.accessedAt = Date()
      directMessagePageCache[conversationID] = cached
      directMessageTask?.cancel()
      activeDirectMessageID = UUID()
      directMessages = cached.messages
      directMessageCursor = cached.cursor
      directMessageWarnings = cached.warnings
      directMessageConsistency = cached.consistency
      directMessageError = nil
      directIsSearchContext = false
      directHighlightedMessageID = nil
      isLoadingDirectMessages = false
      if Date().timeIntervalSince(cached.refreshedAt) < 60 { return }
      loadDirectMessages(
        conversationID: conversationID, cursor: nil, appending: false, preservingContent: true)
    } else {
      loadDirectMessages(conversationID: conversationID, cursor: nil, appending: false)
    }
  }

  func loadOlderDirectMessages() {
    guard let conversationID = directSelectedConversationID,
      let cursor = directMessageCursor,
      !isLoadingDirectMessages,
      !directIsSearchContext
    else { return }
    loadDirectMessages(conversationID: conversationID, cursor: cursor, appending: true)
  }

  func returnToLatestDirectMessages() {
    guard let conversationID = directSelectedConversationID else { return }
    loadDirectMessages(
      conversationID: conversationID, cursor: nil, appending: false,
      preservingContent: !directIsSearchContext)
  }

  func performDirectSearch() async {
    let query = directSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let searchID = UUID()
    activeDirectSearchID = searchID
    guard !query.isEmpty, let configuration = directConfiguration else {
      directSearchTask?.cancel()
      directSearchResults = []
      directSearchCursor = nil
      directSearchWarnings = []
      directSearchError = nil
      isSearchingDirect = false
      return
    }
    isSearchingDirect = true
    directSearchError = nil
    var key = directKeyUTF8
    defer { key.resetBytes(in: 0..<key.count) }
    do {
      try await Task.sleep(for: .milliseconds(250))
      try Task.checkCancellation()
      guard activeDirectSearchID == searchID,
        query == directSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      else { return }
      let page = try await directClient.search(
        configuration: configuration,
        keyUTF8: key,
        query: query,
        conversationID: directSearchConversationID,
        limit: 100
      )
      try Task.checkCancellation()
      guard activeDirectSearchID == searchID,
        directConfiguration == configuration,
        query == directSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      else { return }
      directSearchResults = page.items
      directSearchCursor = page.page.nextCursor
      directSearchWarnings = page.warnings
      isSearchingDirect = false
    } catch is CancellationError {
      if activeDirectSearchID == searchID { isSearchingDirect = false }
    } catch {
      if activeDirectSearchID == searchID {
        isSearchingDirect = false
        directSearchResults = []
        directSearchCursor = nil
        directSearchError = historyUserError(error)
      }
    }
  }

  func loadMoreDirectSearchResults() {
    let query = directSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, let configuration = directConfiguration,
      let cursor = directSearchCursor, !isSearchingDirect
    else { return }
    directSearchTask?.cancel()
    let searchID = UUID()
    activeDirectSearchID = searchID
    isSearchingDirect = true
    directSearchError = nil
    directSearchTask = Task { [weak self] in
      guard let self else { return }
      var key = directKeyUTF8
      defer { key.resetBytes(in: 0..<key.count) }
      do {
        let page = try await directClient.search(
          configuration: configuration,
          keyUTF8: key,
          query: query,
          limit: 100,
          cursor: cursor
        )
        try Task.checkCancellation()
        guard activeDirectSearchID == searchID,
          directConfiguration == configuration,
          directSearchCursor == cursor,
          query == directSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        let existing = Set(directSearchResults.map(\.id))
        directSearchResults.append(contentsOf: page.items.filter { !existing.contains($0.id) })
        directSearchCursor = page.page.nextCursor
        directSearchWarnings = mergeDirectWarnings(directSearchWarnings, page.warnings)
        isSearchingDirect = false
      } catch is CancellationError {
        if activeDirectSearchID == searchID { isSearchingDirect = false }
      } catch {
        if activeDirectSearchID == searchID {
          isSearchingDirect = false
          directSearchError = historyUserError(error)
        }
      }
    }
  }

  func openDirectSearchResult(_ hit: HistoryDirectSearchHit) {
    guard let configuration = directConfiguration else { return }
    directMessageTask?.cancel()
    let requestID = UUID()
    activeDirectMessageID = requestID
    directSection = .chats
    directSelectedConversationID = hit.conversationID
    directMessages = []
    directMessageCursor = nil
    directMessageWarnings = []
    directMessageError = nil
    directIsSearchContext = true
    directHighlightedMessageID = hit.id
    isLoadingDirectMessages = true
    directMessageTask = Task { [weak self] in
      guard let self else { return }
      var key = directKeyUTF8
      defer { key.resetBytes(in: 0..<key.count) }
      do {
        let resource = try await directClient.message(
          configuration: configuration,
          keyUTF8: key,
          conversationID: hit.conversationID,
          messageID: hit.id
        )
        try Task.checkCancellation()
        guard activeDirectMessageID == requestID,
          directSelectedConversationID == hit.conversationID,
          directConfiguration == configuration
        else { return }
        directMessages = [resource.item]
        directMessageWarnings = resource.warnings
        directMessageConsistency = resource.consistency
        saveHistoryCache()
        isLoadingDirectMessages = false
      } catch is CancellationError {
        if activeDirectMessageID == requestID { isLoadingDirectMessages = false }
      } catch {
        if activeDirectMessageID == requestID {
          isLoadingDirectMessages = false
          directMessageError = historyUserError(error)
        }
      }
    }
  }

  func chooseBundle() {
    let panel = NSOpenPanel()
    panel.title = "打开导出的聊天记录文件夹"
    panel.message =
      "选择完整的导出记录文件夹，其中应包含清单文件和四份记录文件。"
    panel.prompt = "打开记录"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    openBundle(url)
  }

  func openStartupBundleIfNeeded() {
    guard !processedStartupBundle else { return }
    processedStartupBundle = true
    guard let pendingStartupBundleURL else {
      restoreRememberedConnection()
      return
    }
    self.pendingStartupBundleURL = nil
    openBundle(pendingStartupBundleURL)
  }

  func restoreRememberedConnection() {
    guard rememberDirectConnection, directConfiguration == nil, session == nil else { return }
    do {
      guard var record = try HistoryConnectionVault().load() else { return }
      defer { record.secret.resetBytes(in: 0..<record.secret.count) }
      let configuration = try record.configuration()
      connectDirectSource(
        executableURL: configuration.executableURL,
        sourceURL: configuration.sourceURL, accessMode: configuration.accessMode,
        keyUTF8: Array(record.secret), recoveryKitURL: configuration.recoveryKitURL,
        localCredentialURL: configuration.localCredentialURL, restoring: true,
        migratingTool: try HistoryRememberedConnection.digest(configuration.executableURL)
          != record.executableDigest)
    } catch let error as RememberedConnectionError {
      libraryError = error.localizedDescription
    } catch { libraryError = historyUserError(error) }
  }

  func forgetRememberedConnection() {
    if let url = persistentHistory?.url { try? FileManager.default.removeItem(at: url) }
    persistentHistory = nil
    rememberDirectConnection = false
    UserDefaults.standard.set(false, forKey: "history.direct.remember")
    do {
      try HistoryConnectionVault().remove()
      connectionPersistenceNotice = "已忘记保存的连接。下次启动不会自动连接。"
    } catch { connectionPersistenceNotice = historyUserError(error) }
  }

  func openExternalURLs(_ urls: [URL]) {
    guard urls.count == 1, let url = urls.first else {
      libraryError = "请每次只打开一个聊天记录文件夹。"
      return
    }
    openBundle(HistoryBrowserLaunchOptions.normalizeOpenedURL(url))
  }

  func openBundle(_ url: URL) {
    clearDirectState()
    showsDirectConnection = false
    loadTask?.cancel()
    timelineTask?.cancel()
    let loadID = UUID()
    activeLoadID = loadID
    activeTimelineID = UUID()
    activeSearchID = UUID()
    activeArtifactID = UUID()
    isLoading = true
    isLoadingTimeline = false
    isSearching = false
    libraryError = nil
    timelineError = nil
    searchError = nil
    loadProgress = nil
    session = nil
    store = nil
    selectedSection = .overview
    selectedConversationID = nil
    selectedContactID = nil
    conversationFilter = ""
    contactFilter = ""
    searchQuery = ""
    searchResults = []
    timelineMessages = []
    timelineCursor = nil
    isSearchContext = false
    highlightedMessageID = nil
    showsCoverageDetails = false
    artifactCache.removeAll()
    pendingMediaRequest = nil
    loadTask = Task { [weak self] in
      guard let self else { return }
      do {
        let indexDirectory = try historyIndexDirectory()
        let loaded = try await HistoryBundleLoader().load(
          bundleURL: url,
          indexDirectory: indexDirectory,
          progress: { [weak self] update in
            Task { @MainActor [weak self] in
              guard let self, self.activeLoadID == loadID, self.isLoading else { return }
              if update.overallFraction >= (self.loadProgress?.overallFraction ?? 0) {
                self.loadProgress = update
              }
            }
          }
        )
        try Task.checkCancellation()
        let openedStore = try HistoryStore(session: loaded)
        guard activeLoadID == loadID else { return }
        session = loaded
        store = openedStore
        selectedSection = .overview
        isLoading = false
        loadProgress = HistoryLoadProgress(
          phase: .ready,
          fileRole: nil,
          completedBytes: loaded.manifest.files.reduce(0) { $0 + $1.byteCount },
          totalBytes: loaded.manifest.files.reduce(0) { $0 + $1.byteCount },
          completedRecords: loaded.manifest.files.reduce(0) { $0 + $1.recordCount },
          totalRecords: loaded.manifest.files.reduce(0) { $0 + $1.recordCount },
          bundleByteCount: loaded.manifest.files.reduce(0) { $0 + $1.byteCount },
          bundleRecordCount: loaded.manifest.files.reduce(0) { $0 + $1.recordCount },
          phaseFraction: 1,
          overallFraction: 1,
          usingCachedIndex: loaded.reusedIndex
        )
      } catch is CancellationError {
        if activeLoadID == loadID { isLoading = false }
      } catch {
        if activeLoadID == loadID {
          isLoading = false
          libraryError = historyUserError(error)
        }
      }
    }
  }

  func closeBundle() {
    loadTask?.cancel()
    timelineTask?.cancel()
    activeLoadID = UUID()
    activeTimelineID = UUID()
    activeSearchID = UUID()
    activeArtifactID = UUID()
    isLoading = false
    isLoadingTimeline = false
    isSearching = false
    session = nil
    store = nil
    loadProgress = nil
    libraryError = nil
    selectedConversationID = nil
    selectedContactID = nil
    selectedSection = .overview
    conversationFilter = ""
    contactFilter = ""
    searchQuery = ""
    searchError = nil
    searchResults = []
    timelineCursor = nil
    timelineError = nil
    timelineMessages = []
    isSearchContext = false
    highlightedMessageID = nil
    showsCoverageDetails = false
    artifactCache.removeAll()
    pendingMediaRequest = nil
    clearDirectState()
    showsDirectConnection = false
  }

  func selectConversation(_ conversationID: String, around canonicalID: String? = nil) {
    selectedSection = .chats
    selectedConversationID = conversationID
    selectedContactID = nil
    loadTimeline(conversationID: conversationID, around: canonicalID)
  }

  func selectContact(_ participantID: String) {
    timelineTask?.cancel()
    activeTimelineID = UUID()
    selectedSection = .contacts
    selectedContactID = participantID
    selectedConversationID = nil
    timelineMessages = []
    timelineCursor = nil
    timelineError = nil
    isLoadingTimeline = false
    isSearchContext = false
    highlightedMessageID = nil
  }

  func loadOlderMessages() {
    guard let conversationID = selectedConversationID, let cursor = timelineCursor,
      !isLoadingTimeline, !isSearchContext, let store
    else { return }
    timelineTask?.cancel()
    let timelineID = UUID()
    activeTimelineID = timelineID
    isLoadingTimeline = true
    timelineError = nil
    timelineTask = Task { [weak self] in
      guard let self else { return }
      do {
        let page = try await store.messages(
          conversationID: conversationID, before: cursor, limit: 100)
        guard activeTimelineID == timelineID, selectedConversationID == conversationID else {
          return
        }
        let existing = Set(timelineMessages.map(\.canonicalID))
        timelineMessages.append(
          contentsOf: page.messages.filter { !existing.contains($0.canonicalID) })
        timelineCursor = page.nextCursor
        isLoadingTimeline = false
      } catch {
        guard activeTimelineID == timelineID else { return }
        isLoadingTimeline = false
        if !(error is CancellationError) {
          timelineError = historyUserError(error)
        }
      }
    }
  }

  func returnToLatestMessages() {
    guard let selectedConversationID else { return }
    loadTimeline(conversationID: selectedConversationID, around: nil)
  }

  func performSearch() async {
    let searchID = UUID()
    activeSearchID = searchID
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, let store else {
      searchResults = []
      searchError = nil
      isSearching = false
      return
    }
    isSearching = true
    searchError = nil
    do {
      try await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled, activeSearchID == searchID,
        query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      else { return }
      let results = try await store.searchMessages(query: query, limit: 150)
      guard activeSearchID == searchID,
        query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      else { return }
      searchResults = results
      isSearching = false
    } catch is CancellationError {
      if activeSearchID == searchID { isSearching = false }
    } catch {
      if activeSearchID == searchID {
        isSearching = false
        searchError = historyUserError(error)
      }
    }
  }

  func openSearchResult(_ message: HistoryMessage) {
    selectConversation(message.conversationID, around: message.canonicalID)
  }

  func artifact(_ artifactID: String) async throws -> HistoryArtifact? {
    if let cached = artifactCache[artifactID] { return cached }
    guard let store else { return nil }
    let generation = activeArtifactID
    guard let artifact = try await store.artifact(artifactID: artifactID) else { return nil }
    try Task.checkCancellation()
    guard activeArtifactID == generation else { throw CancellationError() }
    artifactCache[artifactID] = artifact
    return artifact
  }

  func requestMediaPreview(_ artifact: HistoryArtifact) {
    let conversationID =
      selectedConversationID.flatMap { selected in
        artifact.conversationIDs.contains(selected) ? selected : nil
      } ?? artifact.conversationIDs.first
    guard let conversationID else { return }
    pendingMediaRequest = HistoryMediaRequest(
      conversationID: conversationID,
      artifact: artifact
    )
  }

  func liveMediaConfiguration() throws -> HistoryLiveMediaConfiguration {
    guard !liveExecutablePath.isEmpty, !liveReplicaPath.isEmpty,
      !livePolicyPath.isEmpty, !liveAuditPath.isEmpty, let context = session?.manifest.context
    else {
      throw HistoryLiveMediaError.invalidConfiguration(
        "请选择读取工具、记录副本、访问规则和操作记录文件位置")
    }
    return HistoryLiveMediaConfiguration(
      executableURL: URL(fileURLWithPath: liveExecutablePath),
      replicaURL: URL(fileURLWithPath: liveReplicaPath),
      policyURL: URL(fileURLWithPath: livePolicyPath),
      auditURL: URL(fileURLWithPath: liveAuditPath),
      sessionDirectory: mediaSessionURL,
      scratchDirectory: mediaSessionURL.appending(path: "requests", directoryHint: .isDirectory),
      previewDirectory: mediaSessionURL.appending(path: "previews", directoryHint: .isDirectory),
      expectedAccountID: context.accountID,
      expectedReplicaID: context.replicaID,
      expectedSourceFingerprint: context.sourceFingerprint
    )
  }

  func chooseLiveExecutable() {
    if let url = chooseFile(title: "选择本机读取工具", prompt: "选择工具") {
      liveExecutablePath = url.path
    }
  }

  func chooseLiveReplica() {
    if let url = chooseFile(
      title: "选择加密的聊天记录副本", prompt: "选择副本")
    {
      liveReplicaPath = url.path
    }
  }

  func chooseLivePolicy() {
    if let url = chooseFile(title: "选择访问规则文件", prompt: "选择规则文件") {
      livePolicyPath = url.path
    }
  }

  func chooseLiveAudit() {
    let panel = NSSavePanel()
    panel.title = "选择私有的操作记录文件"
    panel.prompt = "使用此记录文件"
    panel.nameFieldStringValue = "audit.ndjson"
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
      liveAuditPath = url.path
    }
  }

  private func loadTimeline(conversationID: String, around canonicalID: String?) {
    timelineTask?.cancel()
    let timelineID = UUID()
    activeTimelineID = timelineID
    timelineMessages = []
    timelineCursor = nil
    timelineError = nil
    isLoadingTimeline = true
    isSearchContext = canonicalID != nil
    highlightedMessageID = canonicalID
    timelineTask = Task { [weak self] in
      guard let self, let store else { return }
      do {
        if let canonicalID {
          let messages = try await store.messagesAround(canonicalID: canonicalID)
          guard activeTimelineID == timelineID, selectedConversationID == conversationID else {
            return
          }
          timelineMessages = messages
          timelineCursor = nil
        } else {
          let page = try await store.messages(conversationID: conversationID, limit: 100)
          guard activeTimelineID == timelineID, selectedConversationID == conversationID else {
            return
          }
          timelineMessages = page.messages
          timelineCursor = page.nextCursor
        }
        isLoadingTimeline = false
      } catch is CancellationError {
        if activeTimelineID == timelineID { isLoadingTimeline = false }
      } catch {
        if activeTimelineID == timelineID {
          isLoadingTimeline = false
          timelineError = historyUserError(error)
        }
      }
    }
  }

  private func loadDirectMessages(
    conversationID: String,
    cursor: String?,
    appending: Bool,
    preservingContent: Bool = false
  ) {
    guard let configuration = directConfiguration else { return }
    directMessageTask?.cancel()
    let requestID = UUID()
    activeDirectMessageID = requestID
    if !appending && !preservingContent {
      directMessages = []
      directMessageCursor = nil
      directMessageWarnings = []
    }
    directMessageError = nil
    directIsSearchContext = false
    directHighlightedMessageID = nil
    isLoadingDirectMessages = true
    directMessageTask = Task { [weak self] in
      guard let self else { return }
      var key = directKeyUTF8
      defer { key.resetBytes(in: 0..<key.count) }
      do {
        let page = try await directClient.messages(
          configuration: configuration,
          keyUTF8: key,
          conversationID: conversationID,
          limit: 40,
          cursor: cursor
        )
        try Task.checkCancellation()
        guard activeDirectMessageID == requestID,
          directSelectedConversationID == conversationID,
          directConfiguration == configuration
        else { return }
        if appending {
          guard page.page.nextCursor != cursor else {
            isLoadingDirectMessages = false
            directMessageError = "历史分页未前进，请刷新后重试。"
            return
          }
          let existing = Set(directMessages.map(\.id))
          directMessages.append(contentsOf: page.items.filter { !existing.contains($0.id) })
          directMessageWarnings = mergeDirectWarnings(directMessageWarnings, page.warnings)
          directMessageCursor = page.page.nextCursor
        } else if preservingContent, let boundary = page.items.last,
          let overlap = directMessages.firstIndex(where: { $0.id == boundary.id })
        {
          // Only retain older records when the refreshed page proves continuity.
          let refreshedIDs = Set(page.items.map(\.id))
          let older = directMessages.dropFirst(overlap + 1).filter { !refreshedIDs.contains($0.id) }
          directMessages = page.items + older
          directMessageWarnings = mergeDirectWarnings(
            page.warnings, older.isEmpty ? [] : directMessageWarnings)
          if older.isEmpty { directMessageCursor = page.page.nextCursor }
        } else {
          directMessages = page.items
          directMessageWarnings = page.warnings
          directMessageCursor = page.page.nextCursor
        }
        directMessageConsistency = page.consistency
        // Keep a bounded, contiguous timeline with its matching pagination cursor.
        // If the user reads beyond the per-chat budget, retain the last bounded snapshot.
        if directMessages.count <= 400 {
          let now = Date()
          let refreshedAt =
            appending ? directMessagePageCache[conversationID]?.refreshedAt ?? now : now
          directMessagePageCache[conversationID] = CachedTimeline(
            messages: directMessages, cursor: directMessageCursor,
            warnings: directMessageWarnings, consistency: directMessageConsistency,
            refreshedAt: refreshedAt, accessedAt: now)
          while directMessagePageCache.count > 32
            || directMessagePageCache.values.reduce(0, { $0 + $1.messages.count }) > 2_000
          {
            guard
              let oldest = directMessagePageCache.filter({ $0.key != conversationID })
                .min(by: { $0.value.accessedAt < $1.value.accessedAt })?.key
            else { break }
            directMessagePageCache.removeValue(forKey: oldest)
          }
        }
        saveHistoryCache()
        isLoadingDirectMessages = false
      } catch is CancellationError {
        if activeDirectMessageID == requestID { isLoadingDirectMessages = false }
      } catch {
        if activeDirectMessageID == requestID {
          isLoadingDirectMessages = false
          directMessageError = historyUserError(error)
        }
      }
    }
  }

  private func replaceDirectKey(with key: [UInt8]) {
    directKeyUTF8.resetBytes(in: 0..<directKeyUTF8.count)
    directKeyUTF8.removeAll(keepingCapacity: false)
    directKeyUTF8 = key
  }

  private func clearDirectState() {
    conversationChangeMonitor?.stop()
    conversationChangeMonitor = nil
    conversationChangeTask?.cancel()
    conversationChangeTask = nil
    conversationSourceChanged = false
    lastDirectConversationRead = nil
    directLoadTask?.cancel()
    directConversationTask?.cancel()
    directConversationRefreshTask?.cancel()
    directMessageTask?.cancel()
    directSearchTask?.cancel()
    activeDirectLoadID = UUID()
    activeDirectConversationID = UUID()
    activeDirectConversationRefreshID = UUID()
    activeDirectMessageID = UUID()
    activeDirectSearchID = UUID()
    directLoadTask = nil
    directConversationTask = nil
    directConversationRefreshTask = nil
    directMessageTask = nil
    directSearchTask = nil
    directKeyUTF8.resetBytes(in: 0..<directKeyUTF8.count)
    directKeyUTF8.removeAll(keepingCapacity: false)
    directConfiguration = nil
    directImagePreviews.removeAll()
    directImagePreviewOrder.removeAll()
    persistentHistory = nil
    conversationRefreshItems = []
    conversationRefreshCursors = []
    pendingFullConversationRefresh = false
    directMessagePageCache.removeAll()
    directStatus = nil
    directSection = .overview
    directConversations = []
    directConversationCursor = nil
    directConversationWarnings = []
    directConversationConsistency = nil
    directSelectedConversationID = nil
    directMessages = []
    directMessageCursor = nil
    directMessageWarnings = []
    directMessageConsistency = nil
    directSearchQuery = ""
    directSearchResults = []
    directSearchCursor = nil
    directSearchWarnings = []
    isDirectConnecting = false
    isLoadingDirectConversations = false
    isRefreshingDirectConversations = false
    isLoadingDirectMessages = false
    isSearchingDirect = false
    directConversationError = nil
    directMessageError = nil
    directSearchError = nil
    directIsSearchContext = false
    directHighlightedMessageID = nil
    try? FileManager.default.removeItem(at: snapshotUnlockSessionURL)
  }

  private func mergeDirectWarnings(
    _ existing: [HistoryDirectWarning],
    _ additions: [HistoryDirectWarning]
  ) -> [HistoryDirectWarning] {
    var merged = existing
    for warning in additions {
      if let index = merged.firstIndex(where: { $0.id == warning.id }) {
        merged[index] = warning
      } else {
        merged.append(warning)
      }
    }
    return merged
  }

  private func historyIndexDirectory() throws -> URL {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else {
      throw HistoryBundleError.indexFailure("无法访问应用数据文件夹")
    }
    return
      applicationSupport
      .appending(path: "GreenBubbles", directoryHint: .isDirectory)
      .appending(path: "HistoryIndexes", directoryHint: .isDirectory)
  }

  private func chooseFile(title: String, prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = prompt
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    return panel.runModal() == .OK ? panel.url : nil
  }
}
