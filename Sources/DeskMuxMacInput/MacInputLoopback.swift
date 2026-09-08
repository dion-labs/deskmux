import DeskMuxCore
import Foundation

public struct MacInputLoopbackReport: Codable, Equatable, Sendable {
  public let durationSeconds: Double
  public let relayedEventCount: Int
  public let endedByEmergencyChord: Bool

  public init(
    durationSeconds: Double,
    relayedEventCount: Int,
    endedByEmergencyChord: Bool
  ) {
    self.durationSeconds = durationSeconds
    self.relayedEventCount = relayedEventCount
    self.endedByEmergencyChord = endedByEmergencyChord
  }
}

public enum MacInputLoopback {
  public static func run(durationSeconds: Double) throws -> MacInputLoopbackReport {
    let permission = MacInputPermissions.status()
    guard permission.canListen else { throw MacInputCaptureError.listenPermissionMissing }
    guard permission.canPost else { throw MacInputInjectorError.postPermissionMissing }

    let sessionID = UUID()
    let injector = try MacInputInjector(sessionID: sessionID)
    let state = LoopbackState()
    let capture = MacInputCapture(
      sessionID: sessionID,
      packetHandler: { packet in
        do {
          try injector.inject(packet)
          state.recordEvent()
          return true
        } catch {
          state.recordFailure(error)
          return false
        }
      },
      emergencyHandler: {
        state.recordEmergency()
        injector.releaseAll()
      }
    )
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + durationSeconds) {
      capture.stop()
    }
    try capture.run()
    injector.releaseAll()
    if let failure = state.failure { throw failure }
    return MacInputLoopbackReport(
      durationSeconds: durationSeconds,
      relayedEventCount: state.eventCount,
      endedByEmergencyChord: state.endedByEmergency
    )
  }
}

private final class LoopbackState: @unchecked Sendable {
  private let lock = NSLock()
  private var _eventCount = 0
  private var _endedByEmergency = false
  private var _failure: Error?

  var eventCount: Int { lock.withLock { _eventCount } }
  var endedByEmergency: Bool { lock.withLock { _endedByEmergency } }
  var failure: Error? { lock.withLock { _failure } }

  func recordEvent() {
    lock.withLock { _eventCount += 1 }
  }

  func recordEmergency() {
    lock.withLock { _endedByEmergency = true }
  }

  func recordFailure(_ error: Error) {
    lock.withLock {
      if _failure == nil { _failure = error }
    }
  }
}
