import CryptoKit
import Darwin
import Foundation

/// Bounded, read-only access to one live account's downloaded sticker resources.
/// No database access, cross-account lookup, symlink following or path disclosure.
public enum HistoryLocalStickerStore {
  public enum Failure: Error { case unavailable }
  public static func load(md5: String, sourceRoot: URL) throws -> Data {
    guard md5.utf8.count == 32,
      md5.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      sourceRoot.isFileURL, sourceRoot.lastPathComponent == "db_storage",
      sourceRoot.standardizedFileURL == sourceRoot.resolvingSymlinksInPath().standardizedFileURL
    else { throw Failure.unavailable }
    let account = open(
      sourceRoot.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard account >= 0 else { throw Failure.unavailable }
    defer { close(account) }
    let database = openat(account, "db_storage", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard database >= 0 else { throw Failure.unavailable }
    close(database)
    let business = openat(account, "business", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard business >= 0 else { throw Failure.unavailable }
    defer { close(business) }
    let store = openat(business, "emoticon", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard store >= 0 else { throw Failure.unavailable }
    defer { close(store) }
    var budget = 20_000
    guard let data = try walk(store, md5: md5, depth: 0, budget: &budget) else {
      throw Failure.unavailable
    }
    return data
  }

  private static func walk(_ directory: Int32, md5: String, depth: Int, budget: inout Int) throws
    -> Data?
  {
    guard depth <= 12, budget > 0 else { return nil }
    let copy = dup(directory)
    guard copy >= 0 else { return nil }
    guard let stream = fdopendir(copy) else {
      close(copy)
      return nil
    }
    defer { closedir(stream) }
    while budget > 0, let entry = readdir(stream) {
      try Task.checkCancellation()
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
      }
      guard name != ".", name != ".." else { continue }
      budget -= 1
      var info = stat()
      guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
      if info.st_mode & S_IFMT == S_IFDIR {
        let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { continue }
        defer { close(child) }
        if let data = try walk(child, md5: md5, depth: depth + 1, budget: &budget) { return data }
      } else if info.st_mode & S_IFMT == S_IFREG,
        name.lowercased().contains(md5), info.st_size > 0, info.st_size <= 8 * 1_024 * 1_024
      {
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { continue }
        defer { close(file) }
        var actual = stat()
        guard fstat(file, &actual) == 0, actual.st_mode & S_IFMT == S_IFREG,
          actual.st_dev == info.st_dev, actual.st_ino == info.st_ino, actual.st_size == info.st_size
        else { continue }
        var data = Data(count: Int(actual.st_size))
        let count = data.withUnsafeMutableBytes { bytes in
          pread(file, bytes.baseAddress, bytes.count, 0)
        }
        guard count == data.count else { continue }
        let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if digest == md5 { return data }
      }
    }
    return nil
  }
}
