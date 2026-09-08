@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public struct MacInputPermissionStatus: Codable, Equatable, Sendable {
  public let canListen: Bool
  public let canPost: Bool

  public init(canListen: Bool, canPost: Bool) {
    self.canListen = canListen
    self.canPost = canPost
  }
}

public enum MacInputPermissions {
  public static func status() -> MacInputPermissionStatus {
    let canPost = AXIsProcessTrusted()
    return MacInputPermissionStatus(
      // Accessibility also permits Core Graphics event taps. On recent macOS
      // versions CGPreflightListenEventAccess can remain false—and no Input
      // Monitoring row appears—even though the event tap is authorized.
      canListen: CGPreflightListenEventAccess() || canPost,
      canPost: canPost
    )
  }

  public static func request() -> MacInputPermissionStatus {
    _ = CGRequestListenEventAccess()
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    _ = CGRequestPostEventAccess()
    return status()
  }
}
