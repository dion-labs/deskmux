@preconcurrency import AppKit
import DeskMuxCore
import Foundation

/// Process-wide plain-text clipboard synchronization for DeskMux's stable,
/// encrypted peer connection. Remote writes advance the observed pasteboard
/// generation before polling can echo them back to their source.
final class DeskMuxClipboardBridge: @unchecked Sendable {
  static let shared = DeskMuxClipboardBridge()

  typealias UpdateHandler = @Sendable (DeskMuxClipboardUpdate) -> Void

  private let lock = NSLock()
  private var observers: [UUID: UpdateHandler] = [:]
  private var localPeerID: PeerID?
  private var lastObservedChangeCount: Int?
  private var pendingLocalUpdate: DeskMuxClipboardUpdate?
  private var receivedUpdateIDs: [UUID] = []
  private var receivedUpdateIDSet: Set<UUID> = []
  private var timer: DispatchSourceTimer?
  private static let loggingQueue = DispatchQueue(
    label: "dev.deskmux.clipboard.log",
    qos: .utility
  )

  private init() {}

  func addObserver(
    id: UUID,
    localPeerID: PeerID,
    handler: @escaping UpdateHandler
  ) {
    let state = lock.withLock { () -> (Bool, DeskMuxClipboardUpdate?) in
      self.localPeerID = localPeerID
      observers[id] = handler
      return (timer == nil, pendingLocalUpdate)
    }
    if state.0 { startMonitoring() }
    if let pending = state.1 { handler(pending) }
  }

  func removeObserver(id: UUID) {
    _ = lock.withLock { observers.removeValue(forKey: id) }
  }

  func applyRemote(
    _ update: DeskMuxClipboardUpdate,
    completion: @escaping @Sendable () -> Void
  ) {
    guard update.isWithinSizeLimit else { return }
    let shouldApply = lock.withLock { () -> Bool in
      guard !receivedUpdateIDSet.contains(update.id) else { return false }
      receivedUpdateIDs.append(update.id)
      receivedUpdateIDSet.insert(update.id)
      if receivedUpdateIDs.count > 128 {
        let removalCount = receivedUpdateIDs.count - 128
        let removed = receivedUpdateIDs.prefix(removalCount)
        receivedUpdateIDSet.subtract(removed)
        receivedUpdateIDs.removeFirst(removalCount)
      }
      return true
    }
    guard shouldApply else {
      completion()
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(update.text, forType: .string)
      lock.withLock {
        lastObservedChangeCount = pasteboard.changeCount
        pendingLocalUpdate = nil
      }
      record("applied", update: update)
      completion()
    }
  }

  func recordSent(_ update: DeskMuxClipboardUpdate) {
    record("sent", update: update)
  }

  func recordAcknowledged(id: UUID) {
    record("acknowledged", updateID: id)
  }

  private func startMonitoring() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(
      deadline: .now(),
      repeating: .milliseconds(150),
      leeway: .milliseconds(30)
    )
    timer.setEventHandler { [weak self] in self?.pollPasteboard() }
    let adopted = lock.withLock { () -> Bool in
      guard self.timer == nil else { return false }
      self.timer = timer
      return true
    }
    if adopted {
      timer.resume()
    } else {
      timer.cancel()
      timer.resume()
    }
  }

  private func pollPasteboard() {
    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount
    let peerID = lock.withLock { () -> PeerID? in
      if lastObservedChangeCount == nil {
        lastObservedChangeCount = changeCount
        return nil
      }
      guard lastObservedChangeCount != changeCount else { return nil }
      lastObservedChangeCount = changeCount
      return localPeerID
    }
    guard let peerID,
      let text = pasteboard.string(forType: .string)
    else { return }

    let update = DeskMuxClipboardUpdate(sourcePeerID: peerID, text: text)
    guard update.isWithinSizeLimit else { return }
    let handlers = lock.withLock { () -> [UpdateHandler] in
      pendingLocalUpdate = update
      return Array(observers.values)
    }
    for handler in handlers { handler(update) }
  }

  private func record(_ event: String, update: DeskMuxClipboardUpdate) {
    record(
      event,
      updateID: update.id,
      sourcePeerID: update.sourcePeerID.rawValue,
      byteCount: update.text.lengthOfBytes(using: .utf8)
    )
  }

  private func record(
    _ event: String,
    updateID: UUID,
    sourcePeerID: String? = nil,
    byteCount: Int? = nil
  ) {
    Self.loggingQueue.async {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var record: [String: Any] = [
        "timestamp": formatter.string(from: Date()),
        "event": event,
        "update_id": updateID.uuidString,
      ]
      if let sourcePeerID { record["source"] = sourcePeerID }
      if let byteCount { record["bytes"] = byteCount }
      do {
        let directory = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Library/Application Support/DeskMux", isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("clipboard.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
          FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(
          contentsOf: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        )
        try handle.write(contentsOf: Data([0x0a]))
      } catch {
        // Clipboard diagnostics must never affect synchronization.
      }
    }
  }
}
