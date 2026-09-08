import CoreGraphics
import DeskMuxAgentIPC
import DeskMuxCore
import DeskMuxInputTransport
import DeskMuxMacInput
import DeskMuxScreenTransport
import Foundation
import Security

private final class DeskMuxAgentService: NSObject, DeskMuxAgentXPCProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private let logitechProbeLock = NSLock()
  private var cachedLogitechStatus: (status: DeskMuxLogitechStatus, observedAt: Date)?
  private var configuration: DeskMuxAgentReceiverConfiguration?
  private var receiver: BonjourInputReceiver?
  private var screenServer: BonjourScreenStreamServer?
  private var receiverGeneration = UUID()
  private var receiverState: DeskMuxAgentReceiverState = .unconfigured
  private var activeSourcePeerID: String?
  private var receiverError: String?
  private var keyboardRelay: BonjourInputRelaySource?
  private var keyboardRelayGeneration = UUID()
  private var keyboardRelayState: DeskMuxAgentKeyboardRelayState = .idle
  private var keyboardRelayError: String?
  private var warmConnection: BonjourInputRelaySource?
  private var warmConnectionState: DeskMuxAgentWarmConnectionState = .idle
  private var warmConnectionError: String?
  private var warmConnectionRoundTripMilliseconds: Double?
  private let keyboardRelayQueue = DispatchQueue(
    label: "dev.deskmux.agent.keyboard-relay",
    qos: .userInteractive
  )
  private let keyboardReturnFailsafeQueue = DispatchQueue(
    label: "dev.deskmux.agent.keyboard-return-failsafe",
    qos: .utility
  )
  private let warmConnectionQueue = DispatchQueue(
    label: "dev.deskmux.agent.warm-input-connection",
    qos: .utility
  )

  override init() {
    super.init()
    guard let restored = DeskMuxAgentConfigurationStore.load(),
      let data = try? JSONEncoder().encode(restored)
    else { return }
    configureReceiver(data) { _ in }
  }

  func status(withReply reply: @escaping @Sendable (Data) -> Void) {
    reply(encodedStatus())
  }

  func requestPermissions(withReply reply: @escaping @Sendable (Data) -> Void) {
    _ = MacInputPermissions.request()
    reply(encodedStatus())
  }

  func requestScreenCapturePermission(withReply reply: @escaping @Sendable (Data) -> Void) {
    _ = CGRequestScreenCaptureAccess()
    reply(encodedStatus())
  }

  func logitechStatus(withReply reply: @escaping @Sendable (Data) -> Void) {
    replyLogitechStatus(forceRefresh: false, reply: reply)
  }

  func freshLogitechStatus(withReply reply: @escaping @Sendable (Data) -> Void) {
    replyLogitechStatus(forceRefresh: true, reply: reply)
  }

  private func replyLogitechStatus(
    forceRefresh: Bool, reply: @escaping @Sendable (Data) -> Void
  ) {
    let status = logitechProbeLock.withLock { () -> DeskMuxLogitechStatus in
      if !forceRefresh, let cachedLogitechStatus,
        Date().timeIntervalSince(cachedLogitechStatus.observedAt) < 4
      {
        return cachedLogitechStatus.status
      }
      let status = collectLogitechStatus()
      cachedLogitechStatus = (status, Date())
      return status
    }
    reply((try? JSONEncoder().encode(status)) ?? Data())
  }

  private func collectLogitechStatus() -> DeskMuxLogitechStatus {
    let probes = LogitechHIDPlus.probeChangeHost()
    let supported = probes.filter(\.isSupported)
    if let probe = supported.count == 1 ? supported.first : nil {
      return DeskMuxLogitechStatus(
        deviceName: probe.device.product,
        transport: probe.device.isReceiverControl ? "Logi Bolt receiver" : probe.device.transport,
        deviceIndex: probe.deviceIndex,
        featureIndex: probe.featureIndex,
        hostCount: probe.hostCount,
        currentHost: probe.currentHost
      )
    } else if probes.isEmpty {
      return DeskMuxLogitechStatus(error: "No Logitech HID++ control interface is connected.")
    } else {
      return DeskMuxLogitechStatus(
        deviceName: probes.first?.device.product,
        transport: probes.first?.device.transport,
        error: probes.first?.error ?? "The Logitech device is unavailable or ambiguous."
      )
    }
  }

  func switchLogitechHost(
    _ requestData: Data,
    withReply reply: @escaping @Sendable (Data) -> Void
  ) {
    logitechProbeLock.withLock { cachedLogitechStatus = nil }
    guard
      let request = try? JSONDecoder().decode(
        DeskMuxLogitechSwitchRequest.self, from: requestData)
    else {
      reply(
        (try? JSONEncoder().encode(
          DeskMuxLogitechSwitchReceipt(
            previousHost: -1, targetHost: -1, commandAccepted: false,
            error: "The native mouse switch request was invalid."
          ))) ?? Data())
      return
    }
    do {
      let result = try LogitechHIDPlus.switchHost(
        from: request.expectedCurrentHost,
        to: request.targetHost
      )
      reply(
        (try? JSONEncoder().encode(
          DeskMuxLogitechSwitchReceipt(
            previousHost: result.previousHost,
            targetHost: result.targetHost,
            commandAccepted: result.commandAccepted
          ))) ?? Data())
    } catch {
      reply(
        (try? JSONEncoder().encode(
          DeskMuxLogitechSwitchReceipt(
            previousHost: request.expectedCurrentHost,
            targetHost: request.targetHost,
            commandAccepted: false,
            error: String(describing: error)
          ))) ?? Data())
    }
  }

  func configureReceiver(
    _ configurationData: Data,
    withReply reply: @escaping @Sendable (Data) -> Void
  ) {
    guard
      let newConfiguration = try? JSONDecoder().decode(
        DeskMuxAgentReceiverConfiguration.self,
        from: configurationData
      ),
      newConfiguration.sharedKey.count >= 16,
      !newConfiguration.peerID.isEmpty
    else {
      setReceiverFailure("The receiver configuration is invalid.")
      reply(encodedStatus())
      return
    }

    // The stable agent owns receiver availability. Persist its authenticated
    // configuration under the agent's own Keychain identity so an app update,
    // agent restart, or menu-app crash cannot silently remove the input peer.
    DeskMuxAgentConfigurationStore.save(newConfiguration)

    let existing = lock.withLock {
      () -> (
        receiver: BonjourInputReceiver?, relay: BonjourInputRelaySource?,
        warm: BonjourInputRelaySource?, screen: BonjourScreenStreamServer?
      ) in
      guard configuration != newConfiguration || receiver == nil || screenServer == nil else {
        return (nil, nil, nil, nil)
      }
      let existingReceiver = receiver
      let existingRelay = keyboardRelay
      let existingWarm = warmConnection
      let existingScreen = screenServer
      receiver = nil
      screenServer = nil
      keyboardRelay = nil
      warmConnection = nil
      configuration = newConfiguration
      receiverGeneration = UUID()
      keyboardRelayGeneration = UUID()
      receiverState = .starting
      activeSourcePeerID = nil
      receiverError = nil
      keyboardRelayState = .idle
      keyboardRelayError = nil
      warmConnectionState = .idle
      warmConnectionError = nil
      warmConnectionRoundTripMilliseconds = nil
      return (existingReceiver, existingRelay, existingWarm, existingScreen)
    }
    existing.receiver?.stop()
    existing.relay?.stop()
    existing.warm?.cancelPreparedConnection()
    existing.screen?.stop()

    let shouldStart = lock.withLock { receiver == nil && configuration == newConfiguration }
    guard shouldStart else {
      reply(encodedStatus())
      return
    }
    let generation = lock.withLock { receiverGeneration }
    let newReceiver = BonjourInputReceiver(
      peerID: PeerID(rawValue: newConfiguration.peerID),
      sharedKey: newConfiguration.sharedKey,
      // Keep remote recovery and updates available even when the menu app is
      // closed or its bootstrap bundle is difficult to locate.
      acceptsAppUpdates: true,
      versionAdvertisement: DeskMuxVersionAdvertisement(
        component: .agent,
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
        protocolVersion: InputWireMessage.currentProtocolVersion
      ),
      stateHandler: { [weak self] state in
        self?.receiverChanged(state, generation: generation)
      }
    )
    lock.withLock { receiver = newReceiver }
    do {
      try newReceiver.start()
      let newScreenServer = BonjourScreenStreamServer(
        peerID: newConfiguration.peerID,
        sharedKey: newConfiguration.sharedKey
      )
      try newScreenServer.start()
      let adopted = lock.withLock { () -> Bool in
        guard receiverGeneration == generation else { return false }
        screenServer = newScreenServer
        return true
      }
      if !adopted { newScreenServer.stop() }
      startWarmConnectionSupervisor(
        configuration: newConfiguration,
        generation: generation
      )
    } catch {
      lock.withLock {
        guard receiverGeneration == generation else { return }
        receiver = nil
        receiverState = .failed
        receiverError = String(describing: error)
      }
    }
    reply(encodedStatus())
  }

  func startKeyboardRelay(
    to destinationPeerID: String,
    withReply reply: @escaping @Sendable (Data) -> Void
  ) {
    let oneShotReply = OneShotDataReply(reply)
    let setup = lock.withLock {
      () -> (
        configuration: DeskMuxAgentReceiverConfiguration,
        generation: UUID,
        preparedRelay: BonjourInputRelaySource?,
        discardedWarmRelay: BonjourInputRelaySource?
      )? in
      guard let configuration, destinationPeerID != configuration.peerID else { return nil }
      if keyboardRelayState == .connecting || keyboardRelayState == .active {
        return nil
      }
      let generation = UUID()
      keyboardRelayGeneration = generation
      keyboardRelayState = .connecting
      keyboardRelayError = nil
      let existingWarm = warmConnection
      let preparedRelay = existingWarm?.isPrepared == true ? existingWarm : nil
      warmConnection = nil
      keyboardRelay = preparedRelay
      warmConnectionState = .idle
      warmConnectionError = nil
      warmConnectionRoundTripMilliseconds = nil
      return (
        configuration, generation, preparedRelay,
        preparedRelay == nil ? existingWarm : nil
      )
    }
    guard let setup else {
      oneShotReply.send(encodedStatus())
      return
    }
    if setup.preparedRelay != nil {
      recordNetwork("warm_channel_promoted", detail: "destination=\(destinationPeerID)")
    }
    setup.discardedWarmRelay?.cancelPreparedConnection()

    keyboardRelayQueue.async { [weak self, oneShotReply] in
      guard let self else { return }
      superviseKeyboardRelay(
        configuration: setup.configuration,
        destinationPeerID: destinationPeerID,
        generation: setup.generation,
        initialRelay: setup.preparedRelay,
        reply: oneShotReply
      )
    }
  }

  func returnInputToSource(withReply reply: @escaping @Sendable (Data) -> Void) {
    let currentReceiver = lock.withLock { receiver }
    currentReceiver?.returnInputToSource()
    reply(encodedStatus())
  }

  func stopKeyboardRelay(withReply reply: @escaping @Sendable (Data) -> Void) {
    let relay = lock.withLock { () -> BonjourInputRelaySource? in
      let relay = keyboardRelay
      keyboardRelay = nil
      keyboardRelayGeneration = UUID()
      keyboardRelayState = .idle
      keyboardRelayError = nil
      return relay
    }
    relay?.stop()
    reply(encodedStatus())
  }

  private func encodedStatus() -> Data {
    let permissions = MacInputPermissions.status()
    let receiverStatus = lock.withLock {
      (
        receiverState,
        activeSourcePeerID,
        receiverError,
        keyboardRelayState,
        keyboardRelayError,
        warmConnectionState,
        warmConnectionError,
        warmConnectionRoundTripMilliseconds
      )
    }
    return
      (try? JSONEncoder().encode(
        DeskMuxAgentStatus(
          processIdentifier: ProcessInfo.processInfo.processIdentifier,
          agentBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
          canListen: permissions.canListen,
          canPost: permissions.canPost,
          canCaptureScreen: CGPreflightScreenCaptureAccess(),
          receiverState: receiverStatus.0,
          activeSourcePeerID: receiverStatus.1,
          receiverError: receiverStatus.2,
          keyboardRelayState: receiverStatus.3,
          keyboardRelayError: receiverStatus.4,
          warmConnectionState: receiverStatus.5,
          warmConnectionError: receiverStatus.6,
          warmConnectionRoundTripMilliseconds: receiverStatus.7
        ))) ?? Data()
  }

  private func superviseKeyboardRelay(
    configuration: DeskMuxAgentReceiverConfiguration,
    destinationPeerID: String,
    generation: UUID,
    initialRelay: BonjourInputRelaySource?,
    reply: OneShotDataReply
  ) {
    var failuresBeforeFirstConnection = 0
    var nextRelay = initialRelay
    while lock.withLock({ keyboardRelayGeneration == generation }) {
      let relay =
        nextRelay
        ?? BonjourInputRelaySource(
          sourcePeerID: PeerID(rawValue: configuration.peerID),
          destinationPeerID: PeerID(rawValue: destinationPeerID),
          sharedKey: configuration.sharedKey,
          mode: .keyboardOnly
        )
      nextRelay = nil
      relay.setCaptureStartedHandler { [weak self, reply] in
        guard let self else { return }
        let becameActive = lock.withLock { () -> Bool in
          guard keyboardRelayGeneration == generation else { return false }
          keyboardRelayState = .active
          keyboardRelayError = nil
          return true
        }
        if becameActive {
          reply.send(encodedStatus())
          startKeyboardReturnFailsafe(relay: relay, generation: generation)
        }
      }
      let accepted = lock.withLock { () -> Bool in
        guard keyboardRelayGeneration == generation else { return false }
        keyboardRelay = relay
        keyboardRelayState = .connecting
        return true
      }
      guard accepted else {
        reply.send(encodedStatus())
        return
      }

      var failure: String?
      do {
        try relay.run()
      } catch {
        failure = String(describing: error)
      }
      let reason = relay.terminationReason ?? (failure == nil ? .completed : .connectionFailed)
      let stillCurrent = lock.withLock { () -> Bool in
        guard keyboardRelayGeneration == generation else { return false }
        keyboardRelay = nil
        return true
      }
      guard stillCurrent else {
        reply.send(encodedStatus())
        return
      }

      if reason == .destinationRequestedReturn || reason == .localStop || reason == .completed {
        lock.withLock {
          keyboardRelayState = .idle
          keyboardRelayError = "Keyboard relay ended: \(reason.rawValue)."
        }
        reply.send(encodedStatus())
        return
      }

      if !reply.hasSent {
        failuresBeforeFirstConnection += 1
        if failuresBeforeFirstConnection >= 3 {
          lock.withLock {
            keyboardRelayState = .failed
            keyboardRelayError = failure ?? "The keyboard connection closed unexpectedly."
          }
          reply.send(encodedStatus())
          return
        }
      }
      lock.withLock {
        keyboardRelayState = .connecting
        keyboardRelayError =
          "Keyboard link interrupted; reconnecting. \(failure ?? reason.rawValue)"
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    reply.send(encodedStatus())
  }

  private func startKeyboardReturnFailsafe(
    relay: BonjourInputRelaySource,
    generation: UUID
  ) {
    keyboardReturnFailsafeQueue.async { [weak self, weak relay] in
      guard let self, let relay else { return }
      // The device can remain visible briefly while a successful host-change
      // command is taking effect. Do not mistake that transition for a return.
      Thread.sleep(forTimeInterval: 3)
      var consecutiveLocalObservations = 0
      while lock.withLock({
        keyboardRelayGeneration == generation
          && keyboardRelay === relay
          && keyboardRelayState == .active
      }) {
        let status = logitechProbeLock.withLock { () -> DeskMuxLogitechStatus in
          let status = collectLogitechStatus()
          cachedLogitechStatus = (status, Date())
          return status
        }
        consecutiveLocalObservations =
          status.isReady
          ? consecutiveLocalObservations + 1 : 0
        if consecutiveLocalObservations >= 2 {
          let shouldReturn = lock.withLock {
            keyboardRelayGeneration == generation
              && keyboardRelay === relay
              && keyboardRelayState == .active
          }
          if shouldReturn {
            recordNetwork(
              "keyboard_auto_return",
              detail: "Logitech mouse reappeared on the anchor Mac"
            )
            relay.stop()
          }
          return
        }
        Thread.sleep(forTimeInterval: 0.75)
      }
    }
  }

  private func startWarmConnectionSupervisor(
    configuration: DeskMuxAgentReceiverConfiguration,
    generation: UUID
  ) {
    warmConnectionQueue.async { [weak self] in
      self?.superviseWarmConnection(configuration: configuration, generation: generation)
    }
  }

  private func superviseWarmConnection(
    configuration: DeskMuxAgentReceiverConfiguration,
    generation: UUID
  ) {
    let destinationPeerID = configuration.peerID == "studio" ? "macbook" : "studio"
    var lastFailureLogged: String?
    while lock.withLock({ receiverGeneration == generation }) {
      let canPrepare = lock.withLock {
        keyboardRelayState == .idle && warmConnection == nil
      }
      guard canPrepare else {
        Thread.sleep(forTimeInterval: 0.25)
        continue
      }

      let relay = BonjourInputRelaySource(
        sourcePeerID: PeerID(rawValue: configuration.peerID),
        destinationPeerID: PeerID(rawValue: destinationPeerID),
        sharedKey: configuration.sharedKey,
        mode: .keyboardOnly
      )
      let installed = lock.withLock { () -> Bool in
        guard receiverGeneration == generation, keyboardRelayState == .idle,
          warmConnection == nil
        else { return false }
        warmConnection = relay
        warmConnectionState = .connecting
        warmConnectionError = nil
        warmConnectionRoundTripMilliseconds = nil
        return true
      }
      guard installed else { continue }

      do {
        try relay.prepare(timeout: 1)
        let stillWarm = lock.withLock { () -> Bool in
          guard receiverGeneration == generation, warmConnection === relay else {
            return false
          }
          warmConnectionState = .ready
          warmConnectionError = nil
          warmConnectionRoundTripMilliseconds = relay.warmRoundTripMilliseconds
          return true
        }
        if !stillWarm {
          // The handoff path may have atomically taken ownership.
          let wasPromoted = lock.withLock { keyboardRelay === relay }
          if !wasPromoted { relay.cancelPreparedConnection() }
          continue
        }
        let roundTrip =
          relay.warmRoundTripMilliseconds.map {
            String(format: "%.1f", $0)
          } ?? "pending"
        recordNetwork(
          "warm_channel_ready",
          detail: "destination=\(destinationPeerID) rtt_ms=\(roundTrip)"
        )
        lastFailureLogged = nil

        while lock.withLock({ receiverGeneration == generation && warmConnection === relay }),
          relay.isPrepared
        {
          lock.withLock {
            warmConnectionRoundTripMilliseconds = relay.warmRoundTripMilliseconds
          }
          Thread.sleep(forTimeInterval: 0.25)
        }

        let shouldReplace = lock.withLock { () -> Bool in
          guard receiverGeneration == generation, warmConnection === relay else {
            return false
          }
          warmConnection = nil
          warmConnectionState = .connecting
          warmConnectionError = "Warm channel became unavailable; reconnecting."
          warmConnectionRoundTripMilliseconds = nil
          return true
        }
        if shouldReplace { relay.cancelPreparedConnection() }
        if shouldReplace {
          recordNetwork(
            "warm_channel_lost", detail: "destination=\(destinationPeerID)")
        }
      } catch {
        let failure = String(describing: error)
        let shouldRetry = lock.withLock { () -> Bool in
          guard receiverGeneration == generation, warmConnection === relay else {
            return false
          }
          warmConnection = nil
          warmConnectionState = .connecting
          warmConnectionError = failure
          warmConnectionRoundTripMilliseconds = nil
          return true
        }
        relay.cancelPreparedConnection()
        if shouldRetry {
          if failure != lastFailureLogged {
            recordNetwork(
              "warm_channel_failed",
              detail: "destination=\(destinationPeerID) error=\(failure)"
            )
            lastFailureLogged = failure
          }
          Thread.sleep(forTimeInterval: 0.25)
        }
      }
    }
  }

  private func recordNetwork(_ event: String, detail: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let record = [
      "timestamp": formatter.string(from: Date()),
      "event": event,
      "peer": lock.withLock { configuration?.peerID ?? "unknown" },
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      "detail": detail,
    ]
    do {
      let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DeskMux", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("network.jsonl")
      if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(
        contentsOf: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      try handle.write(contentsOf: Data([0x0a]))
    } catch {
      // Network diagnostics must never affect input routing.
    }
  }

  private func receiverChanged(
    _ state: BonjourInputReceiverState,
    generation: UUID
  ) {
    lock.withLock {
      guard receiverGeneration == generation else { return }
      switch state {
      case .starting:
        receiverState = .starting
        activeSourcePeerID = nil
        receiverError = nil
      case .ready:
        receiverState = .ready
        activeSourcePeerID = nil
        receiverError = nil
      case .receiving(let peerID):
        receiverState = .receiving
        activeSourcePeerID = peerID.rawValue
        receiverError = nil
      case .failed(let reason):
        receiverState = .failed
        activeSourcePeerID = nil
        receiverError = reason
      case .stopped:
        receiverState = configuration == nil ? .unconfigured : .starting
        activeSourcePeerID = nil
      }
    }
  }

  private func setReceiverFailure(_ message: String) {
    lock.withLock {
      receiverState = .failed
      activeSourcePeerID = nil
      receiverError = message
    }
  }
}

private enum DeskMuxAgentConfigurationStore {
  private static let service = "dev.deskmux.agent.receiver-configuration"
  private static let account = "default"

  static func load() -> DeskMuxAgentReceiverConfiguration? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return try? JSONDecoder().decode(DeskMuxAgentReceiverConfiguration.self, from: data)
  }

  static func save(_ configuration: DeskMuxAgentReceiverConfiguration) {
    guard let data = try? JSONEncoder().encode(configuration) else { return }
    let identity: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes = [kSecValueData as String: data]
    let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
    guard status == errSecItemNotFound else { return }
    _ = SecItemAdd(identity.merging(attributes) { _, new in new } as CFDictionary, nil)
  }
}

private final class OneShotDataReply: @unchecked Sendable {
  private let lock = NSLock()
  private var reply: (@Sendable (Data) -> Void)?

  init(_ reply: @escaping @Sendable (Data) -> Void) {
    self.reply = reply
  }

  var hasSent: Bool { lock.withLock { reply == nil } }

  func send(_ data: Data) {
    let callback = lock.withLock { () -> (@Sendable (Data) -> Void)? in
      defer { reply = nil }
      return reply
    }
    callback?(data)
  }
}

private final class DeskMuxAgentListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let service = DeskMuxAgentService()

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard isAuthorizedClient(connection) else { return false }
    connection.exportedInterface = NSXPCInterface(with: DeskMuxAgentXPCProtocol.self)
    connection.exportedObject = service
    connection.resume()
    return true
  }

  private func isAuthorizedClient(_ connection: NSXPCConnection) -> Bool {
    guard let mainAppURL = containingMainAppURL() else { return false }
    var mainCode: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(mainAppURL as CFURL, [], &mainCode) == errSecSuccess,
      let mainCode
    else { return false }
    var requirement: SecRequirement?
    guard
      SecCodeCopyDesignatedRequirement(mainCode, [], &requirement) == errSecSuccess,
      let requirement
    else { return false }

    let attributes =
      [
        kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
      ] as CFDictionary
    var guestCode: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
      let guestCode
    else { return false }
    return SecCodeCheckValidity(guestCode, [], requirement) == errSecSuccess
  }

  private func containingMainAppURL() -> URL? {
    var candidate = Bundle.main.bundleURL
    for _ in 0..<6 {
      if Bundle(url: candidate)?.bundleIdentifier == "dev.deskmux.app" {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }
    return nil
  }
}

@main
struct DeskMuxServiceCommand {
  static func main() {
    let delegate = DeskMuxAgentListenerDelegate()
    let listener = NSXPCListener(machServiceName: deskMuxAgentMachServiceName)
    listener.delegate = delegate
    listener.resume()
    RunLoop.current.run()
  }
}
