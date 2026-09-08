import Foundation
import IOKit.hid

public struct ASUSRFModeSendResult: Codable, Equatable, Sendable {
  public let target: String
  public let operation: String
  public let payloadPrefix: String
  public let ioReturn: Int32
  public var succeeded: Bool { ioReturn == kIOReturnSuccess }
}

public struct ASUSRFModeExperimentResult: Codable, Equatable, Sendable {
  public let wiredDevice: ASUSHIDInterfaceDescriptor
  public let receiverDevice: ASUSHIDInterfaceDescriptor
  public let sends: [ASUSRFModeSendResult]
  public let receiverStatus: ASUSReceiverStatus?
  public let receiverStatusError: String?
  public let wiredVendorResponses: [String]
  public let exactDevicesStillPresent: Bool
  public let factoryModeCommandsSent: Int
  public let pairingCommandsSent: Int
  public let firmwareCommandsSent: Int
}

public enum ASUSRFModeExperimentError: Error, CustomStringConvertible {
  case exactDevicesRequired
  case unexpectedRevision(role: String, expected: Int, actual: Int)
  case openFailed(IOReturn)

  public var description: String {
    switch self {
    case .exactDevicesRequired:
      return "Exactly one 64-byte control interface for 0x1A05 and 0x1A07 is required."
    case .unexpectedRevision(let role, let expected, let actual):
      return String(
        format: "%@ revision changed (expected 0x%04X, found 0x%04X); no RF command was sent.",
        role, expected, actual)
    case .openFailed(let result):
      return String(format: "Could not open the wired ASUS control interface (0x%08X).", result)
    }
  }
}

/// Runs only the lowest-risk reversible RF-mode experiment. It deliberately
/// contains no factory, pairing, or firmware command payloads.
public enum ASUSRFModeExperiment {
  public static let expectedWiredRevision = 0x0117
  public static let expectedReceiverRevision = 0x0105
  static let enterRFPrefix: [UInt8] = [0xFA, 0x20, 0x04, 0x00, 0x00]
  static let leaveRFPrefix: [UInt8] = [0xFA, 0x20, 0x05, 0x00, 0x00]

  public static func run() throws -> ASUSRFModeExperimentResult {
    let controls = controlDevices()
    let wired = controls.filter { $0.descriptor.productID == ASUSKeyboardResearchInventory.wiredProductID }
    let receivers = controls.filter {
      $0.descriptor.productID == ASUSKeyboardResearchInventory.receiverProductID
    }
    guard wired.count == 1, receivers.count == 1 else {
      throw ASUSRFModeExperimentError.exactDevicesRequired
    }
    guard wired[0].descriptor.versionNumber == expectedWiredRevision else {
      throw ASUSRFModeExperimentError.unexpectedRevision(
        role: "Wired keyboard",
        expected: expectedWiredRevision,
        actual: wired[0].descriptor.versionNumber
      )
    }
    guard receivers[0].descriptor.versionNumber == expectedReceiverRevision else {
      throw ASUSRFModeExperimentError.unexpectedRevision(
        role: "RF receiver",
        expected: expectedReceiverRevision,
        actual: receivers[0].descriptor.versionNumber
      )
    }

    let session = try ASUSVendorSession(device: wired[0].device, target: "wiredKeyboard")
    defer { session.close() }
    let enter = session.send(operation: "enterRF", prefix: enterRFPrefix)
    Thread.sleep(forTimeInterval: 0.2)

    let receiverStatus: ASUSReceiverStatus?
    let receiverStatusError: String?
    do {
      receiverStatus = try ASUSReceiverStatusProbe.probe(timeoutSeconds: 1)
      receiverStatusError = nil
    } catch {
      receiverStatus = nil
      receiverStatusError = String(describing: error)
    }

    // Always attempt the reverse operation, even if enterRF was rejected or
    // the receiver did not answer.
    let leave = session.send(operation: "leaveRF", prefix: leaveRFPrefix)
    Thread.sleep(forTimeInterval: 0.1)
    let postControls = controlDevices()
    let exactDevicesStillPresent = postControls.contains {
      $0.descriptor.registryEntryID == wired[0].descriptor.registryEntryID
    } && postControls.contains {
      $0.descriptor.registryEntryID == receivers[0].descriptor.registryEntryID
    }

    return ASUSRFModeExperimentResult(
      wiredDevice: wired[0].descriptor,
      receiverDevice: receivers[0].descriptor,
      sends: [enter, leave],
      receiverStatus: receiverStatus,
      receiverStatusError: receiverStatusError,
      wiredVendorResponses: session.responses(),
      exactDevicesStillPresent: exactDevicesStillPresent,
      factoryModeCommandsSent: 0,
      pairingCommandsSent: 0,
      firmwareCommandsSent: 0
    )
  }

  static func payload(prefix: [UInt8]) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: ASUSKeyboardResearchInventory.reportSize)
    payload.replaceSubrange(0..<prefix.count, with: prefix)
    return payload
  }

  private static func controlDevices()
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

final class ASUSVendorSession: @unchecked Sendable {
  private let device: IOHIDDevice
  private let target: String
  private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
  private let queue = DispatchQueue(label: "dev.deskmux.asus-rf-experiment")
  private let cancellationFinished = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var receivedReports: [[UInt8]] = []
  private var isClosed = false

  init(device: IOHIDDevice, target: String) throws {
    self.device = device
    self.target = target
    reportBuffer.initialize(repeating: 0, count: 64)
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      reportBuffer.deinitialize(count: 64)
      reportBuffer.deallocate()
      throw ASUSRFModeExperimentError.openFailed(result)
    }
    IOHIDDeviceRegisterInputReportCallback(
      device,
      reportBuffer,
      64,
      { contextPointer, result, _, _, _, report, reportLength in
        guard result == kIOReturnSuccess, reportLength > 0, let contextPointer else { return }
        Unmanaged<ASUSVendorSession>.fromOpaque(contextPointer).takeUnretainedValue()
          .receive(Array(UnsafeBufferPointer(start: report, count: reportLength)))
      },
      Unmanaged.passUnretained(self).toOpaque()
    )
    IOHIDDeviceSetDispatchQueue(device, queue)
    IOHIDDeviceSetCancelHandler(device) { [cancellationFinished] in
      cancellationFinished.signal()
    }
    IOHIDDeviceActivate(device)
  }

  deinit { close() }

  func receive(_ report: [UInt8]) {
    lock.withLock { receivedReports.append(report) }
  }

  func send(operation: String, prefix: [UInt8]) -> ASUSRFModeSendResult {
    let request = ASUSRFModeExperiment.payload(prefix: prefix)
    let result = request.withUnsafeBytes { bytes in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        0,
        bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
        request.count
      )
    }
    return ASUSRFModeSendResult(
      target: target,
      operation: operation,
      payloadPrefix: ASUSHIDInspector.hexadecimalBytes(prefix),
      ioReturn: result
    )
  }

  func responses() -> [String] {
    lock.withLock { receivedReports.map(ASUSHIDInspector.hexadecimalBytes) }
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    IOHIDDeviceCancel(device)
    _ = cancellationFinished.wait(timeout: .now() + 1)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    reportBuffer.deinitialize(count: 64)
    reportBuffer.deallocate()
  }
}
