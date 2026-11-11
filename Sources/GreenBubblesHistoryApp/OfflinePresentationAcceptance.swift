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
    if FileManager.default.fileExists(atPath: root.appending(path: "ai-blacklist-acceptance").path)
    {
      model.rememberDirectConnection = false
      model.connectDirectSource(
        executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
      do {
        try await waitFor { !model.isDirectConnecting && !model.directConversations.isEmpty }
        model.showsDirectConnection = true
      } catch {
        try? Data("Synthetic blacklist setup failed".utf8).write(to: reportURL)
      }
      return
    }
    var failure: String?
    if FileManager.default.fileExists(
      atPath: root.appending(path: "cache-reconciliation-acceptance").path)
    {
      func stage(_ value: Int) throws {
        try Data(String(value).utf8).write(to: root.appending(path: "reconcile-stage"))
      }
      func captureWindow(_ name: String) throws {
        let sample = model.directMessages.filter { message in
          (56...66).map { "reconcile-\($0)" }.contains(message.id)
        }.reversed()
        let view = VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(sample)) { message in
            HistoryDirectMessageBubble(model: model, message: message, highlighted: false)
          }
        }.padding(18).frame(width: 820).background(HistoryChatPalette.timeline)
        let renderer = ImageRenderer(content: view)
        guard let tiff = renderer.nsImage?.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
        else { throw PresentationError.invalidImage }
        try png.write(to: root.appending(path: "cache-\(name).png"))
      }
      do {
        model.rememberDirectConnection = true
        model.conversationRange = .all
        try stage(0)
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitFor { !model.isDirectConnecting && !model.isPreloadingRecentConversations }
        model.selectDirectConversation("reconcile-a")
        try await waitFor { !model.isLoadingDirectMessages }
        model.loadOlderDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        let originalIDs = Set(model.directMessages.map(\.id))
        try require(originalIDs.count == 80, "initial-eighty-messages")
        try captureWindow("before")
        let catalog = model.directConversations
        try stage(1)
        model.refreshDirectHistory()
        try await waitFor {
          !model.isLoadingDirectMessages && !model.isRefreshingDirectConversations
        }
        try require(model.directConversations == catalog, "deletion-keeps-catalog-summary-and-date")
        try captureWindow("after")
        try require(
          !model.directMessages.contains { $0.id == "reconcile-60" },
          "removed-history-message-disappears")
        try require(
          originalIDs.subtracting(["reconcile-60"]).isSubset(
            of: Set(model.directMessages.map(\.id))), "unremoved-history-preserved")
        try require(
          model.directMessages.first { $0.id == "reconcile-5" }?.displayText
            == "Synthetic revoked replacement", "revoked-body-replaced")
        model.selectDirectConversation("reconcile-b")
        try await waitFor { !model.isLoadingDirectMessages }
        model.loadOlderDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        model.selectDirectConversation("reconcile-a")
        try await waitFor { !model.isLoadingDirectMessages }
        try require(
          !model.directMessages.contains { $0.id == "reconcile-60" },
          "switch-cannot-resurrect-removed-message")
        try stage(6)
        try Data("Synthetic older-message deletion, catalog unchanged".utf8).write(
          to: root.appending(path: "session/session.db-wal"))
        for _ in 0..<1800 {
          if !model.directMessages.contains(where: { $0.id == "reconcile-65" }) { break }
          try await Task.sleep(for: .milliseconds(50))
        }
        try require(
          !model.directMessages.contains { $0.id == "reconcile-65" },
          "file-change-reconciles-unchanged-catalog")
        model.selectDirectConversation("reconcile-b")
        try await waitFor { !model.isLoadingDirectMessages }
        try require(
          !model.directMessages.contains { $0.id == "reconcile-65" },
          "invalidated-unopened-cache-verifies-on-selection")
        model.selectDirectConversation("reconcile-a")
        try await waitFor { !model.isLoadingDirectMessages }
        await model.flushHistoryCache()
        model.closeBundle()
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitFor { !model.directConversations.isEmpty }
        model.selectDirectConversation("reconcile-a")
        try require(
          !model.directMessages.isEmpty, "restart-restores-readable-cache-before-verification")
        try await waitFor { !model.isDirectConnecting && !model.isLoadingDirectMessages }
        try require(
          !model.directMessages.contains { $0.id == "reconcile-60" || $0.id == "reconcile-65" },
          "restart-revalidates-deleted-records")
        let beforePartial = model.directMessages
        try stage(4)
        model.refreshDirectHistory()
        try await waitFor {
          !model.isLoadingDirectMessages && !model.isRefreshingDirectConversations
        }
        try require(
          model.directMessages == beforePartial, "partial-coverage-keeps-readable-content")
        try Data().write(to: root.appending(path: "reconcile-fail"))
        model.refreshDirectHistory()
        try await waitFor { !model.isLoadingDirectMessages }
        try require(model.directMessages == beforePartial, "failure-keeps-readable-content")
        try FileManager.default.removeItem(at: root.appending(path: "reconcile-fail"))
        try stage(7)
        model.refreshDirectConversations(reloadAll: true)
        try await waitFor {
          !model.isRefreshingDirectConversations && !model.isLoadingDirectConversations
            && model.directConversationCursor == nil
        }
        try require(
          model.directSelectedConversationID == "reconcile-a"
            && model.directConversations.contains { $0.id == "reconcile-a" }
            && model.directMessages == beforePartial,
          "partial-first-catalog-page-cannot-remove-selection")
        try stage(2)
        model.refreshDirectHistory()
        try await waitFor {
          !model.isLoadingDirectMessages && !model.isRefreshingDirectConversations
        }
        try require(
          model.directMessages.isEmpty && model.directMessageCursor == nil,
          "complete-empty-source-clears-timeline")
        await model.flushHistoryCache()
        model.closeBundle()
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitFor { !model.directConversations.isEmpty }
        model.selectDirectConversation("reconcile-a")
        try await waitFor { !model.isDirectConnecting && !model.isLoadingDirectMessages }
        try require(model.directMessages.isEmpty, "restart-cannot-resurrect-cleared-source")
        try stage(3)
        model.refreshDirectConversations(reloadAll: true)
        try await waitFor {
          !model.isRefreshingDirectConversations && !model.isLoadingDirectConversations
        }
        try require(
          model.directSelectedConversationID == nil && model.directMessages.isEmpty,
          "removed-conversation-clears-selection")
        await model.flushHistoryCache()
        model.closeBundle()
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [], restoring: true)
        model.closeBundle()
        try await Task.sleep(for: .milliseconds(100))
        try require(
          model.directConfiguration == nil && model.directConversations.isEmpty
            && model.directMessages.isEmpty, "cancelled-cache-hydration-cannot-reopen-source")
      } catch { failure = error.localizedDescription }
      let report: [String: Any] = [
        "checks": checks, "passed": failure == nil, "error": failure ?? "",
        "source": "synthetic-only", "wechatRead": false,
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: root.appending(path: "cache-reconciliation-acceptance.json"))
      }
      return
    }
    if FileManager.default.fileExists(
      atPath: root.appending(path: "conversation-refresh-acceptance").path)
    {
      func waitForRefresh(_ ready: @escaping () -> Bool) async throws {
        for _ in 0..<2400 {
          if ready() { return }
          try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(
          domain: "OfflineAcceptance", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Conversation refresh timed out"])
      }
      func stage(_ value: Int, replaceWAL: Bool = false) throws {
        try Data(String(value).utf8).write(to: root.appending(path: "conversation-refresh-stage"))
        try Data("Synthetic WAL stage \(value) \(UUID().uuidString)".utf8).write(
          to: root.appending(path: "session/session.db-wal"), options: replaceWAL ? .atomic : [])
      }
      func catalogReadCount() throws -> Int {
        let text = try String(contentsOf: root.appending(path: "requests.jsonl"), encoding: .utf8)
        return text.split(separator: "\n").filter { $0.contains("conversations.list") }.count
      }
      func catalogReadTimes() throws -> [Double] {
        let text = try String(contentsOf: root.appending(path: "requests.jsonl"), encoding: .utf8)
        return try text.split(separator: "\n").compactMap { line in
          let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
          return value?["operation"] as? String == "conversations.list"
            ? value?["observedAtUnixSeconds"] as? Double : nil
        }
      }
      func captureTimestampWindow(_ name: String) throws {
        guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { throw PresentationError.invalidImage }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
          throw PresentationError.invalidImage
        }
        try png.write(to: root.appending(path: "conversation-timestamp-\(name).png"))
      }
      do {
        model.rememberDirectConnection = false
        model.conversationRange = .month
        try FileManager.default.createDirectory(
          at: root.appending(path: "session"), withIntermediateDirectories: true)
        try Data("Synthetic database event fixture".utf8).write(
          to: root.appending(path: "session/session.db"))
        try Data(String(Int(Date().timeIntervalSince1970)).utf8).write(
          to: root.appending(path: "conversation-refresh-clock"))
        try stage(0)
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitForRefresh {
          !model.isDirectConnecting && model.directConversationCursor == nil
            && !model.isLoadingDirectConversations
        }
        try require(model.directConversations.count == 230, "initial-full-catalog")
        try require(model.isMonitoringDirectConversationChanges, "file-monitor-attached")
        let quietReadCount = try catalogReadCount()
        let initialQueryTime = try catalogReadTimes().suffix(3).first!
        try Data("Synthetic shared memory".utf8).write(
          to: root.appending(path: "session/session.db-shm"))
        try await Task.sleep(for: .seconds(20))
        try require(try catalogReadCount() == quietReadCount, "idle-source-does-not-poll")
        try require(try catalogReadCount() == quietReadCount, "shared-memory-noise-does-not-query")
        model.selectDirectConversation("demo-room")
        try await waitFor { !model.isLoadingDirectMessages }
        model.loadOlderDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        let historyIDs = model.directMessages.map(\.id)
        let historyCursor = model.directMessageCursor
        try require(historyIDs.count == 80, "history-loaded-before-refresh")
        model.conversationFilter = "Synthetic"
        let existingRowDate = model.directConversations.first { $0.id == "demo-room" }!.sortDate!
        try await Task.sleep(for: .milliseconds(200))
        try captureTimestampWindow("before")
        let oldTime = model.directConversations.first { $0.id == "synthetic-229" }!.sortTimestamp
        model.setDirectConversationMonitoringActive(false)
        try stage(1, replaceWAL: true)
        try stage(1)
        try stage(1)
        try await Task.sleep(for: .seconds(5))
        try require(try catalogReadCount() == quietReadCount, "inactive-scene-retains-throttle")
        model.setDirectConversationMonitoringActive(true)
        // Real filesystem notifications must trigger a throttled read, without a button call.
        try await waitForRefresh {
          model.directConversations.first?.summary == "Synthetic refreshed stage 1"
        }
        try require(model.directConversations.count == 231, "automatic-refresh-discovers-new-chat")
        try require(
          model.directConversations.first?.id == "synthetic-229"
            && model.directConversations.first!.sortTimestamp > oldTime,
          "automatic-refresh-updates-time-summary-and-order")
        try require(
          model.directConversations.contains { $0.id == "synthetic-200" },
          "bounded-refresh-keeps-catalog-tail")
        try require(
          model.directSelectedConversationID == "demo-room"
            && model.directMessages.map(\.id) == historyIDs
            && model.directMessageCursor == historyCursor,
          "automatic-refresh-keeps-selection-and-history")
        try require(
          model.conversationFilter == "Synthetic" && model.directChatCategory == "personal"
            && model.conversationRange == .month,
          "automatic-refresh-keeps-filters")
        try require(
          try catalogReadCount() == quietReadCount + 1, "event-burst-coalesces-to-one-read")
        try require(
          try catalogReadTimes().last! - initialQueryTime >= 59,
          "automatic-query-minimum-sixty-second-gap")
        try require(
          model.directConversations.first?.summary == "Synthetic refreshed stage 1",
          "wal-replacement-still-delivers-changes")
        let updatedRowDate = model.directConversations.first { $0.id == "demo-room" }!.sortDate!
        try require(
          updatedRowDate.timeIntervalSince(existingRowDate) == 60,
          "existing-row-timestamp-advances-one-minute")
        try await Task.sleep(for: .milliseconds(200))
        try captureTimestampWindow("after")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let evidence = [
          "source": "synthetic-only", "row": "Synthetic conversation 0",
          "expectedBefore": formatter.string(from: existingRowDate),
          "expectedAfter": formatter.string(from: updatedRowDate),
          "categorySwitch": "none",
        ]
        try JSONSerialization.data(
          withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]
        )
        .write(to: root.appending(path: "conversation-timestamp-evidence.json"))
        try stage(1)
        try await Task.sleep(for: .seconds(5))
        try require(
          try catalogReadCount() == quietReadCount + 1, "automatic-read-cooldown-enforced")
        let oldCatalog = model.directConversations
        try Data().write(to: root.appending(path: "conversation-refresh-fail"))
        model.refreshDirectConversations()
        try await waitForRefresh { !model.isRefreshingDirectConversations }
        try require(
          model.directConversationError != nil && model.directConversations == oldCatalog,
          "refresh-failure-keeps-readable-catalog")
        model.refreshDirectConversationsIfNeeded()
        try require(!model.isRefreshingDirectConversations, "automatic-error-does-not-retry")
        try FileManager.default.removeItem(at: root.appending(path: "conversation-refresh-fail"))
        try stage(2)
        model.refreshDirectHistory()
        try await waitForRefresh {
          !model.isRefreshingDirectConversations && !model.isLoadingDirectConversations
            && model.directConversationCursor == nil && !model.isLoadingDirectMessages
        }
        try require(
          model.directConversations.first?.summary == "Synthetic refreshed stage 2"
            && model.directConversationError == nil,
          "manual-refresh-retries-catalog-and-updates-summary")
        try require(
          model.directConversations.count == 230
            && !model.directConversations.contains { $0.id == "synthetic-100" },
          "complete-manual-refresh-reconciles-deletion")
        try require(
          model.directMessages.map(\.id) == historyIDs
            && model.directMessageCursor == historyCursor,
          "manual-refresh-keeps-contiguous-history")
        try Data().write(to: root.appending(path: "conversation-refresh-slow"))
        try stage(3)
        model.refreshDirectConversations()
        model.refreshDirectHistory()
        try await waitForRefresh {
          !model.isRefreshingDirectConversations && !model.isLoadingDirectConversations
            && model.directConversationCursor == nil && !model.isLoadingDirectMessages
        }
        try require(
          !model.directConversations.contains { $0.id == "synthetic-200" }
            && model.directConversations.count == 229,
          "manual-during-automatic-refresh-still-reconciles-full-catalog")
        try stage(4)
        model.refreshDirectConversations()
        try await Task.sleep(for: .milliseconds(150))
        model.closeBundle()
        try require(
          !model.isRefreshingDirectConversations && model.directConversations.isEmpty,
          "disconnect-cancels-refresh")
        try stage(5)
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitForRefresh {
          !model.isDirectConnecting && model.directConversationCursor == nil
            && !model.isLoadingDirectConversations
        }
        try require(
          model.directConversations.first?.summary == "Synthetic refreshed stage 5",
          "cancelled-refresh-cannot-overwrite-new-connection")
        try FileManager.default.removeItem(at: root.appending(path: "conversation-refresh-slow"))
        model.conversationFilter = ""
        model.directChatCategory = "group"
        model.selectDirectConversation("synthetic-new@chatroom")
        try await waitFor { !model.isLoadingDirectMessages }
      } catch { failure = error.localizedDescription }
      let report: [String: Any] = [
        "checks": checks, "passed": failure == nil, "error": failure ?? "",
        "source": "synthetic-only", "wechatRead": false,
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: root.appending(path: "conversation-refresh-acceptance.json"))
      }
      return
    }
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
    if FileManager.default.fileExists(atPath: root.appending(path: "body-refresh-acceptance").path)
    {
      func bodyStage(_ value: Int) throws {
        try Data(String(value).utf8).write(to: root.appending(path: "body-stage"))
        try Data("Synthetic body stage \(value)".utf8).write(
          to: root.appending(path: "session/session.db-wal"))
      }
      func waitBody(_ ready: @escaping () -> Bool) async throws {
        for _ in 0..<2400 {
          if ready() { return }
          try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "BodyRefreshAcceptance", code: 1)
      }
      do {
        model.rememberDirectConnection = false
        model.conversationRange = .all
        try bodyStage(0)
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitBody { !model.isDirectConnecting && !model.isPreloadingRecentConversations }
        model.selectDirectConversation("body-a")
        try await waitFor { !model.isLoadingDirectMessages }
        model.loadOlderDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        let cursor = model.directMessageCursor
        let oldIDs = Set(model.directMessages.map(\.id))
        try require(oldIDs.count == 80, "initial-history-loaded")
        model.setDirectConversationMonitoringActive(false)
        try bodyStage(1)
        try await waitBody { model.directMessages.first?.id == "cache--1" }
        try require(
          oldIDs.isSubset(of: Set(model.directMessages.map(\.id))), "automatic-update-keeps-history"
        )
        try require(model.directMessageCursor == cursor, "automatic-update-keeps-cursor")
        try require(
          model.directSelectedConversationID == "body-a", "background-update-keeps-selection")
        // Let the second bounded body query finish, then inspect its synchronous cache hit.
        try await Task.sleep(for: .seconds(2))
        model.selectDirectConversation("body-b")
        try require(
          model.directMessages.first?.id == "cache--1" && !model.isLoadingDirectMessages,
          "unopened-chat-cache-updated")
        model.selectDirectConversation("body-a")
        try require(model.directMessages.count == 81, "switch-restores-contiguous-history")
        model.directTimelineFollowingLatest = false
        try bodyStage(100)
        model.refreshDirectConversations()
        try await waitBody { model.directConversations.first?.summary == "Body stage 100" }
        try await Task.sleep(for: .seconds(2))
        try require(
          model.directMessages.first?.id == "cache--1", "disjoint-refresh-keeps-reading-page")
        model.returnToLatestDirectMessages()
        try await waitFor { !model.isLoadingDirectMessages }
        try require(model.directMessages.first?.id == "cache--100", "explicit-latest-resolves-gap")
        let beforeFailure = model.directMessages.map(\.id)
        try Data().write(to: root.appending(path: "warm-fail"))
        try bodyStage(101)
        model.refreshDirectConversations()
        try await Task.sleep(for: .seconds(3))
        try require(
          model.directMessages.map(\.id) == beforeFailure, "failure-keeps-readable-content")
        try FileManager.default.removeItem(at: root.appending(path: "warm-fail"))
        model.refreshDirectHistory()
        try await waitFor { !model.isLoadingDirectMessages }
        try require(model.directMessages.first?.id == "cache--101", "manual-refresh-recovers")
        try Data().write(to: root.appending(path: "warm-slow"))
        try bodyStage(102)
        model.refreshDirectConversations()
        try await Task.sleep(for: .milliseconds(200))
        model.closeBundle()
        try await Task.sleep(for: .seconds(1))
        try require(
          model.directMessages.isEmpty && model.directConfiguration == nil,
          "disconnect-rejects-late-result")
        try FileManager.default.removeItem(at: root.appending(path: "warm-slow"))
        // Leave a connected synthetic window for native scroll acceptance.
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitBody { !model.isDirectConnecting && !model.isPreloadingRecentConversations }
        model.selectDirectConversation("body-a")
      } catch { failure = error.localizedDescription }
      let report: [String: Any] = [
        "checks": checks, "passed": failure == nil,
        "error": failure ?? "", "source": "synthetic-only", "wechatRead": false,
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: root.appending(path: "body-refresh-acceptance.json"))
      }
      return
    }
    if FileManager.default.fileExists(atPath: root.appending(path: "preload-acceptance").path) {
      var heartbeatTicks = 0
      var maximumHeartbeatGap = 0.0
      let heartbeat = Task { @MainActor in
        var previous = ContinuousClock.now
        while !Task.isCancelled {
          do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
          let now = ContinuousClock.now
          let gap = previous.duration(to: now).components
          maximumHeartbeatGap = max(
            maximumHeartbeatGap, Double(gap.seconds) + Double(gap.attoseconds) / 1e18)
          heartbeatTicks += 1
          previous = now
        }
      }
      defer { heartbeat.cancel() }
      func waitForWarm(_ ready: @escaping () -> Bool) async throws {
        for _ in 0..<2400 {
          if ready() { return }
          try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "PreloadAcceptance", code: 1)
      }
      func requests() throws -> [[String: Any]] {
        let url = root.appending(path: "requests.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n").map {
          try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
      }
      do {
        model.rememberDirectConnection = false
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitForWarm {
          !model.isDirectConnecting && model.directConversationCursor == nil
            && !model.isLoadingDirectConversations && !model.isPreloadingRecentConversations
        }
        let records = try requests()
        let warmReads = records.filter { $0["operation"] as? String == "messages.list" }
        let expected = Set(
          (0..<100).map { "warm-personal-\($0)" }
            + (0..<50).map { "warm-group-\($0)@chatroom" })
        try require(
          Set(warmReads.compactMap { $0["conversation"] as? String }) == expected,
          "exact-latest-100-personal-50-groups")
        try require(warmReads.count == 150, "one-read-per-warm-conversation")
        try require(
          Set(warmReads.prefix(2).compactMap { $0["conversation"] as? String })
            == Set(["warm-personal-0", "warm-group-0@chatroom"]),
          "most-recent-personal-and-group-warm-first")
        try require(
          warmReads.allSatisfy { $0["limit"] as? String == "40" }, "forty-bodies-per-page")
        try require(
          !records.contains { ($0["operation"] as? String ?? "").hasPrefix("attachment.") },
          "no-background-attachments")
        try require(model.directSelectedConversationID == nil, "warming-does-not-select-chat")
        for id in expected.sorted() {
          model.selectDirectConversation(id)
          try require(
            model.directMessages.count == 40 && !model.isLoadingDirectMessages,
            "immediate-cache-hit-\(id)")
          try require(model.directMessages.allSatisfy { $0.conversationID == id }, "isolated-\(id)")
        }
        model.selectDirectConversation("warm-personal-0")
        model.loadOlderDirectMessages()
        try await waitForWarm { !model.isLoadingDirectMessages }
        try require(
          model.directMessages.count == 80 && model.directMessageCursor == "80",
          "history-cursor-after-warming")
        model.selectDirectConversation("warm-group-0@chatroom")
        model.selectDirectConversation("warm-personal-0")
        try require(model.directMessages.count == 80, "warm-switch-keeps-history")
        model.closeBundle()
        try Data().write(to: root.appending(path: "warm-fail"))
        let beforeFail = try requests().filter { $0["operation"] as? String == "messages.list" }
          .count
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitForWarm {
          !model.isDirectConnecting && model.directConversationCursor == nil
            && !model.isLoadingDirectConversations && !model.isPreloadingRecentConversations
        }
        try await Task.sleep(for: .milliseconds(400))
        let afterFail = try requests().filter { $0["operation"] as? String == "messages.list" }
          .count
        try require(afterFail - beforeFail == 1, "warm-failure-stops-without-retry")
        try require(
          model.directConversationError == nil && model.directMessageError == nil,
          "warm-error-does-not-poison-ui")
        try FileManager.default.removeItem(at: root.appending(path: "warm-fail"))
        model.closeBundle()
        model.rememberDirectConnection = true
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitForWarm {
          !model.isDirectConnecting && model.directConversationCursor == nil
            && !model.isLoadingDirectConversations && !model.isPreloadingRecentConversations
        }
        let config = model.directConfiguration!
        await model.flushHistoryCache()
        let cache = HistoryPersistentCache(configuration: config, secret: [], enabled: true)!
        try require(
          try Data(contentsOf: cache.url).range(of: Data("Synthetic cache message".utf8)) == nil,
          "warmed-cache-encrypted")
        model.closeBundle()
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitForWarm { !model.directConversations.isEmpty }
        model.selectDirectConversation("warm-group-49@chatroom")
        try require(
          model.directMessages.count == 40 && model.directMessageCursor == "40",
          "restart-restores-warmed-pages-before-query")
        // An older disk snapshot may refresh in the background while remaining readable.
        try await waitForWarm { !model.isLoadingDirectMessages }
        try require(
          model.directMessages.first?.avatarBase64
            == (try Data(contentsOf: root.appending(path: "sample.png"))).base64EncodedString(),
          "avatar-pool-restores-message-avatar")

        model.closeBundle()
        try Data().write(to: root.appending(path: "warm-slow"))
        model.rememberDirectConnection = false
        model.connectDirectSource(
          executableURL: cli, sourceURL: root, accessMode: .decrypted, keyUTF8: [])
        try await waitForWarm { model.isPreloadingRecentConversations }
        model.closeBundle()
        try await Task.sleep(for: .milliseconds(600))
        try require(
          !model.isPreloadingRecentConversations && model.directMessages.isEmpty
            && model.directConfiguration == nil,
          "close-cancels-warm-and-clears-source")
        try FileManager.default.removeItem(at: root.appending(path: "warm-slow"))
        try require(heartbeatTicks > 100, "main-actor-heartbeat-observed")
        try require(maximumHeartbeatGap < 0.5, "main-actor-gap-under-500ms")
      } catch { failure = error.localizedDescription }
      let report: [String: Any] = [
        "checks": checks, "passed": failure == nil,
        "error": failure ?? "", "source": "synthetic-only", "wechatRead": false,
        "heartbeatTicks": heartbeatTicks,
        "maximumMainActorGapMilliseconds": maximumHeartbeatGap * 1000,
        "keychainAccess": false,
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: root.appending(path: "preload-acceptance.json"))
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
        await model.flushHistoryCache()
        let encrypted = try Data(contentsOf: disk.url)
        try require(
          encrypted.range(of: Data("Synthetic cache message".utf8)) == nil,
          "disk-has-no-plaintext-chat")
        model.closeBundle()
        try Data().write(to: root.appending(path: "slow-source-status"))
        try? FileManager.default.removeItem(at: root.appending(path: "status-entered"))
        model.connectDirectSource(
          executableURL: cli, sourceURL: root,
          accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitFor { !model.directConversations.isEmpty }
        try require(
          model.directConversations.count == 230 && model.isDirectConnecting,
          "reconnect-restores-full-list-before-live-query")
        model.selectDirectConversation("demo-room")
        try require(
          model.directMessages.count == 80 && model.directMessageCursor == "80",
          "reconnect-restores-history-and-cursor")
        try await waitFor { !model.isDirectConnecting && model.directConversationCursor == nil }
        model.closeBundle()
        await model.flushHistoryCache()
        try Data("corrupt".utf8).write(to: disk.url)
        try? FileManager.default.removeItem(at: root.appending(path: "status-entered"))
        model.connectDirectSource(
          executableURL: cli, sourceURL: root,
          accessMode: .decrypted, keyUTF8: [], restoring: true)
        try await waitFor {
          FileManager.default.fileExists(atPath: root.appending(path: "status-entered").path)
        }
        try require(
          model.directConversations.isEmpty && model.isDirectConnecting, "corrupt-cache-is-ignored")
        try FileManager.default.removeItem(at: root.appending(path: "slow-source-status"))
        try await waitFor { !model.isDirectConnecting && model.directConversationCursor == nil }
        try require(model.directConversations.count == 230, "corrupt-cache-rebuilt-from-source")
        await model.flushHistoryCache()
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
      try require(model.directMessages.count == 15, "typed-json-messages")
      let merged = model.directMessages.first { $0.id == "demo-12" }!.content.mergedRecord!
      try require(
        merged.entries.count == 4 && merged.entries[0].text == "第一条 & 完整正文"
          && merged.entries[0].sender == "合成甲" && merged.entries[1].text == "[图片]",
        "merged-record-ordered-text-and-media")
      try require(
        model.directMessages.filter { ["demo-13", "demo-14"].contains($0.id) }
          .allSatisfy { $0.content.mergedRecord?.entries.isEmpty == true },
        "merged-record-malformed-and-entity-safe")
      let mergedImage = try await model.previewDirectImage(
        model.directMessages.first { $0.id == "demo-12" }!, mergedIndex: 1)
      try require(
        mergedImage.size.width > 0 && mergedImage.size.height > 0,
        "merged-image-production-load-and-decode")
      let mergedPDF = try await model.previewDirectPDF(
        model.directMessages.first { $0.id == "demo-12" }!, mergedIndex: 2)
      try require(
        merged.entries[2].filename == "Forwarded report.PDF"
          && mergedPDF.document.pageCount == 2, "merged-file-card-and-pdf-two-pages")
      mergedPDF.cleanup()
      let mergedFileURL = try await model.materializeDirectDocument(
        model.directMessages.first { $0.id == "demo-12" }!, mergedIndex: 3)
      try require(
        FileManager.default.fileExists(atPath: mergedFileURL.path), "merged-file-materialization")
      try FileManager.default.removeItem(at: mergedFileURL)
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
        !model.isLoadingDirectMessages && model.directMessages.count == 15,
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
        Text("\(HistoryBrand.name) · 离线验收").font(.title.bold())
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
      try require(model.directMessages.count == 15, "refresh-restores-message-page")
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
