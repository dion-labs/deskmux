import CoreGraphics
import DeskMuxCore
import Foundation

public enum MacInputCaptureError: Error, CustomStringConvertible {
  case listenPermissionMissing
  case tapCreationFailed
  case runLoopSourceCreationFailed

  public var description: String {
    switch self {
    case .listenPermissionMissing:
      return "Input Monitoring permission is required on the source Mac"
    case .tapCreationFailed:
      return "macOS refused to create an active input event tap"
    case .runLoopSourceCreationFailed:
      return "could not attach the active input event tap to the run loop"
    }
  }
}

public final class MacInputCapture: @unchecked Sendable {
  public typealias PacketHandler = @Sendable (InputEventPacket) -> Bool
  public typealias EmergencyHandler = @Sendable () -> Void
  public typealias StartedHandler = @Sendable () -> Void

  private let scope: MacInputCaptureScope
  private let startedHandler: StartedHandler
  private let context: CaptureContext
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  public init(
    sessionID: UUID,
    scope: MacInputCaptureScope = .allInput,
    packetHandler: @escaping PacketHandler,
    emergencyHandler: @escaping EmergencyHandler,
    startedHandler: @escaping StartedHandler = {}
  ) {
    self.scope = scope
    self.startedHandler = startedHandler
    context = CaptureContext(
      sessionID: sessionID,
      scope: scope,
      packetHandler: packetHandler,
      emergencyHandler: emergencyHandler
    )
  }

  public func run() throws {
    guard MacInputPermissions.status().canListen else {
      throw MacInputCaptureError.listenPermissionMissing
    }
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let context = Unmanaged<CaptureContext>.fromOpaque(userInfo).takeUnretainedValue()
      return context.handle(type: type, event: event)
    }
    guard
      let tap = CGEvent.tapCreate(
        // Capture at the HID boundary so returning nil prevents the physical
        // event from also reaching applications on the source Mac.
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: scope.eventMask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(context).toOpaque()
      )
    else {
      throw MacInputCaptureError.tapCreationFailed
    }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      throw MacInputCaptureError.runLoopSourceCreationFailed
    }
    self.tap = tap
    self.source = source
    context.tap = tap

    let runLoop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    startedHandler()
    while !context.shouldStop {
      CFRunLoopRunInMode(.defaultMode, 0.1, false)
    }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    context.tap = nil
    self.tap = nil
    self.source = nil
  }

  public func stop() {
    context.stop()
  }
}

private final class CaptureContext: @unchecked Sendable {
  let sessionID: UUID
  let scope: MacInputCaptureScope
  let packetHandler: MacInputCapture.PacketHandler
  let emergencyHandler: MacInputCapture.EmergencyHandler
  // CFMachPort is a Core Foundation object, not an Objective-C weak-reference
  // participant. The capture context owns it for exactly as long as run() does.
  var tap: CFMachPort?

  private let lock = NSLock()
  private var sequence: UInt64 = 0
  private var stopped = false
  private var emergencyFired = false

  init(
    sessionID: UUID,
    scope: MacInputCaptureScope,
    packetHandler: @escaping MacInputCapture.PacketHandler,
    emergencyHandler: @escaping MacInputCapture.EmergencyHandler
  ) {
    self.sessionID = sessionID
    self.scope = scope
    self.packetHandler = packetHandler
    self.emergencyHandler = emergencyHandler
  }

  var shouldStop: Bool { lock.withLock { stopped } }

  func stop() {
    lock.withLock { stopped = true }
  }

  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    if MacInputEventCodec.isInjectedByDeskMux(event) {
      return Unmanaged.passUnretained(event)
    }
    guard scope.includes(type) else { return Unmanaged.passUnretained(event) }
    if isEmergencyChord(type: type, event: event) {
      let shouldFire = lock.withLock { () -> Bool in
        guard !emergencyFired else { return false }
        emergencyFired = true
        stopped = true
        return true
      }
      if shouldFire { emergencyHandler() }
      return Unmanaged.passUnretained(event)
    }

    let packet: InputEventPacket
    do {
      let currentSequence = lock.withLock { () -> UInt64 in
        defer { sequence += 1 }
        return sequence
      }
      packet = try MacInputEventCodec.encode(
        event,
        sessionID: sessionID,
        sequence: currentSequence
      )
    } catch {
      return Unmanaged.passUnretained(event)
    }
    return packetHandler(packet) ? nil : Unmanaged.passUnretained(event)
  }

  private func isEmergencyChord(type: CGEventType, event: CGEvent) -> Bool {
    guard type == .keyDown,
      event.getIntegerValueField(.keyboardEventKeycode) == 53
    else {
      return false
    }
    let required: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    return event.flags.intersection(required) == required
  }
}
