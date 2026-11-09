import CryptoKit
import Foundation
import GreenBubblesHistory
import Security

/// A single application-owned item. No queries enumerate the user's Keychain.
struct HistoryRememberedConnection: Codable {
  var executablePath: String
  var executableDigest: String
  var sourcePath: String
  var accessMode: String
  var recoveryKitPath: String?
  var localCredentialPath: String?
  var secret: Data

  static func digest(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
      .map { String(format: "%02x", $0) }.joined()
  }

  static var bundledReadTool: URL? {
    Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "greenbubbles")
      .resolvingSymlinksInPath().standardizedFileURL
  }

  static func bundledReadTool(matching executable: URL) -> URL? {
    guard let bundledReadTool,
      executable.resolvingSymlinksInPath().standardizedFileURL == bundledReadTool
    else { return nil }
    return bundledReadTool
  }

  /// Exact predecessor/successor binding in the app's signed resource envelope.
  /// External tools and unsigned/ad-hoc apps never gain an automatic migration.
  static func acceptsSignedToolUpdate(_ executable: URL, previousDigest: String) -> Bool {
    struct Migration: Decodable {
      let previousSHA256: String
      let previousSHA256s: [String]?
      let currentSHA256: String
    }
    guard Bundle.main.bundleIdentifier == "me.greenbubbles.GreenBubbles",
      bundledReadTool(matching: executable) != nil,
      let manifest = Bundle.main.url(forResource: "ToolUpdate", withExtension: "json"),
      let data = try? Data(contentsOf: manifest),
      let migration = try? JSONDecoder().decode(Migration.self, from: data),
      migration.previousSHA256 == previousDigest
        || (migration.previousSHA256s ?? []).contains(previousDigest),
      let currentDigest = try? digest(executable), currentDigest == migration.currentSHA256
    else { return false }
    var appCode: SecStaticCode?
    var toolCode: SecStaticCode?
    let flags = SecCSFlags(
      rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    guard
      SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &appCode) == errSecSuccess,
      SecStaticCodeCreateWithPath(executable as CFURL, [], &toolCode) == errSecSuccess,
      let appCode, let toolCode,
      SecStaticCodeCheckValidity(appCode, flags, nil) == errSecSuccess,
      SecStaticCodeCheckValidity(toolCode, flags, nil) == errSecSuccess
    else { return false }
    func certificate(_ code: SecStaticCode) -> Data? {
      var info: CFDictionary?
      guard
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
          == errSecSuccess,
        let values = info as? [String: Any],
        let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
        let leaf = certificates.first
      else { return nil }
      return SecCertificateCopyData(leaf) as Data
    }
    guard let appCertificate = certificate(appCode), let toolCertificate = certificate(toolCode)
    else { return false }
    return appCertificate == toolCertificate
  }

  func configuration() throws -> HistoryDirectConfiguration {
    let executable = URL(fileURLWithPath: executablePath)
    guard let mode = HistoryDirectAccessMode(rawValue: accessMode),
      FileManager.default.isExecutableFile(atPath: executablePath),
      try Self.digest(executable) == executableDigest
        || Self.acceptsSignedToolUpdate(executable, previousDigest: executableDigest)
    else {
      throw RememberedConnectionError.changedExecutable
    }
    return HistoryDirectConfiguration(
      executableURL: executable,
      sourceURL: URL(fileURLWithPath: sourcePath), accessMode: mode,
      recoveryKitURL: recoveryKitPath.map { URL(fileURLWithPath: $0) },
      localCredentialURL: localCredentialPath.map { URL(fileURLWithPath: $0) })
  }
}

struct HistoryConnectionVault {
  #if DEBUG
    // This synthetic E2E never exercises real credentials or the Keychain.
    private var isolatedPreloadAcceptance: Bool {
      Bundle.main.bundleIdentifier == "me.greenbubbles.PresentationPreview"
        && Bundle.main.object(forInfoDictionaryKey: "GBOfflineAcceptance") as? Bool == true
        && Bundle.main.resourceURL.map {
          FileManager.default.fileExists(
            atPath: $0.appending(path: "offline-fixture/preload-acceptance").path)
            || FileManager.default.fileExists(
              atPath: $0.appending(path: "offline-fixture/body-refresh-acceptance").path)
        } == true
    }
  #endif
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "me.greenbubbles.GreenBubbles")
        + ".remembered-connection.v1",
      kSecAttrAccount as String: "last-successful-connection",
      kSecAttrSynchronizable as String: false,
    ]
  }

  func save(_ record: HistoryRememberedConnection) throws {
    #if DEBUG
      if isolatedPreloadAcceptance { return }
    #endif
    var bytes = try JSONEncoder().encode(record)
    defer { bytes.resetBytes(in: 0..<bytes.count) }
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = bytes
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      item[kSecAttrLabel as String] = "GreenBubbles remembered connection"
      let result = SecItemAdd(item as CFDictionary, nil)
      guard result == errSecSuccess else { throw RememberedConnectionError.keychain(result) }
    } else if status != errSecSuccess {
      throw RememberedConnectionError.keychain(status)
    }
  }

  func load() throws -> HistoryRememberedConnection? {
    #if DEBUG
      if isolatedPreloadAcceptance { return nil }
    #endif
    var item = query
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(item as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, var bytes = value as? Data else {
      throw RememberedConnectionError.keychain(status)
    }
    defer { bytes.resetBytes(in: 0..<bytes.count) }
    do { return try JSONDecoder().decode(HistoryRememberedConnection.self, from: bytes) } catch {
      throw RememberedConnectionError.invalidRecord
    }
  }

  func remove() throws {
    #if DEBUG
      if isolatedPreloadAcceptance { return }
    #endif
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw RememberedConnectionError.keychain(status)
    }
  }
}

enum RememberedConnectionError: LocalizedError {
  case keychain(OSStatus)
  case changedExecutable, invalidRecord
  var errorDescription: String? {
    switch self {
    case .keychain(let status): "无法访问此 App 保存的连接（钥匙串错误 \(status)）。可重新手动连接。"
    case .changedExecutable: "查询工具已更新或不可用。请手动连接一次以确认新的工具。"
    case .invalidRecord: "保存的连接无法读取。请忘记此连接并重新连接。"
    }
  }
}
