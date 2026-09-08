import CoreGraphics
import DeskMuxAgentIPC
import DeskMuxCore
import DeskMuxMacInput
import Foundation
import Network
import Testing

@testable import DeskMuxInputTransport

@Test func clipboardUpdatesEnforceThePlainTextPayloadLimit() {
  let accepted = DeskMuxClipboardUpdate(
    sourcePeerID: PeerID(rawValue: "studio"),
    text: String(repeating: "a", count: DeskMuxClipboardUpdate.maximumUTF8Size)
  )
  let rejected = DeskMuxClipboardUpdate(
    sourcePeerID: PeerID(rawValue: "studio"),
    text: String(repeating: "é", count: DeskMuxClipboardUpdate.maximumUTF8Size / 2 + 1)
  )

  #expect(accepted.isWithinSizeLimit)
  #expect(!rejected.isWithinSizeLimit)
}

@Test func newMenuCanDecodeStatusFromAnOlderAgentBuild() throws {
  let legacyStatus = Data(
    """
    {"processIdentifier":42,"canListen":true,"canPost":true,"receiverState":"ready"}
    """.utf8)
  let decoded = try JSONDecoder().decode(DeskMuxAgentStatus.self, from: legacyStatus)
  #expect(decoded.processIdentifier == 42)
  #expect(decoded.agentBuild == nil)
  #expect(decoded.receiverState == .ready)
}

@Test func newestBonjourCollisionGetsHighestRank() {
  let peerID = PeerID(rawValue: "macbook")
  #expect(deskMuxServiceRank(name: "macbook", peerID: peerID) == 1)
  #expect(deskMuxServiceRank(name: "macbook (2)", peerID: peerID) == 2)
  #expect(deskMuxServiceRank(name: "macbook (12)", peerID: peerID) == 12)
  #expect(deskMuxServiceRank(name: "other", peerID: peerID) == nil)
}

@Test func updatesMigrateBootstrapCopiesIntoUserApplications() {
  let layout = DeskMuxInstallLayout(
    currentAppURL: URL(fileURLWithPath: "/Users/test/Downloads/DeskMux.app"),
    applicationsDirectory: URL(fileURLWithPath: "/Users/test/Applications")
  )

  #expect(!layout.currentIsCanonical)
  #expect(layout.installedAppURL.path == "/Users/test/Applications/DeskMux.app")
  #expect(layout.canonicalBackupURL.path == "/Users/test/Applications/.DeskMux.previous")
  #expect(layout.migratedBackupURL.path == "/Users/test/Downloads/.DeskMux.migrated.previous")
}

@Test func updatesRecognizeAnExistingCanonicalInstallation() {
  let layout = DeskMuxInstallLayout(
    currentAppURL: URL(fileURLWithPath: "/Users/test/Applications/DeskMux.app"),
    applicationsDirectory: URL(fileURLWithPath: "/Users/test/Applications")
  )

  #expect(layout.currentIsCanonical)
}

@Test func stableAgentUpdatesResolveTheirEnclosingDeskMuxApplication() throws {
  let fileManager = FileManager.default
  let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
    "deskmux-enclosing-app-test-\(UUID().uuidString)",
    isDirectory: true
  )
  let appURL = temporaryRoot.appendingPathComponent("DeskMux.app", isDirectory: true)
  let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
  let agentURL = contentsURL.appendingPathComponent(
    "Library/LoginItems/DeskMux Agent.app",
    isDirectory: true
  )
  try fileManager.createDirectory(at: agentURL, withIntermediateDirectories: true)
  let info: [String: Any] = [
    "CFBundleIdentifier": "dev.deskmux.app",
    "CFBundlePackageType": "APPL",
  ]
  let infoData = try PropertyListSerialization.data(
    fromPropertyList: info,
    format: .xml,
    options: 0
  )
  try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
  defer { try? fileManager.removeItem(at: temporaryRoot) }

  #expect(
    DeskMuxAppUpdateInstaller.enclosingDeskMuxAppURL(startingAt: agentURL)
      == appURL
  )
}

@Test func peerToPeerRouteOutranksAStaleInfrastructureRoute() {
  let awdl = deskMuxRoutePriority(interfaceName: "awdl0", interfaceType: .other)
  let ethernet = deskMuxRoutePriority(interfaceName: "en0", interfaceType: .wiredEthernet)
  let wifi = deskMuxRoutePriority(interfaceName: "en1", interfaceType: .wifi)
  #expect(awdl > ethernet)
  #expect(ethernet > wifi)
}

@Test func versionAdvertisementRoundTripsThroughBonjourTXT() throws {
  let advertised = DeskMuxVersionAdvertisement(
    component: .agent,
    build: "20260825101000",
    protocolVersion: 7
  )
  let decoded = try #require(
    DeskMuxVersionAdvertisement(txtRecord: advertised.txtRecord)
  )
  #expect(decoded == advertised)
}

@Test func incompleteOrMislabeledVersionAdvertisementIsNotTrusted() {
  #expect(
    DeskMuxVersionAdvertisement(
      txtRecord: NWTXTRecord(["component": "agent", "build": "20260825101000"])
    ) == nil
  )
  #expect(
    DeskMuxVersionAdvertisement(
      txtRecord: NWTXTRecord([
        "component": "unknown",
        "build": "20260825101000",
        "protocol": "7",
      ])
    ) == nil
  )
}

@Test func encryptedPeerHandshakeWorksOverARealLoopbackSocket() throws {
  let key = "loopback integration secret"
  let queue = DispatchQueue(label: "dev.deskmux.tests.network")
  let completed = DispatchSemaphore(value: 0)
  let state = ConnectionTestState()
  let listener = try NWListener(using: .tcp, on: .any)

  listener.newConnectionHandler = { nwConnection in
    do {
      let accepted = try InputPeerConnection(
        connection: nwConnection,
        sharedKey: key,
        role: .acceptor,
        queue: queue,
        messageHandler: { message in
          switch message {
          case .hello(let peerID, let version, let purpose):
            state.recordHello(peerID: peerID, version: version)
            state.helloPurpose = purpose
            try state.accepted?.send(
              .ready(peerID: PeerID(rawValue: "macbook"), motionPort: 49_876))
          case .ping(let nonce):
            try state.accepted?.send(.pong(nonce))
          case .beginInput(let sessionID, let mode, let initialModifierFlags):
            state.recordBeginInput(
              sessionID: sessionID,
              mode: mode,
              initialModifierFlags: initialModifierFlags
            )
            completed.signal()
          default:
            break
          }
        },
        stateHandler: { _ in }
      )
      state.accepted = accepted
      accepted.start()
    } catch {
      state.error = error
      completed.signal()
    }
  }
  listener.stateUpdateHandler = { listenerState in
    guard case .ready = listenerState, let port = listener.port else { return }
    do {
      let initiated = try InputPeerConnection(
        connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp),
        sharedKey: key,
        role: .initiator,
        queue: queue,
        messageHandler: { message in
          switch message {
          case .ready(let peerID, _):
            state.readyPeerID = peerID
            try state.initiated?.send(.ping(42))
          case .pong(42):
            try state.initiated?.send(
              .beginInput(
                sessionID: state.expectedSessionID,
                mode: .keyboardOnly,
                initialModifierFlags: CGEventFlags.maskAlternate.rawValue
              ))
          default:
            break
          }
        },
        stateHandler: { connectionState in
          guard case .ready = connectionState else { return }
          do {
            try state.initiated?.send(
              .hello(
                peerID: PeerID(rawValue: "studio"),
                protocolVersion: InputWireMessage.currentProtocolVersion,
                purpose: .inputRelay
              ))
          } catch {
            state.error = error
            completed.signal()
          }
        }
      )
      state.initiated = initiated
      initiated.start()
    } catch {
      state.error = error
      completed.signal()
    }
  }

  listener.start(queue: queue)
  #expect(completed.wait(timeout: .now() + 5) == .success)
  listener.cancel()
  state.initiated?.cancel()
  state.accepted?.cancel()

  #expect(state.error == nil)
  #expect(state.helloPeerID == PeerID(rawValue: "studio"))
  #expect(state.helloVersion == InputWireMessage.currentProtocolVersion)
  #expect(state.helloPurpose == .inputRelay)
  #expect(state.readyPeerID == PeerID(rawValue: "macbook"))
  #expect(state.beginInputSessionID == state.expectedSessionID)
  #expect(state.beginInputMode == .keyboardOnly)
  #expect(state.beginInputModifierFlags == CGEventFlags.maskAlternate.rawValue)
}

@Test func warmHeartbeatWaitsForPongAndExpiresMissingReply() {
  var heartbeat = InputRelayHeartbeatState(timeoutNanoseconds: 3_000)
  #expect(heartbeat.tick(at: 1_000) == .send(10_000_000))
  #expect(heartbeat.tick(at: 3_999) == .none)
  #expect(heartbeat.tick(at: 4_000) == .expired)
}

@Test func warmHeartbeatRecordsRoundTripAndAdvancesNonce() {
  var heartbeat = InputRelayHeartbeatState(timeoutNanoseconds: 3_000)
  #expect(heartbeat.tick(at: 10_000) == .send(10_000_000))
  let wrongNonce = heartbeat.receivePong(9_999_999, at: 10_500)
  let matched = heartbeat.receivePong(10_000_000, at: 10_750)
  #expect(!wrongNonce)
  #expect(matched)
  #expect(heartbeat.lastRoundTripMilliseconds == 0.00075)
  #expect(heartbeat.tick(at: 11_000) == .send(10_000_001))
}

@Test func pointerMotionIsCoalescedBeforeReliableInputWithoutLosingDeltas() throws {
  let sessionID = UUID()
  let state = PacketSenderTestState()
  let sender = LowLatencyInputSender(
    maximumMotionRate: 1,
    packetSender: { state.append($0) },
    failureHandler: { state.failure = $0 }
  )

  #expect(sender.submit(try motionPacket(sessionID: sessionID, sequence: 10, dx: 3, dy: -2)))
  #expect(sender.submit(try motionPacket(sessionID: sessionID, sequence: 11, dx: 4, dy: 3)))
  let keyEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
  #expect(
    sender.submit(
      try MacInputEventCodec.encode(keyEvent, sessionID: sessionID, sequence: 12)
    ))
  sender.flush()

  let packets = state.packets
  #expect(state.failure == nil)
  #expect(packets.count == 2)
  #expect(packets.map(\.sequence) == [0, 1])
  #expect(packets.map(\.kind) == [.mouseMoved, .keyDown])
  let motion = try MacInputEventCodec.decode(packets[0])
  #expect(motion.getIntegerValueField(.mouseEventDeltaX) == 7)
  #expect(motion.getIntegerValueField(.mouseEventDeltaY) == 1)
}

@Test func senderStopsAddingToNetworkQueueUntilReceiverAcknowledges() throws {
  let sessionID = UUID()
  let state = PacketSenderTestState()
  let sender = LowLatencyInputSender(
    maximumMotionRate: 10_000,
    maximumUnacknowledgedPackets: 2,
    packetSender: { state.append($0) },
    failureHandler: { state.failure = $0 }
  )

  for sequence in 0..<3 {
    let keyEvent = CGEvent(
      keyboardEventSource: nil,
      virtualKey: CGKeyCode(sequence),
      keyDown: true
    )!
    #expect(
      sender.submit(
        try MacInputEventCodec.encode(
          keyEvent,
          sessionID: sessionID,
          sequence: UInt64(sequence)
        )
      ))
  }

  #expect(state.waitForPacketCount(2, timeout: 1))
  #expect(state.packets.map(\.sequence) == [0, 1])
  sender.acknowledge(through: 0)
  #expect(state.waitForPacketCount(3, timeout: 1))
  #expect(state.packets.map(\.sequence) == [0, 1, 2])
  sender.stop(discardPending: true)
}

@Test func pointerMotionUsesImmediateDatagramsWithoutCreatingReliableSequenceGaps() throws {
  let sessionID = UUID()
  let reliable = PacketSenderTestState()
  let motion = PacketSenderTestState()
  let sender = LowLatencyInputSender(
    maximumMotionRate: 1,
    packetSender: { reliable.append($0) },
    motionSender: { motion.append($0) },
    failureHandler: { reliable.failure = $0 }
  )

  #expect(sender.submit(try motionPacket(sessionID: sessionID, sequence: 8, dx: 2, dy: 3)))
  #expect(sender.submit(try motionPacket(sessionID: sessionID, sequence: 9, dx: 4, dy: -1)))
  let keyEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
  #expect(
    sender.submit(
      try MacInputEventCodec.encode(keyEvent, sessionID: sessionID, sequence: 10)
    ))
  sender.flush()

  #expect(motion.waitForPacketCount(2, timeout: 1))
  #expect(reliable.waitForPacketCount(1, timeout: 1))
  #expect(motion.packets.map(\.sequence) == [0, 1])
  #expect(reliable.packets.map(\.sequence) == [0])
  let firstMotion = try MacInputEventCodec.decode(motion.packets[0])
  let secondMotion = try MacInputEventCodec.decode(motion.packets[1])
  #expect(firstMotion.getIntegerValueField(.mouseEventDeltaX) == 2)
  #expect(firstMotion.getIntegerValueField(.mouseEventDeltaY) == 3)
  #expect(secondMotion.getIntegerValueField(.mouseEventDeltaX) == 4)
  #expect(secondMotion.getIntegerValueField(.mouseEventDeltaY) == -1)
  sender.stop(discardPending: true)
}

@Test func encryptedPointerMotionCrossesARealNegotiatedDatagramConnection() throws {
  let sharedKey = "loopback pointer motion secret"
  let received = MotionStateTestState()
  let receiver = try BonjourPointerMotionReceiver(
    sharedKey: sharedKey,
    motionHandler: { received.record($0) }
  )
  try receiver.start()
  let port = try #require(receiver.port)
  let source = try PointerMotionDatagramSource(
    endpoint: .hostPort(host: "127.0.0.1", port: port),
    sharedKey: sharedKey
  )
  try source.start(timeout: 5)
  let sessionID = UUID()
  try source.send(try motionPacket(sessionID: sessionID, sequence: 4, dx: 11, dy: -4))

  #expect(received.signal.wait(timeout: .now() + 5) == .success)
  #expect(received.state?.sessionID == sessionID)
  #expect(received.state?.sequence == 4)
  #expect(received.state?.cumulativeDeltaX == 11)
  #expect(received.state?.cumulativeDeltaY == -4)
  let echoDeadline = Date().addingTimeInterval(2)
  while source.statistics.roundTripSamplesMilliseconds.isEmpty, Date() < echoDeadline {
    Thread.sleep(forTimeInterval: 0.01)
  }
  #expect(source.statistics.echoesExpected == 1)
  #expect(source.statistics.roundTripSamplesMilliseconds.count == 1)
  source.stop()
  receiver.stop()
}

@Test func motionTraceRecorderRejectsEveryNonMotionInputKind() throws {
  let recorder = MotionTraceRecorder()
  let sessionID = UUID()
  recorder.record(try motionPacket(sessionID: sessionID, sequence: 0, dx: 2, dy: 1), at: 100)
  let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
  recorder.record(
    try MacInputEventCodec.encode(key, sessionID: sessionID, sequence: 1),
    at: 200
  )
  let drag = try #require(
    CGEvent(
      mouseEventSource: nil,
      mouseType: .leftMouseDragged,
      mouseCursorPosition: .zero,
      mouseButton: .left
    ))
  recorder.record(
    try MacInputEventCodec.encode(drag, sessionID: sessionID, sequence: 2),
    at: 250
  )
  recorder.record(try motionPacket(sessionID: sessionID, sequence: 3, dx: 3, dy: -1), at: 350)

  #expect(recorder.trace.samples.count == 2)
  #expect(recorder.trace.samples.map(\.offsetNanoseconds) == [0, 250])
  #expect(recorder.trace.samples.allSatisfy { $0.kind == .mouseMoved })
}

private func motionPacket(
  sessionID: UUID,
  sequence: UInt64,
  dx: Int64,
  dy: Int64
) throws -> InputEventPacket {
  let event = CGEvent(
    mouseEventSource: nil,
    mouseType: .mouseMoved,
    mouseCursorPosition: .zero,
    mouseButton: .left
  )!
  event.setIntegerValueField(.mouseEventDeltaX, value: dx)
  event.setIntegerValueField(.mouseEventDeltaY, value: dy)
  return try MacInputEventCodec.encode(event, sessionID: sessionID, sequence: sequence)
}

private final class PacketSenderTestState: @unchecked Sendable {
  private let lock = NSLock()
  private var _packets: [InputEventPacket] = []
  private var _failure: Error?

  var packets: [InputEventPacket] { lock.withLock { _packets } }
  var failure: Error? {
    get { lock.withLock { _failure } }
    set { lock.withLock { _failure = newValue } }
  }

  func append(_ packet: InputEventPacket) {
    lock.withLock { _packets.append(packet) }
  }

  func waitForPacketCount(_ count: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if packets.count >= count { return true }
      Thread.sleep(forTimeInterval: 0.001)
    }
    return packets.count >= count
  }
}

private final class MotionStateTestState: @unchecked Sendable {
  let signal = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var _state: PointerMotionState?

  var state: PointerMotionState? { lock.withLock { _state } }

  func record(_ state: PointerMotionState) {
    lock.withLock { _state = state }
    signal.signal()
  }
}

private final class ConnectionTestState: @unchecked Sendable {
  private let lock = NSLock()
  private var _initiated: InputPeerConnection?
  private var _accepted: InputPeerConnection?
  private var _error: Error?
  private var _helloPeerID: PeerID?
  private var _helloVersion: Int?
  private var _helloPurpose: PeerSessionPurpose?
  private var _readyPeerID: PeerID?
  private var _beginInputSessionID: UUID?
  private var _beginInputMode: InputSessionMode?
  private var _beginInputModifierFlags: UInt64?
  let expectedSessionID = UUID()

  var initiated: InputPeerConnection? {
    get { lock.withLock { _initiated } }
    set { lock.withLock { _initiated = newValue } }
  }

  var accepted: InputPeerConnection? {
    get { lock.withLock { _accepted } }
    set { lock.withLock { _accepted = newValue } }
  }

  var error: Error? {
    get { lock.withLock { _error } }
    set { lock.withLock { _error = newValue } }
  }

  var helloPeerID: PeerID? { lock.withLock { _helloPeerID } }
  var helloVersion: Int? { lock.withLock { _helloVersion } }
  var helloPurpose: PeerSessionPurpose? {
    get { lock.withLock { _helloPurpose } }
    set { lock.withLock { _helloPurpose = newValue } }
  }

  var readyPeerID: PeerID? {
    get { lock.withLock { _readyPeerID } }
    set { lock.withLock { _readyPeerID = newValue } }
  }

  var beginInputSessionID: UUID? { lock.withLock { _beginInputSessionID } }
  var beginInputMode: InputSessionMode? { lock.withLock { _beginInputMode } }
  var beginInputModifierFlags: UInt64? { lock.withLock { _beginInputModifierFlags } }

  func recordHello(peerID: PeerID, version: Int) {
    lock.withLock {
      _helloPeerID = peerID
      _helloVersion = version
    }
  }

  func recordBeginInput(
    sessionID: UUID,
    mode: InputSessionMode,
    initialModifierFlags: UInt64
  ) {
    lock.withLock {
      _beginInputSessionID = sessionID
      _beginInputMode = mode
      _beginInputModifierFlags = initialModifierFlags
    }
  }
}
