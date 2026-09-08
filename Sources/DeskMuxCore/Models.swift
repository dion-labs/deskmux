import Foundation

public struct PeerID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public struct MonitorID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

public struct ObservationSessionID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct DDCInput: RawRepresentable, Codable, Hashable, Sendable, Comparable,
  CustomStringConvertible
{
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static func < (lhs: DDCInput, rhs: DDCInput) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public var description: String { String(rawValue) }

  public static let displayPort1 = DDCInput(rawValue: 15)
  public static let displayPort2 = DDCInput(rawValue: 16)
  public static let hdmi1 = DDCInput(rawValue: 17)
  public static let hdmi2 = DDCInput(rawValue: 18)
  public static let usbC = DDCInput(rawValue: 27)
}

public enum RouteConfidence: String, Codable, Hashable, Sendable {
  case candidate
  case confirmed
}

public enum ObservationEvidence: Codable, Hashable, Sendable {
  case passive(session: ObservationSessionID)
  case guided(probeID: UUID)
}

public struct DisplayObservation: Codable, Hashable, Sendable {
  public let peerID: PeerID
  public let monitorID: MonitorID
  public let currentInput: DDCInput?
  public let isActiveSource: Bool
  public let evidence: ObservationEvidence
  public let observedAt: Date

  public init(
    peerID: PeerID,
    monitorID: MonitorID,
    currentInput: DDCInput?,
    isActiveSource: Bool,
    evidence: ObservationEvidence,
    observedAt: Date = Date()
  ) {
    self.peerID = peerID
    self.monitorID = monitorID
    self.currentInput = currentInput
    self.isActiveSource = isActiveSource
    self.evidence = evidence
    self.observedAt = observedAt
  }
}

public struct LearnedRoute: Codable, Hashable, Sendable {
  public let peerID: PeerID
  public let monitorID: MonitorID
  public let input: DDCInput
  public let confidence: RouteConfidence
  public let evidenceCount: Int
  public let lastObservedAt: Date

  public init(
    peerID: PeerID,
    monitorID: MonitorID,
    input: DDCInput,
    confidence: RouteConfidence,
    evidenceCount: Int,
    lastObservedAt: Date
  ) {
    self.peerID = peerID
    self.monitorID = monitorID
    self.input = input
    self.confidence = confidence
    self.evidenceCount = evidenceCount
    self.lastObservedAt = lastObservedAt
  }
}

public struct MonitorAssignment: Codable, Hashable, Sendable {
  public let monitorID: MonitorID
  public let destinationPeerID: PeerID

  public init(monitorID: MonitorID, destinationPeerID: PeerID) {
    self.monitorID = monitorID
    self.destinationPeerID = destinationPeerID
  }
}

public struct DeskProfile: Codable, Hashable, Sendable {
  public let id: UUID
  public let name: String
  public let assignments: [MonitorAssignment]
  public let inputDestinationPeerID: PeerID?
  public let useMacBookAsReceiver: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    assignments: [MonitorAssignment],
    inputDestinationPeerID: PeerID?,
    useMacBookAsReceiver: Bool = false
  ) {
    self.id = id
    self.name = name
    self.assignments = assignments
    self.inputDestinationPeerID = inputDestinationPeerID
    self.useMacBookAsReceiver = useMacBookAsReceiver
  }
}

public struct TopologySnapshot: Codable, Hashable, Sendable {
  public let observations: [DisplayObservation]

  public init(observations: [DisplayObservation]) {
    self.observations = observations
  }

  public func activePeers(for monitorID: MonitorID) -> Set<PeerID> {
    Set(
      observations.lazy
        .filter { $0.monitorID == monitorID && $0.isActiveSource }
        .map(\.peerID)
    )
  }
}
