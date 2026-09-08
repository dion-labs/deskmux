import Foundation
import Network

final class DeskMuxScreenPeerConnection: @unchecked Sendable {
  typealias MessageHandler = @Sendable (DeskMuxScreenWireMessage) throws -> Void
  typealias StateHandler = @Sendable (NWConnection.State) -> Void

  private let connection: NWConnection
  private let codec: DeskMuxSecureScreenCodec
  private let queue: DispatchQueue
  private let sendQueue = DispatchQueue(label: "dev.deskmux.screen.connection.send", qos: .userInteractive)
  private let messageHandler: MessageHandler
  private let stateHandler: StateHandler
  private let lock = NSLock()
  private var parser = DeskMuxScreenFrameParser()
  private var ready = false
  private var cancelled = false

  init(
    connection: NWConnection,
    sharedKey: String,
    role: DeskMuxScreenChannelRole,
    queue: DispatchQueue,
    messageHandler: @escaping MessageHandler,
    stateHandler: @escaping StateHandler
  ) throws {
    self.connection = connection
    codec = try DeskMuxSecureScreenCodec(sharedKey: sharedKey, role: role)
    self.queue = queue
    self.messageHandler = messageHandler
    self.stateHandler = stateHandler
  }

  func start() {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      lock.withLock { ready = state == .ready }
      stateHandler(state)
      if state == .ready { receiveNext() }
    }
    connection.start(queue: queue)
  }

  func send(_ message: DeskMuxScreenWireMessage) throws {
    try sendQueue.sync {
      guard lock.withLock({ ready && !cancelled }) else {
        throw DeskMuxScreenTransportError.notConnected
      }
      let data = try codec.seal(message)
      connection.send(
        content: data,
        completion: .contentProcessed { [weak self] error in
          guard let self, let error else { return }
          stateHandler(.failed(error))
        }
      )
    }
  }

  func cancel() {
    lock.withLock { cancelled = true }
    connection.cancel()
  }

  private func receiveNext() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      do {
        if let data, !data.isEmpty {
          for frame in try parser.append(data) {
            try messageHandler(codec.open(frame))
          }
        }
      } catch {
        stateHandler(.failed(.posix(.EPROTO)))
        connection.cancel()
        return
      }
      if let error {
        stateHandler(.failed(error))
      } else if complete {
        connection.cancel()
      } else {
        receiveNext()
      }
    }
  }
}

public enum DeskMuxScreenTransportError: Error, CustomStringConvertible, Sendable {
  case notConnected
  case destinationNotFound(String)
  case connectionTimedOut(String)
  case listenerFailed(String)
  case captureFailed(String)

  public var description: String {
    switch self {
    case .notConnected: return "The screen connection is not ready."
    case .destinationNotFound(let peer): return "The screen service for \(peer) was not found."
    case .connectionTimedOut(let peer): return "Timed out connecting to \(peer)'s screen service."
    case .listenerFailed(let reason): return "The screen service failed: \(reason)"
    case .captureFailed(let reason): return "Screen capture failed: \(reason)"
    }
  }
}

func deskMuxScreenTCPParameters(requiredInterface: NWInterface? = nil) -> NWParameters {
  let tcp = NWProtocolTCP.Options()
  tcp.noDelay = true
  tcp.enableKeepalive = true
  tcp.keepaliveIdle = 5
  tcp.keepaliveInterval = 2
  tcp.keepaliveCount = 3
  let parameters = NWParameters(tls: nil, tcp: tcp)
  parameters.includePeerToPeer = true
  parameters.allowLocalEndpointReuse = true
  parameters.prohibitedInterfaceTypes = [.cellular]
  parameters.requiredInterface = requiredInterface
  return parameters
}

func screenRoutePriority(_ interface: NWInterface) -> Int {
  // A screen stream needs sustained throughput. Prefer the ordinary LAN when
  // it is present; AWDL remains a discovery/fallback path but can advertise a
  // peer even when that peer has no usable AWDL address.
  if interface.name == "awdl0" { return 200 }
  switch interface.type {
  case .wiredEthernet: return 400
  case .wifi: return 300
  case .cellular: return 100
  case .loopback: return 50
  case .other: return 25
  @unknown default: return 0
  }
}

func screenServiceRank(name: String, peerID: String) -> Int? {
  if name == peerID { return 1 }
  guard name.hasPrefix("\(peerID) ("), name.hasSuffix(")") else { return nil }
  let start = name.index(name.startIndex, offsetBy: peerID.count + 2)
  let end = name.index(before: name.endIndex)
  return Int(name[start..<end])
}
