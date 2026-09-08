import Foundation

public struct ASUSReceiverFactoryExperimentResult: Codable {
  public let baseline: ASUSKeyboardPathObservation
  public let active: ASUSKeyboardPathObservation?
  public let recovery: ASUSKeyboardPathObservation?
  public let sends: [ASUSRFModeSendResult]
  public let responses: [String]
  public let note: String
}

/// Holds physical RF selection constant and changes only receiver factory mode.
public enum ASUSReceiverFactoryExperiment {
  public static func run() throws -> ASUSReceiverFactoryExperimentResult {
    let controls = ASUSFactoryRFModeExperiment.controlDevices()
    let receivers = controls.filter { $0.descriptor.productID == 0x1A07 }
    guard receivers.count == 1 else {
      throw ASUSRFModeExperimentError.exactDevicesRequired
    }
    let receiver = receivers[0]
    guard receiver.descriptor.versionNumber == ASUSRFModeExperiment.expectedReceiverRevision else {
      throw ASUSRFModeExperimentError.unexpectedRevision(
        role: "Receiver", expected: ASUSRFModeExperiment.expectedReceiverRevision,
        actual: receiver.descriptor.versionNumber)
    }
    let baseline = try ASUSKeyboardPathMonitor.monitor(durationSeconds: 10)
    guard baseline.paths.contains(where: {
      $0.role == .rfReceiver && ($0.inputReportDelta ?? 0) >= 4
    }) else {
      return ASUSReceiverFactoryExperimentResult(
        baseline: baseline, active: nil, recovery: nil, sends: [], responses: [],
        note: "No writes: receiver typing baseline was not established.")
    }
    let session = try ASUSVendorSession(device: receiver.device, target: "rfReceiver")
    defer { session.close() }
    var sends: [ASUSRFModeSendResult] = []
    var cleanupAttempted = false
    defer {
      if !cleanupAttempted {
        _ = session.send(operation: "leaveFactory", prefix: ASUSFactoryRFModeExperiment.leaveFactoryPrefix)
        Thread.sleep(forTimeInterval: 0.2)
      }
    }
    sends.append(session.send(operation: "enterFactory", prefix: ASUSFactoryRFModeExperiment.enterFactoryPrefix))
    Thread.sleep(forTimeInterval: 0.2)
    let active = sends[0].succeeded
      ? try ASUSKeyboardPathMonitor.monitor(durationSeconds: 10) : nil
    sends.append(session.send(operation: "leaveFactory", prefix: ASUSFactoryRFModeExperiment.leaveFactoryPrefix))
    cleanupAttempted = true
    Thread.sleep(forTimeInterval: 0.2)
    let recovery = try ASUSKeyboardPathMonitor.monitor(durationSeconds: 10)
    return ASUSReceiverFactoryExperimentResult(
      baseline: baseline, active: active, recovery: recovery, sends: sends,
      responses: session.responses(),
      note: "Only receiver factory entry and exit were sent; no keyboard, pairing, or firmware commands.")
  }
}
