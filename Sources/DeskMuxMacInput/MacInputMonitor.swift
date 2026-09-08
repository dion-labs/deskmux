import CoreGraphics
import DeskMuxCore
import Foundation

public struct MacInputMonitorReport: Codable, Equatable, Sendable {
  public let durationSeconds: Double
  public let eventCounts: [InputEventKind: Int]
  public let tapDisableNotifications: Int

  public init(
    durationSeconds: Double,
    eventCounts: [InputEventKind: Int],
    tapDisableNotifications: Int
  ) {
    self.durationSeconds = durationSeconds
    self.eventCounts = eventCounts
    self.tapDisableNotifications = tapDisableNotifications
  }
}

public enum MacInputMonitorError: Error, CustomStringConvertible {
  case listenPermissionMissing
  case tapCreationFailed
  case runLoopSourceCreationFailed

  public var description: String {
    switch self {
    case .listenPermissionMissing:
      return "Input Monitoring permission is required"
    case .tapCreationFailed:
      return "macOS refused to create an input event tap"
    case .runLoopSourceCreationFailed:
      return "could not attach the input event tap to the run loop"
    }
  }
}

public enum MacInputMonitor {
  public static func run(durationSeconds: Double) throws -> MacInputMonitorReport {
    guard durationSeconds > 0 else {
      return MacInputMonitorReport(
        durationSeconds: durationSeconds,
        eventCounts: [:],
        tapDisableNotifications: 0
      )
    }
    guard MacInputPermissions.status().canListen else {
      throw MacInputMonitorError.listenPermissionMissing
    }

    let context = MonitorContext()
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let context = Unmanaged<MonitorContext>.fromOpaque(userInfo).takeUnretainedValue()
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        context.recordTapDisable()
        return Unmanaged.passUnretained(event)
      }
      if let kind = try? MacInputEventCodec.kind(for: type) {
        context.record(kind)
      }
      return Unmanaged.passUnretained(event)
    }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: MacInputEventMask.relay,
        callback: callback,
        userInfo: Unmanaged.passUnretained(context).toOpaque()
      )
    else {
      throw MacInputMonitorError.tapCreationFailed
    }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      throw MacInputMonitorError.runLoopSourceCreationFailed
    }

    let runLoop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    CFRunLoopRunInMode(.defaultMode, durationSeconds, false)
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)

    return context.report(durationSeconds: durationSeconds)
  }
}

private final class MonitorContext {
  private let lock = NSLock()
  private var counts: [InputEventKind: Int] = [:]
  private var tapDisableNotifications = 0

  func record(_ kind: InputEventKind) {
    lock.withLock { counts[kind, default: 0] += 1 }
  }

  func recordTapDisable() {
    lock.withLock { tapDisableNotifications += 1 }
  }

  func report(durationSeconds: Double) -> MacInputMonitorReport {
    lock.withLock {
      MacInputMonitorReport(
        durationSeconds: durationSeconds,
        eventCounts: counts,
        tapDisableNotifications: tapDisableNotifications
      )
    }
  }
}
