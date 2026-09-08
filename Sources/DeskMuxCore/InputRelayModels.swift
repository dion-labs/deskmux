import Foundation

public enum InputSessionMode: String, Codable, Equatable, Sendable {
  case allInput
  case keyboardOnly

  public var returnsOnDestinationLocalInput: Bool {
    self == .allInput
  }
}

public enum InputEventKind: String, Codable, CaseIterable, Sendable {
  case keyDown
  case keyUp
  case flagsChanged
  case mouseMoved
  case leftMouseDown
  case leftMouseUp
  case leftMouseDragged
  case rightMouseDown
  case rightMouseUp
  case rightMouseDragged
  case otherMouseDown
  case otherMouseUp
  case otherMouseDragged
  case scrollWheel
}

public struct InputEventPacket: Codable, Equatable, Sendable {
  public let sessionID: UUID
  public let sequence: UInt64
  public let kind: InputEventKind
  public let eventData: Data

  public init(sessionID: UUID, sequence: UInt64, kind: InputEventKind, eventData: Data) {
    self.sessionID = sessionID
    self.sequence = sequence
    self.kind = kind
    self.eventData = eventData
  }
}

/// A motion-only recording captured at the HID event-tap boundary. Keeping the
/// original flattened CGEvent bytes lets experiments change extraction,
/// coalescing, pacing, and transport independently while replaying identical
/// physical input. Keyboard, button, and scroll events are never recorded.
public struct MotionTraceSample: Codable, Equatable, Sendable {
  public let offsetNanoseconds: UInt64
  public let kind: InputEventKind
  public let eventData: Data

  public init(offsetNanoseconds: UInt64, kind: InputEventKind, eventData: Data) {
    self.offsetNanoseconds = offsetNanoseconds
    self.kind = kind
    self.eventData = eventData
  }
}

public struct MotionReplayTrace: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let recordedAt: Date
  public let samples: [MotionTraceSample]

  public init(
    schemaVersion: Int = MotionReplayTrace.currentSchemaVersion,
    recordedAt: Date,
    samples: [MotionTraceSample]
  ) {
    self.schemaVersion = schemaVersion
    self.recordedAt = recordedAt
    self.samples = samples
  }

  public var durationNanoseconds: UInt64 { samples.last?.offsetNanoseconds ?? 0 }
}

/// Latest-wins pointer state for the unreliable motion channel. Deltas are
/// cumulative for the session, so a later datagram repairs any packet loss.
public struct PointerMotionState: Codable, Equatable, Sendable {
  public let sessionID: UUID
  public let sequence: UInt64
  public let kind: InputEventKind
  public let cumulativeDeltaX: Int64
  public let cumulativeDeltaY: Int64
  public let receiverReceivedAtNanoseconds: UInt64?
  public let receiverProcessingNanoseconds: UInt64?

  public init(
    sessionID: UUID,
    sequence: UInt64,
    kind: InputEventKind,
    cumulativeDeltaX: Int64,
    cumulativeDeltaY: Int64
  ) {
    self.init(
      sessionID: sessionID,
      sequence: sequence,
      kind: kind,
      cumulativeDeltaX: cumulativeDeltaX,
      cumulativeDeltaY: cumulativeDeltaY,
      receiverReceivedAtNanoseconds: nil,
      receiverProcessingNanoseconds: nil
    )
  }

  public init(
    sessionID: UUID,
    sequence: UInt64,
    kind: InputEventKind,
    cumulativeDeltaX: Int64,
    cumulativeDeltaY: Int64,
    receiverReceivedAtNanoseconds: UInt64?,
    receiverProcessingNanoseconds: UInt64?
  ) {
    self.sessionID = sessionID
    self.sequence = sequence
    self.kind = kind
    self.cumulativeDeltaX = cumulativeDeltaX
    self.cumulativeDeltaY = cumulativeDeltaY
    self.receiverReceivedAtNanoseconds = receiverReceivedAtNanoseconds
    self.receiverProcessingNanoseconds = receiverProcessingNanoseconds
  }
}

public enum InputOwnership: Codable, Equatable, Sendable {
  case local
  case remote(peerID: PeerID, sessionID: UUID)
}

public enum InputOwnershipIssue: Error, Equatable, Sendable {
  case destinationUnavailable(PeerID)
}

public actor InputOwnershipCoordinator {
  public let localPeerID: PeerID
  public private(set) var ownership: InputOwnership = .local
  private var availablePeers = Set<PeerID>()

  public init(localPeerID: PeerID) {
    self.localPeerID = localPeerID
  }

  public func peerBecameAvailable(_ peerID: PeerID) {
    guard peerID != localPeerID else { return }
    availablePeers.insert(peerID)
  }

  @discardableResult
  public func peerBecameUnavailable(_ peerID: PeerID) -> InputOwnership {
    availablePeers.remove(peerID)
    if case .remote(let owner, _) = ownership, owner == peerID {
      ownership = .local
    }
    return ownership
  }

  @discardableResult
  public func handOff(to peerID: PeerID, sessionID: UUID = UUID()) throws -> InputOwnership {
    guard availablePeers.contains(peerID) else {
      throw InputOwnershipIssue.destinationUnavailable(peerID)
    }
    ownership = .remote(peerID: peerID, sessionID: sessionID)
    return ownership
  }

  @discardableResult
  public func returnLocal() -> InputOwnership {
    ownership = .local
    return ownership
  }
}
