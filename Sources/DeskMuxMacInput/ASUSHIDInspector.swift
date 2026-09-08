import Foundation
import IOKit.hid

public struct ASUSHIDInterfaceDescriptor: Codable, Equatable, Sendable {
  public let registryEntryID: UInt64
  public let product: String
  public let transport: String
  public let vendorID: Int
  public let productID: Int
  public let usagePage: Int
  public let usage: Int
  public let versionNumber: Int
  public let maxInputReportSize: Int
  public let maxOutputReportSize: Int
}

public struct ASUSHIDInputReport: Codable, Equatable, Sendable {
  public let offsetMilliseconds: Double
  public let registryEntryID: UInt64
  public let reportID: UInt32
  public let bytes: String
}

public struct ASUSHIDDeviceTransition: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case attached
    case removed
  }

  public let offsetMilliseconds: Double
  public let registryEntryID: UInt64
  public let kind: Kind
}

public struct ASUSHIDInspection: Codable, Equatable, Sendable {
  public let durationSeconds: Double
  public let interfaces: [ASUSHIDInterfaceDescriptor]
  public let inputReports: [ASUSHIDInputReport]
  public let deviceTransitions: [ASUSHIDDeviceTransition]
  public let outputReportsSent: Int
}

public enum ASUSHIDInspectorError: Error, CustomStringConvertible {
  case invalidDuration
  case deviceOpenFailed(IOReturn)

  public var description: String {
    switch self {
    case .invalidDuration:
      return "ASUS HID inspection duration must be between 0 and 60 seconds."
    case .deviceOpenFailed(let result):
      return "Could not open the ASUS vendor HID interface read-only (IOKit \(result))."
    }
  }
}

/// Passively records input reports from the vendor-defined interface exposed by
/// the ASUS ROG Strix Scope RX TKL Wireless Deluxe. This type deliberately has
/// no API that can send output or feature reports.
public enum ASUSHIDInspector {
  public static let vendorID = 0x0B05
  public static let productID = 0x1A05
  public static let vendorUsagePage = 0xFF00
  public static let vendorUsage = 0x0001

  public static func inspect(durationSeconds: Double) throws -> ASUSHIDInspection {
    guard durationSeconds > 0, durationSeconds <= 60 else {
      throw ASUSHIDInspectorError.invalidDuration
    }

    let context = ASUSHIDInspectionContext()
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, matchingDictionary() as CFDictionary)
    IOHIDManagerRegisterDeviceMatchingCallback(
      manager,
      { contextPointer, _, _, device in
        guard let contextPointer else { return }
        let context = Unmanaged<ASUSHIDInspectionContext>.fromOpaque(contextPointer)
          .takeUnretainedValue()
        context.recordTransition(.attached, device: device)
      },
      Unmanaged.passUnretained(context).toOpaque()
    )
    IOHIDManagerRegisterDeviceRemovalCallback(
      manager,
      { contextPointer, _, _, device in
        guard let contextPointer else { return }
        let context = Unmanaged<ASUSHIDInspectionContext>.fromOpaque(contextPointer)
          .takeUnretainedValue()
        context.recordTransition(.removed, device: device)
      },
      Unmanaged.passUnretained(context).toOpaque()
    )
    IOHIDManagerRegisterInputReportCallback(
      manager,
      { contextPointer, result, sender, _, reportID, report, reportLength in
        guard result == kIOReturnSuccess, let contextPointer, let sender else {
          return
        }
        let context = Unmanaged<ASUSHIDInspectionContext>.fromOpaque(contextPointer)
          .takeUnretainedValue()
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        context.recordInput(
          device: device,
          reportID: reportID,
          bytes: Array(UnsafeBufferPointer(start: report, count: reportLength))
        )
      },
      Unmanaged.passUnretained(context).toOpaque()
    )

    let runLoop = CFRunLoopGetCurrent()!
    IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
      throw ASUSHIDInspectorError.deviceOpenFailed(openResult)
    }

    let deadline = Date().addingTimeInterval(durationSeconds)
    while Date() < deadline {
      CFRunLoopRunInMode(.defaultMode, min(0.1, deadline.timeIntervalSinceNow), false)
    }

    let interfaces = discoveredInterfaces(manager)
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
    return context.result(durationSeconds: durationSeconds, interfaces: interfaces)
  }

  static func hexadecimalBytes(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
  }

  private static func matchingDictionary() -> [String: Int] {
    [
      kIOHIDVendorIDKey as String: vendorID,
      kIOHIDProductIDKey as String: productID,
      kIOHIDPrimaryUsagePageKey as String: vendorUsagePage,
      kIOHIDPrimaryUsageKey as String: vendorUsage,
    ]
  }

  private static func discoveredInterfaces(_ manager: IOHIDManager)
    -> [ASUSHIDInterfaceDescriptor]
  {
    guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }
    return (devices as NSSet).map { descriptor(for: $0 as! IOHIDDevice) }
      .sorted { $0.registryEntryID < $1.registryEntryID }
  }

  static func registryEntryID(for device: IOHIDDevice) -> UInt64 {
    var registryEntryID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryEntryID)
    return registryEntryID
  }

  static func descriptor(for device: IOHIDDevice) -> ASUSHIDInterfaceDescriptor {
    ASUSHIDInterfaceDescriptor(
      registryEntryID: registryEntryID(for: device),
      product: stringProperty(device, kIOHIDProductKey as CFString) ?? "Unknown ASUS device",
      transport: stringProperty(device, kIOHIDTransportKey as CFString) ?? "Unknown",
      vendorID: integerProperty(device, kIOHIDVendorIDKey as CFString),
      productID: integerProperty(device, kIOHIDProductIDKey as CFString),
      usagePage: integerProperty(device, kIOHIDPrimaryUsagePageKey as CFString),
      usage: integerProperty(device, kIOHIDPrimaryUsageKey as CFString),
      versionNumber: integerProperty(device, kIOHIDVersionNumberKey as CFString),
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
}

private final class ASUSHIDInspectionContext: @unchecked Sendable {
  private let startedAt = DispatchTime.now().uptimeNanoseconds
  private let lock = NSLock()
  private var reports: [ASUSHIDInputReport] = []
  private var transitions: [ASUSHIDDeviceTransition] = []
  private var observedInterfaces: [UInt64: ASUSHIDInterfaceDescriptor] = [:]
  private var registryIDsByDevicePointer: [UInt: UInt64] = [:]

  func recordInput(device: IOHIDDevice, reportID: UInt32, bytes: [UInt8]) {
    let report = ASUSHIDInputReport(
      offsetMilliseconds: elapsedMilliseconds(),
      registryEntryID: ASUSHIDInspector.registryEntryID(for: device),
      reportID: reportID,
      bytes: ASUSHIDInspector.hexadecimalBytes(bytes)
    )
    lock.withLock { reports.append(report) }
  }

  func recordTransition(_ kind: ASUSHIDDeviceTransition.Kind, device: IOHIDDevice) {
    let devicePointer = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    let registryEntryID = lock.withLock { () -> UInt64 in
      switch kind {
      case .attached:
        let descriptor = ASUSHIDInspector.descriptor(for: device)
        observedInterfaces[descriptor.registryEntryID] = descriptor
        registryIDsByDevicePointer[devicePointer] = descriptor.registryEntryID
        return descriptor.registryEntryID
      case .removed:
        return registryIDsByDevicePointer.removeValue(forKey: devicePointer)
          ?? ASUSHIDInspector.registryEntryID(for: device)
      }
    }
    let transition = ASUSHIDDeviceTransition(
      offsetMilliseconds: elapsedMilliseconds(),
      registryEntryID: registryEntryID,
      kind: kind
    )
    lock.withLock { transitions.append(transition) }
  }

  func result(
    durationSeconds: Double,
    interfaces: [ASUSHIDInterfaceDescriptor]
  ) -> ASUSHIDInspection {
    lock.withLock {
      for interface in interfaces {
        observedInterfaces[interface.registryEntryID] = interface
      }
      return ASUSHIDInspection(
        durationSeconds: durationSeconds,
        interfaces: observedInterfaces.values.sorted {
          $0.registryEntryID < $1.registryEntryID
        },
        inputReports: reports,
        deviceTransitions: transitions,
        outputReportsSent: 0
      )
    }
  }

  private func elapsedMilliseconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
  }
}
