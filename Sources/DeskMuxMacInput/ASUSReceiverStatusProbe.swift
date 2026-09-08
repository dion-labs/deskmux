import Foundation
import IOKit.hid

public struct ASUSReceiverStatus: Codable, Equatable, Sendable {
  public let device: ASUSHIDInterfaceDescriptor
  public let batteryPercentage: Int
  public let charging: Bool
  public let duplicateBatteryPercentage: Int
  public let responseBytes: String
  public let outputReportsSent: Int
}

public enum ASUSReceiverStatusProbeError: Error, CustomStringConvertible {
  case unavailable
  case ambiguous
  case openFailed(IOReturn)
  case writeFailed(IOReturn)
  case timedOut
  case invalidResponse

  public var description: String {
    switch self {
    case .unavailable:
      return "The exact ASUS 0x1A07 receiver control interface is not connected."
    case .ambiguous:
      return "Exactly one ASUS 0x1A07 receiver control interface is required."
    case .openFailed(let result):
      return String(format: "Could not open the ASUS receiver (IOReturn 0x%08X).", result)
    case .writeFailed(let result):
      return String(format: "Could not send the ASUS status query (IOReturn 0x%08X).", result)
    case .timedOut:
      return "The receiver did not answer the non-mutating status query."
    case .invalidResponse:
      return "The receiver returned a malformed status response."
    }
  }
}

public enum ASUSReceiverStatusProbe {
  static let command: [UInt8] = [0x12, 0x01]

  public static func probe(timeoutSeconds: TimeInterval = 1) throws -> ASUSReceiverStatus {
    let candidates = controlDevices()
    guard !candidates.isEmpty else { throw ASUSReceiverStatusProbeError.unavailable }
    guard candidates.count == 1 else { throw ASUSReceiverStatusProbeError.ambiguous }
    let (device, descriptor) = candidates[0]
    let session = try ASUSReceiverStatusSession(device: device)
    defer { session.close() }
    let response = try session.query(timeoutSeconds: timeoutSeconds)
    guard let parsed = parse(response) else { throw ASUSReceiverStatusProbeError.invalidResponse }
    return ASUSReceiverStatus(
      device: descriptor,
      batteryPercentage: parsed.battery,
      charging: parsed.charging,
      duplicateBatteryPercentage: parsed.duplicateBattery,
      responseBytes: ASUSHIDInspector.hexadecimalBytes(response),
      outputReportsSent: 1
    )
  }

  static func parse(_ response: [UInt8])
    -> (battery: Int, charging: Bool, duplicateBattery: Int)?
  {
    guard response.count >= 11,
      response[0] == command[0], response[1] == command[1],
      response[5] <= 100, response[8] <= 1, response[10] <= 100
    else { return nil }
    return (Int(response[5]), response[8] == 1, Int(response[10]))
  }

  private static func controlDevices() -> [(IOHIDDevice, ASUSHIDInterfaceDescriptor)] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      [
        kIOHIDVendorIDKey as String: ASUSKeyboardResearchInventory.vendorID,
        kIOHIDProductIDKey as String: ASUSKeyboardResearchInventory.receiverProductID,
        kIOHIDPrimaryUsagePageKey as String: ASUSKeyboardResearchInventory.vendorUsagePage,
        kIOHIDPrimaryUsageKey as String: ASUSKeyboardResearchInventory.vendorUsage,
      ] as CFDictionary
    )
    guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }
    return (devices as NSSet).compactMap { value in
      let device = value as! IOHIDDevice
      let descriptor = ASUSHIDInspector.descriptor(for: device)
      guard descriptor.maxInputReportSize == ASUSKeyboardResearchInventory.reportSize,
        descriptor.maxOutputReportSize == ASUSKeyboardResearchInventory.reportSize
      else { return nil }
      return (device, descriptor)
    }
  }
}

private final class ASUSReceiverStatusSession: @unchecked Sendable {
  private let device: IOHIDDevice
  private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
  private let queue = DispatchQueue(label: "dev.deskmux.asus-receiver-status")
  private let inputAvailable = DispatchSemaphore(value: 0)
  private let cancellationFinished = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var reports: [[UInt8]] = []
  private var isClosed = false

  init(device: IOHIDDevice) throws {
    self.device = device
    reportBuffer.initialize(repeating: 0, count: 64)
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      reportBuffer.deinitialize(count: 64)
      reportBuffer.deallocate()
      throw ASUSReceiverStatusProbeError.openFailed(result)
    }
    IOHIDDeviceRegisterInputReportCallback(
      device,
      reportBuffer,
      64,
      { contextPointer, result, _, _, _, report, reportLength in
        guard result == kIOReturnSuccess, reportLength > 0, let contextPointer else { return }
        let session = Unmanaged<ASUSReceiverStatusSession>.fromOpaque(contextPointer)
          .takeUnretainedValue()
        session.receive(Array(UnsafeBufferPointer(start: report, count: reportLength)))
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
    lock.withLock { reports.append(report) }
    inputAvailable.signal()
  }

  func query(timeoutSeconds: TimeInterval) throws -> [UInt8] {
    lock.withLock { reports.removeAll(keepingCapacity: true) }
    while inputAvailable.wait(timeout: .now()) == .success {}
    var request = [UInt8](repeating: 0, count: 64)
    request[0] = ASUSReceiverStatusProbe.command[0]
    request[1] = ASUSReceiverStatusProbe.command[1]
    let result = request.withUnsafeBytes { bytes in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        0,
        bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
        request.count
      )
    }
    guard result == kIOReturnSuccess else { throw ASUSReceiverStatusProbeError.writeFailed(result) }

    let deadline = DispatchTime.now() + timeoutSeconds
    repeat {
      _ = inputAvailable.wait(timeout: deadline)
      if let response = lock.withLock({ reports.first(where: { report in
        report.count >= 2 && report[0] == 0x12 && report[1] == 0x01
      }) }) {
        return response
      }
    } while DispatchTime.now() < deadline
    throw ASUSReceiverStatusProbeError.timedOut
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
