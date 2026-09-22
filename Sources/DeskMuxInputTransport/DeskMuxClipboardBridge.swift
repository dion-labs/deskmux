@preconcurrency import AppKit
import DeskMuxCore
import Foundation

/// Tracks only text belonging to the current observed pasteboard generation.
/// Unsupported or oversized replacements must invalidate reconnect delivery too.
struct DeskMuxClipboardObservation {
  private var lastObservedChangeCount: Int?
  private(set) var pendingLocalUpdate: DeskMuxClipboardUpdate?

  mutating func observe(changeCount: Int) -> Bool {
    guard lastObservedChangeCount != changeCount else { return false }
    let wasInitialized = lastObservedChangeCount != nil
    lastObservedChangeCount = changeCount
    pendingLocalUpdate = nil
    return wasInitialized
  }

  mutating func recordLocal(_ update: DeskMuxClipboardUpdate) {
    pendingLocalUpdate = update.isWithinSizeLimit ? update : nil
  }

  mutating func appliedRemote(changeCount: Int) {
    lastObservedChangeCount = changeCount
    pendingLocalUpdate = nil
  }
}

/// All generation changes and deliveries execute on the main actor. In particular,
/// reconnect replay reads the current pending value only when its queued work runs;
/// it never carries a snapshot across an observed invalidation.
@MainActor
final class DeskMuxClipboardDelivery {
  typealias UpdateHandler = @Sendable (DeskMuxClipboardUpdate) -> Void
  typealias Work = @MainActor @Sendable () -> Void
  typealias Enqueue = @Sendable (@escaping Work) -> Void

  private nonisolated let enqueue: Enqueue
  private var observers: [UUID: UpdateHandler] = [:]
  private var localPeerID: PeerID?
  private var observation = DeskMuxClipboardObservation()

  nonisolated init(enqueue: @escaping Enqueue = { work in
    DispatchQueue.main.async { work() }
  }) {
    self.enqueue = enqueue
  }

  nonisolated func addObserver(id: UUID, localPeerID: PeerID, handler: @escaping UpdateHandler) {
    enqueue { [weak self] in
      guard let self else { return }
      self.localPeerID = localPeerID
      self.observers[id] = handler
      if let pending = self.observation.pendingLocalUpdate { handler(pending) }
    }
  }

  nonisolated func removeObserver(id: UUID) {
    enqueue { [weak self] in self?.observers.removeValue(forKey: id) }
  }

  func observe(changeCount: Int, readText: () -> String?) {
    guard observation.observe(changeCount: changeCount),
      let localPeerID, let text = readText()
    else { return }
    let update = DeskMuxClipboardUpdate(sourcePeerID: localPeerID, text: text)
    observation.recordLocal(update)
    guard update.isWithinSizeLimit else { return }
    for handler in observers.values { handler(update) }
  }

  func appliedRemote(changeCount: Int) {
    observation.appliedRemote(changeCount: changeCount)
  }
}

/// Process-wide plain-text clipboard synchronization for DeskMux's stable,
/// encrypted peer connection. Remote writes advance the observed pasteboard
/// generation before polling can echo them back to their source.
final class DeskMuxClipboardBridge: @unchecked Sendable {
  static let shared = DeskMuxClipboardBridge()

  typealias UpdateHandler = @Sendable (DeskMuxClipboardUpdate) -> Void

  private let lock = NSLock()
  private let delivery = DeskMuxClipboardDelivery()
  private var receivedUpdateIDs: [UUID] = []
  private var receivedUpdateIDSet: Set<UUID> = []
  private var timer: DispatchSourceTimer?
  private static let eventLog = DeskMuxClipboardEventLog(
    directory: FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/DeskMux", isDirectory: true)
  )

  private init() {}

  func addObserver(
    id: UUID,
    localPeerID: PeerID,
    handler: @escaping UpdateHandler
  ) {
    delivery.addObserver(id: id, localPeerID: localPeerID, handler: handler)
    startMonitoring()
  }

  func removeObserver(id: UUID) {
    delivery.removeObserver(id: id)
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
      delivery.appliedRemote(changeCount: pasteboard.changeCount)
      record("applied", update: update)
      completion()
    }
  }

  func recordSent(_ update: DeskMuxClipboardUpdate) {
    record("sent", update: update)
  }

  func recordAcknowledged(id: UUID) {
    Self.eventLog.record("acknowledged", updateID: id)
  }

  private func startMonitoring() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(
      deadline: .now(),
      repeating: .milliseconds(150),
      leeway: .milliseconds(30)
    )
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      MainActor.assumeIsolated { self.pollPasteboard() }
    }
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

  @MainActor
  private func pollPasteboard() {
    let pasteboard = NSPasteboard.general
    delivery.observe(changeCount: pasteboard.changeCount) {
      pasteboard.string(forType: .string)
    }
  }

  private func record(_ event: String, update: DeskMuxClipboardUpdate) {
    Self.eventLog.record(event, update: update)
  }
}
