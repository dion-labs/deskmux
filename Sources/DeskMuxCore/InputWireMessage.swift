import Foundation

public enum PeerSessionPurpose: String, Codable, Equatable, Sendable {
  case inputRelay
  case appUpdate
}

public struct DeskMuxUpdatePackage: Codable, Equatable, Sendable {
  public let version: String
  public let build: String
  public let bundleIdentifier: String
  public let archiveSHA256: String
  public let archiveData: Data

  public init(
    version: String,
    build: String,
    bundleIdentifier: String,
    archiveSHA256: String,
    archiveData: Data
  ) {
    self.version = version
    self.build = build
    self.bundleIdentifier = bundleIdentifier
    self.archiveSHA256 = archiveSHA256
    self.archiveData = archiveData
  }
}

public enum DeskMuxUpdateResult: Codable, Equatable, Sendable {
  case accepted(build: String)
  case rejected(reason: String)
}

public struct DeskMuxClipboardUpdate: Codable, Equatable, Sendable {
  public static let maximumUTF8Size = 1_048_576

  public let id: UUID
  public let sourcePeerID: PeerID
  public let text: String

  public init(id: UUID = UUID(), sourcePeerID: PeerID, text: String) {
    self.id = id
    self.sourcePeerID = sourcePeerID
    self.text = text
  }

  public var isWithinSizeLimit: Bool {
    text.lengthOfBytes(using: .utf8) <= Self.maximumUTF8Size
  }
}

public enum InputWireMessage: Codable, Equatable, Sendable {
  case hello(peerID: PeerID, protocolVersion: Int, purpose: PeerSessionPurpose)
  case ready(peerID: PeerID, motionPort: UInt16?)
  case ping(UInt64)
  case pong(UInt64)
  case beginInput(sessionID: UUID, mode: InputSessionMode, initialModifierFlags: UInt64)
  case event(InputEventPacket)
  case eventAck(sequence: UInt64, receiverProcessingNanoseconds: UInt64)
  case releaseAll
  case goodbye
  case appUpdate(DeskMuxUpdatePackage)
  case appUpdateResult(DeskMuxUpdateResult)
  case clipboardUpdate(DeskMuxClipboardUpdate)
  case clipboardUpdateApplied(UUID)

  public static let currentProtocolVersion = 9
}
