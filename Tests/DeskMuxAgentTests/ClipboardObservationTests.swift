import DeskMuxCore
import Foundation
import Testing
@testable import DeskMuxInputTransport

// DM-036: exercise reconnect state without reading or writing NSPasteboard.general.
@Test func clipboardUnsupportedReplacementCannotReplayEarlierText() {
  var observation = DeskMuxClipboardObservation()
  let changed1 = observation.observe(changeCount: 10)
  #expect(changed1 == false) // Startup does not share old contents.
  #expect(observation.pendingLocalUpdate == nil)
  let changed2 = observation.observe(changeCount: 11)
  #expect(changed2 == true)
  let text = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"), text: "synthetic")
  observation.recordLocal(text)
  #expect(observation.pendingLocalUpdate == text)
  let changed3 = observation.observe(changeCount: 11)
  #expect(changed3 == false)
  #expect(observation.pendingLocalUpdate == text) // Reconnect can resend unchanged text.
  let changed4 = observation.observe(changeCount: 12)
  #expect(changed4 == true) // New image/file/cleared clipboard has no text.
  #expect(observation.pendingLocalUpdate == nil)
  let changed5 = observation.observe(changeCount: 12)
  #expect(changed5 == false)
  #expect(observation.pendingLocalUpdate == nil)
}

@Test func clipboardOversizedReplacementInvalidatesPendingTextAndCanRecover() {
  var observation = DeskMuxClipboardObservation()
  _ = observation.observe(changeCount: 1)
  let changed6 = observation.observe(changeCount: 2)
  #expect(changed6 == true)
  let text = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"), text: "synthetic")
  observation.recordLocal(text)
  let changed7 = observation.observe(changeCount: 3)
  #expect(changed7 == true)
  let oversized = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"),
    text: String(repeating: "é", count: DeskMuxClipboardUpdate.maximumUTF8Size / 2 + 1))
  observation.recordLocal(oversized)
  #expect(observation.pendingLocalUpdate == nil)
  let changed8 = observation.observe(changeCount: 4)
  #expect(changed8 == true)
  observation.recordLocal(text)
  #expect(observation.pendingLocalUpdate == text)
}

@Test func clipboardRemoteApplicationSuppressesEchoAndClearsReconnectState() {
  var observation = DeskMuxClipboardObservation()
  _ = observation.observe(changeCount: 1)
  let changed9 = observation.observe(changeCount: 2)
  #expect(changed9 == true)
  observation.recordLocal(DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"), text: "synthetic"))
  observation.appliedRemote(changeCount: 3)
  #expect(observation.pendingLocalUpdate == nil)
  let changed10 = observation.observe(changeCount: 3)
  #expect(changed10 == false)
  let changed11 = observation.observe(changeCount: 4)
  #expect(changed11 == true)
}

// DM-037: pause the production delivery scheduler, invalidate, then resume replay.
@Test @MainActor func clipboardQueuedReplayUsesCurrentGenerationAtDelivery() {
  let queue = PausedClipboardDeliveryQueue()
  let delivery = DeskMuxClipboardDelivery(enqueue: { queue.append($0) })
  let recorder = ClipboardDeliveryRecorder()
  let peer = PeerID(rawValue: "fixture")
  delivery.addObserver(id: UUID(), localPeerID: peer, handler: { _ in })
  queue.drain()
  delivery.observe(changeCount: 1) { "initial must stay local" }
  delivery.observe(changeCount: 2) { "old synthetic text" }
  delivery.addObserver(id: UUID(), localPeerID: peer, handler: { recorder.append($0.text) })
  #expect(recorder.texts.isEmpty)
  delivery.observe(changeCount: 3) { nil } // image/file/cleared clipboard while replay paused
  queue.drain()
  #expect(recorder.texts.isEmpty)
  delivery.observe(changeCount: 4) { "new synthetic text" }
  #expect(recorder.texts == ["new synthetic text"])
}

@Test @MainActor func clipboardQueuedReplayCannotOutliveOversizeOrRemoteInvalidation() {
  for remote in [false, true] {
    let queue = PausedClipboardDeliveryQueue()
    let delivery = DeskMuxClipboardDelivery(enqueue: { queue.append($0) })
    let recorder = ClipboardDeliveryRecorder()
    let peer = PeerID(rawValue: "fixture")
    delivery.addObserver(id: UUID(), localPeerID: peer, handler: { _ in })
    queue.drain()
    delivery.observe(changeCount: 1) { nil }
    delivery.observe(changeCount: 2) { "old synthetic text" }
    delivery.addObserver(id: UUID(), localPeerID: peer, handler: { recorder.append($0.text) })
    if remote {
      delivery.appliedRemote(changeCount: 3)
    } else {
      delivery.observe(changeCount: 3) {
        String(repeating: "é", count: DeskMuxClipboardUpdate.maximumUTF8Size / 2 + 1)
      }
    }
    queue.drain()
    #expect(recorder.texts.isEmpty)
  }
}

@Test @MainActor func clipboardReplayAndRemovalPreserveSerialOrdering() {
  let queue = PausedClipboardDeliveryQueue()
  let delivery = DeskMuxClipboardDelivery(enqueue: { queue.append($0) })
  let recorder = ClipboardDeliveryRecorder()
  let peer = PeerID(rawValue: "fixture")
  let observer = UUID()
  delivery.addObserver(id: UUID(), localPeerID: peer, handler: { _ in })
  queue.drain()
  delivery.observe(changeCount: 1) { nil }
  delivery.observe(changeCount: 2) { "current synthetic text" }
  delivery.addObserver(id: observer, localPeerID: peer, handler: { recorder.append($0.text) })
  queue.drain()
  #expect(recorder.texts == ["current synthetic text"])
  delivery.removeObserver(id: observer)
  queue.drain()
  delivery.observe(changeCount: 3) { "later synthetic text" }
  #expect(recorder.texts == ["current synthetic text"])
}

private final class PausedClipboardDeliveryQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var work: [DeskMuxClipboardDelivery.Work] = []

  func append(_ action: @escaping DeskMuxClipboardDelivery.Work) {
    lock.withLock { work.append(action) }
  }

  @MainActor func drain() {
    let pending = lock.withLock {
      let pending = work
      work.removeAll()
      return pending
    }
    for action in pending { action() }
  }
}

private final class ClipboardDeliveryRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []
  var texts: [String] { lock.withLock { values } }
  func append(_ text: String) { lock.withLock { values.append(text) } }
}
