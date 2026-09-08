import Foundation

public enum RouteLearningOutcome: Equatable, Sendable {
  case ignoredNoInput
  case ignoredInactiveSource
  case learned(LearnedRoute)
  case confirmed(LearnedRoute)
  case unchanged(LearnedRoute)
  case conflict(existing: LearnedRoute, observedInput: DDCInput)
}

private struct RouteKey: Hashable, Sendable {
  let peerID: PeerID
  let monitorID: MonitorID
}

private struct RouteState: Sendable {
  var route: LearnedRoute
  var passiveSessions: Set<ObservationSessionID>
}

public actor RouteRegistry {
  private var states: [RouteKey: RouteState] = [:]

  public init() {}

  @discardableResult
  public func observe(_ observation: DisplayObservation) -> RouteLearningOutcome {
    guard let input = observation.currentInput else { return .ignoredNoInput }
    guard observation.isActiveSource else { return .ignoredInactiveSource }

    let key = RouteKey(peerID: observation.peerID, monitorID: observation.monitorID)
    let isGuided: Bool
    let passiveSession: ObservationSessionID?
    switch observation.evidence {
    case .guided:
      isGuided = true
      passiveSession = nil
    case .passive(let session):
      isGuided = false
      passiveSession = session
    }

    guard var state = states[key] else {
      let sessions = passiveSession.map { Set([$0]) } ?? []
      let route = LearnedRoute(
        peerID: observation.peerID,
        monitorID: observation.monitorID,
        input: input,
        confidence: isGuided ? .confirmed : .candidate,
        evidenceCount: isGuided ? 1 : sessions.count,
        lastObservedAt: observation.observedAt
      )
      states[key] = RouteState(route: route, passiveSessions: sessions)
      return isGuided ? .confirmed(route) : .learned(route)
    }

    guard state.route.input == input else {
      return .conflict(existing: state.route, observedInput: input)
    }

    let previousConfidence = state.route.confidence
    if let passiveSession {
      state.passiveSessions.insert(passiveSession)
    }
    let evidenceCount = max(state.passiveSessions.count, isGuided ? 1 : 0)
    let confidence: RouteConfidence =
      isGuided || state.route.confidence == .confirmed || evidenceCount >= 2
      ? .confirmed : .candidate
    let updated = LearnedRoute(
      peerID: state.route.peerID,
      monitorID: state.route.monitorID,
      input: state.route.input,
      confidence: confidence,
      evidenceCount: evidenceCount,
      lastObservedAt: max(state.route.lastObservedAt, observation.observedAt)
    )
    state.route = updated
    states[key] = state

    if previousConfidence != confidence {
      return .confirmed(updated)
    }
    return .unchanged(updated)
  }

  public func confirm(peerID: PeerID, monitorID: MonitorID, input: DDCInput, at date: Date = Date())
  {
    let key = RouteKey(peerID: peerID, monitorID: monitorID)
    let existingCount = states[key]?.route.evidenceCount ?? 0
    let route = LearnedRoute(
      peerID: peerID,
      monitorID: monitorID,
      input: input,
      confidence: .confirmed,
      evidenceCount: max(existingCount, 1),
      lastObservedAt: date
    )
    states[key] = RouteState(route: route, passiveSessions: states[key]?.passiveSessions ?? [])
  }

  public func route(peerID: PeerID, monitorID: MonitorID) -> LearnedRoute? {
    states[RouteKey(peerID: peerID, monitorID: monitorID)]?.route
  }

  public func confirmedRoute(peerID: PeerID, monitorID: MonitorID) -> LearnedRoute? {
    guard let route = route(peerID: peerID, monitorID: monitorID),
      route.confidence == .confirmed
    else {
      return nil
    }
    return route
  }

  public func snapshot() -> [LearnedRoute] {
    states.values.map(\.route).sorted { lhs, rhs in
      if lhs.monitorID.rawValue != rhs.monitorID.rawValue {
        return lhs.monitorID.rawValue < rhs.monitorID.rawValue
      }
      return lhs.peerID.rawValue < rhs.peerID.rawValue
    }
  }
}
