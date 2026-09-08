import Foundation
import IOKit.hid

/// A sanitized description of a Logitech HID++ control interface.
public struct LogitechHIDDeviceDescriptor: Codable, Equatable, Sendable {
  public let registryEntryID: UInt64
  public let product: String
  public let transport: String
  public let vendorID: Int
  public let productID: Int
  public let usagePage: Int
  public let usage: Int
  public let maxInputReportSize: Int
  public let maxOutputReportSize: Int

  public var isDirectBluetoothControl: Bool {
    usagePage == 0xFF43 && usage == 0x0202
  }

  public var isReceiverControl: Bool {
    usagePage == 0xFF00 && (usage == 0x0001 || usage == 0x0002)
  }
}

/// The result of a read-only HID++ ChangeHost feature probe.
public struct LogitechChangeHostProbe: Codable, Equatable, Sendable {
  public let device: LogitechHIDDeviceDescriptor
  public let deviceIndex: Int?
  public let featureIndex: Int?
  public let hostCount: Int?
  public let currentHost: Int?
  public let roundTripMilliseconds: Double?
  public let error: String?

  public var isSupported: Bool { featureIndex != nil }
}

public struct LogitechHostSwitchResult: Codable, Equatable, Sendable {
  public let device: LogitechHIDDeviceDescriptor
  public let deviceIndex: Int
  public let featureIndex: Int
  public let previousHost: Int
  public let targetHost: Int
  public let commandAccepted: Bool
}

public enum LogitechHIDPlus {
  public static let vendorID = 0x046D
  public static let changeHostFeatureID = 0x1814
  private static let transactionLock = NSLock()

  /// Finds only the vendor-defined HID interfaces that can carry HID++ control reports.
  /// This does not open devices or transmit data.
  public static func discover() -> [LogitechHIDDeviceDescriptor] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      [kIOHIDVendorIDKey as String: vendorID] as CFDictionary
    )
    guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }
    return (devices as NSSet).compactMap { value in
      let device = value as! IOHIDDevice
      let descriptor = descriptor(for: device)
      guard descriptor.isDirectBluetoothControl || descriptor.isReceiverControl else {
        return nil
      }
      return descriptor
    }
    .sorted {
      ($0.product, $0.registryEntryID) < ($1.product, $1.registryEntryID)
    }
  }

  /// Resolves HID++ feature 0x1814 without changing the active host.
  public static func probeChangeHost(timeoutSeconds: TimeInterval = 0.25)
    -> [LogitechChangeHostProbe]
  {
    transactionLock.withLock {
      probeChangeHostUnlocked(timeoutSeconds: timeoutSeconds)
    }
  }

  private static func probeChangeHostUnlocked(timeoutSeconds: TimeInterval)
    -> [LogitechChangeHostProbe]
  {
    controlDevices().map { device, descriptor in
      do {
        let session = try LogitechHIDSession(device: device)
        defer { session.close() }
        let candidateIndexes =
          descriptor.isDirectBluetoothControl
          ? [0xFF, 0x00]
          : Array(1...6) + [0xFF, 0x00]

        for deviceIndex in candidateIndexes {
          let started = ContinuousClock.now
          if let response = try session.resolveFeature(
            changeHostFeatureID,
            deviceIndex: UInt8(deviceIndex),
            timeoutSeconds: timeoutSeconds
          ) {
            let elapsed = ContinuousClock.now - started
            let hostInfo = try session.getHostInfo(
              featureIndex: response.featureIndex,
              deviceIndex: UInt8(deviceIndex),
              timeoutSeconds: timeoutSeconds
            )
            return LogitechChangeHostProbe(
              device: descriptor,
              deviceIndex: deviceIndex,
              featureIndex: Int(response.featureIndex),
              hostCount: Int(hostInfo.hostCount),
              currentHost: Int(hostInfo.currentHost),
              roundTripMilliseconds: durationMilliseconds(elapsed),
              error: nil
            )
          }
        }
        return LogitechChangeHostProbe(
          device: descriptor,
          deviceIndex: nil,
          featureIndex: nil,
          hostCount: nil,
          currentHost: nil,
          roundTripMilliseconds: nil,
          error: "ChangeHost feature 0x1814 did not answer on any safe device index."
        )
      } catch {
        return LogitechChangeHostProbe(
          device: descriptor,
          deviceIndex: nil,
          featureIndex: nil,
          hostCount: nil,
          currentHost: nil,
          roundTripMilliseconds: nil,
          error: String(describing: error)
        )
      }
    }
  }

  /// Sends ChangeHost only when the caller's expected current host still matches.
  /// Host indexes are zero-based, matching the Logitech protocol.
  public static func switchHost(
    from expectedCurrentHost: Int,
    to targetHost: Int,
    timeoutSeconds: TimeInterval = 0.25
  ) throws -> LogitechHostSwitchResult {
    try transactionLock.withLock {
      guard expectedCurrentHost >= 0, targetHost >= 0 else {
        throw LogitechHIDError.invalidHostIndex
      }
      let supported = probeChangeHostUnlocked(timeoutSeconds: timeoutSeconds).filter(\.isSupported)
      guard supported.count == 1,
        let probe = supported.first,
        let deviceIndex = probe.deviceIndex,
        let featureIndex = probe.featureIndex,
        let hostCount = probe.hostCount,
        let currentHost = probe.currentHost
      else { throw LogitechHIDError.ambiguousDevice }
      guard currentHost == expectedCurrentHost else {
        throw LogitechHIDError.currentHostChanged(
          expected: expectedCurrentHost, actual: currentHost)
      }
      guard targetHost < hostCount, targetHost != currentHost else {
        throw LogitechHIDError.invalidTargetHost(target: targetHost, hostCount: hostCount)
      }
      guard
        let (device, _) = controlDevices().first(where: {
          $0.1.registryEntryID == probe.device.registryEntryID
        })
      else { throw LogitechHIDError.deviceDisappeared }
      let session = try LogitechHIDSession(device: device)
      defer { session.close() }
      try session.setCurrentHost(
        featureIndex: UInt8(featureIndex),
        deviceIndex: UInt8(deviceIndex),
        targetHost: UInt8(targetHost)
      )
      return LogitechHostSwitchResult(
        device: probe.device,
        deviceIndex: deviceIndex,
        featureIndex: featureIndex,
        previousHost: currentHost,
        targetHost: targetHost,
        commandAccepted: true
      )
    }
  }

  static func parseFeatureResponse(
    _ report: [UInt8],
    deviceIndex: UInt8,
    softwareID: UInt8 = 0x0D
  ) -> UInt8? {
    guard report.count >= 5,
      report[0] == 0x11,
      report[1] == deviceIndex,
      report[2] == 0x00,
      report[3] == softwareID,
      report[4] != 0x00
    else { return nil }
    return report[4]
  }

  static func selectControlUsage(
    primary: (page: Int, usage: Int),
    usagePairs: [(page: Int, usage: Int)]
  ) -> (page: Int, usage: Int) {
    let usages = [primary] + usagePairs
    if let direct = usages.first(where: { $0.page == 0xFF43 && $0.usage == 0x0202 }) {
      return direct
    }
    if primary.page == 0xFF00 && (primary.usage == 0x0001 || primary.usage == 0x0002) {
      return primary
    }
    return usages.first(where: {
      $0.page == 0xFF00 && ($0.usage == 0x0001 || $0.usage == 0x0002)
    }) ?? primary
  }

  private static func controlDevices() -> [(IOHIDDevice, LogitechHIDDeviceDescriptor)] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      [kIOHIDVendorIDKey as String: vendorID] as CFDictionary
    )
    guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }

    // IOHIDDevice references remain valid after the manager closes because the
    // copied device set retains them for the duration of this function's result.
    let results = (devices as NSSet).compactMap {
      value -> (IOHIDDevice, LogitechHIDDeviceDescriptor)? in
      let device = value as! IOHIDDevice
      let descriptor = descriptor(for: device)
      guard descriptor.isDirectBluetoothControl || descriptor.isReceiverControl else {
        return nil
      }
      return (device, descriptor)
    }
    return results
  }

  private static func descriptor(for device: IOHIDDevice) -> LogitechHIDDeviceDescriptor {
    var registryEntryID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryEntryID)
    let controlUsage = selectControlUsage(
      primary: (
        integerProperty(device, kIOHIDPrimaryUsagePageKey as CFString),
        integerProperty(device, kIOHIDPrimaryUsageKey as CFString)
      ),
      usagePairs: usagePairs(device)
    )
    return LogitechHIDDeviceDescriptor(
      registryEntryID: registryEntryID,
      product: stringProperty(device, kIOHIDProductKey as CFString) ?? "Unknown Logitech device",
      transport: stringProperty(device, kIOHIDTransportKey as CFString) ?? "Unknown",
      vendorID: integerProperty(device, kIOHIDVendorIDKey as CFString),
      productID: integerProperty(device, kIOHIDProductIDKey as CFString),
      usagePage: controlUsage.page,
      usage: controlUsage.usage,
      maxInputReportSize: integerProperty(device, kIOHIDMaxInputReportSizeKey as CFString),
      maxOutputReportSize: integerProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)
    )
  }

  private static func integerProperty(_ device: IOHIDDevice, _ key: CFString) -> Int {
    (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
  }

  private static func stringProperty(_ device: IOHIDDevice, _ key: CFString) -> String? {
    IOHIDDeviceGetProperty(device, key) as? String
  }

  private static func usagePairs(_ device: IOHIDDevice) -> [(page: Int, usage: Int)] {
    guard
      let values = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        as? [Any]
    else { return [] }
    return values.compactMap { value in
      guard let pair = value as? [String: Any],
        let page = pair[kIOHIDDeviceUsagePageKey as String] as? NSNumber,
        let usage = pair[kIOHIDDeviceUsageKey as String] as? NSNumber
      else { return nil }
      return (page.intValue, usage.intValue)
    }
  }

  private static func durationMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

private struct LogitechFeatureResponse {
  let featureIndex: UInt8
}

private struct LogitechHostInfo {
  let hostCount: UInt8
  let currentHost: UInt8
}

private final class LogitechHIDSession: @unchecked Sendable {
  private let device: IOHIDDevice
  private let reportBuffer: UnsafeMutablePointer<UInt8>
  private let reportBufferSize: Int
  private let inputQueue = DispatchQueue(label: "dev.deskmux.logitech-hid-input")
  private let inputAvailable = DispatchSemaphore(value: 0)
  private let cancellationFinished = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var receivedReports: [[UInt8]] = []
  private var isClosed = false

  init(device: IOHIDDevice) throws {
    self.device = device
    reportBufferSize = max(
      64,
      (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?
        .intValue ?? 0
    )
    reportBuffer = .allocate(capacity: reportBufferSize)
    reportBuffer.initialize(repeating: 0, count: reportBufferSize)

    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      reportBuffer.deinitialize(count: reportBufferSize)
      reportBuffer.deallocate()
      throw LogitechHIDError.openFailed(result)
    }
    IOHIDDeviceRegisterInputReportCallback(
      device,
      reportBuffer,
      reportBufferSize,
      logitechInputReportCallback,
      Unmanaged.passUnretained(self).toOpaque()
    )
    IOHIDDeviceSetDispatchQueue(device, inputQueue)
    IOHIDDeviceSetCancelHandler(device) { [cancellationFinished] in
      cancellationFinished.signal()
    }
    IOHIDDeviceActivate(device)
  }

  deinit { close() }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    IOHIDDeviceCancel(device)
    _ = cancellationFinished.wait(timeout: .now() + 1)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    reportBuffer.deinitialize(count: reportBufferSize)
    reportBuffer.deallocate()
  }

  func receive(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
    guard length > 0 else { return }
    let copy = Array(UnsafeBufferPointer(start: report, count: length))
    lock.withLock { receivedReports.append(copy) }
    inputAvailable.signal()
  }

  func resolveFeature(
    _ featureID: Int,
    deviceIndex: UInt8,
    timeoutSeconds: TimeInterval
  ) throws -> LogitechFeatureResponse? {
    let softwareID: UInt8 = 0x0D
    var request = [UInt8](repeating: 0, count: 20)
    request[0] = 0x11
    request[1] = deviceIndex
    request[2] = 0x00
    request[3] = softwareID
    request[4] = UInt8((featureID >> 8) & 0xFF)
    request[5] = UInt8(featureID & 0xFF)

    if let report = try sendAndWait(
      request,
      deviceIndex: deviceIndex,
      featureIndex: 0x00,
      functionAndSoftwareID: softwareID,
      timeoutSeconds: timeoutSeconds
    ),
      let featureIndex = LogitechHIDPlus.parseFeatureResponse(
        report, deviceIndex: deviceIndex, softwareID: softwareID
      )
    {
      return LogitechFeatureResponse(featureIndex: featureIndex)
    }
    return nil
  }

  func getHostInfo(
    featureIndex: UInt8,
    deviceIndex: UInt8,
    timeoutSeconds: TimeInterval
  ) throws -> LogitechHostInfo {
    let softwareID: UInt8 = 0x0D
    var request = [UInt8](repeating: 0, count: 20)
    request[0] = 0x11
    request[1] = deviceIndex
    request[2] = featureIndex
    request[3] = softwareID
    guard
      let response = try sendAndWait(
        request,
        deviceIndex: deviceIndex,
        featureIndex: featureIndex,
        functionAndSoftwareID: softwareID,
        timeoutSeconds: timeoutSeconds
      ), response.count >= 6
    else { throw LogitechHIDError.hostInfoUnavailable }
    return LogitechHostInfo(hostCount: response[4], currentHost: response[5])
  }

  func setCurrentHost(featureIndex: UInt8, deviceIndex: UInt8, targetHost: UInt8) throws {
    var request = [UInt8](repeating: 0, count: 20)
    request[0] = 0x11
    request[1] = deviceIndex
    request[2] = featureIndex
    request[3] = 0x1D
    request[4] = targetHost
    try send(request)
  }

  private func sendAndWait(
    _ request: [UInt8],
    deviceIndex: UInt8,
    featureIndex: UInt8,
    functionAndSoftwareID: UInt8,
    timeoutSeconds: TimeInterval
  ) throws -> [UInt8]? {
    lock.withLock { receivedReports.removeAll(keepingCapacity: true) }
    while inputAvailable.wait(timeout: .now()) == .success {}
    try send(request)

    let deadline = DispatchTime.now() + timeoutSeconds
    repeat {
      _ = inputAvailable.wait(timeout: deadline)
      let reports = lock.withLock { receivedReports }
      for report in reports {
        if report.count >= 4,
          report[0] == 0x11,
          report[1] == deviceIndex,
          report[2] == featureIndex,
          report[3] == functionAndSoftwareID
        {
          return report
        }
        if report.count >= 7,
          report[0] == 0x11,
          report[1] == deviceIndex,
          report[2] == 0xFF,
          report[3] == featureIndex,
          report[4] == functionAndSoftwareID
        {
          throw LogitechHIDError.protocolError(Int(report[5]))
        }
      }
    } while DispatchTime.now() < deadline
    return nil
  }

  private func send(_ request: [UInt8]) throws {
    let result = request.withUnsafeBytes { bytes in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        CFIndex(request[0]),
        bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
        request.count
      )
    }
    guard result == kIOReturnSuccess else { throw LogitechHIDError.writeFailed(result) }
  }
}

private let logitechInputReportCallback: IOHIDReportCallback = {
  context, result, _, _, _, report, reportLength in
  guard result == kIOReturnSuccess, let context else { return }
  Unmanaged<LogitechHIDSession>.fromOpaque(context).takeUnretainedValue()
    .receive(report, length: reportLength)
}

public enum LogitechHIDError: Error, CustomStringConvertible {
  case openFailed(IOReturn)
  case writeFailed(IOReturn)
  case protocolError(Int)
  case hostInfoUnavailable
  case invalidHostIndex
  case invalidTargetHost(target: Int, hostCount: Int)
  case ambiguousDevice
  case currentHostChanged(expected: Int, actual: Int)
  case deviceDisappeared

  public var description: String {
    switch self {
    case .openFailed(let result):
      return String(format: "Could not open Logitech HID++ interface (IOReturn 0x%08X).", result)
    case .writeFailed(let result):
      return String(format: "Could not write Logitech HID++ report (IOReturn 0x%08X).", result)
    case .protocolError(let code):
      return String(format: "The Logitech device returned HID++ error 0x%02X.", code)
    case .hostInfoUnavailable:
      return "ChangeHost exists, but the current Easy-Switch host could not be read."
    case .invalidHostIndex:
      return "Easy-Switch host indexes cannot be negative."
    case .invalidTargetHost(let target, let hostCount):
      return
        "Easy-Switch host \(target) is invalid for a \(hostCount)-host device or is already active."
    case .ambiguousDevice:
      return "Exactly one reachable Logitech ChangeHost device is required."
    case .currentHostChanged(let expected, let actual):
      return
        "The Logitech current host changed (expected \(expected), found \(actual)); no switch was sent."
    case .deviceDisappeared:
      return "The Logitech control interface disappeared before the switch could be sent."
    }
  }
}
