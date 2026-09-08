import Foundation

public let deskMuxAgentMachServiceName = "dev.deskmux.agent"
public let deskMuxAgentPlistName = "dev.deskmux.agent.plist"

public struct DeskMuxAgentReceiverConfiguration: Codable, Equatable, Sendable {
  public let peerID: String
  public let sharedKey: String

  public init(peerID: String, sharedKey: String) {
    self.peerID = peerID
    self.sharedKey = sharedKey
  }
}

public struct DeskMuxLogitechStatus: Codable, Equatable, Sendable {
  public let deviceName: String?
  public let transport: String?
  public let deviceIndex: Int?
  public let featureIndex: Int?
  public let hostCount: Int?
  public let currentHost: Int?
  public let error: String?

  public init(
    deviceName: String? = nil,
    transport: String? = nil,
    deviceIndex: Int? = nil,
    featureIndex: Int? = nil,
    hostCount: Int? = nil,
    currentHost: Int? = nil,
    error: String? = nil
  ) {
    self.deviceName = deviceName
    self.transport = transport
    self.deviceIndex = deviceIndex
    self.featureIndex = featureIndex
    self.hostCount = hostCount
    self.currentHost = currentHost
    self.error = error
  }

  public var isReady: Bool {
    featureIndex != nil && hostCount != nil && currentHost != nil && error == nil
  }
}

public struct DeskMuxLogitechSwitchRequest: Codable, Equatable, Sendable {
  public let expectedCurrentHost: Int
  public let targetHost: Int

  public init(expectedCurrentHost: Int, targetHost: Int) {
    self.expectedCurrentHost = expectedCurrentHost
    self.targetHost = targetHost
  }
}

public struct DeskMuxLogitechSwitchReceipt: Codable, Equatable, Sendable {
  public let previousHost: Int
  public let targetHost: Int
  public let commandAccepted: Bool
  public let error: String?

  public init(
    previousHost: Int,
    targetHost: Int,
    commandAccepted: Bool,
    error: String? = nil
  ) {
    self.previousHost = previousHost
    self.targetHost = targetHost
    self.commandAccepted = commandAccepted
    self.error = error
  }
}

public enum DeskMuxAgentReceiverState: String, Codable, Equatable, Sendable {
  case unconfigured
  case starting
  case ready
  case receiving
  case failed
}

public enum DeskMuxAgentKeyboardRelayState: String, Codable, Equatable, Sendable {
  case idle
  case connecting
  case active
  case failed
}

public enum DeskMuxAgentWarmConnectionState: String, Codable, Equatable, Sendable {
  case idle
  case connecting
  case ready
}

public struct DeskMuxAgentStatus: Codable, Equatable, Sendable {
  public let processIdentifier: Int32
  public let agentBuild: String?
  public let canListen: Bool
  public let canPost: Bool
  public let canCaptureScreen: Bool?
  public let receiverState: DeskMuxAgentReceiverState
  public let activeSourcePeerID: String?
  public let receiverError: String?
  public let keyboardRelayState: DeskMuxAgentKeyboardRelayState?
  public let keyboardRelayError: String?
  public let warmConnectionState: DeskMuxAgentWarmConnectionState?
  public let warmConnectionError: String?
  public let warmConnectionRoundTripMilliseconds: Double?

  public init(
    processIdentifier: Int32,
    agentBuild: String? = nil,
    canListen: Bool,
    canPost: Bool,
    canCaptureScreen: Bool? = nil,
    receiverState: DeskMuxAgentReceiverState = .unconfigured,
    activeSourcePeerID: String? = nil,
    receiverError: String? = nil,
    keyboardRelayState: DeskMuxAgentKeyboardRelayState? = nil,
    keyboardRelayError: String? = nil,
    warmConnectionState: DeskMuxAgentWarmConnectionState? = nil,
    warmConnectionError: String? = nil,
    warmConnectionRoundTripMilliseconds: Double? = nil
  ) {
    self.processIdentifier = processIdentifier
    self.agentBuild = agentBuild
    self.canListen = canListen
    self.canPost = canPost
    self.canCaptureScreen = canCaptureScreen
    self.receiverState = receiverState
    self.activeSourcePeerID = activeSourcePeerID
    self.receiverError = receiverError
    self.keyboardRelayState = keyboardRelayState
    self.keyboardRelayError = keyboardRelayError
    self.warmConnectionState = warmConnectionState
    self.warmConnectionError = warmConnectionError
    self.warmConnectionRoundTripMilliseconds = warmConnectionRoundTripMilliseconds
  }
}

@objc public protocol DeskMuxAgentXPCProtocol {
  func status(withReply reply: @escaping @Sendable (Data) -> Void)
  func requestPermissions(withReply reply: @escaping @Sendable (Data) -> Void)
  func requestScreenCapturePermission(withReply reply: @escaping @Sendable (Data) -> Void)
  func logitechStatus(withReply reply: @escaping @Sendable (Data) -> Void)
  /// Handoff preparation must never be rejected by a cached "mouse absent" result.
  func freshLogitechStatus(withReply reply: @escaping @Sendable (Data) -> Void)
  func switchLogitechHost(
    _ request: Data,
    withReply reply: @escaping @Sendable (Data) -> Void
  )
  func configureReceiver(
    _ configuration: Data,
    withReply reply: @escaping @Sendable (Data) -> Void
  )
  func startKeyboardRelay(
    to destinationPeerID: String,
    withReply reply: @escaping @Sendable (Data) -> Void
  )
  func stopKeyboardRelay(withReply reply: @escaping @Sendable (Data) -> Void)
  func returnInputToSource(withReply reply: @escaping @Sendable (Data) -> Void)
}
