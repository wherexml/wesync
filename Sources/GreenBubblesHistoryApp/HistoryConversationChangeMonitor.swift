import Darwin
import Dispatch
import Foundation

/// Filesystem changes are hints only. This monitor reads metadata, never database bytes.
final class HistoryConversationChangeMonitor: @unchecked Sendable {
  private struct Fingerprint: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let seconds: Int
    let nanoseconds: Int
  }

  private struct Watch {
    let fingerprint: Fingerprint
    let token: UUID
    let source: DispatchSourceFileSystemObject
  }

  private let queue = DispatchQueue(label: "greenbubbles.history-conversation-changes")
  private let locations: [(name: String, url: URL, directory: Bool)]
  private let onChange: @Sendable () -> Void
  private var watches: [String: Watch] = [:]
  private var observedFiles: [String: Fingerprint] = [:]

  init(sourceRoot: URL, onChange: @escaping @Sendable () -> Void) throws {
    let session = sourceRoot.appending(path: "session", directoryHint: .isDirectory)
    locations = [
      ("root", sourceRoot, true), ("session", session, true),
      ("database", session.appending(path: "session.db"), false),
      ("wal", session.appending(path: "session.db-wal"), false),
    ]
    self.onChange = onChange
    do {
      try queue.sync {
        guard fingerprint(of: locations[1]) != nil else {
          throw CocoaError(.fileReadNoPermission)
        }
        observedFiles = fileFingerprints()
        try synchronizeWatches()
      }
    } catch {
      stop()
      throw error
    }
  }

  func checkForChanges() {
    queue.async { [weak self] in self?.inspectChanges() }
  }

  func stop() {
    queue.sync {
      for watch in watches.values { watch.source.cancel() }
      watches.removeAll()
    }
  }

  deinit {
    for watch in watches.values { watch.source.cancel() }
  }

  private func fingerprint(
    of location: (name: String, url: URL, directory: Bool)
  ) -> Fingerprint? {
    var metadata = stat()
    guard lstat(location.url.path, &metadata) == 0,
      metadata.st_uid == geteuid(),
      metadata.st_mode & S_IFMT == (location.directory ? S_IFDIR : S_IFREG)
    else { return nil }
    return Fingerprint(
      device: metadata.st_dev, inode: metadata.st_ino, size: metadata.st_size,
      seconds: metadata.st_mtimespec.tv_sec, nanoseconds: metadata.st_mtimespec.tv_nsec)
  }

  private func fileFingerprints() -> [String: Fingerprint] {
    var result: [String: Fingerprint] = [:]
    for location in locations where !location.directory {
      if let value = fingerprint(of: location) { result[location.name] = value }
    }
    return result
  }

  private func synchronizeWatches() throws {
    for location in locations {
      let current = fingerprint(of: location)
      if let current, let previous = watches[location.name],
        previous.fingerprint.device == current.device,
        previous.fingerprint.inode == current.inode
      {
        continue
      }
      watches.removeValue(forKey: location.name)?.source.cancel()
      guard let current else { continue }
      let descriptor = Darwin.open(location.url.path, O_EVTONLY | O_CLOEXEC | O_NOFOLLOW)
      guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
      var actual = stat()
      guard fstat(descriptor, &actual) == 0, actual.st_dev == current.device,
        actual.st_ino == current.inode
      else {
        Darwin.close(descriptor)
        throw CocoaError(.fileReadUnknown)
      }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.write, .extend, .delete, .rename, .revoke], queue: queue)
      let token = UUID()
      let name = location.name
      source.setEventHandler { [weak self] in
        guard let self, let watch = watches[name], watch.token == token else { return }
        if !watch.source.data.intersection([.delete, .rename, .revoke]).isEmpty {
          watches.removeValue(forKey: name)?.source.cancel()
        }
        inspectChanges()
      }
      source.setCancelHandler { Darwin.close(descriptor) }
      watches[name] = Watch(fingerprint: current, token: token, source: source)
      source.resume()
    }
  }

  private func inspectChanges() {
    let current = fileFingerprints()
    let changed = current != observedFiles
    do { try synchronizeWatches() } catch {
      if changed {
        observedFiles = current
        onChange()
      }
      return
    }
    observedFiles = current
    if changed { onChange() }
  }
}
