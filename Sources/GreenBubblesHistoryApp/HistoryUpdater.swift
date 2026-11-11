import AppKit
import Combine
import Security
import Sparkle
import SwiftUI

struct HistoryUpdateMenu: View {
  @ObservedObject var updater: HistoryUpdater

  var body: some View {
    Button("检查更新…") { updater.check() }
      .disabled(!updater.canOpenNotice)
    if updater.supportsAutomaticUpdates {
      Toggle(
        "自动检查更新",
        isOn: Binding(
          get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
    }
  }
}

/// The public channel never replaces a differently signed local development installation.
@MainActor
final class HistoryUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
  static let feed = "https://raw.githubusercontent.com/wherexml/wesync/main/updates/appcast.xml"
  static let publicKey = "Ezf1BaLI+RnN7zPKzrRp2gxsyYhDvWYSEwiFuxIkJXg="
  static let releases = URL(string: "https://github.com/wherexml/wesync/releases/latest")!
  @Published private(set) var canCheck = true
  private(set) var updater: SPUUpdater?
  private lazy var driver = HistoryUpdateDriver(model: self)
  private var observation: AnyCancellable?
  #if DEBUG
    var diagnosticHandler: ((String, Int?) -> Void)?
    private func record(_ kind: String, code: Int? = nil) {
      guard isUpdatePreview else { return }
      diagnosticHandler?(kind, code)
    }
    private var isUpdatePreview: Bool {
      ["me.greenbubbles.UpdaterPreview", "me.greenbubbles.PresentationPreview"].contains(
        Bundle.main.bundleIdentifier ?? "")
        && Bundle.main.object(forInfoDictionaryKey: "GBUpdatePreview") as? Bool == true
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
      record("available")
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { record("current") }
    func userDidCancelDownload(_ updater: SPUUpdater) { record("cancelled") }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
      record("installing")
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
      if (error as NSError).code != SUError.noUpdateError.rawValue {
        record("error", code: (error as NSError).code)
      }
    }
  #endif

  var supportsAutomaticUpdates: Bool { updater != nil }
  var automaticallyChecks: Bool {
    get { updater?.automaticallyChecksForUpdates ?? false }
    set {
      objectWillChange.send()
      updater?.automaticallyChecksForUpdates = newValue
    }
  }

  enum Phase {
    case idle, checking, downloading, verifying, ready, installing, current, failed, localBuild,
      permissionRequired
  }
  @Published fileprivate(set) var phase: Phase = .idle
  @Published fileprivate(set) var noticeVisible = false
  @Published fileprivate(set) var availableVersion = ""
  @Published fileprivate(set) var progress: Double?
  fileprivate var manualCheck = false
  fileprivate var cancellation: (() -> Void)?
  fileprivate var installReply: ((SPUUserUpdateChoice) -> Void)?
  private var dismissTask: Task<Void, Never>?

  var canCancel: Bool { cancellation != nil }
  var canOpenNotice: Bool {
    canCheck || [.checking, .downloading, .verifying, .ready, .installing].contains(phase)
  }
  fileprivate var canReplaceWithoutAuthorization: Bool {
    let url = Bundle.main.bundleURL
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let owner = attributes[.ownerAccountID] as? NSNumber,
      let group = attributes[.groupOwnerAccountID] as? NSNumber,
      owner.uint32Value == getuid(),
      FileManager.default.isWritableFile(atPath: url.path),
      FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    else { return false }
    var groups = [gid_t](repeating: 0, count: 128)
    let count = getgroups(Int32(groups.count), &groups)
    return group.uint32Value == getgid()
      || (count >= 0 && groups.prefix(Int(count)).contains(group.uint32Value))
  }

  func start() {
    guard updater == nil, acceptsChannel else { return }
    #if DEBUG
      if isUpdatePreview, diagnosticHandler == nil,
        let directory = Bundle.main.object(forInfoDictionaryKey: "GBUpdateEvidenceDirectory")
          as? String
      {
        diagnosticHandler = { kind, code in
          let url = URL(fileURLWithPath: directory).appending(path: "events.jsonl")
          let row: [String: Any] = [
            "event": kind, "code": code as Any? ?? NSNull(),
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "",
          ]
          guard var bytes = try? JSONSerialization.data(withJSONObject: row) else { return }
          bytes.append(10)
          if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
          }
          guard let file = try? FileHandle(forWritingTo: url) else { return }
          defer { try? file.close() }
          _ = try? file.seekToEnd()
          try? file.write(contentsOf: bytes)
        }
      }
    #endif
    let updater = SPUUpdater(
      hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
    self.updater = updater
    observation = updater.publisher(for: \.canCheckForUpdates)
      .receive(on: RunLoop.main)
      .sink { [weak self] value in self?.canCheck = value }
    do {
      try updater.start()
      #if DEBUG
        record("started")
      #endif
      // Respect the user's automatic-check preference; this call is only made at startup.
      if updater.automaticallyChecksForUpdates { updater.checkForUpdatesInBackground() }
    } catch { phase = .failed }
  }

  func check() {
    dismissTask?.cancel()
    noticeVisible = true
    manualCheck = true
    if phase == .ready || phase == .installing || phase == .downloading || phase == .verifying {
      return
    }
    guard let updater else {
      phase = .localBuild
      return
    }
    guard updater.canCheckForUpdates else { return }
    updater.checkForUpdates()
  }

  func install() {
    guard phase == .ready, let reply = installReply else { return }
    guard canReplaceWithoutAuthorization else {
      phase = .permissionRequired
      return
    }
    installReply = nil
    phase = .installing
    reply(.install)
  }

  func cancel() {
    let cancel = cancellation
    cancellation = nil
    manualCheck = false
    phase = .idle
    noticeVisible = false
    cancel?()
  }

  func closeNotice() {
    guard phase != .installing else { return }
    dismissTask?.cancel()
    manualCheck = false
    noticeVisible = false
  }

  func openReleases() { NSWorkspace.shared.open(Self.releases) }

  fileprivate func finish(_ phase: Phase) {
    cancellation = nil
    installReply = nil
    self.phase = phase
    if manualCheck {
      noticeVisible = true
      dismissTask?.cancel()
      if phase == .current {
        dismissTask = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(4)) } catch { return }
          self?.noticeVisible = false
        }
      }
    }
  }

  private var acceptsChannel: Bool {
    #if DEBUG
      if isUpdatePreview { return true }
    #endif
    guard Bundle.main.bundleIdentifier == "me.greenbubbles.GreenBubbles",
      Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == Self.feed,
      Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String == Self.publicKey
    else { return false }
    var code: SecCode?
    var requirement: SecRequirement?
    let identity =
      "anchor apple generic and identifier \"me.greenbubbles.GreenBubbles\" "
      + "and certificate leaf[subject.OU] = \"T695TT4HT9\" "
      + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    return SecCodeCopySelf([], &code) == errSecSuccess
      && SecRequirementCreateWithString(identity as CFString, [], &requirement) == errSecSuccess
      && code.map { SecCodeCheckValidity($0, [], requirement) == errSecSuccess } == true
  }

  func updater(
    _ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem,
    updateCheck: SPUUpdateCheck
  ) throws {
    #if DEBUG
      if isUpdatePreview { return }
    #endif
    guard let url = item.fileURL, url.scheme == "https", url.host == "github.com",
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.hasPrefix("/wherexml/wesync/releases/download/v"),
      url.pathExtension == "dmg"
    else {
      throw NSError(
        domain: "me.greenbubbles.updates", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "更新地址不受信任。"])
    }
  }
}

/// Sparkle continues to own transport, signatures and installation. This driver owns only presentation.
@MainActor
private final class HistoryUpdateDriver: NSObject, SPUUserDriver {
  weak var model: HistoryUpdater?
  private var received: UInt64 = 0
  private var expected: UInt64 = 0

  init(model: HistoryUpdater) { self.model = model }

  func show(
    _ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    model?.manualCheck = true
    model?.phase = .checking
    model?.noticeVisible = true
    model?.cancellation = cancellation
  }

  func showUpdateFound(
    with item: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    guard let model else {
      reply(.dismiss)
      return
    }
    model.availableVersion = item.displayVersionString
    guard !item.isInformationOnlyUpdate else {
      model.finish(.permissionRequired)
      reply(.dismiss)
      return
    }
    // Do not request a privileged installer for an unwritable or differently owned app.
    guard model.canReplaceWithoutAuthorization else {
      model.finish(.permissionRequired)
      reply(.dismiss)
      return
    }
    reply(.install)
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    model?.finish(.current)
    acknowledgement()
  }

  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    model?.finish(.failed)
    acknowledgement()
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    received = 0
    expected = 0
    model?.phase = .downloading
    model?.progress = nil
    model?.cancellation = cancellation
  }

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    expected = expectedContentLength
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    received += length
    if expected > 0 { model?.progress = min(0.99, Double(received) / Double(expected)) }
  }

  func showDownloadDidStartExtractingUpdate() {
    model?.cancellation = nil
    model?.phase = .verifying
    model?.progress = nil
  }

  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    guard let model else {
      reply(.dismiss)
      return
    }
    model.installReply = reply
    model.phase = .ready
    model.progress = nil
    model.noticeVisible = true
    #if DEBUG
      model.diagnosticHandler?("ready", nil)
    #endif
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    model?.phase = .installing
    model?.cancellation = nil
  }

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    model?.noticeVisible = false
    acknowledgement()
  }

  func dismissUpdateInstallation() {
    model?.cancellation = nil
    guard let model, model.phase != .ready, model.phase != .current, model.phase != .failed,
      model.phase != .permissionRequired
    else { return }
    model.noticeVisible = false
  }

  func showUpdateInFocus() { model?.noticeVisible = true }
}
