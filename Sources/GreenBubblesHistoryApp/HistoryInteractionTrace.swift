import AppKit
import Foundation
import SwiftUI

/// Opt-in, bounded and content-free. Never records connection or message identifiers.
@MainActor
final class HistoryInteractionTrace {
  static let shared = HistoryInteractionTrace()
  static let preference = "history.interactionDiagnostics"
  private let enabled = UserDefaults.standard.bool(forKey: preference)
  var isEnabled: Bool { enabled }
  private let writer = DispatchQueue(label: "me.greenbubbles.interaction-trace", qos: .utility)
  private var timer: Timer?
  private var monitor: Any?
  private var previousTick = ProcessInfo.processInfo.systemUptime
  private var sequence = 0
  private var pendingSwitch: (id: String, started: Double)?
  private var pendingScroll: Double?
  private let started = ProcessInfo.processInfo.systemUptime

  struct Record: Encodable, Sendable {
    let kind: String
    let sequence: Int
    let sinceStartMs: Double
    let elapsedMs: Double
    let count: Int?
    let cacheHit: Bool?
  }

  func start() {
    guard enabled, timer == nil else { return }
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: Bundle.main.bundleIdentifier ?? "me.greenbubbles.GreenBubbles")
      .appending(path: "Diagnostics/interaction-latest.jsonl")
    writer.async {
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      FileManager.default.createFile(
        atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }
    previousTick = ProcessInfo.processInfo.systemUptime
    timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = (now - self.previousTick) * 1000
        self.previousTick = now
        if elapsed > 50 { self.record("main-thread-gap", elapsedMs: elapsed) }
      }
    }
    RunLoop.main.add(timer!, forMode: .common)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
      MainActor.assumeIsolated {
        self?.pendingScroll = event.timestamp
        self?.record(
          "scroll-delivery",
          elapsedMs: max(0, (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000))
        let stamp = event.timestamp
        // A wheel at the boundary may never change bounds. Do not match it to a later layout.
        DispatchQueue.main.async { [weak self] in
          if self?.pendingScroll == stamp { self?.pendingScroll = nil }
        }
      }
      return event
    }
  }

  func beginSwitch(_ id: String, cacheHit: Bool) {
    guard enabled else { return }
    let now = ProcessInfo.processInfo.systemUptime
    pendingSwitch = (id, now)
    record("switch-handler", elapsedMs: 0, cacheHit: cacheHit)
  }

  func timelineLaidOut(_ id: String, count: Int, loading: Bool) {
    guard enabled, let pending = pendingSwitch, pending.id == id, count > 0 || !loading else {
      return
    }
    pendingSwitch = nil
    record(
      "switch-layout", elapsedMs: (ProcessInfo.processInfo.systemUptime - pending.started) * 1000,
      count: count)
  }

  func scrollBoundsChanged() {
    guard enabled, let began = pendingScroll else { return }
    pendingScroll = nil
    record(
      "scroll-bounds", elapsedMs: max(0, (ProcessInfo.processInfo.systemUptime - began) * 1000))
  }

  func queryFinished(startedAt: Double, count: Int) {
    guard enabled else { return }
    record(
      "message-query", elapsedMs: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000,
      count: count)
  }

  private func record(_ kind: String, elapsedMs: Double, count: Int? = nil, cacheHit: Bool? = nil) {
    guard enabled, sequence < 2_000 else { return }
    sequence += 1
    let record = Record(
      kind: kind, sequence: sequence,
      sinceStartMs: (ProcessInfo.processInfo.systemUptime - started) * 1000,
      elapsedMs: elapsedMs, count: count, cacheHit: cacheHit)
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: Bundle.main.bundleIdentifier ?? "me.greenbubbles.GreenBubbles")
      .appending(path: "Diagnostics/interaction-latest.jsonl")
    writer.async {
      guard var data = try? JSONEncoder().encode(record),
        let file = try? FileHandle(forWritingTo: url)
      else { return }
      defer { try? file.close() }
      data.append(10)
      _ = try? file.seekToEnd()
      try? file.write(contentsOf: data)
    }
  }
}

struct HistoryTimelineLayoutTrace: NSViewRepresentable {
  let conversationID: String
  let messageCount: Int
  let loading: Bool

  func makeNSView(context: Context) -> Probe { Probe() }
  func updateNSView(_ view: Probe, context: Context) {
    view.didLayout = {
      HistoryInteractionTrace.shared.timelineLaidOut(
        conversationID, count: messageCount, loading: loading)
    }
    view.needsLayout = true
  }

  final class Probe: NSView {
    var didLayout: (() -> Void)?
    override func layout() {
      super.layout()
      if window != nil { didLayout?() }
    }
  }
}
