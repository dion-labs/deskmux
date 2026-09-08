import CoreGraphics
import Foundation

public enum MacLocalEscapeMonitorError: Error {
  case listenPermissionMissing
  case tapCreationFailed
  case runLoopSourceCreationFailed
}

/// Watches only for deliberate input produced on the destination Mac itself.
/// DeskMux-injected events carry a marker and are ignored. A local click or
/// key press can therefore serve as an out-of-band request to end a relay.
public final class MacLocalEscapeMonitor: @unchecked Sendable {
  public typealias EscapeHandler = @Sendable () -> Void

  private static let eventTypes: [CGEventType] = [
    .keyDown,
    .leftMouseDown,
    .rightMouseDown,
    .otherMouseDown,
  ]
  private static let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
    mask | (CGEventMask(1) << type.rawValue)
  }

  private let context: LocalEscapeContext

  public init(handler: @escaping EscapeHandler) {
    context = LocalEscapeContext(handler: handler)
  }

  public func run() throws {
    guard MacInputPermissions.status().canListen else {
      throw MacLocalEscapeMonitorError.listenPermissionMissing
    }
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let context = Unmanaged<LocalEscapeContext>.fromOpaque(userInfo).takeUnretainedValue()
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
      }
      guard !MacInputEventCodec.isInjectedByDeskMux(event) else {
        return Unmanaged.passUnretained(event)
      }
      context.trigger()
      return Unmanaged.passUnretained(event)
    }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: Self.eventMask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(context).toOpaque()
      )
    else { throw MacLocalEscapeMonitorError.tapCreationFailed }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      throw MacLocalEscapeMonitorError.runLoopSourceCreationFailed
    }

    let runLoop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    while !context.shouldStop {
      CFRunLoopRunInMode(.defaultMode, 0.1, false)
    }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
  }

  public func stop() {
    context.stop()
  }
}

private final class LocalEscapeContext: @unchecked Sendable {
  private let handler: MacLocalEscapeMonitor.EscapeHandler
  private let lock = NSLock()
  private var stopped = false

  init(handler: @escaping MacLocalEscapeMonitor.EscapeHandler) {
    self.handler = handler
  }

  var shouldStop: Bool { lock.withLock { stopped } }

  func trigger() {
    let shouldTrigger = lock.withLock { () -> Bool in
      guard !stopped else { return false }
      stopped = true
      return true
    }
    if shouldTrigger { handler() }
  }

  func stop() {
    lock.withLock { stopped = true }
  }
}
