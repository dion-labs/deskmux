import Foundation
import IOKit.hid

public struct ASUSFactoryRFModeExperimentResult: Codable, Equatable, Sendable {
  public let wiredDevice: ASUSHIDInterfaceDescriptor
  public let receiverDevice: ASUSHIDInterfaceDescriptor
  public let sends: [ASUSRFModeSendResult]
  public let wiredVendorResponses: [String]
  public let receiverVendorResponses: [String]
  public let inputPathObservation: ASUSKeyboardPathObservation
  public let exactDevicesStillPresent: Bool
  public let factoryModeCommandsSent: Int
  public let pairingCommandsSent: Int
  public let firmwareCommandsSent: Int
}

/// Reproduces only the transient factory/RF connection-test state machine from
/// ASUS's protocol-1.0 keyboard pairing flow. Pairing-data commands are absent.
public enum ASUSFactoryRFModeExperiment {
  static let enterFactoryPrefix: [UInt8] = [0xFA, 0x00, 0xD6, 0xA5, 0x00]
  static let leaveFactoryPrefix: [UInt8] = [0xFA, 0x00, 0x00, 0x00, 0x00]
  static let checkRFConnectionPrefix: [UInt8] = [0xFA, 0x20, 0x06, 0x00, 0x00]

  public static func run(activeDurationSeconds: TimeInterval = 0.15) throws
    -> ASUSFactoryRFModeExperimentResult
  {
    guard activeDurationSeconds >= 0.1, activeDurationSeconds <= 15 else {
      throw ASUSKeyboardPathMonitorError.invalidDuration
    }
    let controls = controlDevices()
    let wired = controls.filter {
      $0.descriptor.productID == ASUSKeyboardResearchInventory.wiredProductID
    }
    let receivers = controls.filter {
      $0.descriptor.productID == ASUSKeyboardResearchInventory.receiverProductID
    }
    guard wired.count == 1, receivers.count == 1 else {
      throw ASUSRFModeExperimentError.exactDevicesRequired
    }
    guard wired[0].descriptor.versionNumber == ASUSRFModeExperiment.expectedWiredRevision else {
      throw ASUSRFModeExperimentError.unexpectedRevision(
        role: "Wired keyboard",
        expected: ASUSRFModeExperiment.expectedWiredRevision,
        actual: wired[0].descriptor.versionNumber
      )
    }
    guard receivers[0].descriptor.versionNumber == ASUSRFModeExperiment.expectedReceiverRevision else {
      throw ASUSRFModeExperimentError.unexpectedRevision(
        role: "RF receiver",
        expected: ASUSRFModeExperiment.expectedReceiverRevision,
        actual: receivers[0].descriptor.versionNumber
      )
    }

    // Open both handles before changing either device's transient mode so that
    // cleanup does not depend on rediscovery while the experiment is active.
    let wiredSession = try ASUSVendorSession(
      device: wired[0].device,
      target: "wiredKeyboard"
    )
    defer { wiredSession.close() }
    let receiverSession = try ASUSVendorSession(
      device: receivers[0].device,
      target: "rfReceiver"
    )
    defer { receiverSession.close() }

    var sends: [ASUSRFModeSendResult] = []
    sends.append(wiredSession.send(operation: "enterFactory", prefix: enterFactoryPrefix))
    Thread.sleep(forTimeInterval: 0.15)
    sends.append(receiverSession.send(operation: "enterFactory", prefix: enterFactoryPrefix))
    Thread.sleep(forTimeInterval: 0.15)
    sends.append(
      wiredSession.send(operation: "enterRF", prefix: ASUSRFModeExperiment.enterRFPrefix)
    )
    Thread.sleep(forTimeInterval: 0.15)
    sends.append(
      receiverSession.send(operation: "checkRFConnection", prefix: checkRFConnectionPrefix)
    )
    Thread.sleep(forTimeInterval: 0.15)
    let inputPathObservation = try ASUSKeyboardPathMonitor.monitor(
      durationSeconds: activeDurationSeconds
    )

    // These cleanup writes are intentionally unconditional. A failed entry or
    // connection-check write must never skip RF leave or either factory leave.
    sends.append(
      wiredSession.send(operation: "leaveRF", prefix: ASUSRFModeExperiment.leaveRFPrefix)
    )
    Thread.sleep(forTimeInterval: 0.15)
    sends.append(wiredSession.send(operation: "leaveFactory", prefix: leaveFactoryPrefix))
    Thread.sleep(forTimeInterval: 0.15)
    sends.append(receiverSession.send(operation: "leaveFactory", prefix: leaveFactoryPrefix))
    Thread.sleep(forTimeInterval: 0.15)

    let postControls = controlDevices()
    let exactDevicesStillPresent = postControls.contains {
      $0.descriptor.registryEntryID == wired[0].descriptor.registryEntryID
    } && postControls.contains {
      $0.descriptor.registryEntryID == receivers[0].descriptor.registryEntryID
    }

    return ASUSFactoryRFModeExperimentResult(
      wiredDevice: wired[0].descriptor,
      receiverDevice: receivers[0].descriptor,
      sends: sends,
      wiredVendorResponses: wiredSession.responses(),
      receiverVendorResponses: receiverSession.responses(),
      inputPathObservation: inputPathObservation,
      exactDevicesStillPresent: exactDevicesStillPresent,
      factoryModeCommandsSent: 4,
      pairingCommandsSent: 0,
      firmwareCommandsSent: 0
    )
  }

  static func payload(prefix: [UInt8]) -> [UInt8] {
    ASUSRFModeExperiment.payload(prefix: prefix)
  }

  static func controlDevices()
    -> [(device: IOHIDDevice, descriptor: ASUSHIDInterfaceDescriptor)]
  {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      [
        kIOHIDVendorIDKey as String: ASUSKeyboardResearchInventory.vendorID,
        kIOHIDPrimaryUsagePageKey as String: ASUSKeyboardResearchInventory.vendorUsagePage,
        kIOHIDPrimaryUsageKey as String: ASUSKeyboardResearchInventory.vendorUsage,
      ] as CFDictionary
    )
    guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }
    return (devices as NSSet).compactMap { value in
      let device = value as! IOHIDDevice
      let descriptor = ASUSHIDInspector.descriptor(for: device)
      guard ASUSKeyboardResearchInventory.role(productID: descriptor.productID) != nil,
        descriptor.maxInputReportSize == ASUSKeyboardResearchInventory.reportSize,
        descriptor.maxOutputReportSize == ASUSKeyboardResearchInventory.reportSize
      else { return nil }
      return (device, descriptor)
    }
  }
}
