import Foundation
import IOKit.hid

public struct ASUSKeyboardResearchInterface: Codable, Equatable, Sendable {
  public enum Role: String, Codable, Sendable {
    case wiredKeyboard
    case rfReceiver
  }

  public let role: Role
  public let descriptor: ASUSHIDInterfaceDescriptor

  public var isCandidateControlInterface: Bool {
    descriptor.usagePage == ASUSKeyboardResearchInventory.vendorUsagePage
      && descriptor.usage == ASUSKeyboardResearchInventory.vendorUsage
      && descriptor.maxInputReportSize == ASUSKeyboardResearchInventory.reportSize
      && descriptor.maxOutputReportSize == ASUSKeyboardResearchInventory.reportSize
  }
}

/// Read-only inventory for the exact wired keyboard and 2.4 GHz receiver pair
/// used by the ASUS RF-mode research. This type does not open either device.
public enum ASUSKeyboardResearchInventory {
  public static let vendorID = 0x0B05
  public static let wiredProductID = 0x1A05
  public static let receiverProductID = 0x1A07
  public static let vendorUsagePage = 0xFF00
  public static let vendorUsage = 0x0001
  public static let reportSize = 64

  public static func discover() -> [ASUSKeyboardResearchInterface] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      [kIOHIDVendorIDKey as String: vendorID] as CFDictionary
    )
    guard let devices = IOHIDManagerCopyDevices(manager) else { return [] }
    return (devices as NSSet).compactMap { value in
      let descriptor = ASUSHIDInspector.descriptor(for: value as! IOHIDDevice)
      guard let role = role(productID: descriptor.productID) else { return nil }
      return ASUSKeyboardResearchInterface(role: role, descriptor: descriptor)
    }
    .sorted {
      ($0.role.rawValue, $0.descriptor.usagePage, $0.descriptor.usage,
        $0.descriptor.registryEntryID)
        < ($1.role.rawValue, $1.descriptor.usagePage, $1.descriptor.usage,
          $1.descriptor.registryEntryID)
    }
  }

  static func role(productID: Int) -> ASUSKeyboardResearchInterface.Role? {
    switch productID {
    case wiredProductID: .wiredKeyboard
    case receiverProductID: .rfReceiver
    default: nil
    }
  }
}
