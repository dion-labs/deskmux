import Foundation
import Network

public enum DeskMuxScreenClientState: Equatable, Sendable {
  case idle
  case discovering
  case connecting
  case streaming(sourcePeerID: String)
  case failed(String)
  case stopped
}

public final class BonjourScreenStreamClient: @unchecked Sendable {
  public static let serviceType = "_deskmux-screen._tcp"
  public typealias StateHandler = @Sendable (DeskMuxScreenClientState) -> Void
  public typealias MessageHandler = @Sendable (DeskMuxScreenWireMessage) -> Void

  private let localPeerID: String
  private let destinationPeerID: String
  private let sharedKey: String
  private let stateHandler: StateHandler
  private let messageHandler: MessageHandler
  private let queue = DispatchQueue(label: "dev.deskmux.screen.client", qos: .userInteractive)
  private let lock = NSLock()
  private var browser: NWBrowser?
  private var connection: DeskMuxScreenPeerConnection?
  private var timeout: DispatchWorkItem?
  private var connectWork: DispatchWorkItem?
  private var discoveredRoute: (endpoint: NWEndpoint, interface: NWInterface?, priority: Int)?

  public init(
    localPeerID: String,
    destinationPeerID: String,
    sharedKey: String,
    stateHandler: @escaping StateHandler,
    messageHandler: @escaping MessageHandler
  ) {
    self.localPeerID = localPeerID
    self.destinationPeerID = destinationPeerID
    self.sharedKey = sharedKey
    self.stateHandler = stateHandler
    self.messageHandler = messageHandler
  }

  public func start() {
    stop(sendState: false)
    stateHandler(.discovering)
    let browser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil),
      using: deskMuxScreenTCPParameters()
    )
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self else { return }
      let routes = results.compactMap { result
        -> (endpoint: NWEndpoint, interface: NWInterface?, priority: Int)? in
        guard case .service(let name, _, _, _) = result.endpoint,
          screenServiceRank(name: name, peerID: destinationPeerID) != nil
        else { return nil }
        let interface = result.interfaces.max {
          screenRoutePriority($0) < screenRoutePriority($1)
        }
        return (result.endpoint, interface, interface.map(screenRoutePriority) ?? 0)
      }
      guard let selected = routes.max(by: { $0.priority < $1.priority }) else { return }
      scheduleConnect(to: selected.endpoint, interface: selected.interface, priority: selected.priority)
    }
    browser.stateUpdateHandler = { [weak self] state in
      if case .failed(let error) = state {
        self?.fail("Screen discovery failed: \(error)")
      }
    }
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, lock.withLock({ connection == nil }) else { return }
      fail(DeskMuxScreenTransportError.destinationNotFound(destinationPeerID).description)
    }
    lock.withLock {
      self.browser = browser
      self.timeout = timeout
    }
    browser.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 6, execute: timeout)
  }

  public func stop() { stop(sendState: true) }

  public func sendInput(_ event: DeskMuxScreenInputEvent) {
    do {
      try lock.withLock {
        guard let connection else { throw DeskMuxScreenTransportError.notConnected }
        try connection.send(.input(event))
      }
    } catch {
      fail("Remote input failed: \(error)")
    }
  }

  private func stop(sendState: Bool) {
    let current = lock.withLock { () -> (NWBrowser?, DeskMuxScreenPeerConnection?) in
      timeout?.cancel()
      timeout = nil
      connectWork?.cancel()
      connectWork = nil
      discoveredRoute = nil
      let current = (browser, connection)
      browser = nil
      connection = nil
      return current
    }
    current.0?.cancel()
    current.1?.cancel()
    if sendState { stateHandler(.stopped) }
  }

  private func scheduleConnect(
    to endpoint: NWEndpoint,
    interface: NWInterface?,
    priority: Int
  ) {
    let work = lock.withLock { () -> DispatchWorkItem? in
      guard connection == nil else { return nil }
      if discoveredRoute == nil || priority > discoveredRoute!.priority {
        discoveredRoute = (endpoint, interface, priority)
      }
      guard connectWork == nil else { return nil }
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        let route = lock.withLock { () -> (NWEndpoint, NWInterface?)? in
          connectWork = nil
          return discoveredRoute.map { ($0.endpoint, $0.interface) }
        }
        guard let route else { return }
        connect(to: route.0, interface: route.1)
      }
      connectWork = work
      return work
    }
    if let work { queue.asyncAfter(deadline: .now() + 0.4, execute: work) }
  }

  private func connect(to endpoint: NWEndpoint, interface: NWInterface?) {
    let shouldConnect = lock.withLock { connection == nil }
    guard shouldConnect else { return }
    browser?.cancel()
    browser = nil
    stateHandler(.connecting)
    let nwConnection = NWConnection(
      to: endpoint,
      using: deskMuxScreenTCPParameters(requiredInterface: interface)
    )
    do {
      let connection = try DeskMuxScreenPeerConnection(
        connection: nwConnection,
        sharedKey: sharedKey,
        role: .initiator,
        queue: queue,
        messageHandler: { [weak self] message in
          guard let self else { return }
          if case .ready(let peerID) = message {
            lock.withLock {
              timeout?.cancel()
              timeout = nil
            }
            stateHandler(.streaming(sourcePeerID: peerID))
          } else if case .failure(let reason) = message {
            fail(reason)
          }
          messageHandler(message)
        },
        stateHandler: { [weak self] state in
          guard let self else { return }
          switch state {
          case .ready:
            do {
              try self.connection?.send(
                .hello(
                  peerID: localPeerID,
                  protocolVersion: DeskMuxScreenWireMessage.currentProtocolVersion
                )
              )
            } catch {
              fail(String(describing: error))
            }
          case .failed(let error): fail("Screen connection failed: \(error)")
          case .cancelled:
            let wasActive = self.lock.withLock { self.connection != nil }
            if wasActive { fail("The screen connection closed before the stream was ready.") }
          default: break
          }
        }
      )
      let connectionTimeout = DispatchWorkItem { [weak self, weak connection] in
        guard let self, let connection else { return }
        let isCurrent = lock.withLock { self.connection === connection }
        guard isCurrent else { return }
        let path = nwConnection.currentPath.map { String(describing: $0) } ?? "no network path"
        fail("Timed out starting the screen stream (\(path)).")
      }
      lock.withLock {
        self.connection = connection
        timeout?.cancel()
        timeout = connectionTimeout
      }
      connection.start()
      queue.asyncAfter(deadline: .now() + 6, execute: connectionTimeout)
    } catch {
      fail(String(describing: error))
    }
  }

  private func fail(_ reason: String) {
    stop(sendState: false)
    stateHandler(.failed(reason))
  }
}

public final class BonjourScreenStreamServer: @unchecked Sendable {
  public static let serviceType = BonjourScreenStreamClient.serviceType

  private let peerID: String
  private let sharedKey: String
  private let queue = DispatchQueue(label: "dev.deskmux.screen.server", qos: .userInteractive)
  private let lock = NSLock()
  private var listener: NWListener?
  private var sessions: [ObjectIdentifier: ScreenServerSession] = [:]

  public init(peerID: String, sharedKey: String) {
    self.peerID = peerID
    self.sharedKey = sharedKey
  }

  public func start() throws {
    guard lock.withLock({ self.listener == nil }) else { return }
    let listener = try NWListener(using: deskMuxScreenTCPParameters())
    listener.service = NWListener.Service(name: peerID, type: Self.serviceType)
    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    listener.stateUpdateHandler = { [weak self] state in
      if case .failed = state { self?.stop() }
    }
    lock.withLock { self.listener = listener }
    listener.start(queue: queue)
  }

  public func stop() {
    let current = lock.withLock { () -> (NWListener?, [ScreenServerSession]) in
      let result = (listener, Array(sessions.values))
      listener = nil
      sessions.removeAll()
      return result
    }
    current.0?.cancel()
    for session in current.1 { session.stop() }
  }

  private func accept(_ nwConnection: NWConnection) {
    do {
      var session: ScreenServerSession!
      session = try ScreenServerSession(
        localPeerID: peerID,
        sharedKey: sharedKey,
        nwConnection: nwConnection,
        queue: queue,
        ended: { [weak self] identifier in
          _ = self?.lock.withLock { self?.sessions.removeValue(forKey: identifier) }
        }
      )
      lock.withLock { sessions[ObjectIdentifier(session)] = session }
      session.start()
    } catch {
      nwConnection.cancel()
    }
  }
}

private final class ScreenServerSession: @unchecked Sendable {
  private let localPeerID: String
  private let ended: @Sendable (ObjectIdentifier) -> Void
  private let lock = NSLock()
  private var connection: DeskMuxScreenPeerConnection!
  private var source: VirtualDisplayVideoSource?
  private var stopped = false

  init(
    localPeerID: String,
    sharedKey: String,
    nwConnection: NWConnection,
    queue: DispatchQueue,
    ended: @escaping @Sendable (ObjectIdentifier) -> Void
  ) throws {
    self.localPeerID = localPeerID
    self.ended = ended
    connection = try DeskMuxScreenPeerConnection(
      connection: nwConnection,
      sharedKey: sharedKey,
      role: .acceptor,
      queue: queue,
      messageHandler: { [weak self] message in try self?.handle(message) },
      stateHandler: { [weak self] state in
        switch state {
        case .failed, .cancelled: self?.stop()
        default: break
        }
      }
    )
  }

  func start() { connection.start() }

  func stop() {
    let shouldStop = lock.withLock { () -> Bool in
      guard !stopped else { return false }
      stopped = true
      return true
    }
    guard shouldStop else { return }
    connection.cancel()
    let source = lock.withLock { () -> VirtualDisplayVideoSource? in
      defer { self.source = nil }
      return self.source
    }
    Task { @MainActor in await source?.stop() }
    ended(ObjectIdentifier(self))
  }

  private func handle(_ message: DeskMuxScreenWireMessage) throws {
    switch message {
    case .hello(_, let version):
      guard version == DeskMuxScreenWireMessage.currentProtocolVersion else {
        try connection.send(.failure("Screen protocol version \(version) is unsupported."))
        stop()
        return
      }
      let alreadyStarted = lock.withLock { source != nil }
      guard !alreadyStarted else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        let source = VirtualDisplayVideoSource { [weak self] message in
          try? self?.connection.send(message)
        }
        lock.withLock { self.source = source }
        do {
          try await source.start()
          try connection.send(.ready(sourcePeerID: localPeerID))
        } catch {
          try? connection.send(.failure(String(describing: error)))
          stop()
        }
      }
    case .stop:
      stop()
    case .input(let event):
      let source = lock.withLock { self.source }
      Task { @MainActor in source?.inject(event) }
    default:
      break
    }
  }
}
