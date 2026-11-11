import CryptoKit
import Foundation
import GreenBubblesHistory
import LocalAuthentication
import Security

/// Encrypted disposable cache. The existing connection secret never leaves memory.
struct HistoryPersistentCache: Sendable {
  let url: URL
  let key: SymmetricKey

  init?(configuration: HistoryDirectConfiguration, secret: [UInt8], enabled: Bool) {
    guard enabled,
      let digest = try? HistoryRememberedConnection.digest(configuration.executableURL)
    else { return nil }
    guard let material = secret.isEmpty ? Self.localCacheKey() : Data(secret) else { return nil }
    let scope = [
      configuration.sourceURL.standardizedFileURL.path,
      configuration.accessMode.rawValue, digest,
      configuration.localCredentialURL?.standardizedFileURL.path ?? "",
      configuration.recoveryKitURL?.standardizedFileURL.path ?? "",
    ].joined(separator: "\n")
    let salt = Data(scope.utf8)
    key = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: material), salt: salt,
      info: Data("GreenBubbles.history-cache.v1".utf8), outputByteCount: 32)
    let name = SHA256.hash(data: salt).map { String(format: "%02x", $0) }.joined()
    url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: Bundle.main.bundleIdentifier ?? "me.greenbubbles.GreenBubbles")
      .appending(path: "History-v1").appending(path: name + ".sealed")
  }

  // Exact application-owned item; never enumerate credentials or reuse a DB key file.
  private static func localCacheKey() -> Data? {
    #if DEBUG
      // Public test material is confined to the synthetic preview's namespace.
      if Bundle.main.bundleIdentifier == "me.greenbubbles.PresentationPreview" {
        return Data(repeating: 0x42, count: 32)
      }
    #endif
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "me.greenbubbles.GreenBubbles")
        + ".history-cache.v1",
      kSecAttrAccount as String: "encryption-key",
      kSecAttrSynchronizable as String: false,
    ]
    var lookup = query
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    lookup[kSecUseAuthenticationContext as String] = authentication
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecSuccess { return result as? Data }
    guard status == errSecItemNotFound else { return nil }
    let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return nil }
    return data
  }

  func read<T: Decodable>(_ type: T.Type) -> T? {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size <= 32 * 1_024 * 1_024, let data = try? Data(contentsOf: url),
      let box = try? AES.GCM.SealedBox(combined: data),
      var plain = try? AES.GCM.open(box, using: key)
    else { return nil }
    defer { plain.resetBytes(in: 0..<plain.count) }
    return try? JSONDecoder().decode(type, from: plain)
  }

  func write<T: Encodable>(_ value: T) throws {
    var plain = try JSONEncoder().encode(value)
    defer { plain.resetBytes(in: 0..<plain.count) }
    guard plain.count <= 32 * 1_024 * 1_024 else { return }
    let sealed = try AES.GCM.seal(plain, using: key).combined!
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try sealed.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
