import DeskMuxCore
import DeskMuxMacInput
import Foundation
import Network

enum InputPeerConnectionError: Error, CustomStringConvertible {
  case notReady
  case connectionFailed(String)

  var description: String {
    switch self {
    case .notReady: return "peer connection is not ready"
    case .connectionFailed(let message): return "peer connection failed: \(message)"
    }
  }
}

final class InputPeerConnection: @unchecked Sendable {
  typealias MessageHandler = @Sendable (InputWireMessage) throws -> Void
  typealias StateHandler = @Sendable (NWConnection.State) -> Void

  private let connection: NWConnection
  private let codec: SecureInputFrameCodec
  private let queue: DispatchQueue
  private let messageHandler: MessageHandler
  private let stateHandler: StateHandler
  private let lock = NSLock()
  private var parser = InputFrameParser()
  private var ready = false
  private var cancelledByOwner = false

  init(
    connection: NWConnection,
    sharedKey: String,
    role: SecureChannelRole,
    queue: DispatchQueue,
    messageHandler: @escaping MessageHandler,
    stateHandler: @escaping StateHandler
  ) throws {
    self.connection = connection
    codec = try SecureInputFrameCodec(sharedKey: sharedKey, role: role)
    self.queue = queue
    self.messageHandler = messageHandler
    self.stateHandler = stateHandler
  }

  func start() {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      lock.withLock {
        if case .ready = state { ready = true } else { ready = false }
      }
      stateHandler(state)
      if state == .ready { receiveNext() }
    }
    connection.start(queue: queue)
  }

  func send(_ message: InputWireMessage) throws {
    guard lock.withLock({ ready }) else { throw InputPeerConnectionError.notReady }
    let data = try codec.seal(message)
    connection.send(
      content: data,
      completion: .contentProcessed { [weak self] error in
        guard let self, let error else { return }
        guard !lock.withLock({ cancelledByOwner }) else { return }
        stateHandler(.failed(error))
        connection.cancel()
      })
  }

  func cancel() {
    lock.withLock { cancelledByOwner = true }
    connection.cancel()
  }

  func remoteEndpoint(using port: NWEndpoint.Port) -> NWEndpoint? {
    guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint else {
      return nil
    }
    return .hostPort(host: host, port: port)
  }

  private func receiveNext() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      do {
        if let data, !data.isEmpty {
          for payload in try parser.append(data) {
            try messageHandler(codec.open(payload))
          }
        }
      } catch {
        stateHandler(.failed(NWError.posix(.EPROTO)))
        connection.cancel()
        return
      }
      if let error {
        stateHandler(.failed(error))
        connection.cancel()
      } else if isComplete {
        connection.cancel()
      } else {
        receiveNext()
      }
    }
  }
}
