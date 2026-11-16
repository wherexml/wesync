import Foundation
import GreenBubblesHistory

/// The app owns this process and its connection. Agents receive query results only.
@MainActor
final class HistoryQueryProxy {
  private var process: Process?

  func start(configuration: HistoryDirectConfiguration, key: [UInt8]) throws {
    stop()
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/GreenBubbles")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let socket = directory.appending(path: "query.sock")
    let child = Process()
    child.executableURL = configuration.executableURL
    var arguments = ["query-serve", configuration.sourceURL.path, socket.path]
    switch configuration.accessMode {
    case .liveEncrypted: arguments.append("--passphrase-stdin")
    case .snapshotEncrypted: arguments.append("--snapshot-key-stdin")
    case .snapshotPassphrase: arguments.append("--snapshot-passphrase-stdin")
    case .snapshotKeychain, .snapshotLocalCredential:
      guard let url = configuration.localCredentialURL else { throw CocoaError(.fileNoSuchFile) }
      arguments += ["--snapshot-local-credential", url.path]
    case .snapshotRecoveryKit:
      guard let url = configuration.recoveryKitURL else { throw CocoaError(.fileNoSuchFile) }
      arguments += ["--snapshot-recovery-kit", url.path]
    case .decrypted: arguments.append("--decrypted")
    }
    child.arguments = arguments
    let input = Pipe()
    child.standardInput = input
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    process = child
    var data = Data(key)
    defer { data.resetBytes(in: 0..<data.count) }
    if !key.isEmpty { data.append(10) }
    do {
      try input.fileHandleForWriting.write(contentsOf: data)
      try input.fileHandleForWriting.close()
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    guard let process else { return }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    self.process = nil
    // The next authenticated server validates and removes its stale socket.
  }
}
