import Foundation
import Testing

@testable import DeskMuxCore

@Test func inactiveSourceCannotTeachARoute() async {
  let registry = RouteRegistry()
  let outcome = await registry.observe(
    DisplayObservation(
      peerID: PeerID(rawValue: "studio"),
      monitorID: MonitorID(rawValue: "viewsonic"),
      currentInput: .hdmi1,
      isActiveSource: false,
      evidence: .guided(probeID: UUID())
    )
  )

  #expect(outcome == .ignoredInactiveSource)
  #expect(await registry.snapshot().isEmpty)
}

@Test func passiveRouteRequiresIndependentEvidence() async {
  let registry = RouteRegistry()
  let peer = PeerID(rawValue: "studio")
  let monitor = MonitorID(rawValue: "viewsonic")
  let firstSession = ObservationSessionID()
  let secondSession = ObservationSessionID()

  let first = await registry.observe(
    DisplayObservation(
      peerID: peer,
      monitorID: monitor,
      currentInput: .hdmi1,
      isActiveSource: true,
      evidence: .passive(session: firstSession)
    )
  )
  guard case .learned(let candidate) = first else {
    Issue.record("Expected a newly learned candidate route")
    return
  }
  #expect(candidate.confidence == .candidate)
  #expect(await registry.confirmedRoute(peerID: peer, monitorID: monitor) == nil)

  let duplicate = await registry.observe(
    DisplayObservation(
      peerID: peer,
      monitorID: monitor,
      currentInput: .hdmi1,
      isActiveSource: true,
      evidence: .passive(session: firstSession)
    )
  )
  guard case .unchanged(let duplicateRoute) = duplicate else {
    Issue.record("Repeated evidence from one session must not confirm a route")
    return
  }
  #expect(duplicateRoute.confidence == .candidate)

  let second = await registry.observe(
    DisplayObservation(
      peerID: peer,
      monitorID: monitor,
      currentInput: .hdmi1,
      isActiveSource: true,
      evidence: .passive(session: secondSession)
    )
  )
  guard case .confirmed(let confirmed) = second else {
    Issue.record("Expected independent evidence to confirm the route")
    return
  }
  #expect(confirmed.confidence == .confirmed)
  #expect(confirmed.evidenceCount == 2)
}

@Test func guidedObservationConfirmsImmediatelyAndConflictDoesNotOverwrite() async {
  let registry = RouteRegistry()
  let peer = PeerID(rawValue: "macbook")
  let monitor = MonitorID(rawValue: "aoc")

  let learned = await registry.observe(
    DisplayObservation(
      peerID: peer,
      monitorID: monitor,
      currentInput: .usbC,
      isActiveSource: true,
      evidence: .guided(probeID: UUID())
    )
  )
  guard case .confirmed(let confirmed) = learned else {
    Issue.record("Guided observation should confirm immediately")
    return
  }
  #expect(confirmed.input == .usbC)

  let conflict = await registry.observe(
    DisplayObservation(
      peerID: peer,
      monitorID: monitor,
      currentInput: .hdmi2,
      isActiveSource: true,
      evidence: .guided(probeID: UUID())
    )
  )
  guard case .conflict(let existing, let observedInput) = conflict else {
    Issue.record("Expected conflicting input evidence")
    return
  }
  #expect(existing.input == .usbC)
  #expect(observedInput == .hdmi2)
  #expect(await registry.confirmedRoute(peerID: peer, monitorID: monitor)?.input == .usbC)
}
