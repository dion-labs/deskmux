import CoreGraphics
import DeskMuxCore
import DeskMuxMacInput
import Foundation
import Network

struct PointerMotionTransportStatistics: Sendable {
  let statesSubmitted: Int
  let datagramsSent: Int
  let pendingStatesReplaced: Int
  let completionSamplesMilliseconds: [Double]
  let roundTripSamplesMilliseconds: [Double]
  let echoesExpected: Int
  let echoObservations: [MotionDatagramEchoObservation]
  let acceleratedStates: Int
  let rawDistance: Double
  let transmittedDistance: Double
}

protocol PointerMotionSourceTransport: AnyObject, Sendable {
  var statistics: PointerMotionTransportStatistics { get }
  func start(timeout: TimeInterval) throws
  func send(_ packet: InputEventPacket) throws
  func stop()
}

final class PointerMotionDatagramSource: PointerMotionSourceTransport, @unchecked Sendable {
  private struct OutboundDatagram: Sendable {
    let data: Data
    let sequence: UInt64
  }

  private let endpoint: NWEndpoint
  private let codec: SecurePointerMotionCodec
  private let queue = DispatchQueue(
    label: "dev.deskmux.motion.datagram.source", qos: .userInteractive)
  private let lock = NSLock()
  private var connection: NWConnection?
  private var cumulativeDeltaX: Int64 = 0
  private var cumulativeDeltaY: Int64 = 0
  private var sendInFlight = false
  private var pendingDatagram: OutboundDatagram?
  private var stopped = false
  private var statesSubmitted = 0
  private var datagramsSent = 0
  private var pendingStatesReplaced = 0
  private var completionSamplesMilliseconds: [Double] = []
  private var sentAtBySequence: [UInt64: UInt64] = [:]
  private var roundTripSamplesMilliseconds: [Double] = []
  private var echoesExpected = 0
  private var echoObservations: [MotionDatagramEchoObservation] = []
  private var acceleratedStates = 0
  private var rawDistance: Double = 0
  private var transmittedDistance: Double = 0

  var statistics: PointerMotionTransportStatistics {
    lock.withLock {
      PointerMotionTransportStatistics(
        statesSubmitted: statesSubmitted,
        datagramsSent: datagramsSent,
        pendingStatesReplaced: pendingStatesReplaced,
        completionSamplesMilliseconds: completionSamplesMilliseconds,
        roundTripSamplesMilliseconds: roundTripSamplesMilliseconds,
        echoesExpected: echoesExpected,
        echoObservations: echoObservations,
        acceleratedStates: acceleratedStates,
        rawDistance: rawDistance,
        transmittedDistance: transmittedDistance
      )
    }
  }

  init(endpoint: NWEndpoint, sharedKey: String) throws {
    self.endpoint = endpoint
    codec = try SecurePointerMotionCodec(sharedKey: sharedKey)
  }

  func start(timeout: TimeInterval = 5) throws {
    let ready = DispatchSemaphore(value: 0)
    let startState = MotionConnectionStartState()
    let connection = NWConnection(to: endpoint, using: pointerMotionDatagramParameters())
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      switch state {
      case .ready:
        if let self, let connection { self.receiveNextEcho(on: connection) }
        ready.signal()
      case .failed(let error):
        startState.set(error)
        ready.signal()
      case .cancelled:
        ready.signal()
      default:
        break
      }
    }
    lock.withLock { self.connection = connection }
    connection.start(queue: queue)
    guard ready.wait(timeout: .now() + timeout) == .success else {
      connection.cancel()
      throw InputPeerConnectionError.connectionFailed("motion datagram connection timed out")
    }
    if let startError = startState.getError() {
      connection.cancel()
      throw startError
    }
  }

  func send(_ packet: InputEventPacket) throws {
    let event = try MacInputEventCodec.decode(packet)
    let rawDeltaX = event.getIntegerValueField(.mouseEventDeltaX)
    let rawDeltaY = event.getIntegerValueField(.mouseEventDeltaY)
    // The source-event-location heuristic was tested in build 20260824201417
    // and changed only 22/1781 samples while the user-visible lag remained.
    // Keep the measured baseline honest; future alternatives are evaluated as
    // explicit research candidates rather than silently mixed into it.
    let selectedDelta = (x: rawDeltaX, y: rawDeltaY, usedAcceleratedLocation: false)
    let state = lock.withLock { () -> PointerMotionState in
      cumulativeDeltaX += selectedDelta.x
      cumulativeDeltaY += selectedDelta.y
      rawDistance += hypot(Double(rawDeltaX), Double(rawDeltaY))
      transmittedDistance += hypot(Double(selectedDelta.x), Double(selectedDelta.y))
      if selectedDelta.usedAcceleratedLocation { acceleratedStates += 1 }
      return PointerMotionState(
        sessionID: packet.sessionID,
        sequence: packet.sequence,
        kind: packet.kind,
        cumulativeDeltaX: cumulativeDeltaX,
        cumulativeDeltaY: cumulativeDeltaY
      )
    }
    let datagram = OutboundDatagram(data: try codec.seal(state), sequence: state.sequence)
    let outbound = lock.withLock { () -> (NWConnection, OutboundDatagram)? in
      statesSubmitted += 1
      guard !stopped, let connection else { return nil }
      if sendInFlight {
        if pendingDatagram != nil { pendingStatesReplaced += 1 }
        pendingDatagram = datagram
        return nil
      }
      sendInFlight = true
      datagramsSent += 1
      return (connection, datagram)
    }
    guard let outbound else {
      if lock.withLock({ stopped || connection == nil }) {
        throw InputPeerConnectionError.notReady
      }
      return
    }
    sendDatagram(outbound.1, on: outbound.0)
  }

  private func sendDatagram(_ datagram: OutboundDatagram, on connection: NWConnection) {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    if datagram.sequence.isMultiple(of: 4) {
      lock.withLock {
        sentAtBySequence[datagram.sequence] = startedAt
        echoesExpected += 1
      }
    }
    connection.send(
      content: datagram.data,
      contentContext: .defaultMessage,
      isComplete: true,
      completion: .contentProcessed { [weak self] _ in
        guard let self else { return }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        let next = lock.withLock { () -> OutboundDatagram? in
          completionSamplesMilliseconds.append(duration)
          guard !stopped, let pendingDatagram else {
            sendInFlight = false
            return nil
          }
          self.pendingDatagram = nil
          datagramsSent += 1
          return pendingDatagram
        }
        if let next { sendDatagram(next, on: connection) }
      }
    )
  }

  private func receiveNextEcho(on connection: NWConnection) {
    connection.receiveMessage { [weak self, weak connection] data, _, _, error in
      guard let self, let connection else { return }
      if let data, !data.isEmpty, let state = try? codec.open(data) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
          if let sentAt = sentAtBySequence.removeValue(forKey: state.sequence), now >= sentAt {
            let roundTrip = Double(now - sentAt) / 1_000_000
            roundTripSamplesMilliseconds.append(roundTrip)
            echoObservations.append(
              MotionDatagramEchoObservation(
                sequence: state.sequence,
                roundTripMilliseconds: roundTrip,
                receiverReceivedAtNanoseconds: state.receiverReceivedAtNanoseconds,
                receiverProcessingNanoseconds: state.receiverProcessingNanoseconds
              ))
          }
          if sentAtBySequence.count > 512 {
            let oldest = sentAtBySequence.keys.sorted().prefix(sentAtBySequence.count - 256)
            for sequence in oldest { sentAtBySequence.removeValue(forKey: sequence) }
          }
        }
      }
      if error == nil, !lock.withLock({ stopped }) {
        receiveNextEcho(on: connection)
      }
    }
  }

  func stop() {
    let connection = lock.withLock { () -> NWConnection? in
      stopped = true
      pendingDatagram = nil
      sentAtBySequence.removeAll()
      sendInFlight = false
      defer { self.connection = nil }
      return self.connection
    }
    connection?.cancel()
  }

}

final class BonjourPointerMotionReceiver: @unchecked Sendable {
  typealias MotionHandler = @Sendable (PointerMotionState) -> Void

  private let codec: SecurePointerMotionCodec
  private let motionHandler: MotionHandler
  private let queue = DispatchQueue(
    label: "dev.deskmux.motion.datagram.receiver", qos: .userInteractive)
  private let lock = NSLock()
  private var listener: NWListener?
  private var listeningPort: NWEndpoint.Port?
  private var connections: [ObjectIdentifier: NWConnection] = [:]

  init(
    sharedKey: String,
    motionHandler: @escaping MotionHandler
  ) throws {
    codec = try SecurePointerMotionCodec(sharedKey: sharedKey)
    self.motionHandler = motionHandler
  }

  func start(timeout: TimeInterval = 5) throws {
    let ready = DispatchSemaphore(value: 0)
    let startState = MotionConnectionStartState()
    let listener = try NWListener(using: pointerMotionDatagramParameters(), on: .any)
    listener.stateUpdateHandler = { [weak listener] state in
      switch state {
      case .ready:
        if let port = listener?.port { startState.set(port) }
        ready.signal()
      case .failed(let error):
        startState.set(error)
        ready.signal()
      case .cancelled:
        ready.signal()
      default:
        break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    lock.withLock { self.listener = listener }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + timeout) == .success else {
      listener.cancel()
      throw InputPeerConnectionError.connectionFailed("motion datagram listener timed out")
    }
    if let error = startState.getError() {
      listener.cancel()
      throw error
    }
    guard let port = startState.getPort() else {
      listener.cancel()
      throw InputPeerConnectionError.connectionFailed("motion datagram listener has no port")
    }
    lock.withLock { listeningPort = port }
  }

  var port: NWEndpoint.Port? { lock.withLock { listeningPort } }

  func stop() {
    let active = lock.withLock { () -> (NWListener?, [NWConnection]) in
      let state = (listener, Array(connections.values))
      listener = nil
      listeningPort = nil
      connections.removeAll()
      return state
    }
    active.0?.cancel()
    for connection in active.1 { connection.cancel() }
  }

  private func accept(_ connection: NWConnection) {
    let identifier = ObjectIdentifier(connection)
    lock.withLock { connections[identifier] = connection }
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      if case .ready = state { receiveNext(on: connection) }
      if case .failed = state { remove(connection) }
      if case .cancelled = state { remove(connection) }
    }
    connection.start(queue: queue)
  }

  private func receiveNext(on connection: NWConnection) {
    connection.receiveMessage { [weak self, weak connection] data, _, _, error in
      guard let self, let connection else { return }
      if let data, !data.isEmpty, let state = try? codec.open(data) {
        let receivedAt = DispatchTime.now().uptimeNanoseconds
        motionHandler(state)
        // Echo a sampled authenticated datagram only after receiver-side
        // handling. The source can therefore measure the actual UDP motion
        // path, including injection, without adding traffic for every event.
        if state.sequence.isMultiple(of: 4) {
          let processedAt = DispatchTime.now().uptimeNanoseconds
          let echo = PointerMotionState(
            sessionID: state.sessionID,
            sequence: state.sequence,
            kind: state.kind,
            cumulativeDeltaX: state.cumulativeDeltaX,
            cumulativeDeltaY: state.cumulativeDeltaY,
            receiverReceivedAtNanoseconds: receivedAt,
            receiverProcessingNanoseconds: processedAt - receivedAt
          )
          connection.send(
            content: try? codec.seal(echo),
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .idempotent
          )
        }
      }
      if error == nil {
        receiveNext(on: connection)
      } else {
        remove(connection)
      }
    }
  }

  private func remove(_ connection: NWConnection) {
    _ = lock.withLock { connections.removeValue(forKey: ObjectIdentifier(connection)) }
    connection.cancel()
  }

}

public struct MotionDatagramEchoObservation: Codable, Equatable, Sendable {
  public let sequence: UInt64
  public let roundTripMilliseconds: Double
  public let receiverReceivedAtNanoseconds: UInt64?
  public let receiverProcessingNanoseconds: UInt64?

  public init(
    sequence: UInt64,
    roundTripMilliseconds: Double,
    receiverReceivedAtNanoseconds: UInt64?,
    receiverProcessingNanoseconds: UInt64?
  ) {
    self.sequence = sequence
    self.roundTripMilliseconds = roundTripMilliseconds
    self.receiverReceivedAtNanoseconds = receiverReceivedAtNanoseconds
    self.receiverProcessingNanoseconds = receiverProcessingNanoseconds
  }
}

private final class MotionConnectionStartState: @unchecked Sendable {
  private let lock = NSLock()
  private var error: Error?
  private var port: NWEndpoint.Port?

  func set(_ error: Error) { lock.withLock { self.error = error } }
  func set(_ port: NWEndpoint.Port) { lock.withLock { self.port = port } }
  func getError() -> Error? { lock.withLock { error } }
  func getPort() -> NWEndpoint.Port? { lock.withLock { port } }
}

private func pointerMotionDatagramParameters() -> NWParameters {
  let parameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
  parameters.includePeerToPeer = true
  parameters.allowLocalEndpointReuse = true
  parameters.serviceClass = .interactiveVoice
  return parameters
}
