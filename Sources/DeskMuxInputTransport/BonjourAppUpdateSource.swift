import DeskMuxCore
import Foundation
import Network

public final class BonjourAppUpdateSource: @unchecked Sendable {
  public static let serviceType = "_deskmux._tcp"

  private let sourcePeerID: PeerID
  private let destinationPeerID: PeerID
  private let sharedKey: String
  private let serviceType: String
  private let queue = DispatchQueue(label: "dev.deskmux.app.update", qos: .userInitiated)
  private let lock = NSLock()
  private var connection: InputPeerConnection?
  private var result: DeskMuxUpdateResult?
  private var failure: Error?

  public init(
    sourcePeerID: PeerID,
    destinationPeerID: PeerID,
    sharedKey: String,
    serviceType: String = BonjourAppUpdateSource.serviceType
  ) {
    self.sourcePeerID = sourcePeerID
    self.destinationPeerID = destinationPeerID
    self.sharedKey = sharedKey
    self.serviceType = serviceType
  }

  public func send(_ package: DeskMuxUpdatePackage) throws -> DeskMuxUpdateResult {
    guard sharedKey.count >= 16 else { throw BonjourInputRelayError.sharedKeyTooShort }
    let discovered = try discoverDestination(timeout: 8)
    let completed = DispatchSemaphore(value: 0)
    let nwConnection = NWConnection(
      to: discovered.endpoint,
      using: inputRelayTCPParameters(requiredInterface: discovered.interface)
    )
    let peerConnection = try InputPeerConnection(
      connection: nwConnection,
      sharedKey: sharedKey,
      role: .initiator,
      queue: queue,
      messageHandler: { [weak self] message in
        guard let self else { return }
        switch message {
        case .ready(let peerID, _) where peerID == destinationPeerID:
          do {
            try lock.withLock { try connection?.send(.appUpdate(package)) }
          } catch {
            recordFailure(error)
            completed.signal()
          }
        case .appUpdateResult(let updateResult):
          lock.withLock { result = updateResult }
          completed.signal()
        default:
          break
        }
      },
      stateHandler: { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          do {
            try lock.withLock {
              guard let connection else { throw InputPeerConnectionError.notReady }
              try connection.send(
                .hello(
                  peerID: sourcePeerID,
                  // App updates remain compatible with the v2 receiver so a
                  // newer Studio can deliver the protocol upgrade itself.
                  protocolVersion: 2,
                  purpose: .appUpdate
                )
              )
            }
          } catch {
            recordFailure(error)
            completed.signal()
          }
        case .failed(let error):
          recordFailure(error)
          completed.signal()
        case .cancelled:
          if lock.withLock({ result == nil && failure == nil }) {
            recordFailure(BonjourInputRelayError.receiverRejected("connection closed"))
            completed.signal()
          }
        default:
          break
        }
      }
    )
    lock.withLock { connection = peerConnection }
    peerConnection.start()

    guard completed.wait(timeout: .now() + 30) == .success else {
      let localNetworkDenied =
        nwConnection.currentPath?.unsatisfiedReason == .localNetworkDenied
      peerConnection.cancel()
      if localNetworkDenied { throw BonjourInputRelayError.localNetworkPermissionMissing }
      throw BonjourInputRelayError.connectionTimedOut(destinationPeerID)
    }
    if let failure = lock.withLock({ failure }) {
      peerConnection.cancel()
      throw failure
    }
    guard let result = lock.withLock({ result }) else {
      peerConnection.cancel()
      throw BonjourInputRelayError.receiverRejected("no update acknowledgement")
    }
    try? peerConnection.send(.goodbye)
    peerConnection.cancel()
    return result
  }

  private func discoverDestination(
    timeout: TimeInterval
  ) throws -> (endpoint: NWEndpoint, interface: NWInterface?) {
    let signal = DispatchSemaphore(value: 0)
    let found = UpdateLockedEndpoint()
    let browser = NWBrowser(
      for: .bonjour(type: serviceType, domain: nil),
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
    let outcome = signal.wait(timeout: .now() + timeout)
    if outcome == .success { Thread.sleep(forTimeInterval: 0.4) }
    browser.cancel()
    guard outcome == .success, let endpoint = found.get() else {
      throw BonjourInputRelayError.destinationNotFound(destinationPeerID)
    }
    return endpoint
  }

  private func recordFailure(_ error: Error) {
    lock.withLock {
      if failure == nil { failure = error }
    }
  }
}

private final class UpdateLockedEndpoint: @unchecked Sendable {
  private let lock = NSLock()
  private var value:
    (
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
