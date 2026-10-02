#if DEBUG
  import AppKit
  import GreenBubblesHistory
  import SwiftUI
  import PDFKit

  /// End-to-end offline acceptance: real subprocess transport, production model,
  /// attachment integrity validation, private avatar storage, and native SwiftUI rendering.
  /// Compiled out of release builds. Its CLI rejects non-fixture paths and all credentials.
  @MainActor
  func runOfflinePresentationAcceptance(model: HistoryBrowserModel) async {
    guard
      [
        "me.greenbubbles.PresentationPreview", "me.greenbubbles.PolishPreview",
        "me.greenbubbles.ChinesePreview", "me.greenbubbles.DarkModePreview",
      ].contains(Bundle.main.bundleIdentifier ?? ""),
      let resources = Bundle.main.resourceURL, let binary = Bundle.main.executableURL
    else { return }
    let root = resources.appending(path: "offline-fixture")
    let reportURL = root.appending(path: "acceptance.json")
    let cli = binary.deletingLastPathComponent().appending(path: "greenbubbles")
    var checks: [String: Bool] = [:]
    func require(_ ok: Bool, _ name: String) throws {
      checks[name] = ok
      if !ok {
        throw NSError(
          domain: "OfflineAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: name])
      }
    }
    func waitFor(_ ready: @escaping () -> Bool) async throws {
      for _ in 0..<200 {
        if ready() { return }
        try await Task.sleep(for: .milliseconds(50))
      }
      throw NSError(
        domain: "OfflineAcceptance", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out"])
    }
    var failure: String?
    if FileManager.default.fileExists(
      atPath: root.appending(path: "conversation-range-acceptance").path)
    {
      do {
        model.rememberDirectConnection = false
        model.conversationRangeReferenceDate = Date(timeIntervalSince1970: 1_790_942_400)
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitFor { !model.isDirectConnecting && model.directConversationCursor == nil }
        try require(model.directConversations.count == 21, "full-source-retained")
        for category in ["personal", "group", "other"] {
          model.directChatCategory = category
          for (range, count) in [
            (HistoryConversationRange.week, 1), (.month, 3), (.threeMonths, 4), (.year, 5),
            (.all, 7),
          ] {
            model.conversationRange = range
            try require(
              model.filteredDirectConversations.count == count, "\(category)-\(range.rawValue)")
            model.conversationFilter = "Synthetic"
            try require(
              model.filteredDirectConversations.count == count,
              "search-intersection-\(category)-\(range.rawValue)")
            model.conversationFilter = ""
          }
        }
        model.directChatCategory = "personal"
        model.selectDirectConversation("range-personal-4")
        try await waitFor { !model.isLoadingDirectMessages }
        model.conversationRange = .month
        try require(
          model.directSelectedConversationID == nil && model.directMessages.isEmpty,
          "hidden-selection-cleared")
        model.conversationRange = .all
        try require(
          model.filteredDirectConversations.count == 7, "expansion-restores-unknown-and-old")
        try require(model.directConversations.count == 21, "filter-never-deletes-source")
        model.conversationRange = .threeMonths
        let restored = HistoryBrowserModel(arguments: [])
        try require(restored.conversationRange == .threeMonths, "preference-persisted")
        let calendar = Calendar(identifier: .gregorian)
        let monthEnd = Date(timeIntervalSince1970: 1_743_422_400)
        let cutoff = HistoryConversationRange.month.cutoff(
          relativeTo: monthEnd, calendar: calendar)!
        try require(
          calendar.dateComponents([.month, .day], from: cutoff).month == 2
            && calendar.component(.day, from: cutoff) == 28, "calendar-month-end")
        for range in HistoryConversationRange.allCases where range != .all {
          let cutoff = range.cutoff(relativeTo: model.conversationRangeReferenceDate)!
          try require(
            range.includes(cutoff, relativeTo: model.conversationRangeReferenceDate),
            "inclusive-boundary-\(range.rawValue)")
          try require(
            !range.includes(
              cutoff.addingTimeInterval(-1), relativeTo: model.conversationRangeReferenceDate),
            "older-than-boundary-\(range.rawValue)")
          try require(
            !range.includes(nil, relativeTo: model.conversationRangeReferenceDate),
            "unknown-time-hidden-\(range.rawValue)")
        }
        model.conversationRange = .month
      } catch { failure = error.localizedDescription }
      let report: [String: Any] = [
        "checks": checks, "passed": failure == nil, "error": failure ?? "",
        "source": "synthetic-only", "wechatRead": false,
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: root.appending(path: "conversation-range-acceptance.json"))
      }
      return
    }
    if FileManager.default.fileExists(atPath: root.appending(path: "message-cache-acceptance").path)
    {
      do {
        model.rememberDirectConnection = false
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitFor { !model.isDirectConnecting }
        try require(model.isDirectHistoryOpen, "fixture-connected")
        try await waitFor {
          model.directConversationCursor == nil && !model.isLoadingDirectConversations
        }
        try require(
          model.directConversations.count == 230, "all-conversations-loaded-without-click")
        model.selectDirectConversation("demo-room")
        try await waitFor { !model.isLoadingDirectMessages }
        try require(model.directMessages.count == 40, "first-page")
        model.loadOlderDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        try require(
          model.directMessages.count == 80 && model.directMessageCursor == "80", "second-page")
        for index in 0..<9 {
          model.selectDirectConversation("synthetic-\(index)")
          try await waitFor { !model.isLoadingDirectMessages }
        }
        model.selectDirectConversation("demo-room")
        try require(
          model.directMessages.count == 80 && !model.isLoadingDirectMessages
            && model.directMessageCursor == "80",
          "return-after-nine-chats-keeps-history-immediately")
        model.selectDirectConversation("demo-room")
        try require(
          !model.isLoadingDirectMessages && model.directMessages.count == 80,
          "reselect-does-not-query")
        model.returnToLatestDirectMessages()
        try require(model.directMessages.count == 80, "refresh-retains-readable-content")
        try await waitFor { !model.isLoadingDirectMessages }
        try require(
          model.directMessages.count == 80 && model.directMessageCursor == "80",
          "refresh-preserves-contiguous-history")
        try Data().write(to: root.appending(path: "cache-fail"))
        model.returnToLatestDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        try require(
          model.directMessageError != nil && model.directMessages.count == 80,
          "refresh-failure-keeps-content")
        try FileManager.default.removeItem(at: root.appending(path: "cache-fail"))
        model.selectDirectConversation("synthetic-slow")
        model.selectDirectConversation("demo-room")
        try await Task.sleep(for: .milliseconds(500))
        try require(
          model.directMessages.allSatisfy { $0.conversationID == "demo-room" },
          "cancelled-query-cannot-overwrite-selection")
        model.closeBundle()
        try require(model.directMessages.isEmpty, "disconnect-clears-visible-content")
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitFor { !model.isDirectConnecting }
        model.selectDirectConversation("demo-room")
        try require(
          model.directMessages.isEmpty && model.isLoadingDirectMessages,
          "reconnect-does-not-reuse-prior-session")
        try await waitFor { !model.isLoadingDirectMessages }
        model.closeBundle()
        model.rememberDirectConnection = true
        model.connectDirectSource(
          executableURL: cli, sourceURL: root,
          accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitFor { !model.isDirectConnecting && model.directConversationCursor == nil }
        model.selectDirectConversation("demo-room")
        try await waitFor { !model.isLoadingDirectMessages }
        model.loadOlderDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        let configuration = model.directConfiguration!
        let disk = HistoryPersistentCache(configuration: configuration, secret: [], enabled: true)!
        let encrypted = try Data(contentsOf: disk.url)
        try require(
          encrypted.range(of: Data("Synthetic cache message".utf8)) == nil,
          "disk-has-no-plaintext-chat")
        model.closeBundle()
        model.connectDirectSource(
          executableURL: cli, sourceURL: root,
          accessMode: .decrypted, keyUTF8: [], restoring: true)
        try require(
          model.directConversations.count == 230, "reconnect-restores-full-list-synchronously")
        model.selectDirectConversation("demo-room")
        try require(
          model.directMessages.count == 80 && !model.isLoadingDirectMessages,
          "reconnect-restores-history-and-cursor")
        try await waitFor { !model.isDirectConnecting && model.directConversationCursor == nil }
        model.closeBundle()
        try Data("corrupt".utf8).write(to: disk.url)
        model.connectDirectSource(
          executableURL: cli, sourceURL: root,
          accessMode: .decrypted, keyUTF8: [], restoring: true)
        try require(model.directConversations.isEmpty, "corrupt-cache-is-ignored")
        try await waitFor { !model.isDirectConnecting && model.directConversationCursor == nil }
        try require(model.directConversations.count == 230, "corrupt-cache-rebuilt-from-source")
        model.selectDirectConversation("demo-room")
        try await waitFor { !model.isLoadingDirectMessages }
      } catch { failure = error.localizedDescription }
      let report: [String: Any] = [
        "checks": checks, "passed": failure == nil, "error": failure ?? "",
        "source": "synthetic-only", "wechatRead": false,
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: root.appending(path: "message-cache-acceptance.json"))
      }
      return
    }
    if FileManager.default.fileExists(atPath: root.appending(path: "verify-restart").path) {
      model.openStartupBundleIfNeeded()
      do { try await waitFor { !model.isDirectConnecting } } catch {
        failure = error.localizedDescription
      }
      let ok = failure == nil && model.isDirectHistoryOpen && model.directConversations.count == 9
      let result: [String: Any] = [
        "passed": ok, "source": "synthetic-only", "wechatRead": false,
        "actualProcessRestart": true, "manualConnectionCalled": false, "keyTyped": false,
        "manualGroupMoveSurvived": model.directConversations.first(where: {
          $0.id == "demo@chatroom"
        }).map { model.directCategory(for: $0) == "other" } ?? false,
      ]
      if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]) {
        try? data.write(to: root.appending(path: "restart-acceptance.json"))
      }
      return
    }
    do {
      for name in ["retry-ready", "bad-digest", "pdf-retry-ready", "pdf-corrupt"] {
        try? FileManager.default.removeItem(at: root.appending(path: name))
      }
      let syntheticPDF = PDFDocument()
      for title in ["Synthetic PDF report", "Second page - preview acceptance"] {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.string = title
        view.font = NSFont.systemFont(ofSize: 28)
        let pageData = view.dataWithPDF(inside: view.bounds)
        if let page = PDFDocument(data: pageData)?.page(at: 0) {
          syntheticPDF.insert(page, at: syntheticPDF.pageCount)
        }
      }
      try require(
        syntheticPDF.write(to: root.appending(path: "sample.pdf")), "synthetic-pdf-created")
      model.directCategoryOverrides = [:]
      UserDefaults.standard.removeObject(forKey: "history.direct.categoryOverrides.v1")
      model.rememberDirectConnection = true
      model.connectDirectSource(
        executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
      try await waitFor { !model.isDirectConnecting }
      try require(
        model.isDirectHistoryOpen && model.directConversations.count == 9,
        "source-and-conversations")
      try require(model.connectionPersistenceNotice == nil, "connection-saved-in-keychain")
      let vault = HistoryConnectionVault()
      guard let saved = try vault.load() else { throw RememberedConnectionError.invalidRecord }
      var syntheticSecret = saved
      syntheticSecret.secret = Data("synthetic-only-secret-never-used-for-query".utf8)
      try vault.save(syntheticSecret)
      let secretRoundtrip = try vault.load()
      try require(secretRoundtrip?.secret == syntheticSecret.secret, "keychain-secret-roundtrip")
      try vault.save(saved)
      let reopened = HistoryBrowserModel(arguments: [])
      reopened.openStartupBundleIfNeeded()
      try await waitFor { !reopened.isDirectConnecting }
      try require(
        reopened.libraryError == nil, "restart-no-error: " + (reopened.libraryError ?? "none"))
      try require(
        reopened.isDirectHistoryOpen && reopened.directConversations.count == 9
          && reopened.directSection == .chats,
        "fresh-model-auto-connect-without-input")
      reopened.closeBundle()
      var changed = saved
      changed.executableDigest = "invalid-synthetic-digest"
      try vault.save(changed)
      let invalid = HistoryBrowserModel(arguments: [])
      invalid.openStartupBundleIfNeeded()
      try require(
        !invalid.isDirectHistoryOpen && invalid.libraryError != nil,
        "changed-cli-blocked-before-query")
      try vault.save(saved)
      reopened.forgetRememberedConnection()
      let forgotten = try vault.load()
      try require(forgotten == nil, "forget-deletes-keychain-item")
      let forgottenModel = HistoryBrowserModel(arguments: [])
      forgottenModel.openStartupBundleIfNeeded()
      try require(
        !forgottenModel.isDirectHistoryOpen && !forgottenModel.isDirectConnecting,
        "forgotten-startup-stays-disconnected")
      UserDefaults.standard.set(true, forKey: "history.direct.remember")
      model.rememberDirectConnection = true
      try vault.save(saved)

      try require(
        model.directChatCategory == "personal" && model.filteredDirectConversations.count == 3,
        "personal-default-excludes-groups-and-placeholders")
      model.directChatCategory = "group"
      try require(
        model.filteredDirectConversations.map(\.id) == ["demo@chatroom"], "group-tab-filter")
      model.directChatCategory = "other"
      try require(
        Set(model.filteredDirectConversations.map(\.id))
          == Set(["cmb4008205555", "wxid_legacy_public", "notifymessage", "gh_demo"]),
        "other-tab-services-and-legacy-officials")
      model.conversationFilter = "服务通知"
      try require(
        model.filteredDirectConversations.map(\.id) == ["notifymessage"],
        "other-search-stays-in-category")
      model.conversationFilter = ""
      model.directChatCategory = "personal"
      try require(
        Set(model.filteredDirectConversations.map(\.id))
          == Set(["demo-room", "demo-human", "demo@openim"]),
        "same-name-human-and-enterprise-remain-personal")
      model.selectDirectConversation("demo-room")
      try await waitFor { !model.isLoadingDirectMessages }
      try require(model.directMessages.count == 12, "typed-json-messages")
      let emoji = model.directMessages.first { $0.id == "demo-9" }!
      let unsafeEmoji = model.directMessages.first { $0.id == "demo-10" }!
      let malformedEmoji = model.directMessages.first { $0.id == "demo-11" }!
      try require(
        emoji.displayText == "[表情]" && !emoji.displayText.contains("aeskey"),
        "emoji-never-displays-xml")
      try require(
        emoji.sticker?.previewURLs.first?.scheme == "https", "sticker-cdn-upgraded-to-https")
      try require(
        unsafeEmoji.sticker?.previewURLs.isEmpty == true
          && malformedEmoji.sticker?.previewURLs.isEmpty == true,
        "sticker-rejects-entities-and-malformed-xml")
      model.selectDirectConversation("demo-room")
      try require(
        !model.isLoadingDirectMessages && model.directMessages.count == 12,
        "recent-chat-memory-cache-immediate")

      try require(
        model.directMessages.contains { $0.isAccountHolder == true }
          && model.directMessages.contains { $0.isAccountHolder == false },
        "explicit-message-directions")
      try require(
        HistoryPresentationAssets.shared.embeddedAvatar(model.directMessages.first?.avatarBase64)
          != nil, "cached-avatar-decoded")
      guard let quote = model.directMessages.first(where: { $0.id == "demo-1" }),
        let empty = model.directMessages.first(where: { $0.id == "demo-3" }),
        let xml = model.directMessages.first(where: { $0.id == "demo-5" }),
        let image = model.directMessages.first(where: { $0.id == "demo-2" }),
        let missing = model.directMessages.first(where: { $0.id == "demo-4" })
      else {
        throw PresentationError.unavailable
      }
      try require(
        quote.content.quote?.reply == "这个方向可以，周五确认。" && quote.content.quote?.text != nil,
        "structured-quote")
      try require(
        empty.content.quote?.isEmpty == true && empty.displayText == "引用回复正文未能解析",
        "missing-quote-honest-fallback")
      try require(
        xml.content.quote?.reply == "XML 引用恢复成功" && xml.content.quote?.sender == "小周",
        "xml-quote-fallback")
      _ = try await model.previewDirectImage(image)
      try require(
        model.directImagePreviews[image.id] != nil, "image-preview-integrity-with-cli-managed-key")
      var missingRejected = false
      do { _ = try await model.previewDirectImage(missing) } catch PresentationError.unavailable {
        missingRejected = true
      }
      try require(missingRejected, "missing-image-error")
      try Data().write(to: root.appending(path: "retry-ready"))
      _ = try await model.previewDirectImage(missing)
      try require(model.directImagePreviews[missing.id] != nil, "wxgf-image-retry-and-conversion")
      try Data().write(to: root.appending(path: "bad-digest"))
      var digestRejected = false
      do { _ = try await model.previewDirectImage(image) } catch PresentationError.invalidIntegrity
      { digestRejected = true }
      try require(digestRejected, "image-bad-digest-rejected")
      try FileManager.default.removeItem(at: root.appending(path: "bad-digest"))
      guard let pdf = model.directMessages.first(where: { $0.id == "demo-7" }),
        let missingPDF = model.directMessages.first(where: { $0.id == "demo-8" })
      else { throw PresentationError.unavailable }
      try require(
        pdf.pdfFilename == "Synthetic report.PDF" && quote.pdfFilename == nil,
        "pdf-card-classification")
      let loadedPDF = try await model.previewDirectPDF(pdf)
      try require(loadedPDF.document.pageCount == 2, "pdf-cli-integrity-and-two-pages")
      try require(
        loadedPDF.document.page(at: 1)?.string?.contains("Second page") == true,
        "pdf-second-page-content")
      let loadedURL = loadedPDF.url
      loadedPDF.cleanup()
      try require(
        !FileManager.default.fileExists(atPath: loadedURL.path), "pdf-preview-copy-cleanup")
      var pdfMissing = false
      do { _ = try await model.previewDirectPDF(missingPDF) } catch PDFPreviewError.unavailable {
        pdfMissing = true
      }
      try require(pdfMissing, "pdf-missing-download-error")
      try Data().write(to: root.appending(path: "pdf-retry-ready"))
      let retriedPDF = try await model.previewDirectPDF(missingPDF)
      try require(retriedPDF.document.pageCount == 2, "pdf-missing-retry-recovers")
      retriedPDF.cleanup()
      try Data().write(to: root.appending(path: "bad-digest"))
      var pdfDigest = false
      do { _ = try await model.previewDirectPDF(pdf) } catch PresentationError.invalidIntegrity {
        pdfDigest = true
      }
      try require(pdfDigest, "pdf-bad-digest-rejected")
      try FileManager.default.removeItem(at: root.appending(path: "bad-digest"))
      try Data().write(to: root.appending(path: "pdf-corrupt"))
      var pdfCorrupt = false
      do { _ = try await model.previewDirectPDF(pdf) } catch PDFPreviewError.invalid {
        pdfCorrupt = true
      }
      try require(pdfCorrupt, "pdf-corrupt-document-rejected")
      try FileManager.default.removeItem(at: root.appending(path: "pdf-corrupt"))
      let assets = HistoryPresentationAssets.shared
      try assets.importAvatar(
        from: root.appending(path: "sample.png"), source: "synthetic-presentation-v1",
        person: "demo-lin")
      let reopenedAssets = HistoryPresentationAssets()
      try require(
        reopenedAssets.avatar(source: "synthetic-presentation-v1", person: "demo-lin") != nil,
        "avatar-persisted")
      try require(
        reopenedAssets.avatar(source: "different-synthetic-source", person: "demo-lin") == nil,
        "avatar-source-isolation")
      let corrupt = root.appending(path: "not-an-image.txt")
      try Data("synthetic non-image".utf8).write(to: corrupt)
      var corruptRejected = false
      do {
        try assets.importAvatar(
          from: corrupt, source: "synthetic-presentation-v1", person: "demo-lin")
      } catch PresentationError.invalidImage { corruptRejected = true }
      try require(
        corruptRejected
          && assets.avatar(source: "synthetic-presentation-v1", person: "demo-lin") != nil,
        "bad-avatar-preserves-existing")
      let content = VStack(alignment: .leading, spacing: 16) {
        Text("GreenBubbles · 离线验收").font(.title.bold())
        Text("仅使用合成消息和应用图标，未连接微信").foregroundStyle(.secondary)
        ForEach(Array(model.directMessages.reversed())) { message in
          HistoryDirectMessageBubble(model: model, message: message, highlighted: false)
        }
      }.padding(28).frame(width: 920).background(Color(nsColor: .windowBackgroundColor))
      let renderer = ImageRenderer(content: content)
      renderer.scale = 1.5
      guard let rendered = renderer.nsImage, let tiff = rendered.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else {
        throw PresentationError.invalidImage
      }
      try png.write(to: root.appending(path: "presentation.png"))
      try require(true, "native-swiftui-render")
      // Repeat the production bubble render in both appearances using synthetic data only.
      for (name, scheme, appearanceName) in [
        ("light", ColorScheme.light, NSAppearance.Name.aqua),
        ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua),
      ] {
        let appearance = NSAppearance(named: appearanceName)!
        var imageData: Data?
        appearance.performAsCurrentDrawingAppearance {
          let themed = HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
              Text("聊天").font(.title2.bold())
              Text("合成会话").font(.headline)
              Text("仅用于配色验收").foregroundStyle(.secondary)
              Spacer()
            }.padding(20).frame(width: 220).frame(maxHeight: .infinity)
              .background(HistoryChatPalette.sidebar)
            VStack(alignment: .leading, spacing: 16) {
              Text("明暗配色 · 合成消息").font(.title2.bold())
              ForEach(Array(model.directMessages.reversed())) { message in
                HistoryDirectMessageBubble(model: model, message: message, highlighted: false)
              }
            }.padding(24).frame(width: 820).background(HistoryChatPalette.timeline)
          }.fixedSize().environment(\.colorScheme, scheme)
          let themedRenderer = ImageRenderer(content: themed)
          themedRenderer.scale = 1
          if let image = themedRenderer.nsImage, let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
          {
            imageData = bitmap.representation(using: .png, properties: [:])
          }
        }
        try require(imageData != nil, "native-\(name)-palette-render")
        try imageData?.write(to: root.appending(path: "presentation-\(name).png"))
      }

      model.returnToLatestDirectMessages()
      try await waitFor { !model.isLoadingDirectMessages }
      try require(model.directMessages.count == 12, "refresh-restores-message-page")
      let personal = model.directConversations.first { $0.id == "demo-room" }!
      let group = model.directConversations.first { $0.id == "demo@chatroom" }!
      let official = model.directConversations.first { $0.id == "cmb4008205555" }!
      model.moveDirectConversation(personal, toOther: true)
      try require(
        model.directCategory(for: personal) == "other" && model.directSelectedConversationID == nil,
        "move-personal-clears-selection")
      model.moveDirectConversation(group, toOther: true)
      try require(model.directCategory(for: group) == "other", "move-group-to-other")
      model.moveDirectConversation(group, toOther: false)
      try require(model.directCategory(for: group) == "group", "move-group-back")
      model.moveDirectConversation(official, toOther: false)
      try require(model.directCategory(for: official) == "personal", "move-automatic-official-out")
      let persisted = HistoryBrowserModel(arguments: [])
      persisted.directSourcePath = model.directSourcePath
      try require(
        persisted.directCategory(for: personal) == "other"
          && persisted.directCategory(for: official) == "personal", "manual-moves-persisted")
      persisted.directSourcePath = "/synthetic-another-account"
      try require(
        persisted.directCategory(for: personal) == "personal"
          && persisted.directCategory(for: official) == "other", "manual-moves-source-isolated")
      model.restoreDirectCategory(official)
      try require(
        model.directCategory(for: official) == "other"
          && !model.hasDirectCategoryOverride(official), "restore-automatic-category")
      model.moveDirectConversation(personal, toOther: false)
      try require(model.directCategory(for: personal) == "personal", "move-personal-back")
      model.moveDirectConversation(group, toOther: true)

    } catch { failure = error.localizedDescription }
    let report: [String: Any] = [
      "schema": "greenbubbles.offline-presentation-acceptance.v1",
      "checks": checks, "passed": failure == nil, "error": failure ?? "",
      "source": "synthetic-only", "wechatRead": false,
      "uiInteraction":
        "Production SwiftUI rendered in-process; native interactions recorded separately",
      "timestamp": ISO8601DateFormatter().string(from: Date()),
    ]
    if let data = try? JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    {
      try? data.write(to: reportURL)
    }
  }
#endif
