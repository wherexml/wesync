import AppKit
import Combine
import Security
import Sparkle
import SwiftUI

struct HistoryUpdateMenu: View {
  @ObservedObject var updater: HistoryUpdater

  var body: some View {
    Button("检查更新…") { updater.check() }
      .disabled(!updater.canCheck)
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
  private(set) var controller: SPUStandardUpdaterController?
  private var observation: AnyCancellable?
  #if DEBUG
    var diagnosticHandler: ((String, Int?) -> Void)?
    private func record(_ kind: String, code: Int? = nil) {
      guard Bundle.main.bundleIdentifier == "me.greenbubbles.UpdaterPreview" else { return }
      diagnosticHandler?(kind, code)
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
      record("error", code: (error as NSError).code)
    }
  #endif

  var supportsAutomaticUpdates: Bool { controller != nil }
  var automaticallyChecks: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? false }
    set {
      objectWillChange.send()
      controller?.updater.automaticallyChecksForUpdates = newValue
    }
  }

  func start() {
    guard controller == nil, acceptsChannel else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    observation = controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: RunLoop.main)
      .sink { [weak self] value in self?.canCheck = value }
    controller.startUpdater()
  }

  func check() {
    NSApp.activate(ignoringOtherApps: true)
    if let controller {
      controller.checkForUpdates(nil)
    } else {
      let alert = NSAlert()
      alert.messageText = "当前为本机开发版"
      alert.informativeText = "公开版使用不同的签名身份，请从 GitHub 查看版本。"
      alert.addButton(withTitle: "查看 GitHub 版本")
      alert.addButton(withTitle: "取消")
      if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releases) }
    }
  }

  private var acceptsChannel: Bool {
    #if DEBUG
      if Bundle.main.bundleIdentifier == "me.greenbubbles.UpdaterPreview",
        Bundle.main.object(forInfoDictionaryKey: "GBUpdatePreview") as? Bool == true
      {
        return true
      }
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
      if Bundle.main.bundleIdentifier == "me.greenbubbles.UpdaterPreview",
        Bundle.main.object(forInfoDictionaryKey: "GBUpdatePreview") as? Bool == true
      {
        return
      }
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
