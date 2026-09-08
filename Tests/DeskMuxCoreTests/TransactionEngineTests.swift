import Foundation
import Testing

@testable import DeskMuxCore

private enum DriverFailure: Error, CustomStringConvertible {
  case requested(String)

  var description: String {
    switch self {
    case .requested(let operation): return "requested failure at \(operation)"
    }
  }
}

private actor TestDriver: ProfileOperationDriver {
  enum FailurePoint: Equatable {
    case prepare(PeerID)
    case switchMonitor(MonitorID)
    case confirm(MonitorID)
    case routeInput
  }

  let failurePoint: FailurePoint?
  private(set) var operations: [String] = []

  init(failurePoint: FailurePoint? = nil) {
    self.failurePoint = failurePoint
  }

  func prepare(peerID: PeerID, for profile: DeskProfile) async throws {
    if failurePoint == .prepare(peerID) { throw DriverFailure.requested("prepare") }
    operations.append("prepare:\(peerID.rawValue)")
  }

  func switchMonitor(_ command: MonitorSwitchCommand) async throws {
    if failurePoint == .switchMonitor(command.monitorID) {
      throw DriverFailure.requested("switch")
    }
    operations.append("switch:\(command.monitorID.rawValue)")
  }

  func waitForDisplay(_ confirmation: DisplayConfirmation, timeout: Duration) async throws {
    if failurePoint == .confirm(confirmation.monitorID) {
      throw DriverFailure.requested("confirm")
    }
    operations.append("confirm:\(confirmation.monitorID.rawValue)")
  }

  func routeInput(to peerID: PeerID) async throws {
    if failurePoint == .routeInput { throw DriverFailure.requested("routeInput") }
    operations.append("input:\(peerID.rawValue)")
  }
}

private func transactionFixture() -> (
  profile: DeskProfile, topology: TopologySnapshot, routes: [LearnedRoute]
) {
  let profile = DeskProfile(
    name: "Studio",
    assignments: [
      MonitorAssignment(monitorID: viewSonic, destinationPeerID: studio),
      MonitorAssignment(monitorID: aoc, destinationPeerID: studio),
    ],
    inputDestinationPeerID: studio
  )
  return (
    profile,
    TopologySnapshot(observations: [
      observation(macBook, viewSonic),
      observation(macBook, aoc),
    ]),
    [
      route(studio, viewSonic, .hdmi1),
      route(studio, aoc, .hdmi1),
    ]
  )
}

@Test func transactionCompletesInSafePhases() async {
  let fixture = transactionFixture()
  let driver = TestDriver()
  let report = await TransactionEngine().execute(
    profile: fixture.profile,
    topology: fixture.topology,
    confirmedRoutes: fixture.routes,
    driver: driver
  )

  #expect(report.outcome == .completed)
  #expect(
    await driver.operations == [
      "prepare:macbook",
      "prepare:studio",
      "switch:aoc",
      "switch:viewsonic",
      "confirm:aoc",
      "confirm:viewsonic",
      "input:studio",
    ])
}

@Test func partialSwitchFailureIsReportedWithoutFalseRollback() async {
  let fixture = transactionFixture()
  let driver = TestDriver(failurePoint: .switchMonitor(viewSonic))
  let report = await TransactionEngine().execute(
    profile: fixture.profile,
    topology: fixture.topology,
    confirmedRoutes: fixture.routes,
    driver: driver
  )

  guard case .failed(let phase, _) = report.outcome else {
    Issue.record("Expected a failed transaction")
    return
  }
  #expect(phase == .switchingDisplays)
  #expect(
    report.completedSteps.contains(
      .switched(
        MonitorSwitchCommand(
          monitorID: aoc,
          controllingPeerID: macBook,
          destinationPeerID: studio,
          destinationInput: .hdmi1
        )
      )))
  #expect(
    await driver.operations == [
      "prepare:macbook",
      "prepare:studio",
      "switch:aoc",
    ])
}

@Test func planningRejectionCallsNoDriverOperations() async {
  let driver = TestDriver()
  let profile = DeskProfile(
    name: "MacBook",
    assignments: [MonitorAssignment(monitorID: viewSonic, destinationPeerID: macBook)],
    inputDestinationPeerID: macBook
  )
  let report = await TransactionEngine().execute(
    profile: profile,
    topology: TopologySnapshot(observations: [observation(studio, viewSonic)]),
    confirmedRoutes: [],
    driver: driver
  )

  guard case .rejected(.missingConfirmedRoute(let monitor, let peer)) = report.outcome else {
    Issue.record("Expected a missing-route planning rejection")
    return
  }
  #expect(monitor == viewSonic)
  #expect(peer == macBook)
  #expect(await driver.operations.isEmpty)
}
