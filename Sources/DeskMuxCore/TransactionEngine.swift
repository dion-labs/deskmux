import Foundation

public protocol ProfileOperationDriver: Sendable {
  func prepare(peerID: PeerID, for profile: DeskProfile) async throws
  func switchMonitor(_ command: MonitorSwitchCommand) async throws
  func waitForDisplay(_ confirmation: DisplayConfirmation, timeout: Duration) async throws
  func routeInput(to peerID: PeerID) async throws
}

public enum TransactionPhase: String, Codable, Equatable, Sendable {
  case planning
  case preparing
  case switchingDisplays
  case confirmingDisplays
  case routingInput
  case completed
}

public enum TransactionStep: Codable, Equatable, Sendable {
  case prepared(PeerID)
  case switched(MonitorSwitchCommand)
  case confirmed(DisplayConfirmation)
  case routedInput(PeerID)
}

public enum TransactionOutcome: Codable, Equatable, Sendable {
  case completed
  case rejected(PlanningIssue)
  case failed(phase: TransactionPhase, message: String)
}

public struct TransactionReport: Codable, Equatable, Sendable {
  public let id: UUID
  public let profileID: UUID
  public let outcome: TransactionOutcome
  public let completedSteps: [TransactionStep]
  public let startedAt: Date
  public let finishedAt: Date

  public init(
    id: UUID,
    profileID: UUID,
    outcome: TransactionOutcome,
    completedSteps: [TransactionStep],
    startedAt: Date,
    finishedAt: Date
  ) {
    self.id = id
    self.profileID = profileID
    self.outcome = outcome
    self.completedSteps = completedSteps
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}

public struct TransactionEngine: Sendable {
  private let planner: ProfilePlanner
  private let confirmationTimeout: Duration

  public init(
    planner: ProfilePlanner = ProfilePlanner(),
    confirmationTimeout: Duration = .seconds(8)
  ) {
    self.planner = planner
    self.confirmationTimeout = confirmationTimeout
  }

  public func execute(
    profile: DeskProfile,
    topology: TopologySnapshot,
    confirmedRoutes: [LearnedRoute],
    driver: any ProfileOperationDriver
  ) async -> TransactionReport {
    let transactionID = UUID()
    let startedAt = Date()
    var steps: [TransactionStep] = []

    let plan: ProfilePlan
    do {
      plan = try planner.plan(
        profile: profile,
        topology: topology,
        confirmedRoutes: confirmedRoutes
      )
    } catch let issue as PlanningIssue {
      return report(
        id: transactionID,
        profile: profile,
        outcome: .rejected(issue),
        steps: steps,
        startedAt: startedAt
      )
    } catch {
      return report(
        id: transactionID,
        profile: profile,
        outcome: .failed(phase: .planning, message: String(describing: error)),
        steps: steps,
        startedAt: startedAt
      )
    }

    do {
      for peerID in plan.involvedPeers.sorted(by: { $0.rawValue < $1.rawValue }) {
        try await driver.prepare(peerID: peerID, for: profile)
        steps.append(.prepared(peerID))
      }
    } catch {
      return report(
        id: transactionID,
        profile: profile,
        outcome: .failed(phase: .preparing, message: String(describing: error)),
        steps: steps,
        startedAt: startedAt
      )
    }

    do {
      for command in plan.switches {
        try await driver.switchMonitor(command)
        steps.append(.switched(command))
      }
    } catch {
      return report(
        id: transactionID,
        profile: profile,
        outcome: .failed(phase: .switchingDisplays, message: String(describing: error)),
        steps: steps,
        startedAt: startedAt
      )
    }

    do {
      for confirmation in plan.confirmations {
        try await driver.waitForDisplay(confirmation, timeout: confirmationTimeout)
        steps.append(.confirmed(confirmation))
      }
    } catch {
      return report(
        id: transactionID,
        profile: profile,
        outcome: .failed(phase: .confirmingDisplays, message: String(describing: error)),
        steps: steps,
        startedAt: startedAt
      )
    }

    if let inputPeer = profile.inputDestinationPeerID {
      do {
        try await driver.routeInput(to: inputPeer)
        steps.append(.routedInput(inputPeer))
      } catch {
        return report(
          id: transactionID,
          profile: profile,
          outcome: .failed(phase: .routingInput, message: String(describing: error)),
          steps: steps,
          startedAt: startedAt
        )
      }
    }

    return report(
      id: transactionID,
      profile: profile,
      outcome: .completed,
      steps: steps,
      startedAt: startedAt
    )
  }

  private func report(
    id: UUID,
    profile: DeskProfile,
    outcome: TransactionOutcome,
    steps: [TransactionStep],
    startedAt: Date
  ) -> TransactionReport {
    TransactionReport(
      id: id,
      profileID: profile.id,
      outcome: outcome,
      completedSteps: steps,
      startedAt: startedAt,
      finishedAt: Date()
    )
  }
}
