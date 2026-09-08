import CoreGraphics
import Foundation

/// Shares authenticated remote modifier state between the stable input agent
/// and the menu app's local edge detector without injecting that state into
/// destination applications.
public enum MacInputModifierBridge {
  public static let notificationName = Notification.Name(
    "dev.deskmux.input.remote-modifier-flags"
  )
  public static let flagsUserInfoKey = "flags"

  public static let supportedFlags: CGEventFlags = [
    .maskAlternate,
    .maskCommand,
    .maskControl,
    .maskShift,
  ]

  public static func publish(_ flags: CGEventFlags) {
    let relevantFlags = flags.intersection(supportedFlags)
    DistributedNotificationCenter.default().postNotificationName(
      notificationName,
      object: nil,
      userInfo: [flagsUserInfoKey: NSNumber(value: relevantFlags.rawValue)],
      deliverImmediately: true
    )
  }

  public static func flags(from notification: Notification) -> CGEventFlags? {
    guard let number = notification.userInfo?[flagsUserInfoKey] as? NSNumber else {
      return nil
    }
    return CGEventFlags(rawValue: number.uint64Value).intersection(supportedFlags)
  }
}
