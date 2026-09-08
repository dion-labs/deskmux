import Foundation
import IOKit

public struct ASUSKeyboardPathValueCount: Codable, Equatable, Sendable {
  public let role: ASUSKeyboardResearchInterface.Role
  public let productID: Int
  public let registryEntryID: UInt64
  public let maxInputReportSize: Int
  public let inputReportCountBefore: Int?
  public let inputReportCountAfter: Int?
  public let inputReportDelta: Int?
}

public struct ASUSKeyboardPathObservation: Codable, Equatable, Sendable {
  public let durationSeconds: Double
  public let paths: [ASUSKeyboardPathValueCount]
  public let outputReportsSent: Int
}

public enum ASUSKeyboardPathMonitorError: Error, CustomStringConvertible {
  case invalidDuration

  public var description: String {
    switch self {
    case .invalidDuration:
      return "ASUS keyboard path monitoring must run for between 0 and 30 seconds."
    }
  }
}

/// Passively samples macOS's kernel-level HID input-report counters for the
/// exact wired keyboard and receiver interfaces. No HID device is opened and
/// no report contents or key values are read.
public enum ASUSKeyboardPathMonitor {
  public static func monitor(durationSeconds: Double) throws -> ASUSKeyboardPathObservation {
    guard durationSeconds > 0, durationSeconds <= 30 else {
      throw ASUSKeyboardPathMonitorError.invalidDuration
    }

    let paths = standardKeyboardInterfaces()
    let before = Dictionary(uniqueKeysWithValues: paths.map { path in
      (path.descriptor.registryEntryID, inputReportCount(path.descriptor.registryEntryID))
    })
    Thread.sleep(forTimeInterval: durationSeconds)

    return ASUSKeyboardPathObservation(
      durationSeconds: durationSeconds,
      paths: paths.map { path in
        let registryID = path.descriptor.registryEntryID
        let start = before[registryID] ?? nil
        let end = inputReportCount(registryID)
        return ASUSKeyboardPathValueCount(
          role: path.role,
          productID: path.descriptor.productID,
          registryEntryID: registryID,
          maxInputReportSize: path.descriptor.maxInputReportSize,
          inputReportCountBefore: start,
          inputReportCountAfter: end,
          inputReportDelta: reportDelta(before: start, after: end)
        )
      },
      outputReportsSent: 0
    )
  }

  // A missing baseline is not zero; a decreasing counter may have reset.
  // Neither case supports a measured report delta.
  static func reportDelta(before: Int?, after: Int?) -> Int? {
    guard let before, let after, before >= 0, after >= before else { return nil }
    return after - before
  }

  static func inputReportCount(_ registryEntryID: UInt64) -> Int? {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IORegistryEntryIDMatching(registryEntryID)
    )
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard
      let value = IORegistryEntryCreateCFProperty(
        service,
        "DebugState" as CFString,
        kCFAllocatorDefault,
        IOOptionBits(0)
      )?.takeRetainedValue(),
      let debugState = value as? [String: Any],
      let count = debugState["InputReportCount"] as? NSNumber
    else { return nil }
    return count.intValue
  }

  private static func standardKeyboardInterfaces() -> [ASUSKeyboardResearchInterface] {
    ASUSKeyboardResearchInventory.discover().filter { item in
      item.descriptor.usagePage == 0x0001 && item.descriptor.usage == 0x0006
    }
  }
}
