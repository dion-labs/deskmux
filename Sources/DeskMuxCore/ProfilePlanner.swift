import Foundation

public enum PlanningIssue: Error, Codable, Equatable, Sendable, CustomStringConvertible {
  case duplicateMonitorAssignment(MonitorID)
  case monitorHasNoActiveController(MonitorID)
  case monitorHasAmbiguousControllers(MonitorID, [PeerID])
  case missingConfirmedRoute(monitorID: MonitorID, destinationPeerID: PeerID)
  case conflictingConfirmedRoutes(peerID: PeerID, monitorID: MonitorID, inputs: [DDCInput])

  public var description: String {
    switch self {
    case .duplicateMonitorAssignment(let monitorID):
      return "Profile assigns monitor \(monitorID) more than once"
    case .monitorHasNoActiveController(let monitorID):
      return "Monitor \(monitorID) has no active controlling peer"
    case .monitorHasAmbiguousControllers(let monitorID, let peers):
      return "Monitor \(monitorID) appears active on multiple peers: \(peers)"
    case .missingConfirmedRoute(let monitorID, let destinationPeerID):
      return "No confirmed route from peer \(destinationPeerID) to monitor \(monitorID)"
    case .conflictingConfirmedRoutes(let peerID, let monitorID, let inputs):
      return "Peer \(peerID) has conflicting confirmed inputs for monitor \(monitorID): \(inputs)"
    }
  }
}

public struct MonitorSwitchCommand: Codable, Equatable, Hashable, Sendable {
  public let monitorID: MonitorID
  public let controllingPeerID: PeerID
  public let destinationPeerID: PeerID
  public let destinationInput: DDCInput

  public init(
    monitorID: MonitorID,
    controllingPeerID: PeerID,
    destinationPeerID: PeerID,
    destinationInput: DDCInput
  ) {
    self.monitorID = monitorID
    self.controllingPeerID = controllingPeerID
    self.destinationPeerID = destinationPeerID
    self.destinationInput = destinationInput
  }
}

public struct DisplayConfirmation: Codable, Equatable, Hashable, Sendable {
  public let monitorID: MonitorID
  public let destinationPeerID: PeerID

  public init(monitorID: MonitorID, destinationPeerID: PeerID) {
    self.monitorID = monitorID
    self.destinationPeerID = destinationPeerID
  }
}

public struct ProfilePlan: Codable, Equatable, Sendable {
  public let profile: DeskProfile
  public let involvedPeers: Set<PeerID>
  public let switches: [MonitorSwitchCommand]
  public let confirmations: [DisplayConfirmation]

  public init(
    profile: DeskProfile,
    involvedPeers: Set<PeerID>,
    switches: [MonitorSwitchCommand],
    confirmations: [DisplayConfirmation]
  ) {
    self.profile = profile
    self.involvedPeers = involvedPeers
    self.switches = switches
    self.confirmations = confirmations
  }
}

public struct ProfilePlanner: Sendable {
  public init() {}

  public func plan(
    profile: DeskProfile,
    topology: TopologySnapshot,
    confirmedRoutes: [LearnedRoute]
  ) throws -> ProfilePlan {
    var assignedMonitors = Set<MonitorID>()
    for assignment in profile.assignments {
      guard assignedMonitors.insert(assignment.monitorID).inserted else {
        throw PlanningIssue.duplicateMonitorAssignment(assignment.monitorID)
      }
    }

    var routeLookup: [RouteLookupKey: LearnedRoute] = [:]
    for route in confirmedRoutes where route.confidence == .confirmed {
      let key = RouteLookupKey(peerID: route.peerID, monitorID: route.monitorID)
      if let existing = routeLookup[key], existing.input != route.input {
        throw PlanningIssue.conflictingConfirmedRoutes(
          peerID: route.peerID,
          monitorID: route.monitorID,
          inputs: [existing.input, route.input].sorted()
        )
      }
      routeLookup[key] = route
    }

    var involvedPeers = Set<PeerID>()
    var switches: [MonitorSwitchCommand] = []
    var confirmations: [DisplayConfirmation] = []

    for assignment in profile.assignments.sorted(by: assignmentSort) {
      let activePeers = topology.activePeers(for: assignment.monitorID)
      guard !activePeers.isEmpty else {
        throw PlanningIssue.monitorHasNoActiveController(assignment.monitorID)
      }
      guard activePeers.count == 1, let controllingPeerID = activePeers.first else {
        throw PlanningIssue.monitorHasAmbiguousControllers(
          assignment.monitorID,
          activePeers.sorted { $0.rawValue < $1.rawValue }
        )
      }

      involvedPeers.insert(controllingPeerID)
      involvedPeers.insert(assignment.destinationPeerID)
      confirmations.append(
        DisplayConfirmation(
          monitorID: assignment.monitorID,
          destinationPeerID: assignment.destinationPeerID
        )
      )

      guard controllingPeerID != assignment.destinationPeerID else { continue }
      let key = RouteLookupKey(
        peerID: assignment.destinationPeerID,
        monitorID: assignment.monitorID
      )
      guard let route = routeLookup[key] else {
        throw PlanningIssue.missingConfirmedRoute(
          monitorID: assignment.monitorID,
          destinationPeerID: assignment.destinationPeerID
        )
      }
      switches.append(
        MonitorSwitchCommand(
          monitorID: assignment.monitorID,
          controllingPeerID: controllingPeerID,
          destinationPeerID: assignment.destinationPeerID,
          destinationInput: route.input
        )
      )
    }

    if let inputPeer = profile.inputDestinationPeerID {
      involvedPeers.insert(inputPeer)
    }

    return ProfilePlan(
      profile: profile,
      involvedPeers: involvedPeers,
      switches: switches,
      confirmations: confirmations
    )
  }

  private func assignmentSort(_ lhs: MonitorAssignment, _ rhs: MonitorAssignment) -> Bool {
    lhs.monitorID.rawValue < rhs.monitorID.rawValue
  }
}

private struct RouteLookupKey: Hashable {
  let peerID: PeerID
  let monitorID: MonitorID
}
