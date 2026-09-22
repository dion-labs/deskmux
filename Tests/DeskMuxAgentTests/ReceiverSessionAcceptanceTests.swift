import DeskMuxCore
import DeskMuxMacInput
import Foundation
import Network
import Testing
@testable import DeskMuxInputTransport

// These fixtures instantiate the real ReceiverSession, but NEVER the native
// dependency factory, BonjourInputReceiver, input injector, clipboard or updater.
@Test func receiverHandshakeInputAndDisconnectReleaseHeldStateOnce() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.client.send(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 7))
  try fixture.client.send(.event(packet(session, 0, key: 42)))
  #expect(fixture.receipt.waitForMessages(2))
  let sink = try #require(fixture.effects.inputs.first)
  #expect(sink.heldKeys == [42])
  #expect(fixture.effects.registered == [session])
  #expect(fixture.effects.modifiers == [7])
  fixture.client.cancel()
  #expect(fixture.waitForEnd())
  fixture.server.stop()
  fixture.server.stop()
  #expect(sink.heldKeys.isEmpty)
  #expect(sink.releasedKeys == [42])
  #expect(sink.releaseCalls == 1)
  #expect(fixture.effects.unregistered == [session])
  #expect(fixture.endCount == 1)
}

@Test func receiverRejectsBeginBeforeHelloWithoutCreatingInput() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.client.send(.beginInput(sessionID: UUID(), mode: .keyboardOnly, initialModifierFlags: 0))
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.inputs.isEmpty)
  #expect(fixture.effects.modifiers.isEmpty)
}

@Test func receiverRejectsInputBeforeExplicitBegin() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  try fixture.client.send(.event(packet(UUID(), 0, key: 42)))
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.inputs.isEmpty)
  #expect(fixture.effects.registered.isEmpty)
}

@Test func receiverCannotChangeHelloIdentityOrPurposeMidConnection() throws {
  let fixture = try ReceiverAcceptanceHarness(acceptsUpdates: true)
  defer { fixture.stop() }
  try fixture.hello()
  try fixture.client.send(.hello(peerID: PeerID(rawValue: "different-synthetic-peer"),
    protocolVersion: InputWireMessage.currentProtocolVersion, purpose: .appUpdate))
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.installed.count == 0)
  #expect(fixture.receipt.messages.count == 1)
}

@Test func receiverDoesNotCreateASecondInputForDuplicateBegin() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.client.send(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  try fixture.client.send(.event(packet(session, 0, key: 42)))
  #expect(fixture.receipt.waitForMessages(2))
  try fixture.client.send(.beginInput(sessionID: UUID(), mode: .keyboardOnly, initialModifierFlags: 0))
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.inputs.count == 1)
  #expect(fixture.effects.inputs.first?.releasedKeys == [42])
}

// Native UUID/order/CGEvent validation remains a sink contract. This case proves
// receiver transport termination and cleanup when that contract rejects a packet.
@Test func receiverSinkSessionRejectionClosesTransportAndReleasesPriorInput() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.client.send(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  try fixture.client.send(.event(packet(session, 0, key: 42)))
  #expect(fixture.receipt.waitForMessages(2))
  try fixture.client.send(.event(packet(UUID(), 1, key: 43)))
  #expect(fixture.waitForEnd())
  let sink = try #require(fixture.effects.inputs.first)
  #expect(sink.accepted.count == 1)
  #expect(sink.releasedKeys == [42])
  #expect(fixture.receipt.messages.count == 2) // Ready + only the valid packet acknowledgement.
}

@Test func receiverMalformedSinkPayloadClosesWithoutAcknowledgement() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.client.send(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  try fixture.client.send(.event(InputEventPacket(sessionID: session, sequence: 0, kind: .keyDown, eventData: Data())))
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.inputs.first?.accepted.isEmpty == true)
  #expect(fixture.effects.unregistered == [session])
  #expect(fixture.receipt.messages.count == 1)
}

@Test func receiverTerminalSessionRejectsAlreadyDecodedTailFrame() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.client.send(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  try fixture.client.send(.event(packet(session, 0, key: 42)))
  #expect(fixture.receipt.waitForMessages(2))
  fixture.server.stop()
  #expect(fixture.waitForEnd())
  // Deterministic model of the next decoded frame in the same receive batch.
  #expect(throws: (any Error).self) { try fixture.server.handle(.event(packet(session, 1, key: 43))) }
  let sink = try #require(fixture.effects.inputs.first)
  #expect(sink.accepted.count == 1)
  #expect(sink.heldKeys.isEmpty)
  #expect(sink.releasedKeys == [42])
}

@Test(arguments: [false, true]) func receiverEncryptedGoodbyeBatchCannotApplyTailEffects(_ hasInput: Bool) throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  var frames: [InputWireMessage] = []
  if hasInput {
    frames += [.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0),
      .event(packet(session, 0, key: 42))]
  }
  frames.append(.goodbye)
  if !hasInput { frames.append(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0)) }
  frames.append(.event(packet(session, hasInput ? 1 : 0, key: 43)))
  frames.append(.clipboardUpdate(DeskMuxClipboardUpdate(sourcePeerID: fixture.peerID, text: "synthetic stale tail")))
  try fixture.client.sendBatch(frames) // One real TCP write containing separately encrypted frames.
  #expect(fixture.waitForEnd())
  fixture.drain()
  #expect(fixture.effects.clipboard.isEmpty)
  if hasInput {
    let sink = try #require(fixture.effects.inputs.first)
    #expect(sink.accepted.count == 1)
    #expect(sink.heldKeys.isEmpty)
    #expect(sink.releasedKeys == [42])
    #expect(fixture.effects.unregistered == [session])
  } else {
    #expect(fixture.effects.inputs.isEmpty)
    #expect(fixture.effects.registered.isEmpty)
  }
}

@Test func receiverStopDuringInputFactoryCannotRegisterAfterCleanup() throws {
  let effects = ReceiverFakeEffects()
  effects.pauseInputFactory()
  let fixture = try ReceiverAcceptanceHarness(effects: effects)
  defer { effects.resumeInputFactory(); fixture.stop() }
  try fixture.hello()
  try fixture.client.send(.beginInput(sessionID: UUID(), mode: .keyboardOnly, initialModifierFlags: 7))
  #expect(effects.waitForInputFactory())
  let stopped = DispatchSemaphore(value: 0)
  DispatchQueue.global().async { fixture.server.stop(); stopped.signal() }
  let stopReturned = stopped.wait(timeout: .now() + 2) == .success
  effects.resumeInputFactory() // Always unblock the receiver even if the assertion fails.
  #expect(stopReturned)
  #expect(fixture.waitForEnd())
  fixture.drain()
  #expect(effects.registered.isEmpty)
  #expect(effects.modifiers.isEmpty)
  #expect(effects.inputs.allSatisfy { $0.heldKeys.isEmpty })
  #expect(fixture.endCount == 1)
}

@Test func receiverLocalReturnPreventsLaterInputFromIgnoringPeer() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.client.send(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  try fixture.client.send(.event(packet(session, 0, key: 42)))
  #expect(fixture.receipt.waitForMessages(2))
  fixture.server.requestReturnInput()
  #expect(fixture.receipt.waitForMessages(3))
  try fixture.client.send(.event(packet(session, 1, key: 43)))
  #expect(fixture.waitForEnd())
  let sink = try #require(fixture.effects.inputs.first)
  #expect(sink.accepted.count == 1)
  #expect(sink.heldKeys.isEmpty)
  #expect(sink.releasedKeys == [42])
}

@Test(arguments: [0, 1, 2]) func receiverClipboardRejectsMissingHelloWrongSourceAndOversize(_ variant: Int) throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  if variant != 0 { try fixture.hello() }
  let update = DeskMuxClipboardUpdate(
    sourcePeerID: variant == 1 ? PeerID(rawValue: "wrong-synthetic-peer") : fixture.peerID,
    text: variant == 2 ? String(repeating: "a", count: DeskMuxClipboardUpdate.maximumUTF8Size + 1) : "synthetic text")
  try fixture.client.send(.clipboardUpdate(update))
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.clipboard.isEmpty)
}

@Test func receiverOldClipboardCompletionCannotAcknowledgeIntoNewConnection() throws {
  let effects = ReceiverFakeEffects()
  let old = try ReceiverAcceptanceHarness(effects: effects)
  defer { old.stop() }
  try old.hello()
  let update = DeskMuxClipboardUpdate(sourcePeerID: old.peerID, text: "synthetic old text")
  try old.client.send(.clipboardUpdate(update))
  #expect(effects.waitForClipboard())
  old.client.cancel()
  #expect(old.waitForEnd())
  let fresh = try ReceiverAcceptanceHarness(effects: effects)
  defer { fresh.stop() }
  try fresh.hello()
  effects.completeClipboard()
  try fresh.client.send(.ping(77))
  #expect(fresh.receipt.waitForMessages(2))
  #expect(fresh.receipt.messages.last == .pong(77))
  #expect(!fresh.receipt.messages.contains(.clipboardUpdateApplied(update.id)))
  // This proves callback routing only; stale physical pasteboard application is
  // not certified by a fake completion and needs an explicit cancellable sink.
}

@Test func receiverClipboardAcknowledgesOnlyAfterFakeApplication() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let update = DeskMuxClipboardUpdate(sourcePeerID: fixture.peerID, text: "synthetic text")
  try fixture.client.send(.clipboardUpdate(update))
  #expect(fixture.effects.waitForClipboard())
  #expect(fixture.receipt.messages.count == 1)
  fixture.effects.completeClipboard()
  #expect(fixture.receipt.waitForMessages(2))
  #expect(fixture.receipt.messages.last == .clipboardUpdateApplied(update.id))
}

@Test(arguments: [false, true]) func receiverInstallerRequiresExplicitCapability(_ enabled: Bool) throws {
  let fixture = try ReceiverAcceptanceHarness(acceptsUpdates: enabled)
  defer { fixture.stop() }
  try fixture.hello(purpose: .appUpdate, version: 2)
  let package = DeskMuxUpdatePackage(version: "fixture", build: "2", bundleIdentifier: "synthetic",
    archiveSHA256: "fixture", archiveData: Data([0]))
  try fixture.client.send(.appUpdate(package))
  if enabled {
    #expect(fixture.receipt.waitForMessages(2))
    #expect(fixture.receipt.messages.last == .appUpdateResult(.rejected(reason: "synthetic installer")))
    #expect(fixture.effects.installed.count == 1)
    #expect(fixture.effects.installed.first?.1 == fixture.peerID)
  } else {
    #expect(fixture.waitForEnd())
    #expect(fixture.effects.installed.isEmpty)
  }
}

@Test func receiverAdmittedInstallerCanFinishAfterStopWithoutNewAdmission() throws {
  let effects = ReceiverFakeEffects()
  effects.pauseInstaller()
  let fixture = try ReceiverAcceptanceHarness(effects: effects, acceptsUpdates: true)
  defer { effects.resumeInstaller(); fixture.stop() }
  try fixture.hello(purpose: .appUpdate)
  let package = DeskMuxUpdatePackage(version: "fixture", build: "2", bundleIdentifier: "synthetic",
    archiveSHA256: "fixture", archiveData: Data([0]))
  try fixture.client.send(.appUpdate(package))
  #expect(effects.waitForInstaller())
  fixture.server.stop()
  #expect(fixture.waitForEnd())
  #expect(throws: (any Error).self) { try fixture.server.handle(.appUpdate(package)) }
  effects.resumeInstaller()
  fixture.drain()
  #expect(effects.installed.count == 1)
  #expect(!fixture.receipt.messages.contains(.appUpdateResult(.rejected(reason: "synthetic installer"))))
}

@Test(arguments: [InputWireMessage.pong(1), .ready(peerID: PeerID(rawValue: "fixture"), motionPort: nil),
  .eventAck(sequence: 1, receiverProcessingNanoseconds: 0), .appUpdateResult(.accepted(build: "fixture")),
  .clipboardUpdateApplied(UUID())])
func receiverRejectsUnsupportedInboundMessageDirection(_ message: InputWireMessage) throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  try fixture.client.send(message)
  #expect(fixture.waitForEnd())
  #expect(fixture.effects.inputs.isEmpty)
  #expect(fixture.effects.clipboard.isEmpty)
  #expect(fixture.effects.installed.isEmpty)
}

@Test(arguments: [1, InputWireMessage.currentProtocolVersion - 1, InputWireMessage.currentProtocolVersion + 1])
func receiverRejectsUnsupportedInputProtocolVersion(_ version: Int) throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.client.send(.hello(peerID: fixture.peerID, protocolVersion: version, purpose: .inputRelay))
  #expect(fixture.waitForEnd())
  #expect(fixture.receipt.messages.isEmpty)
  #expect(fixture.effects.inputs.isEmpty)
}

private func packet(_ session: UUID, _ sequence: UInt64, key: UInt8) -> InputEventPacket {
  InputEventPacket(sessionID: session, sequence: sequence, kind: .keyDown, eventData: Data([key]))
}

@Test(arguments: [false, true]) func receiverMotionCannotContinueAfterReturnOrStop(_ returning: Bool) throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.server.handle(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  let sink = try #require(fixture.effects.inputs.first)
  let motion = PointerMotionState(sessionID: session, sequence: 0, kind: .mouseMoved,
    cumulativeDeltaX: 1, cumulativeDeltaY: 2)
  fixture.effects.motionRegistry.inject(motion)
  #expect(sink.motionCount == 1)
  if returning { fixture.server.requestReturnInput() } else { fixture.server.stop() }
  fixture.effects.motionRegistry.inject(motion)
  #expect(sink.motionCount == 1)
}

@Test func receiverMotionInFlightCompletesBeforeTerminalRelease() throws {
  let fixture = try ReceiverAcceptanceHarness()
  defer { fixture.stop() }
  try fixture.hello()
  let session = UUID()
  try fixture.server.handle(.beginInput(sessionID: session, mode: .keyboardOnly, initialModifierFlags: 0))
  let sink = try #require(fixture.effects.inputs.first)
  sink.pauseMotion()
  let motionDone = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    fixture.effects.motionRegistry.inject(PointerMotionState(sessionID: session, sequence: 0,
      kind: .mouseMoved, cumulativeDeltaX: 1, cumulativeDeltaY: 2))
    motionDone.signal()
  }
  #expect(sink.waitForMotion())
  let stopping = DispatchSemaphore(value: 0)
  let stopped = DispatchSemaphore(value: 0)
  DispatchQueue.global().async { stopping.signal(); fixture.server.stop(); stopped.signal() }
  #expect(stopping.wait(timeout: .now() + 5) == .success)
  // A terminal operation must wait for the already-admitted motion effect.
  #expect(stopped.wait(timeout: .now() + 0.05) == .timedOut)
  sink.resumeMotion()
  #expect(motionDone.wait(timeout: .now() + 5) == .success)
  #expect(fixture.waitForEnd())
  #expect(sink.effectOrder == ["motion", "release"])
}

private enum ReceiverFixtureError: Error { case timeout, malformedSyntheticPacket }

private final class ReceiverAcceptanceHarness: @unchecked Sendable {
  let peerID = PeerID(rawValue: "synthetic-\(UUID().uuidString)")
  let effects: ReceiverFakeEffects
  let receipt = TransportReceipt()
  private let queue = DispatchQueue(label: "dev.deskmux.tests.receiver.\(UUID().uuidString)")
  private let listener: NWListener
  private let lock = NSLock()
  private var storedClient: ReceiverWireClient?
  private var storedServer: ReceiverSession?
  private var endedCount = 0
  private let ready = DispatchSemaphore(value: 0)
  private let accepted = DispatchSemaphore(value: 0)
  private let ended = DispatchSemaphore(value: 0)
  var client: ReceiverWireClient { lock.withLock { storedClient! } }
  var server: ReceiverSession { lock.withLock { storedServer! } }
  var endCount: Int { lock.withLock { endedCount } }

  init(effects: ReceiverFakeEffects = ReceiverFakeEffects(), acceptsUpdates: Bool = false) throws {
    self.effects = effects
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
    listener.stateUpdateHandler = { [weak self] state in if case .ready = state { self?.ready.signal() } }
    listener.newConnectionHandler = { [weak self] nw in
      guard let self else { nw.cancel(); return }
      do {
        let session = try ReceiverSession(localPeerID: PeerID(rawValue: "synthetic-receiver"),
          nwConnection: nw, sharedKey: "synthetic-receiver-secret", acceptsAppUpdates: acceptsUpdates,
          dependencies: effects.dependencies, motionPort: nil, queue: self.queue,
          activityChanged: { _ in }, ended: { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.endedCount += 1 }
            self.ended.signal()
          })
        self.lock.withLock { self.storedServer = session }
        session.start()
        self.accepted.signal()
      } catch { nw.cancel() }
    }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
      listener.cancel(); throw ReceiverFixtureError.timeout
    }
    let client = try ReceiverWireClient(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp),
      queue: queue, receipt: receipt)
    lock.withLock { storedClient = client }
    client.start()
    guard receipt.waitForReady(), accepted.wait(timeout: .now() + 5) == .success else {
      stop(); throw ReceiverFixtureError.timeout
    }
  }

  func hello(purpose: PeerSessionPurpose = .inputRelay, version: Int = InputWireMessage.currentProtocolVersion) throws {
    try client.send(.hello(peerID: peerID, protocolVersion: version, purpose: purpose))
    guard receipt.waitForMessages(1) else { throw ReceiverFixtureError.timeout }
  }
  func waitForEnd() -> Bool { ended.wait(timeout: .now() + 5) == .success }
  func drain() { queue.sync {} }
  func stop() {
    let pair = lock.withLock { (storedClient, storedServer) }
    pair.0?.cancel(); pair.1?.stop(); listener.cancel()
  }
}

private final class ReceiverFakeEffects: @unchecked Sendable {
  private let lock = NSLock()
  private var storedInputs: [ReceiverFakeInput] = []
  private var storedRegistered: [UUID] = []
  private var storedUnregistered: [UUID] = []
  private var storedModifiers: [UInt64] = []
  private var storedClipboard: [(DeskMuxClipboardUpdate, @Sendable () -> Void)] = []
  private var storedInstalled: [(DeskMuxUpdatePackage, PeerID?)] = []
  let motionRegistry = MotionSessionRegistry()
  private let clipboardSignal = DispatchSemaphore(value: 0)
  private var installerPaused = false
  private let installerStarted = DispatchSemaphore(value: 0)
  private let installerResume = DispatchSemaphore(value: 0)
  private var factoryPaused = false
  private let factoryStarted = DispatchSemaphore(value: 0)
  private let factoryResume = DispatchSemaphore(value: 0)
  var inputs: [ReceiverFakeInput] { lock.withLock { storedInputs } }
  var registered: [UUID] { lock.withLock { storedRegistered } }
  var unregistered: [UUID] { lock.withLock { storedUnregistered } }
  var modifiers: [UInt64] { lock.withLock { storedModifiers } }
  var clipboard: [DeskMuxClipboardUpdate] { lock.withLock { storedClipboard.map { $0.0 } } }
  var installed: [(DeskMuxUpdatePackage, PeerID?)] { lock.withLock { storedInstalled } }
  var dependencies: ReceiverSessionDependencies {
    ReceiverSessionDependencies(
      makeInput: { [self] id in
        if lock.withLock({ factoryPaused }) {
          factoryStarted.signal()
          guard factoryResume.wait(timeout: .now() + 5) == .success else { throw ReceiverFixtureError.timeout }
        }
        let sink = ReceiverFakeInput(sessionID: id)
        lock.withLock { storedInputs.append(sink) }
        return sink
      },
      registerInput: { [self] sink in
        motionRegistry.register(sink)
        lock.withLock { storedRegistered.append(sink.sessionID) }
      },
      unregisterInput: { [self] id in
        motionRegistry.unregister(sessionID: id)
        lock.withLock { storedUnregistered.append(id) }
      },
      publishModifiers: { [self] flags in lock.withLock { storedModifiers.append(flags) } },
      makeEscapeMonitor: { _ in ReceiverFakeEscapeMonitor() },
      applyClipboard: { [self] update, completion in
        lock.withLock { storedClipboard.append((update, completion)) }
        clipboardSignal.signal()
      },
      installUpdate: { [self] package, peer in
        lock.withLock { storedInstalled.append((package, peer)) }
        if lock.withLock({ installerPaused }) {
          installerStarted.signal()
          _ = installerResume.wait(timeout: .now() + 5)
        }
        return .rejected(reason: "synthetic installer")
      })
  }
  func pauseInstaller() { lock.withLock { installerPaused = true } }
  func waitForInstaller() -> Bool { installerStarted.wait(timeout: .now() + 5) == .success }
  func resumeInstaller() { installerResume.signal() }
  func pauseInputFactory() { lock.withLock { factoryPaused = true } }
  func waitForInputFactory() -> Bool { factoryStarted.wait(timeout: .now() + 5) == .success }
  func resumeInputFactory() { factoryResume.signal() }
  func waitForClipboard() -> Bool { clipboardSignal.wait(timeout: .now() + 5) == .success }
  func completeClipboard() {
    let completions = lock.withLock { storedClipboard.map { $0.1 } }
    for completion in completions { completion() }
  }
}

private final class ReceiverFakeInput: ReceiverInputSink, @unchecked Sendable {
  let sessionID: UUID
  private let lock = NSLock()
  private var sequence: UInt64 = 0
  private var packets: [InputEventPacket] = []
  private var held = Set<UInt8>()
  private var released: [UInt8] = []
  private var releases = 0
  private var motions = 0
  private var order: [String] = []
  private var motionPaused = false
  private let motionStarted = DispatchSemaphore(value: 0)
  private let motionResume = DispatchSemaphore(value: 0)
  var motionCount: Int { lock.withLock { motions } }
  var effectOrder: [String] { lock.withLock { order } }
  func pauseMotion() { lock.withLock { motionPaused = true } }
  func waitForMotion() -> Bool { motionStarted.wait(timeout: .now() + 5) == .success }
  func resumeMotion() { motionResume.signal() }
  init(sessionID: UUID) { self.sessionID = sessionID }
  var accepted: [InputEventPacket] { lock.withLock { packets } }
  var heldKeys: Set<UInt8> { lock.withLock { held } }
  var releasedKeys: [UInt8] { lock.withLock { released } }
  var releaseCalls: Int { lock.withLock { releases } }
  func inject(_ packet: InputEventPacket) throws {
    try lock.withLock {
      guard packet.sessionID == sessionID else {
        throw MacInputInjectorError.wrongSession(expected: sessionID, received: packet.sessionID)
      }
      guard packet.sequence == sequence else { throw MacInputInjectorError.outOfOrder(expected: sequence, received: packet.sequence) }
      guard packet.eventData.count == 1, let key = packet.eventData.first else { throw ReceiverFixtureError.malformedSyntheticPacket }
      packets.append(packet)
      if packet.kind == .keyDown { held.insert(key) }
      if packet.kind == .keyUp { held.remove(key) }
      sequence += 1
    }
  }
  func injectPointerMotion(_ state: PointerMotionState) throws {
    if lock.withLock({ motionPaused }) {
      motionStarted.signal()
      guard motionResume.wait(timeout: .now() + 5) == .success else { throw ReceiverFixtureError.timeout }
    }
    lock.withLock { motions += 1; order.append("motion") }
  }
  func releaseAll() {
    lock.withLock { order.append("release"); releases += 1; released.append(contentsOf: held.sorted()); held.removeAll() }
  }
}

private final class ReceiverFakeEscapeMonitor: ReceiverEscapeMonitor, @unchecked Sendable {
  func run() throws {}
  func stop() {}
}

// Test-only raw encrypted endpoint enables a single socket write with multiple
// valid frames, including a terminal frame followed by adversarial tail frames.
private final class ReceiverWireClient: @unchecked Sendable {
  private let connection: NWConnection
  private let queue: DispatchQueue
  private let receipt: TransportReceipt
  private let codec: SecureInputFrameCodec
  private let lock = NSLock()
  private var ready = false
  private var parser = InputFrameParser()

  init(connection: NWConnection, queue: DispatchQueue, receipt: TransportReceipt) throws {
    self.connection = connection
    self.queue = queue
    self.receipt = receipt
    codec = try SecureInputFrameCodec(sharedKey: "synthetic-receiver-secret", role: .initiator)
  }
  func start() {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      lock.withLock { if case .ready = state { ready = true } else { ready = false } }
      receipt.record(state)
      if case .ready = state { receive() }
    }
    connection.start(queue: queue)
  }
  func send(_ message: InputWireMessage) throws { try sendBatch([message]) }
  func sendBatch(_ messages: [InputWireMessage]) throws {
    try lock.withLock {
      guard ready else { throw InputPeerConnectionError.notReady }
      let bytes = try messages.reduce(into: Data()) { $0.append(try codec.seal($1)) }
      connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
        if let error { self?.receipt.recordFailure(error) }
      })
    }
  }
  func cancel() {
    lock.withLock { ready = false }
    connection.cancel()
  }
  private func receive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
      guard let self else { return }
      do {
        if let data {
          for frame in try parser.append(data) { receipt.record(try codec.open(frame)) }
        }
      } catch { receipt.recordFailure(error); cancel(); return }
      if error != nil || complete { cancel() } else { receive() }
    }
  }
}
