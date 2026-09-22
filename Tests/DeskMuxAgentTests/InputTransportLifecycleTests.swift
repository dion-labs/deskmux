import DeskMuxCore
import Foundation
import Network
import Testing
@testable import DeskMuxInputTransport

// DM-039/007/025: production encryption/framing over loopback-only TCP, no Bonjour or input sink.
@Test func loopbackTransportOrdersFramesAndReconnectsWithFreshSequence() throws {
  let harness = try LoopbackInputHarness()
  defer { harness.stop() }
  let first = try harness.connect()
  let expected = (0..<100).map { InputWireMessage.ping(UInt64($0)) }
  for message in expected { try first.client.connection.send(message) }
  #expect(first.server.receipt.waitForMessages(100))
  #expect(first.server.receipt.messages == expected)
  first.client.connection.cancel()
  #expect(first.server.receipt.waitForCancellation())
  #expect(throws: InputPeerConnectionError.self) { try first.client.connection.send(.ping(101)) }

  let second = try harness.connect()
  let identity = PeerID(rawValue: "synthetic-\(UUID().uuidString)")
  let hello = InputWireMessage.hello(peerID: identity,
    protocolVersion: InputWireMessage.currentProtocolVersion, purpose: .inputRelay)
  try second.client.connection.send(hello)
  #expect(second.server.receipt.waitForMessages(1))
  #expect(second.server.receipt.messages == [hello])
  try second.server.connection.send(.ready(peerID: PeerID(rawValue: "synthetic-destination"), motionPort: nil))
  #expect(second.client.receipt.waitForMessages(1))
  #expect(first.server.receipt.messages == expected)
  #expect(second.server.receipt.failures.isEmpty)
}

// DM-044/008: exercise the real 64 KiB receive boundary with an eligible UTF-8 payload.
@Test func loopbackClipboardPayloadSurvivesChunkingAndAcknowledgement() throws {
  let harness = try LoopbackInputHarness()
  defer { harness.stop() }
  let pair = try harness.connect()
  let update = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "synthetic-peer"),
    text: String(repeating: "é", count: DeskMuxClipboardUpdate.maximumUTF8Size / 2))
  let message = InputWireMessage.clipboardUpdate(update)
  try pair.client.connection.send(message)
  #expect(pair.server.receipt.waitForMessages(1))
  let payloadMatches = pair.server.receipt.messages.first == message
  #expect(payloadMatches)
  try pair.server.connection.send(.clipboardUpdateApplied(update.id))
  #expect(pair.client.receipt.waitForMessages(1))
  #expect(pair.client.receipt.messages == [.clipboardUpdateApplied(update.id)])
  #expect(pair.server.receipt.failures.isEmpty)
}

// DM-040/001: wrong secrets must never deliver plaintext and must not poison a new connection.
@Test func loopbackTransportRejectsWrongKeyAndAcceptsNextConnection() throws {
  let harness = try LoopbackInputHarness()
  defer { harness.stop() }
  let rejected = try harness.connect(clientKey: "synthetic-wrong-secret")
  try rejected.client.connection.send(.ping(99))
  #expect(rejected.server.receipt.waitForFailure())
  #expect(rejected.server.receipt.messages.isEmpty)
  #expect(rejected.server.receipt.waitForCancellation())
  let fresh = try harness.connect()
  try fresh.client.connection.send(.ping(1))
  #expect(fresh.server.receipt.waitForMessages(1))
  #expect(fresh.server.receipt.messages == [.ping(1)])
  #expect(fresh.server.receipt.failures.isEmpty)
}

// A throwing protocol consumer is an existing seam: verify actual transport rejection, not a fake receiver policy.
@Test func loopbackTransportClosesWhenConsumerRejectsAuthenticatedMessage() throws {
  let harness = try LoopbackInputHarness { message in
    if case .hello(let peerID, _, _) = message, peerID.rawValue == "synthetic-allowed" { return }
    throw FixtureRejection.unexpectedPeerOrMessage
  }
  defer { harness.stop() }
  let rejected = try harness.connect()
  try rejected.client.connection.send(.hello(peerID: PeerID(rawValue: "synthetic-wrong-peer"),
    protocolVersion: InputWireMessage.currentProtocolVersion, purpose: .inputRelay))
  #expect(rejected.server.receipt.waitForFailure())
  #expect(rejected.server.receipt.messages.isEmpty)
  #expect(rejected.server.receipt.waitForCancellation())
  let accepted = try harness.connect()
  let hello = InputWireMessage.hello(peerID: PeerID(rawValue: "synthetic-allowed"),
    protocolVersion: InputWireMessage.currentProtocolVersion, purpose: .inputRelay)
  try accepted.client.connection.send(hello)
  #expect(accepted.server.receipt.waitForMessages(1))
  #expect(accepted.server.receipt.messages == [hello])
}

// DM-041: cancel must become terminal before delayed NWConnection callbacks can run.
@Test func loopbackCancelImmediatelyRejectsFurtherSends() throws {
  let harness = try LoopbackInputHarness()
  defer { harness.stop() }
  let pair = try harness.connect()
  harness.queue.suspend()
  defer { harness.queue.resume() }
  pair.client.connection.cancel()
  #expect(throws: InputPeerConnectionError.self) { try pair.client.connection.send(.ping(1)) }
}

// DM-042: multiple producers must not enqueue encrypted sequence N+1 before N.
@Test func loopbackConcurrentProducersPreserveEncryptedSequence() throws {
  let harness = try LoopbackInputHarness()
  defer { harness.stop() }
  let pair = try harness.connect()
  let errors = TransportReceipt()
  DispatchQueue.concurrentPerform(iterations: 8) { producer in
    for index in 0..<100 {
      do { try pair.client.connection.send(.ping(UInt64(producer * 100 + index))) }
      catch { errors.recordFailure(error) }
    }
  }
  #expect(pair.server.receipt.waitForMessages(800))
  #expect(pair.server.receipt.failures.isEmpty)
  let senderFailureCount = errors.failures.count
  #expect(senderFailureCount == 0)
  let values = pair.server.receipt.messages.compactMap { message -> UInt64? in
    guard case .ping(let value) = message else { return nil }
    return value
  }
  #expect(values.count == 800)
  let missingCount = Set((0..<800).map(UInt64.init)).subtracting(values).count
  #expect(missingCount == 0)
}

private enum FixtureRejection: Error { case unexpectedPeerOrMessage, timedOut }

private struct HarnessPeer: Sendable {
  let connection: InputPeerConnection
  let receipt: TransportReceipt
}

private final class LoopbackInputHarness: @unchecked Sendable {
  let queue = DispatchQueue(label: "dev.deskmux.tests.isolated-transport.\(UUID().uuidString)")
  private let listener: NWListener
  private let lock = NSLock()
  private let listenerReady = DispatchSemaphore(value: 0)
  private let acceptedReady = DispatchSemaphore(value: 0)
  private var accepted: [HarnessPeer] = []
  private var allPeers: [HarnessPeer] = []
  private let key = "synthetic-loopback-secret"

  init(consumer: @escaping @Sendable (InputWireMessage) throws -> Void = { _ in }) throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
    listener.stateUpdateHandler = { [weak self] state in
      if case .ready = state { self?.listenerReady.signal() }
    }
    listener.newConnectionHandler = { [weak self] nw in
      guard let self else { nw.cancel(); return }
      do {
        let receipt = TransportReceipt()
        let connection = try InputPeerConnection(connection: nw, sharedKey: self.key,
          role: .acceptor, queue: self.queue,
          messageHandler: { message in try consumer(message); receipt.record(message) },
          stateHandler: { receipt.record($0) })
        let peer = HarnessPeer(connection: connection, receipt: receipt)
        self.lock.withLock { self.accepted.append(peer); self.allPeers.append(peer) }
        connection.start()
        self.acceptedReady.signal()
      } catch { nw.cancel() }
    }
    listener.start(queue: queue)
    guard listenerReady.wait(timeout: .now() + 5) == .success else {
      listener.cancel()
      throw FixtureRejection.timedOut
    }
  }

  func connect(clientKey: String? = nil) throws -> (client: HarnessPeer, server: HarnessPeer) {
    guard let port = listener.port else { throw FixtureRejection.timedOut }
    let receipt = TransportReceipt()
    let connection = try InputPeerConnection(
      connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp),
      sharedKey: clientKey ?? key, role: .initiator, queue: queue,
      messageHandler: { receipt.record($0) }, stateHandler: { receipt.record($0) })
    let client = HarnessPeer(connection: connection, receipt: receipt)
    lock.withLock { allPeers.append(client) }
    connection.start()
    guard receipt.waitForReady(), acceptedReady.wait(timeout: .now() + 5) == .success else {
      throw FixtureRejection.timedOut
    }
    let server = lock.withLock { accepted.removeFirst() }
    guard server.receipt.waitForReady() else { throw FixtureRejection.timedOut }
    return (client, server)
  }

  func stop() {
    for peer in lock.withLock({ allPeers }) { peer.connection.cancel() }
    listener.cancel()
  }
}

final class TransportReceipt: @unchecked Sendable {
  private let lock = NSLock()
  private var storedMessages: [InputWireMessage] = []
  private var storedFailures: [String] = []
  private let messageSignal = DispatchSemaphore(value: 0)
  private let readySignal = DispatchSemaphore(value: 0)
  private let failureSignal = DispatchSemaphore(value: 0)
  private let cancelSignal = DispatchSemaphore(value: 0)
  var messages: [InputWireMessage] { lock.withLock { storedMessages } }
  var failures: [String] { lock.withLock { storedFailures } }

  func record(_ message: InputWireMessage) {
    lock.withLock { storedMessages.append(message) }
    messageSignal.signal()
  }
  func record(_ state: NWConnection.State) {
    switch state {
    case .ready: readySignal.signal()
    case .failed(let error): recordFailure(error)
    case .cancelled: cancelSignal.signal()
    default: break
    }
  }
  func recordFailure(_ error: Error) {
    lock.withLock { storedFailures.append(String(describing: error)) }
    failureSignal.signal()
  }
  func waitForReady() -> Bool { readySignal.wait(timeout: .now() + 5) == .success }
  func waitForFailure() -> Bool { failureSignal.wait(timeout: .now() + 5) == .success }
  func waitForCancellation() -> Bool { cancelSignal.wait(timeout: .now() + 5) == .success }
  func waitForMessages(_ count: Int) -> Bool {
    let deadline = DispatchTime.now() + 5
    while messages.count < count {
      if messageSignal.wait(timeout: deadline) == .timedOut { return messages.count >= count }
    }
    return true
  }
}
