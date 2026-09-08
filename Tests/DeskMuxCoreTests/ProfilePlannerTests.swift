import Foundation
import Testing

@testable import DeskMuxCore

let studio = PeerID(rawValue: "studio")
let macBook = PeerID(rawValue: "macbook")
let viewSonic = MonitorID(rawValue: "viewsonic")
let aoc = MonitorID(rawValue: "aoc")

func route(_ peer: PeerID, _ monitor: MonitorID, _ input: DDCInput) -> LearnedRoute {
  LearnedRoute(
    peerID: peer,
    monitorID: monitor,
    input: input,
    confidence: .confirmed,
    evidenceCount: 1,
    lastObservedAt: Date()
  )
}

func observation(_ peer: PeerID, _ monitor: MonitorID) -> DisplayObservation {
  DisplayObservation(
    peerID: peer,
    monitorID: monitor,
    currentInput: nil,
    isActiveSource: true,
    evidence: .passive(session: ObservationSessionID())
  )
}

@Test func plansOnlyTheMonitorThatMustMove() throws {
  let profile = DeskProfile(
    name: "Studio",
    assignments: [
      MonitorAssignment(monitorID: viewSonic, destinationPeerID: studio),
      MonitorAssignment(monitorID: aoc, destinationPeerID: studio),
    ],
    inputDestinationPeerID: studio
  )
  let topology = TopologySnapshot(observations: [
    observation(studio, viewSonic),
    observation(macBook, aoc),
  ])
  let plan = try ProfilePlanner().plan(
    profile: profile,
    topology: topology,
    confirmedRoutes: [
      route(studio, viewSonic, .hdmi1),
      route(macBook, viewSonic, .hdmi2),
      route(studio, aoc, .hdmi1),
      route(macBook, aoc, .usbC),
    ]
  )

  #expect(
    plan.switches == [
      MonitorSwitchCommand(
        monitorID: aoc,
        controllingPeerID: macBook,
        destinationPeerID: studio,
        destinationInput: .hdmi1
      )
    ])
  #expect(plan.confirmations.count == 2)
  #expect(plan.involvedPeers == Set([studio, macBook]))
}

@Test func rejectsConflictingConfirmedRoutesInsteadOfCrashing() {
  let profile = DeskProfile(
    name: "MacBook",
    assignments: [MonitorAssignment(monitorID: viewSonic, destinationPeerID: macBook)],
    inputDestinationPeerID: macBook
  )
  let topology = TopologySnapshot(observations: [observation(studio, viewSonic)])

  #expect {
    try ProfilePlanner().plan(
      profile: profile,
      topology: topology,
      confirmedRoutes: [
        route(macBook, viewSonic, .hdmi1),
        route(macBook, viewSonic, .hdmi2),
      ]
    )
  } throws: { error in
    error as? PlanningIssue
      == .conflictingConfirmedRoutes(
        peerID: macBook,
        monitorID: viewSonic,
        inputs: [.hdmi1, .hdmi2]
      )
  }
}

@Test func rejectsUnknownDestinationRouteBeforeExecution() {
  let profile = DeskProfile(
    name: "MacBook",
    assignments: [MonitorAssignment(monitorID: viewSonic, destinationPeerID: macBook)],
    inputDestinationPeerID: macBook
  )
  let topology = TopologySnapshot(observations: [observation(studio, viewSonic)])

  #expect(
    throws: PlanningIssue.missingConfirmedRoute(monitorID: viewSonic, destinationPeerID: macBook)
  ) {
    try ProfilePlanner().plan(profile: profile, topology: topology, confirmedRoutes: [])
  }
}

@Test func rejectsAmbiguousActiveController() {
  let profile = DeskProfile(
    name: "Studio",
    assignments: [MonitorAssignment(monitorID: viewSonic, destinationPeerID: studio)],
    inputDestinationPeerID: studio
  )
  let topology = TopologySnapshot(observations: [
    observation(studio, viewSonic),
    observation(macBook, viewSonic),
  ])

  #expect {
    try ProfilePlanner().plan(profile: profile, topology: topology, confirmedRoutes: [])
  } throws: { error in
    guard case PlanningIssue.monitorHasAmbiguousControllers(let monitor, let peers) = error else {
      return false
    }
    return monitor == viewSonic && peers == [macBook, studio]
  }
}
