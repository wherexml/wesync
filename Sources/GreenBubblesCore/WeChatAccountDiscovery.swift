import Darwin
import Foundation

public enum WeChatLocalDatabaseAccess: Equatable, Sendable {
  case readable(URL?)
  case permissionRequired
  case sourceUnavailable
}

public struct WeChatAccountLocation: Codable, Equatable, Sendable {
  public let accountID: String
  public let root: PathReference
  public let databaseRoot: PathReference
  public let attachmentRoot: PathReference?
  public let isReadable: Bool

  public init(
    accountID: String,
    root: PathReference,
    databaseRoot: PathReference,
    attachmentRoot: PathReference?,
    isReadable: Bool
  ) {
    self.accountID = accountID
    self.root = root
    self.databaseRoot = databaseRoot
    self.attachmentRoot = attachmentRoot
    self.isReadable = isReadable
  }
}

public struct WeChatAccountDiscovery: Sendable {
  private let homeDirectory: URL
  private let privacy: PathPrivacy

  public init(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    includePaths: Bool = false
  ) {
    self.homeDirectory = homeDirectory.standardizedFileURL
    self.privacy = PathPrivacy(includePaths: includePaths)
  }

  public func discover() -> [WeChatAccountLocation] {
    resolvedAccounts().map(\.report)
  }

  public func databaseRoots(accountID: String? = nil) -> [URL] {
    resolvedAccounts()
      .filter { accountID == nil || $0.report.accountID == accountID }
      .map(\.databaseRoot)
  }

  public func accountRoot(accountID: String) -> URL? {
    resolvedAccounts().first { $0.report.accountID == accountID }?.root
  }

  /// Checks access to the core files without reading bytes, acquiring a key, or opening SQLite.
  public func localDatabaseAccess(preferredRoot: URL? = nil) -> WeChatLocalDatabaseAccess {
    if let preferredRoot { return checkDatabaseAccess(at: preferredRoot) }

    let manager = FileManager.default
    var readableRoots = Set<URL>()
    var needsPermission = false
    for container in xwechatFileRoots(fileManager: manager) {
      do {
        let children = try manager.contentsOfDirectory(
          at: container, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        for account in children where safeDirectory(account) {
          let root = account.appending(path: "db_storage", directoryHint: .isDirectory)
          switch checkDatabaseAccess(at: root) {
          case .readable: readableRoots.insert(root.standardizedFileURL)
          case .permissionRequired: needsPermission = true
          case .sourceUnavailable: break
          }
        }
      } catch {
        let failure = error as NSError
        let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        if (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
          || [failure, underlying].compactMap({ $0 }).contains(where: {
            $0.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains($0.code)
          })
        {
          needsPermission = true
        }
      }
    }
    if !readableRoots.isEmpty {
      return .readable(readableRoots.count == 1 && !needsPermission ? readableRoots.first : nil)
    }
    return needsPermission ? .permissionRequired : .sourceUnavailable
  }

  private func checkDatabaseAccess(at root: URL) -> WeChatLocalDatabaseAccess {
    for relative in ["session/session.db", "contact/contact.db"] {
      let file = root.appending(path: relative)
      let descriptor = Darwin.open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
      guard descriptor >= 0 else {
        return errno == EACCES || errno == EPERM ? .permissionRequired : .sourceUnavailable
      }
      var info = stat()
      let regular = fstat(descriptor, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
      Darwin.close(descriptor)
      guard regular else { return .sourceUnavailable }
    }
    return .readable(root)
  }

  struct ResolvedAccount: Sendable {
    let report: WeChatAccountLocation
    let root: URL
    let databaseRoot: URL
    let attachmentRoot: URL?
  }

  func resolvedAccounts() -> [ResolvedAccount] {
    let fileManager = FileManager.default
    var accounts: [ResolvedAccount] = []
    for xwechatRoot in xwechatFileRoots(fileManager: fileManager) {
      let children =
        (try? fileManager.contentsOfDirectory(
          at: xwechatRoot,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )) ?? []
      for root in children {
        guard
          let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
          values.isDirectory == true,
          values.isSymbolicLink != true
        else { continue }
        let databaseRoot = root.appending(path: "db_storage", directoryHint: .isDirectory)
        guard safeDirectory(databaseRoot) else { continue }
        let attachmentCandidate = root.appending(path: "msg/attach", directoryHint: .isDirectory)
        let attachmentRoot =
          safeDirectory(attachmentCandidate)
          ? attachmentCandidate.standardizedFileURL : nil
        let rootReference = privacy.reference(for: root)
        accounts.append(
          ResolvedAccount(
            report: WeChatAccountLocation(
              accountID: rootReference.opaqueID,
              root: rootReference,
              databaseRoot: privacy.reference(for: databaseRoot),
              attachmentRoot: attachmentRoot.map { privacy.reference(for: $0) },
              isReadable: fileManager.isReadableFile(atPath: databaseRoot.path)
            ),
            root: root.standardizedFileURL,
            databaseRoot: databaseRoot.standardizedFileURL,
            attachmentRoot: attachmentRoot
          ))
      }
    }
    var seen = Set<String>()
    return
      accounts
      .filter { seen.insert($0.root.path).inserted }
      .sorted { $0.report.accountID < $1.report.accountID }
  }

  private func xwechatFileRoots(fileManager: FileManager) -> [URL] {
    var candidates: [URL] = []
    let documents = homeDirectory.appending(
      path: "Library/Containers/com.tencent.xinWeChat/Data/Documents")
    candidates.append(documents.appending(path: "xwechat_files", directoryHint: .isDirectory))

    let groups = homeDirectory.appending(
      path: "Library/Group Containers", directoryHint: .isDirectory)
    let groupChildren =
      (try? fileManager.contentsOfDirectory(
        at: groups,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    for group in groupChildren {
      let name = group.lastPathComponent.lowercased()
      guard name.contains("wechat") || name.contains("xinwechat") else { continue }
      candidates.append(group.appending(path: "xwechat_files", directoryHint: .isDirectory))
    }

    var seen = Set<String>()
    return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
  }

  private func safeDirectory(_ url: URL) -> Bool {
    guard
      let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    else { return false }
    return values.isDirectory == true && values.isSymbolicLink != true
  }
}
