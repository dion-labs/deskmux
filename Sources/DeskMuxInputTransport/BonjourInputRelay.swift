import CoreGraphics
import DeskMuxCore
import DeskMuxMacInput
import Foundation
import Network

public enum BonjourInputRelayError: Error, CustomStringConvertible {
  case sharedKeyMissing
  case sharedKeyTooShort
  case localNetworkPermissionMissing
  case destinationNotFound(PeerID)
  case connectionTimedOut(PeerID)
  case connectionTimedOutWithDetails(PeerID, String)
  case receiverRejected(String)
  case listenerFailed(String)
  case invalidMotionTrace(String)

  public var description: String {
    switch self {
    case .sharedKeyMissing:
      return "DESKMUX_SHARED_KEY is required"
    case .sharedKeyTooShort:
      return "The DeskMux pairing code must contain at least 16 characters"
    case .localNetworkPermissionMissing:
      return
        "Local Network access is disabled for DeskMux. Enable it in System Settings → Privacy & Security → Local Network, then try again."
    case .destinationNotFound(let peerID):
      return "Bonjour peer '\(peerID)' was not found"
    case .connectionTimedOut(let peerID):
      return "timed out connecting to Bonjour peer '\(peerID)'"
    case .connectionTimedOutWithDetails(let peerID, let details):
      return "timed out connecting to Bonjour peer '\(peerID)' (\(details))"
    case .receiverRejected(let reason):
      return "receiver rejected the relay: \(reason)"
    case .listenerFailed(let reason):
      return "input receiver failed: \(reason)"
    case .invalidMotionTrace(let reason):
      return "motion replay trace is invalid: \(reason)"
    }
  }
}

public enum InputRelayEnvironment {
  public static func sharedKey() throws -> String {
    guard let key = ProcessInfo.processInfo.environment["DESKMUX_SHARED_KEY"] else {
      throw BonjourInputRelayError.sharedKeyMissing
    }
    guard key.count >= 16 else { throw BonjourInputRelayError.sharedKeyTooShort }
    return key
  }
}

public enum BonjourInputRelayMode: String, Codable, Equatable, Sendable {
  case allInput
  case keyboardOnly

  fileprivate var captureScope: MacInputCaptureScope {
    switch self {
    case .allInput: return .allInput
    case .keyboardOnly: return .keyboardOnly
    }
  }

  fileprivate var sessionMode: InputSessionMode {
    switch self {
    case .allInput: return .allInput
    case .keyboardOnly: return .keyboardOnly
    }
  }
}

public enum BonjourInputRelayTerminationReason: String, Sendable {
  case completed
  case localStop
  case destinationRequestedReturn
  case connectionFailed
}

enum InputRelayHeartbeatAction: Equatable {
  case none
  case send(UInt64)
  case expired
}

/// Small deterministic state machine shared by the warm-connection watchdog
/// and its tests. A new ping is sent only after the previous one was answered;
/// one missing reply expires the channel so the agent can replace it.
struct InputRelayHeartbeatState {
  private(set) var pending: (nonce: UInt64, sentAt: UInt64)?
  private(set) var nextNonce: UInt64 = 10_000_000
  private(set) var lastRoundTripMilliseconds: Double?
  let timeoutNanoseconds: UInt64

  init(timeoutNanoseconds: UInt64 = 3_000_000_000) {
    self.timeoutNanoseconds = timeoutNanoseconds
  }

  mutating func tick(at now: UInt64) -> InputRelayHeartbeatAction {
    if let pending {
      return now >= pending.sentAt && now - pending.sentAt >= timeoutNanoseconds
        ? .expired : .none
    }
    let nonce = nextNonce
    nextNonce &+= 1
    pending = (nonce, now)
    return .send(nonce)
  }

  mutating func receivePong(_ nonce: UInt64, at now: UInt64) -> Bool {
    guard let pending, pending.nonce == nonce, now >= pending.sentAt else { return false }
    lastRoundTripMilliseconds = Double(now - pending.sentAt) / 1_000_000
    self.pending = nil
    return true
  }
}

public struct InputRelayLatencyReport: Codable, Equatable, Sendable {
  public let motionTransport: String
  public let motionTransportFailure: String?
  public let connectionPath: String?
  public let motionStatesSubmitted: Int
  public let motionDatagramsSent: Int
  public let motionPendingStatesReplaced: Int
  public let motionSendCompletionSamplesMilliseconds: [Double]
  public let motionSendCompletionMedianMilliseconds: Double?
  public let motionSendCompletionMaximumMilliseconds: Double?
  public let motionRoundTripSamplesMilliseconds: [Double]
  public let motionRoundTripMedianMilliseconds: Double?
  public let motionRoundTripMaximumMilliseconds: Double?
  public let motionEchoesExpected: Int
  public let motionEchoObservations: [MotionDatagramEchoObservation]
  public let motionAcceleratedStates: Int
  public let motionRawDistance: Double
  public let motionTransmittedDistance: Double
  public let roundTripSamplesMilliseconds: [Double]
  public let continuousRoundTripSamplesMilliseconds: [Double]
  public let injectionAckSamplesMilliseconds: [Double]
  public let receiverProcessingSamplesMilliseconds: [Double]
  public let roundTripMedianMilliseconds: Double?
  public let roundTripMaximumMilliseconds: Double?
  public let injectionAckMedianMilliseconds: Double?
  public let injectionAckMaximumMilliseconds: Double?
  public let receiverProcessingMedianMilliseconds: Double?
  public let receiverProcessingMaximumMilliseconds: Double?

  public init(
    motionTransport: String,
    motionTransportFailure: String?,
    connectionPath: String?,
    motionStatesSubmitted: Int,
    motionDatagramsSent: Int,
    motionPendingStatesReplaced: Int,
    motionSendCompletionSamplesMilliseconds: [Double],
    motionSendCompletionMedianMilliseconds: Double?,
    motionSendCompletionMaximumMilliseconds: Double?,
    motionRoundTripSamplesMilliseconds: [Double],
    motionRoundTripMedianMilliseconds: Double?,
    motionRoundTripMaximumMilliseconds: Double?,
    motionEchoesExpected: Int,
    motionEchoObservations: [MotionDatagramEchoObservation],
    motionAcceleratedStates: Int,
    motionRawDistance: Double,
    motionTransmittedDistance: Double,
    roundTripSamplesMilliseconds: [Double],
    continuousRoundTripSamplesMilliseconds: [Double],
    injectionAckSamplesMilliseconds: [Double],
    receiverProcessingSamplesMilliseconds: [Double],
    roundTripMedianMilliseconds: Double?,
    roundTripMaximumMilliseconds: Double?,
    injectionAckMedianMilliseconds: Double?,
    injectionAckMaximumMilliseconds: Double?,
    receiverProcessingMedianMilliseconds: Double?,
    receiverProcessingMaximumMilliseconds: Double?
  ) {
    self.motionTransport = motionTransport
    self.motionTransportFailure = motionTransportFailure
    self.connectionPath = connectionPath
    self.motionStatesSubmitted = motionStatesSubmitted
    self.motionDatagramsSent = motionDatagramsSent
    self.motionPendingStatesReplaced = motionPendingStatesReplaced
    self.motionSendCompletionSamplesMilliseconds = motionSendCompletionSamplesMilliseconds
    self.motionSendCompletionMedianMilliseconds = motionSendCompletionMedianMilliseconds
    self.motionSendCompletionMaximumMilliseconds = motionSendCompletionMaximumMilliseconds
    self.motionRoundTripSamplesMilliseconds = motionRoundTripSamplesMilliseconds
    self.motionRoundTripMedianMilliseconds = motionRoundTripMedianMilliseconds
    self.motionRoundTripMaximumMilliseconds = motionRoundTripMaximumMilliseconds
    self.motionEchoesExpected = motionEchoesExpected
    self.motionEchoObservations = motionEchoObservations
    self.motionAcceleratedStates = motionAcceleratedStates
    self.motionRawDistance = motionRawDistance
    self.motionTransmittedDistance = motionTransmittedDistance
    self.roundTripSamplesMilliseconds = roundTripSamplesMilliseconds
    self.continuousRoundTripSamplesMilliseconds = continuousRoundTripSamplesMilliseconds
    self.injectionAckSamplesMilliseconds = injectionAckSamplesMilliseconds
    self.receiverProcessingSamplesMilliseconds = receiverProcessingSamplesMilliseconds
    self.roundTripMedianMilliseconds = roundTripMedianMilliseconds
    self.roundTripMaximumMilliseconds = roundTripMaximumMilliseconds
    self.injectionAckMedianMilliseconds = injectionAckMedianMilliseconds
    self.injectionAckMaximumMilliseconds = injectionAckMaximumMilliseconds
    self.receiverProcessingMedianMilliseconds = receiverProcessingMedianMilliseconds
    self.receiverProcessingMaximumMilliseconds = receiverProcessingMaximumMilliseconds
  }
}

public final class BonjourInputRelaySource: @unchecked Sendable {
  public static let serviceType = "_deskmux-input._tcp"

  private let sourcePeerID: PeerID
  private let destinationPeerID: PeerID
  private let sharedKey: String
  private let mode: BonjourInputRelayMode
  private var captureStartedHandler: MacInputCapture.StartedHandler
  private let queue = DispatchQueue(label: "dev.deskmux.input.relay", qos: .userInteractive)
  private let stateLock = NSLock()
  private var connection: InputPeerConnection?
  private var capture: MacInputCapture?
  private var lowLatencySender: LowLatencyInputSender?
  private var motionDatagramSource: (any PointerMotionSourceTransport)?
  private var motionTransport = "not-started"
  private var motionTransportFailure: String?
  private var motionStatesSubmitted = 0
  private var motionDatagramsSent = 0
  private var motionPendingStatesReplaced = 0
  private var motionSendCompletionSamples: [Double] = []
  private var motionRoundTripSamples: [Double] = []
  private var motionEchoesExpected = 0
  private var motionEchoObservations: [MotionDatagramEchoObservation] = []
  private var motionAcceleratedStates = 0
  private var motionRawDistance: Double = 0
  private var motionTransmittedDistance: Double = 0
  private let motionTraceRecorder = MotionTraceRecorder()
  private var receiverReady = false
  private var receiverMotionPort: UInt16?
  private var failure: Error?
  private var connectionProgress = "connection created"
  private var connectionPath: String?
  private let pingSignal = DispatchSemaphore(value: 0)
  private var pendingPing: (nonce: UInt64, sentAt: UInt64)?
  private var roundTripSamples: [Double] = []
  private var continuousRoundTripSamples: [Double] = []
  private var continuousPingSentAt: [UInt64: UInt64] = [:]
  private var nextContinuousPingNonce: UInt64 = 1_000_000
  private var continuousPingTimer: DispatchSourceTimer?
  private var warmHeartbeatTimer: DispatchSourceTimer?
  private var warmHeartbeat = InputRelayHeartbeatState()
  private var eventSentAt: [UInt64: UInt64] = [:]
  private var injectionAckSamples: [Double] = []
  private var receiverProcessingSamples: [Double] = []
  private var replayRequest: MotionReplayRequest?
  private var terminationReasonStorage: BonjourInputRelayTerminationReason?
  private var connectionCancellationExpected = false
  private let clipboardObserverID = UUID()

  public var terminationReason: BonjourInputRelayTerminationReason? {
    stateLock.withLock { terminationReasonStorage }
  }

  public var latencyReport: InputRelayLatencyReport {
    stateLock.withLock {
      InputRelayLatencyReport(
        motionTransport: motionTransport,
        motionTransportFailure: motionTransportFailure,
        connectionPath: connectionPath,
        motionStatesSubmitted: motionStatesSubmitted,
        motionDatagramsSent: motionDatagramsSent,
        motionPendingStatesReplaced: motionPendingStatesReplaced,
        motionSendCompletionSamplesMilliseconds: motionSendCompletionSamples,
        motionSendCompletionMedianMilliseconds: Self.median(motionSendCompletionSamples),
        motionSendCompletionMaximumMilliseconds: motionSendCompletionSamples.max(),
        motionRoundTripSamplesMilliseconds: motionRoundTripSamples,
        motionRoundTripMedianMilliseconds: Self.median(motionRoundTripSamples),
        motionRoundTripMaximumMilliseconds: motionRoundTripSamples.max(),
        motionEchoesExpected: motionEchoesExpected,
        motionEchoObservations: motionEchoObservations,
        motionAcceleratedStates: motionAcceleratedStates,
        motionRawDistance: motionRawDistance,
        motionTransmittedDistance: motionTransmittedDistance,
        roundTripSamplesMilliseconds: roundTripSamples,
        continuousRoundTripSamplesMilliseconds: continuousRoundTripSamples,
        injectionAckSamplesMilliseconds: injectionAckSamples,
        receiverProcessingSamplesMilliseconds: receiverProcessingSamples,
        roundTripMedianMilliseconds: Self.median(roundTripSamples),
        roundTripMaximumMilliseconds: roundTripSamples.max(),
        injectionAckMedianMilliseconds: Self.median(injectionAckSamples),
        injectionAckMaximumMilliseconds: injectionAckSamples.max(),
        receiverProcessingMedianMilliseconds: Self.median(receiverProcessingSamples),
        receiverProcessingMaximumMilliseconds: receiverProcessingSamples.max()
      )
    }
  }

  public var motionTrace: MotionReplayTrace { motionTraceRecorder.trace }

  public var isPrepared: Bool {
    stateLock.withLock { receiverReady && connection != nil && failure == nil }
  }

  public var warmRoundTripMilliseconds: Double? {
    stateLock.withLock { warmHeartbeat.lastRoundTripMilliseconds }
  }

  public init(
    sourcePeerID: PeerID,
    destinationPeerID: PeerID,
    sharedKey: String,
    mode: BonjourInputRelayMode = .allInput,
    captureStartedHandler: @escaping MacInputCapture.StartedHandler = {}
  ) {
    self.sourcePeerID = sourcePeerID
    self.destinationPeerID = destinationPeerID
    self.sharedKey = sharedKey
    self.mode = mode
    self.captureStartedHandler = captureStartedHandler
  }

  public func run() throws {
    try run(maxDuration: nil)
  }

  /// Establishes and authenticates the input channel without beginning input
  /// capture. The same connection is promoted by `run` later.
  public func prepare(timeout: TimeInterval = 1) throws {
    _ = try ensurePreparedConnection(timeout: timeout)
  }

  public func cancelPreparedConnection() {
    stopWarmHeartbeat()
    stopClipboardSync()
    let current = stateLock.withLock { () -> InputPeerConnection? in
      connectionCancellationExpected = true
      receiverReady = false
      defer { connection = nil }
      return connection
    }
    current?.cancel()
  }

  public func setCaptureStartedHandler(_ handler: @escaping MacInputCapture.StartedHandler) {
    stateLock.withLock { captureStartedHandler = handler }
  }

  /// Verifies discovery, authenticated framing, and the receiver-ready
  /// acknowledgement without beginning an input session or opening an event tap.
  public func probe(timeout: TimeInterval = 8) throws -> PeerID {
    guard sharedKey.count >= 16 else { throw BonjourInputRelayError.sharedKeyTooShort }
    let discovered = try discoverDestination(timeout: timeout)
    let signal = DispatchSemaphore(value: 0)
    let result = InputRelayProbeResult()
    let nwConnection = NWConnection(
      to: discovered.endpoint,
      using: inputRelayTCPParameters(requiredInterface: discovered.interface)
    )
    let peerConnection = try InputPeerConnection(
      connection: nwConnection,
      sharedKey: sharedKey,
      role: .initiator,
      queue: queue,
      messageHandler: { message in
        if case .ready(let peerID, _) = message {
          result.succeed(peerID)
          signal.signal()
        }
      },
      stateHandler: { state in
        switch state {
        case .ready:
          do {
            try result.connection?.send(
              .hello(
                peerID: self.sourcePeerID,
                protocolVersion: InputWireMessage.currentProtocolVersion,
                purpose: .inputRelay
              ))
          } catch {
            result.fail(error)
            signal.signal()
          }
        case .failed(let error):
          result.fail(error)
          signal.signal()
        case .cancelled:
          result.fail(InputPeerConnectionError.notReady)
          signal.signal()
        default:
          break
        }
      }
    )
    result.connection = peerConnection
    peerConnection.start()
    guard signal.wait(timeout: .now() + timeout) == .success else {
      peerConnection.cancel()
      throw BonjourInputRelayError.connectionTimedOut(destinationPeerID)
    }
    peerConnection.cancel()
    return try result.get()
  }

  public func run(maxDuration: TimeInterval?) throws {
    guard sharedKey.count >= 16 else { throw BonjourInputRelayError.sharedKeyTooShort }
    let replayRequest = stateLock.withLock { self.replayRequest }
    guard replayRequest != nil || MacInputPermissions.status().canListen else {
      throw MacInputCaptureError.listenPermissionMissing
    }
    let peerConnection = try ensurePreparedConnection(timeout: 1)

    if mode == .allInput {
      measureRoundTrip(using: peerConnection)
      startContinuousRoundTripProbe(using: peerConnection)
    }

    let sessionID = UUID()
    let motionSetup:
      (source: (any PointerMotionSourceTransport)?, transport: String, failure: String?) = {
        guard mode == .allInput else {
          return (nil, "disabled-keyboard-only", nil)
        }
        do {
          guard
            let rawPort = stateLock.withLock({ receiverMotionPort }),
            let port = NWEndpoint.Port(rawValue: rawPort),
            let endpoint = peerConnection.remoteEndpoint(using: port)
          else {
            return (nil, "tcp-fallback", "receiver did not negotiate a reachable UDP endpoint")
          }
          let source = try PointerMotionDatagramSource(endpoint: endpoint, sharedKey: sharedKey)
          try source.start(timeout: 5)
          return (source, "udp-latest-state", nil)
        } catch {
          return (nil, "tcp-fallback", String(describing: error))
        }
      }()
    let motionSource = motionSetup.source
    stateLock.withLock {
      motionDatagramSource = motionSource
      motionTransport = motionSetup.transport
      motionTransportFailure = motionSetup.failure
    }
    let initialModifierFlags = CGEventSource.flagsState(.combinedSessionState)
      .intersection(MacInputModifierBridge.supportedFlags)
    try peerConnection.send(
      .beginInput(
        sessionID: sessionID,
        mode: mode.sessionMode,
        initialModifierFlags: initialModifierFlags.rawValue
      )
    )
    let motionPacketSender: LowLatencyInputSender.MotionSender?
    if let motionSource {
      motionPacketSender = { packet in try motionSource.send(packet) }
    } else {
      motionPacketSender = nil
    }
    let lowLatencySender = LowLatencyInputSender(
      packetSender: { [weak self] packet in
        guard let self else { throw InputPeerConnectionError.notReady }
        try stateLock.withLock {
          guard let connection else { throw InputPeerConnectionError.notReady }
          eventSentAt[packet.sequence] = DispatchTime.now().uptimeNanoseconds
          try connection.send(.event(packet))
        }
      },
      motionSender: motionPacketSender,
      failureHandler: { [weak self] error in
        guard let self else { return }
        recordFailure(error)
        stop()
      }
    )
    stateLock.withLock { self.lowLatencySender = lowLatencySender }
    if let replayRequest {
      try Self.replay(replayRequest, sessionID: sessionID, sender: lowLatencySender)
      lowLatencySender.flush()
      // Leave enough time for the final sampled echo to return before closing
      // the UDP session. This does not affect any measured packet timestamp.
      Thread.sleep(forTimeInterval: 0.15)
    } else {
      let capture = MacInputCapture(
        sessionID: sessionID,
        scope: mode.captureScope,
        packetHandler: { [motionTraceRecorder] packet in
          motionTraceRecorder.record(packet)
          return lowLatencySender.submit(packet)
        },
        emergencyHandler: { [weak self] in
          guard let self else { return }
          lowLatencySender.stop(discardPending: true)
          try? stateLock.withLock { try connection?.send(.releaseAll) }
        },
        startedHandler: stateLock.withLock { captureStartedHandler }
      )
      stateLock.withLock { self.capture = capture }
      if let maxDuration {
        queue.asyncAfter(deadline: .now() + maxDuration) { [weak self] in
          self?.stop()
        }
      }
      try capture.run()
    }
    lowLatencySender.flush()
    lowLatencySender.stop(discardPending: true)
    stopContinuousRoundTripProbe()
    stopWarmHeartbeat()
    stopClipboardSync()
    try? peerConnection.send(.releaseAll)
    try? peerConnection.send(.goodbye)
    stateLock.withLock {
      connectionCancellationExpected = true
      if terminationReasonStorage == nil { terminationReasonStorage = .completed }
    }
    peerConnection.cancel()
    motionSource?.stop()
    stateLock.withLock {
      if let statistics = motionSource?.statistics {
        motionStatesSubmitted = statistics.statesSubmitted
        motionDatagramsSent = statistics.datagramsSent
        motionPendingStatesReplaced = statistics.pendingStatesReplaced
        motionSendCompletionSamples = statistics.completionSamplesMilliseconds
        motionRoundTripSamples = statistics.roundTripSamplesMilliseconds
        motionEchoesExpected = statistics.echoesExpected
        motionEchoObservations = statistics.echoObservations
        motionAcceleratedStates = statistics.acceleratedStates
        motionRawDistance = statistics.rawDistance
        motionTransmittedDistance = statistics.transmittedDistance
      }
      self.capture = nil
      self.lowLatencySender = nil
      self.motionDatagramSource = nil
      self.connection = nil
      receiverReady = false
    }
    if let failure = stateLock.withLock({ failure }) { throw failure }
  }

  /// Replays only pointer-motion samples; it never captures, suppresses, or
  /// transmits keys, clicks, or scroll events.
  public func replay(_ trace: MotionReplayTrace, playbackRate: Double = 1) throws {
    guard trace.schemaVersion == MotionReplayTrace.currentSchemaVersion else {
      throw BonjourInputRelayError.invalidMotionTrace(
        "unsupported schema version \(trace.schemaVersion)")
    }
    guard playbackRate > 0, playbackRate.isFinite else {
      throw BonjourInputRelayError.invalidMotionTrace("playback rate must be positive")
    }
    guard !trace.samples.isEmpty else {
      throw BonjourInputRelayError.invalidMotionTrace("the trace has no motion samples")
    }
    guard trace.samples.allSatisfy({ Self.isPointerMotion($0.kind) }) else {
      throw BonjourInputRelayError.invalidMotionTrace("non-motion input is forbidden")
    }
    guard
      zip(trace.samples, trace.samples.dropFirst()).allSatisfy({
        $0.0.offsetNanoseconds <= $0.1.offsetNanoseconds
      })
    else {
      throw BonjourInputRelayError.invalidMotionTrace("sample timestamps are not ordered")
    }
    stateLock.withLock {
      replayRequest = MotionReplayRequest(trace: trace, playbackRate: playbackRate)
    }
    defer { stateLock.withLock { replayRequest = nil } }
    try run(maxDuration: nil)
  }

  public func stop() {
    stop(reason: .localStop, expectsCancellation: true)
  }

  private func stop(
    reason: BonjourInputRelayTerminationReason,
    expectsCancellation: Bool
  ) {
    stopContinuousRoundTripProbe()
    stopClipboardSync()
    let active = stateLock.withLock {
      if terminationReasonStorage == nil || reason == .connectionFailed {
        terminationReasonStorage = reason
      }
      if expectsCancellation { connectionCancellationExpected = true }
      return (capture, lowLatencySender, motionDatagramSource)
    }
    active.1?.stop(discardPending: true)
    active.2?.stop()
    active.0?.stop()
  }

  private func ensurePreparedConnection(timeout: TimeInterval) throws -> InputPeerConnection {
    guard sharedKey.count >= 16 else { throw BonjourInputRelayError.sharedKeyTooShort }
    if let prepared = stateLock.withLock({
      receiverReady && failure == nil ? connection : nil
    }) {
      return prepared
    }

    let discovered = try discoverDestination(timeout: timeout)
    let readySignal = DispatchSemaphore(value: 0)
    let parameters = inputRelayTCPParameters(requiredInterface: discovered.interface)
    let nwConnection = NWConnection(to: discovered.endpoint, using: parameters)
    let peerConnection = try InputPeerConnection(
      connection: nwConnection,
      sharedKey: sharedKey,
      role: .initiator,
      queue: queue,
      messageHandler: { [weak self] message in
        guard let self else { return }
        switch message {
        case .ready(let peerID, let motionPort) where peerID == destinationPeerID:
          stateLock.withLock {
            receiverReady = true
            receiverMotionPort = motionPort
          }
          readySignal.signal()
        case .goodbye:
          stop(reason: .destinationRequestedReturn, expectsCancellation: true)
        case .pong(let nonce):
          recordPong(nonce)
        case .eventAck(let sequence, let receiverProcessingNanoseconds):
          recordEventAck(
            sequence,
            receiverProcessingNanoseconds: receiverProcessingNanoseconds
          )
        case .clipboardUpdateApplied(let id):
          DeskMuxClipboardBridge.shared.recordAcknowledged(id: id)
        default:
          break
        }
      },
      stateHandler: { [weak self] state in
        guard let self else { return }
        stateLock.withLock { connectionProgress = Self.describe(state) }
        switch state {
        case .ready:
          do {
            try stateLock.withLock {
              connectionPath = nwConnection.currentPath.map { String(describing: $0) }
              guard let connection else { throw InputPeerConnectionError.notReady }
              try connection.send(
                .hello(
                  peerID: sourcePeerID,
                  protocolVersion: InputWireMessage.currentProtocolVersion,
                  purpose: .inputRelay
                ))
            }
          } catch {
            recordFailure(error)
            readySignal.signal()
          }
        case .failed(let error):
          recordFailure(error)
          stateLock.withLock { receiverReady = false }
          stop(reason: .connectionFailed, expectsCancellation: false)
          readySignal.signal()
        case .cancelled:
          let expected = stateLock.withLock { () -> Bool in
            receiverReady = false
            return connectionCancellationExpected
          }
          if expected {
            stop(reason: terminationReason ?? .localStop, expectsCancellation: true)
          } else {
            recordFailure(
              BonjourInputRelayError.receiverRejected("connection closed unexpectedly"))
            stop(reason: .connectionFailed, expectsCancellation: false)
          }
          readySignal.signal()
        default:
          break
        }
      }
    )
    stateLock.withLock {
      connection = peerConnection
      connectionCancellationExpected = false
      connectionProgress = "connection created"
    }
    peerConnection.start()

    guard readySignal.wait(timeout: .now() + timeout) == .success else {
      let localNetworkDenied = nwConnection.currentPath?.unsatisfiedReason == .localNetworkDenied
      let details = timeoutDetails(for: nwConnection)
      stateLock.withLock {
        connectionCancellationExpected = true
        receiverReady = false
      }
      peerConnection.cancel()
      if localNetworkDenied { throw BonjourInputRelayError.localNetworkPermissionMissing }
      throw BonjourInputRelayError.connectionTimedOutWithDetails(destinationPeerID, details)
    }
    if let failure = stateLock.withLock({ failure }) { throw failure }
    guard stateLock.withLock({ receiverReady }) else {
      throw BonjourInputRelayError.receiverRejected("no ready acknowledgement")
    }
    startWarmHeartbeat(using: peerConnection)
    startClipboardSync(using: peerConnection)
    return peerConnection
  }

  private func startClipboardSync(using peerConnection: InputPeerConnection) {
    DeskMuxClipboardBridge.shared.addObserver(
      id: clipboardObserverID,
      localPeerID: sourcePeerID
    ) { [weak peerConnection] update in
      do {
        try peerConnection?.send(.clipboardUpdate(update))
        DeskMuxClipboardBridge.shared.recordSent(update)
      } catch {
        // The pending update is replayed when the warm channel reconnects.
      }
    }
  }

  private func stopClipboardSync() {
    DeskMuxClipboardBridge.shared.removeObserver(id: clipboardObserverID)
  }

  private func startWarmHeartbeat(using peerConnection: InputPeerConnection) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(100))
    timer.setEventHandler { [weak self, weak peerConnection] in
      guard let self, let peerConnection else { return }
      let action = stateLock.withLock {
        warmHeartbeat.tick(at: DispatchTime.now().uptimeNanoseconds)
      }
      switch action {
      case .none:
        break
      case .send(let nonce):
        do {
          try peerConnection.send(.ping(nonce))
        } catch {
          recordFailure(error)
          peerConnection.cancel()
        }
      case .expired:
        recordFailure(
          BonjourInputRelayError.receiverRejected("warm-channel heartbeat timed out"))
        stateLock.withLock { receiverReady = false }
        peerConnection.cancel()
      }
    }
    stateLock.withLock {
      warmHeartbeat = InputRelayHeartbeatState()
      warmHeartbeatTimer?.cancel()
      warmHeartbeatTimer = timer
    }
    timer.resume()
  }

  private func stopWarmHeartbeat() {
    let timer = stateLock.withLock { () -> DispatchSourceTimer? in
      defer { warmHeartbeatTimer = nil }
      return warmHeartbeatTimer
    }
    timer?.cancel()
  }

  private func discoverDestination(
    timeout: TimeInterval
  ) throws -> (endpoint: NWEndpoint, interface: NWInterface?) {
    let signal = DispatchSemaphore(value: 0)
    let found = LockedEndpoint()
    let browser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil),
      using: inputRelayTCPParameters()
    )
    browser.browseResultsChangedHandler = { [destinationPeerID] results, _ in
      let matches = results.compactMap {
        result -> (rank: Int, routePriority: Int, endpoint: NWEndpoint, interface: NWInterface?)? in
        guard case .service(let name, _, _, _) = result.endpoint,
          let rank = deskMuxServiceRank(name: name, peerID: destinationPeerID)
        else { return nil }
        let interface = result.interfaces.max {
          deskMuxRoutePriority(interface: $0) < deskMuxRoutePriority(interface: $1)
        }
        return (
          rank,
          interface.map(deskMuxRoutePriority(interface:)) ?? 0,
          result.endpoint,
          interface
        )
      }
      if let selected = matches.max(by: {
        if $0.rank != $1.rank { return $0.rank < $1.rank }
        return $0.routePriority < $1.routePriority
      }) {
        found.set(
          endpoint: selected.endpoint,
          interface: selected.interface,
          rank: selected.rank,
          routePriority: selected.routePriority
        )
        signal.signal()
      }
    }
    browser.start(queue: queue)
    let result = signal.wait(timeout: .now() + timeout)
    // Bonjour commonly publishes the infrastructure route first and its AWDL
    // peer-to-peer route a fraction of a second later. Keep browsing briefly
    // so a stale Wi-Fi route cannot win merely by arriving first.
    if result == .success { Thread.sleep(forTimeInterval: 0.4) }
    browser.cancel()
    guard result == .success, let endpoint = found.get() else {
      throw BonjourInputRelayError.destinationNotFound(destinationPeerID)
    }
    return endpoint
  }

  private func recordFailure(_ error: Error) {
    stateLock.withLock {
      if failure == nil { failure = error }
    }
  }

  private func measureRoundTrip(using peerConnection: InputPeerConnection) {
    for nonce in 0..<UInt64(8) {
      let sentAt = DispatchTime.now().uptimeNanoseconds
      stateLock.withLock { pendingPing = (nonce, sentAt) }
      do {
        try peerConnection.send(.ping(nonce))
      } catch {
        recordFailure(error)
        return
      }
      if pingSignal.wait(timeout: .now() + 1) != .success { return }
    }
  }

  private func recordPong(_ nonce: UInt64) {
    let now = DispatchTime.now().uptimeNanoseconds
    let matchedInitialProbe = stateLock.withLock { () -> Bool in
      if warmHeartbeat.receivePong(nonce, at: now) { return false }
      if let pendingPing, pendingPing.nonce == nonce {
        roundTripSamples.append(Self.milliseconds(from: now - pendingPing.sentAt))
        self.pendingPing = nil
        return true
      }
      if let sentAt = continuousPingSentAt.removeValue(forKey: nonce), now >= sentAt {
        continuousRoundTripSamples.append(Self.milliseconds(from: now - sentAt))
        if continuousPingSentAt.count > 256 {
          let stale = continuousPingSentAt.keys.sorted().prefix(continuousPingSentAt.count - 128)
          for nonce in stale { continuousPingSentAt.removeValue(forKey: nonce) }
        }
      }
      return false
    }
    if matchedInitialProbe { pingSignal.signal() }
  }

  private func startContinuousRoundTripProbe(using peerConnection: InputPeerConnection) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(2))
    timer.setEventHandler { [weak self, weak peerConnection] in
      guard let self, let peerConnection else { return }
      let probe = stateLock.withLock { () -> (UInt64, UInt64) in
        let nonce = nextContinuousPingNonce
        nextContinuousPingNonce &+= 1
        let sentAt = DispatchTime.now().uptimeNanoseconds
        continuousPingSentAt[nonce] = sentAt
        return (nonce, sentAt)
      }
      do {
        try peerConnection.send(.ping(probe.0))
      } catch {
        _ = stateLock.withLock { continuousPingSentAt.removeValue(forKey: probe.0) }
      }
    }
    stateLock.withLock {
      continuousPingTimer?.cancel()
      continuousPingTimer = timer
    }
    timer.resume()
  }

  private func stopContinuousRoundTripProbe() {
    let timer = stateLock.withLock { () -> DispatchSourceTimer? in
      defer { continuousPingTimer = nil }
      return continuousPingTimer
    }
    timer?.cancel()
  }

  private func recordEventAck(
    _ sequence: UInt64,
    receiverProcessingNanoseconds: UInt64
  ) {
    let now = DispatchTime.now().uptimeNanoseconds
    let sender = stateLock.withLock { () -> LowLatencyInputSender? in
      if let sentAt = eventSentAt[sequence] {
        injectionAckSamples.append(Self.milliseconds(from: now - sentAt))
      }
      receiverProcessingSamples.append(
        Self.milliseconds(from: receiverProcessingNanoseconds))
      eventSentAt = eventSentAt.filter { $0.key > sequence }
      return lowLatencySender
    }
    sender?.acknowledge(through: sequence)
  }

  private func timeoutDetails(for nwConnection: NWConnection) -> String {
    let progress = stateLock.withLock { connectionProgress }
    let path = nwConnection.currentPath.map { String(describing: $0) } ?? "no path"
    return "state: \(progress); path: \(path)"
  }

  private static func describe(_ state: NWConnection.State) -> String {
    switch state {
    case .setup: return "setup"
    case .preparing: return "preparing"
    case .ready: return "ready"
    case .waiting(let error): return "waiting: \(error)"
    case .failed(let error): return "failed: \(error)"
    case .cancelled: return "cancelled"
    @unknown default: return "unknown"
    }
  }

  private static func milliseconds(from nanoseconds: UInt64) -> Double {
    Double(nanoseconds) / 1_000_000
  }

  private static func replay(
    _ request: MotionReplayRequest,
    sessionID: UUID,
    sender: LowLatencyInputSender
  ) throws {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    for (sequence, sample) in request.trace.samples.enumerated() {
      let scaledOffset = UInt64(Double(sample.offsetNanoseconds) / request.playbackRate)
      wait(until: startedAt &+ scaledOffset)
      let accepted = sender.submit(
        InputEventPacket(
          sessionID: sessionID,
          sequence: UInt64(sequence),
          kind: sample.kind,
          eventData: sample.eventData
        ))
      if !accepted { throw InputPeerConnectionError.notReady }
    }
  }

  private static func wait(until target: UInt64) {
    while true {
      let now = DispatchTime.now().uptimeNanoseconds
      guard now < target else { return }
      let remaining = target - now
      if remaining > 1_000_000 {
        Thread.sleep(forTimeInterval: Double(remaining - 400_000) / 1_000_000_000)
      } else if remaining > 100_000 {
        Thread.sleep(forTimeInterval: 0.000_05)
      }
    }
  }

  private static func isPointerMotion(_ kind: InputEventKind) -> Bool {
    kind == .mouseMoved
  }

  private static func median(_ samples: [Double]) -> Double? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }
}

private struct MotionReplayRequest: Sendable {
  let trace: MotionReplayTrace
  let playbackRate: Double
}

private final class InputRelayProbeResult: @unchecked Sendable {
  private let lock = NSLock()
  var connection: InputPeerConnection?
  private var peerID: PeerID?
  private var failure: Error?

  func succeed(_ peerID: PeerID) {
    lock.withLock {
      guard self.peerID == nil, failure == nil else { return }
      self.peerID = peerID
    }
  }

  func fail(_ error: Error) {
    lock.withLock {
      guard peerID == nil, failure == nil else { return }
      failure = error
    }
  }

  func get() throws -> PeerID {
    try lock.withLock {
      if let peerID { return peerID }
      throw failure ?? InputPeerConnectionError.notReady
    }
  }
}

public enum BonjourInputReceiverState: Equatable, Sendable {
  case starting
  case ready
  case receiving(from: PeerID)
  case failed(String)
  case stopped
}

public final class BonjourInputReceiver: @unchecked Sendable {
  public typealias StateHandler = @Sendable (BonjourInputReceiverState) -> Void

  private let peerID: PeerID
  private let sharedKey: String
  private let acceptsAppUpdates: Bool
  private let serviceType: String
  private let versionAdvertisement: DeskMuxVersionAdvertisement?
  private let stateHandler: StateHandler
  private let queue = DispatchQueue(label: "dev.deskmux.input.receiver", qos: .userInteractive)
  private let lock = NSLock()
  private let motionSessions = MotionSessionRegistry()
  private var listener: NWListener?
  private var motionReceiver: BonjourPointerMotionReceiver?
  private var sessions: [ObjectIdentifier: ReceiverSession] = [:]
  private var latencyActivity: NSObjectProtocol?

  public init(
    peerID: PeerID,
    sharedKey: String,
    acceptsAppUpdates: Bool = false,
    serviceType: String = BonjourInputRelaySource.serviceType,
    versionAdvertisement: DeskMuxVersionAdvertisement? = nil,
    stateHandler: @escaping StateHandler = { _ in }
  ) {
    self.peerID = peerID
    self.sharedKey = sharedKey
    self.acceptsAppUpdates = acceptsAppUpdates
    self.serviceType = serviceType
    self.versionAdvertisement = versionAdvertisement
    self.stateHandler = stateHandler
  }

  public func start() throws {
    guard sharedKey.count >= 16 else { throw BonjourInputRelayError.sharedKeyTooShort }
    guard serviceType != BonjourInputRelaySource.serviceType
      || MacInputPermissions.status().canPost
    else {
      throw MacInputInjectorError.postPermissionMissing
    }
    let shouldStart = lock.withLock { listener == nil }
    guard shouldStart else { return }

    let activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
      reason: "DeskMux low-latency input receiver"
    )
    var adoptedActivity = false
    defer {
      if !adoptedActivity { ProcessInfo.processInfo.endActivity(activity) }
    }

    let newMotionReceiver: BonjourPointerMotionReceiver?
    if serviceType == BonjourInputRelaySource.serviceType {
      let receiver = try BonjourPointerMotionReceiver(
        sharedKey: sharedKey,
        motionHandler: { [motionSessions] state in
          motionSessions.inject(state)
        }
      )
      try receiver.start()
      newMotionReceiver = receiver
    } else {
      newMotionReceiver = nil
    }
    let newListener = try NWListener(using: inputRelayTCPParameters())
    newListener.service = if let versionAdvertisement {
      NWListener.Service(
        name: peerID.rawValue,
        type: serviceType,
        txtRecord: versionAdvertisement.txtRecord
      )
    } else {
      NWListener.Service(name: peerID.rawValue, type: serviceType)
    }
    newListener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        stateHandler(.ready)
      case .failed(let error):
        stateHandler(.failed(String(describing: error)))
      case .cancelled:
        stateHandler(.stopped)
      default:
        break
      }
    }
    newListener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    lock.withLock {
      listener = newListener
      motionReceiver = newMotionReceiver
      latencyActivity = activity
      adoptedActivity = true
    }
    stateHandler(.starting)
    newListener.start(queue: queue)
  }

  public func run() throws -> Never {
    try start()
    dispatchMain()
  }

  public func stop() {
    let state = lock.withLock {
      () -> (
        NWListener?, BonjourPointerMotionReceiver?, [ReceiverSession], NSObjectProtocol?
      ) in
      let current = listener
      listener = nil
      let currentMotionReceiver = motionReceiver
      motionReceiver = nil
      let activeSessions = Array(sessions.values)
      sessions.removeAll()
      let currentActivity = latencyActivity
      latencyActivity = nil
      return (current, currentMotionReceiver, activeSessions, currentActivity)
    }
    for session in state.2 { session.stop() }
    state.0?.cancel()
    state.1?.stop()
    if let activity = state.3 { ProcessInfo.processInfo.endActivity(activity) }
  }

  public func returnInputToSource() {
    let activeSessions = lock.withLock { Array(sessions.values) }
    for session in activeSessions { session.requestReturnInput() }
  }

  private func accept(_ nwConnection: NWConnection) {
    do {
      let session = try ReceiverSession(
        localPeerID: peerID,
        nwConnection: nwConnection,
        sharedKey: sharedKey,
        acceptsAppUpdates: acceptsAppUpdates,
        motionSessions: motionSessions,
        motionPort: motionReceiver?.port?.rawValue,
        queue: queue,
        activityChanged: { [weak self] peerID in
          self?.stateHandler(.receiving(from: peerID))
        },
        ended: { [weak self] identifier in
          guard let self else { return }
          let isIdle = lock.withLock { () -> Bool in
            sessions.removeValue(forKey: identifier)
            return sessions.isEmpty
          }
          if isIdle { stateHandler(.ready) }
        }
      )
      lock.withLock { sessions[ObjectIdentifier(session)] = session }
      session.start()
    } catch {
      nwConnection.cancel()
    }
  }
}

private final class ReceiverSession: @unchecked Sendable {
  private let localPeerID: PeerID
  private let acceptsAppUpdates: Bool
  private let activityChanged: @Sendable (PeerID) -> Void
  private let ended: @Sendable (ObjectIdentifier) -> Void
  private let motionSessions: MotionSessionRegistry
  private let motionPort: UInt16?
  private let lock = NSLock()
  private var remotePeerID: PeerID?
  private var sessionPurpose: PeerSessionPurpose?
  private var injector: MacInputInjector?
  private var localEscapeMonitor: MacLocalEscapeMonitor?
  private var connection: InputPeerConnection!
  private var finished = false
  private var returnRequested = false

  init(
    localPeerID: PeerID,
    nwConnection: NWConnection,
    sharedKey: String,
    acceptsAppUpdates: Bool,
    motionSessions: MotionSessionRegistry,
    motionPort: UInt16?,
    queue: DispatchQueue,
    activityChanged: @escaping @Sendable (PeerID) -> Void,
    ended: @escaping @Sendable (ObjectIdentifier) -> Void
  ) throws {
    self.localPeerID = localPeerID
    self.acceptsAppUpdates = acceptsAppUpdates
    self.motionSessions = motionSessions
    self.motionPort = motionPort
    self.activityChanged = activityChanged
    self.ended = ended
    connection = try InputPeerConnection(
      connection: nwConnection,
      sharedKey: sharedKey,
      role: .acceptor,
      queue: queue,
      messageHandler: { [weak self] message in try self?.handle(message) },
      stateHandler: { [weak self] state in
        guard let self else { return }
        if case .failed = state { finish() }
        if case .cancelled = state { finish() }
      }
    )
  }

  func start() { connection.start() }
  func stop() { finish() }

  func requestReturnInput() {
    let shouldRequest = lock.withLock { () -> Bool in
      guard !returnRequested, !finished else { return false }
      returnRequested = true
      injector?.releaseAll()
      localEscapeMonitor?.stop()
      return true
    }
    guard shouldRequest else { return }
    try? connection.send(.goodbye)
  }

  private func handle(_ message: InputWireMessage) throws {
    switch message {
    case .hello(let peerID, let version, let purpose):
      let versionIsCompatible =
        purpose == .appUpdate
        ? (2...InputWireMessage.currentProtocolVersion).contains(version)
        : version == InputWireMessage.currentProtocolVersion
      guard versionIsCompatible else {
        throw BonjourInputRelayError.receiverRejected("protocol version \(version)")
      }
      lock.withLock {
        remotePeerID = peerID
        sessionPurpose = purpose
      }
      try connection.send(.ready(peerID: localPeerID, motionPort: motionPort))
    case .beginInput(let sessionID, let mode, let initialModifierFlags):
      guard let peerID = lock.withLock({
        sessionPurpose == .inputRelay ? remotePeerID : nil
      }) else {
        throw BonjourInputRelayError.receiverRejected(
          "input session arrived outside an input relay")
      }
      let injector = try MacInputInjector(sessionID: sessionID)
      try lock.withLock {
        guard self.injector == nil else {
          throw BonjourInputRelayError.receiverRejected("input session already started")
        }
        self.injector = injector
      }
      motionSessions.register(injector)
      MacInputModifierBridge.publish(CGEventFlags(rawValue: initialModifierFlags))
      activityChanged(peerID)
      if mode.returnsOnDestinationLocalInput { startLocalEscapeMonitor() }
    case .event(let packet):
      guard lock.withLock({ remotePeerID != nil && sessionPurpose == .inputRelay }) else {
        throw BonjourInputRelayError.receiverRejected(
          "input event arrived outside an input relay")
      }
      let injector = try lock.withLock { () throws -> MacInputInjector in
        if let existing = self.injector { return existing }
        let created = try MacInputInjector(sessionID: packet.sessionID)
        self.injector = created
        motionSessions.register(created)
        return created
      }
      let processingStartedAt = DispatchTime.now().uptimeNanoseconds
      try injector.inject(packet)
      let processingNanoseconds =
        DispatchTime.now().uptimeNanoseconds - processingStartedAt
      try connection.send(
        .eventAck(
          sequence: packet.sequence,
          receiverProcessingNanoseconds: processingNanoseconds
        ))
    case .ping(let nonce):
      try connection.send(.pong(nonce))
    case .pong:
      throw BonjourInputRelayError.receiverRejected("unexpected pong message")
    case .eventAck:
      throw BonjourInputRelayError.receiverRejected("unexpected event acknowledgement")
    case .releaseAll:
      lock.withLock { injector?.releaseAll() }
    case .goodbye:
      finish()
    case .ready:
      throw BonjourInputRelayError.receiverRejected("unexpected ready message")
    case .appUpdate(let package):
      guard lock.withLock({ sessionPurpose == .appUpdate }), acceptsAppUpdates else {
        throw BonjourInputRelayError.receiverRejected("app update is not enabled for this session")
      }
      let sourcePeerID = lock.withLock { remotePeerID }
      let result = DeskMuxAppUpdateInstaller.verifyInstallAndScheduleRelaunch(
        package, sourcePeerID: sourcePeerID)
      try connection.send(.appUpdateResult(result))
    case .appUpdateResult:
      throw BonjourInputRelayError.receiverRejected("unexpected app update result")
    case .clipboardUpdate(let update):
      guard let remotePeerID = lock.withLock({
        sessionPurpose == .inputRelay ? self.remotePeerID : nil
      }), update.sourcePeerID == remotePeerID else {
        throw BonjourInputRelayError.receiverRejected(
          "clipboard update arrived outside an input relay")
      }
      guard update.isWithinSizeLimit else {
        throw BonjourInputRelayError.receiverRejected("clipboard update is too large")
      }
      DeskMuxClipboardBridge.shared.applyRemote(update) { [weak connection] in
        try? connection?.send(.clipboardUpdateApplied(update.id))
      }
    case .clipboardUpdateApplied:
      throw BonjourInputRelayError.receiverRejected(
        "unexpected clipboard acknowledgement")
    }
  }

  private func finish() {
    let shouldFinish = lock.withLock { () -> Bool in
      guard !finished else { return false }
      finished = true
      injector?.releaseAll()
      if let injector { motionSessions.unregister(sessionID: injector.sessionID) }
      localEscapeMonitor?.stop()
      localEscapeMonitor = nil
      return true
    }
    guard shouldFinish else { return }
    connection.cancel()
    ended(ObjectIdentifier(self))
  }

  private func startLocalEscapeMonitor() {
    let monitor = MacLocalEscapeMonitor { [weak self] in
      self?.requestReturnInput()
    }
    let shouldStart = lock.withLock { () -> Bool in
      guard localEscapeMonitor == nil else { return false }
      localEscapeMonitor = monitor
      return true
    }
    guard shouldStart else { return }
    DispatchQueue.global(qos: .userInteractive).async {
      try? monitor.run()
    }
  }
}

private final class MotionSessionRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var injectors: [UUID: MacInputInjector] = [:]

  func register(_ injector: MacInputInjector) {
    lock.withLock { injectors[injector.sessionID] = injector }
  }

  func unregister(sessionID: UUID) {
    _ = lock.withLock { injectors.removeValue(forKey: sessionID) }
  }

  func inject(_ state: PointerMotionState) {
    let injector = lock.withLock { injectors[state.sessionID] }
    try? injector?.injectPointerMotion(state)
  }
}

private final class LockedEndpoint: @unchecked Sendable {
  private let lock = NSLock()
  private var value: (
    endpoint: NWEndpoint, interface: NWInterface?, rank: Int, routePriority: Int
  )?

  func set(endpoint: NWEndpoint, interface: NWInterface?, rank: Int, routePriority: Int) {
    lock.withLock {
      if let value,
        value.rank > rank || (value.rank == rank && value.routePriority >= routePriority)
      {
        return
      }
      value = (endpoint, interface, rank, routePriority)
    }
  }
  func get() -> (endpoint: NWEndpoint, interface: NWInterface?)? {
    lock.withLock { value.map { ($0.endpoint, $0.interface) } }
  }
}

func inputRelayTCPParameters(requiredInterface: NWInterface? = nil) -> NWParameters {
  let tcp = NWProtocolTCP.Options()
  tcp.noDelay = true
  tcp.enableKeepalive = true
  tcp.keepaliveIdle = 5
  tcp.keepaliveInterval = 2
  tcp.keepaliveCount = 3
  let parameters = NWParameters(tls: nil, tcp: tcp)
  parameters.includePeerToPeer = true
  parameters.requiredInterface = requiredInterface
  return parameters
}

func deskMuxRoutePriority(interface: NWInterface) -> Int {
  deskMuxRoutePriority(interfaceName: interface.name, interfaceType: interface.type)
}

func deskMuxRoutePriority(
  interfaceName: String,
  interfaceType: NWInterface.InterfaceType
) -> Int {
  // AWDL is a direct, self-healing Apple peer-to-peer path. Prefer it to the
  // infrastructure LAN, which may retain a valid Bonjour record while ARP or
  // routing to that address is temporarily broken.
  if interfaceName == "awdl0" { return 400 }
  switch interfaceType {
  case .wiredEthernet: return 300
  case .wifi: return 200
  case .cellular: return 100
  case .loopback: return 50
  case .other: return 25
  @unknown default: return 0
  }
}

func deskMuxServiceRank(name: String, peerID: PeerID) -> Int? {
  let base = peerID.rawValue
  if name == base { return 1 }
  guard name.hasPrefix("\(base) ("), name.hasSuffix(")") else { return nil }
  let start = name.index(name.startIndex, offsetBy: base.count + 2)
  let end = name.index(before: name.endIndex)
  return Int(name[start..<end])
}
