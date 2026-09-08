import CoreGraphics
import Foundation

public enum MacPointerEdge: String, Codable, CaseIterable, Sendable {
  case left
  case right
}

public enum MacPointerEdgeTriggerMode: String, Codable, CaseIterable, Sendable {
  case holdModifier
  case pushAndDwell
}

public enum MacPointerEdgeModifier: String, Codable, CaseIterable, Sendable {
  case option
  case command
  case control
  case shift

  public var displayName: String {
    switch self {
    case .option: "Option (Alt) ⌥"
    case .command: "Command ⌘"
    case .control: "Control ⌃"
    case .shift: "Shift ⇧"
    }
  }

  fileprivate var eventFlag: CGEventFlags {
    switch self {
    case .option: .maskAlternate
    case .command: .maskCommand
    case .control: .maskControl
    case .shift: .maskShift
    }
  }
}

public struct MacPointerEdgeConfiguration: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var edge: MacPointerEdge
  public var dwellMilliseconds: Int
  public var triggerMode: MacPointerEdgeTriggerMode
  public var modifier: MacPointerEdgeModifier

  public init(
    enabled: Bool,
    edge: MacPointerEdge,
    dwellMilliseconds: Int,
    triggerMode: MacPointerEdgeTriggerMode = .pushAndDwell,
    modifier: MacPointerEdgeModifier = .option
  ) {
    self.enabled = enabled
    self.edge = edge
    self.dwellMilliseconds = min(max(dwellMilliseconds, 100), 1_000)
    self.triggerMode = triggerMode
    self.modifier = modifier
  }

  private enum CodingKeys: String, CodingKey {
    case enabled
    case edge
    case dwellMilliseconds
    case triggerMode
    case modifier
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      enabled: try container.decode(Bool.self, forKey: .enabled),
      edge: try container.decode(MacPointerEdge.self, forKey: .edge),
      dwellMilliseconds: try container.decode(Int.self, forKey: .dwellMilliseconds),
      triggerMode: try container.decodeIfPresent(
        MacPointerEdgeTriggerMode.self,
        forKey: .triggerMode
      ) ?? .pushAndDwell,
      modifier: try container.decodeIfPresent(
        MacPointerEdgeModifier.self,
        forKey: .modifier
      ) ?? .option
    )
  }
}

public enum MacPointerEdgeMonitorError: Error, CustomStringConvertible {
  case listenPermissionMissing
  case displayBoundsUnavailable
  case tapCreationFailed
  case runLoopSourceCreationFailed

  public var description: String {
    switch self {
    case .listenPermissionMissing:
      return "Input Monitoring permission is required for edge switching."
    case .displayBoundsUnavailable:
      return "DeskMux could not determine the active desktop bounds."
    case .tapCreationFailed:
      return "macOS refused to create the pointer edge monitor."
    case .runLoopSourceCreationFailed:
      return "DeskMux could not attach the pointer edge monitor to its run loop."
    }
  }
}

public final class MacPointerEdgeMonitor: @unchecked Sendable {
  public typealias TriggerHandler = @Sendable () -> Void

  private let context: PointerEdgeMonitorContext

  public init(
    configuration: MacPointerEdgeConfiguration,
    triggerHandler: @escaping TriggerHandler
  ) {
    context = PointerEdgeMonitorContext(
      detector: PointerEdgeDetector(configuration: configuration),
      triggerHandler: triggerHandler
    )
  }

  public func run() throws {
    guard context.configuration.enabled else { return }
    guard MacInputPermissions.status().canListen else {
      throw MacPointerEdgeMonitorError.listenPermissionMissing
    }
    guard let geometry = Self.activeDesktopGeometry() else {
      throw MacPointerEdgeMonitorError.displayBoundsUnavailable
    }
    context.setDesktopGeometry(geometry)
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()

    let modifierObserver = DistributedNotificationCenter.default().addObserver(
      forName: MacInputModifierBridge.notificationName,
      object: nil,
      queue: nil
    ) { [context] notification in
      guard let flags = MacInputModifierBridge.flags(from: notification) else { return }
      context.setBridgedModifierFlags(flags)
    }
    defer {
      DistributedNotificationCenter.default().removeObserver(modifierObserver)
      context.setBridgedModifierFlags([])
    }

    let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
      guard let userInfo else { return }
      let context = Unmanaged<PointerEdgeMonitorContext>.fromOpaque(userInfo)
        .takeUnretainedValue()
      if flags.contains(.beginConfigurationFlag) {
        // Ignore pointer motion while macOS is between the old and new layout.
        context.setDesktopGeometry(nil)
      } else {
        context.refreshDesktopGeometry()
      }
    }
    let watchesDisplayChanges =
      CGDisplayRegisterReconfigurationCallback(displayCallback, contextPointer) == .success

    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let context = Unmanaged<PointerEdgeMonitorContext>.fromOpaque(userInfo)
        .takeUnretainedValue()
      return context.handle(type: type, event: event)
    }
    let events = [
      CGEventType.mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
      .flagsChanged,
    ].reduce(CGEventMask(0)) { mask, type in
      mask | (CGEventMask(1) << CGEventMask(type.rawValue))
    }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: events,
        callback: callback,
        userInfo: contextPointer
      )
    else { throw MacPointerEdgeMonitorError.tapCreationFailed }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      throw MacPointerEdgeMonitorError.runLoopSourceCreationFailed
    }
    context.setTap(tap)
    let runLoop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(runLoop, source, .commonModes)
    let dwellTimer = CFRunLoopTimerCreateWithHandler(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.02, 0.02, 0, 0
    ) { [context] _ in context.advanceDwell() }
    CFRunLoopAddTimer(runLoop, dwellTimer, .commonModes)
    defer {
      if watchesDisplayChanges {
        CGDisplayRemoveReconfigurationCallback(displayCallback, contextPointer)
      }
      CFRunLoopTimerInvalidate(dwellTimer)
      CFRunLoopRemoveTimer(runLoop, dwellTimer, .commonModes)
    }
    CGEvent.tapEnable(tap: tap, enable: true)
    while !context.shouldStop {
      CFRunLoopRunInMode(.defaultMode, 0.1, false)
    }
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    context.setTap(nil)
  }

  public func stop() {
    context.stop()
  }

  fileprivate static func activeDesktopGeometry() -> PointerEdgeDesktopGeometry? {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
    let bounds = displays.prefix(Int(count))
      .filter { displayID in
        // A DeskMux stream creates a real Core Graphics display, but it must
        // not move the physical handoff edge away from the user's monitor.
        !(CGDisplayVendorNumber(displayID) == 0xD35C
          && CGDisplayModelNumber(displayID) == 0x4D58)
      }
      .map(CGDisplayBounds)
    return PointerEdgeDesktopGeometry(displayBounds: bounds)
  }
}

struct PointerEdgeBoundary: Equatable {
  let minimumY: Double
  let maximumY: Double
}

struct PointerEdgeDesktopGeometry: Equatable {
  let displayBounds: [CGRect]
  let minimumX: Double
  let maximumX: Double

  init?(displayBounds: [CGRect]) {
    guard let minimumX = displayBounds.map(\.minX).min(),
      let maximumX = displayBounds.map(\.maxX).max()
    else { return nil }
    self.displayBounds = displayBounds
    self.minimumX = minimumX
    self.maximumX = maximumX
  }

  func containsPhysicalPoint(_ point: CGPoint) -> Bool {
    displayBounds.contains { bounds in
      point.x >= bounds.minX && point.x < bounds.maxX
        && point.y >= bounds.minY && point.y < bounds.maxY
    }
  }

  func boundary(for edge: MacPointerEdge, y: Double) -> PointerEdgeBoundary? {
    let tolerance = 0.5
    return displayBounds.first { bounds in
      let ownsOuterEdge =
        switch edge {
        case .left: abs(bounds.minX - minimumX) <= tolerance
        case .right: abs(bounds.maxX - maximumX) <= tolerance
        }
      return ownsOuterEdge && y >= bounds.minY && y < bounds.maxY
    }.map { PointerEdgeBoundary(minimumY: $0.minY, maximumY: $0.maxY) }
  }
}

struct PointerEdgeDetector {
  let configuration: MacPointerEdgeConfiguration
  // A mouse can reconnect with the saved pointer position already touching the
  // return edge. Require an observed inward movement before accepting an
  // outward gesture so a newly arrived mouse cannot immediately bounce back.
  private(set) var armed = false
  private var gestureStartedAt: UInt64?
  private var outwardDistance: Int64 = 0

  private let edgeInset = 2.0
  private let rearmDistance = 24.0
  private let minimumOutwardDistance: Int64 = 8
  private let cornerExclusion = 80.0

  var hasPendingGesture: Bool { gestureStartedAt != nil }

  init(configuration: MacPointerEdgeConfiguration) {
    self.configuration = configuration
  }

  mutating func observe(
    x: Double,
    deltaX: Int64,
    minimumX: Double,
    maximumX: Double,
    y: Double = 500,
    edgeMinimumY: Double = 0,
    edgeMaximumY: Double = 1_000,
    modifierFlags: CGEventFlags = [],
    timestampNanoseconds: UInt64
  ) -> Bool {
    guard configuration.enabled else { return false }
    let atEdge: Bool
    let pushingOutward: Bool
    let sufficientlyAway: Bool
    switch configuration.edge {
    case .left:
      atEdge = x <= minimumX + edgeInset
      pushingOutward = deltaX < 0
      sufficientlyAway = x >= minimumX + rearmDistance
    case .right:
      atEdge = x >= maximumX - 1 - edgeInset
      pushingOutward = deltaX > 0
      sufficientlyAway = x <= maximumX - rearmDistance
    }

    if !atEdge {
      cancelPendingGesture()
      if sufficientlyAway { armed = true }
      return false
    }
    let availableHeight = max(edgeMaximumY - edgeMinimumY, 0)
    let reservedCornerHeight = min(cornerExclusion, availableHeight / 3)
    let isInCorner =
      y < edgeMinimumY + reservedCornerHeight
      || y >= edgeMaximumY - reservedCornerHeight
    guard !isInCorner else {
      cancelPendingGesture()
      return false
    }
    guard armed else { return false }

    if configuration.triggerMode == .holdModifier {
      cancelPendingGesture()
      guard modifierFlags.contains(configuration.modifier.eventFlag) else { return false }
      armed = false
      return true
    }

    // An outward push starts the dwell. Staying inside the edge zone keeps it
    // alive, including zero-delta samples and tiny tangential/inward jitter.
    // The timer can then finish it even if the mouse stops producing events.
    // Moving away from the edge still cancels immediately (above).
    if pushingOutward {
      if gestureStartedAt == nil { gestureStartedAt = timestampNanoseconds }
      outwardDistance += abs(deltaX)
    }
    guard let gestureStartedAt, timestampNanoseconds >= gestureStartedAt else { return false }
    let elapsed = timestampNanoseconds - gestureStartedAt
    let required = UInt64(configuration.dwellMilliseconds) * 1_000_000
    guard elapsed >= required, outwardDistance >= minimumOutwardDistance else { return false }
    armed = false
    self.gestureStartedAt = nil
    outwardDistance = 0
    return true
  }

  mutating func cancelPendingGesture() {
    gestureStartedAt = nil
    outwardDistance = 0
  }
}

struct PointerEdgeModifierLatch {
  private(set) var flags: CGEventFlags = []
  private var bridgedFlags: CGEventFlags = []

  private static let trackedFlags: CGEventFlags = [
    .maskAlternate,
    .maskCommand,
    .maskControl,
    .maskShift,
  ]

  mutating func observe(type: CGEventType, eventFlags: CGEventFlags) -> CGEventFlags {
    let relevantEventFlags = eventFlags.intersection(Self.trackedFlags)
    if type == .flagsChanged {
      // Injected keyboard modifiers and the native Logitech mouse are separate
      // event streams on the destination Mac. Keep the latest keyboard flag
      // snapshot until its matching key-up arrives, then apply it to mouse
      // movement for edge detection.
      flags = relevantEventFlags
    }
    return relevantEventFlags.union(flags).union(bridgedFlags)
  }

  mutating func setBridgedFlags(_ newFlags: CGEventFlags) {
    bridgedFlags = newFlags.intersection(Self.trackedFlags)
  }

  mutating func reset() {
    flags = []
    bridgedFlags = []
  }
}

private final class PointerEdgeMonitorContext: @unchecked Sendable {
  let configuration: MacPointerEdgeConfiguration
  private let triggerHandler: MacPointerEdgeMonitor.TriggerHandler
  private let lock = NSLock()
  private var detector: PointerEdgeDetector
  private var desktopGeometry: PointerEdgeDesktopGeometry?
  private var stopped = false
  private var tap: CFMachPort?
  private var modifierLatch = PointerEdgeModifierLatch()

  init(
    detector: PointerEdgeDetector,
    triggerHandler: @escaping MacPointerEdgeMonitor.TriggerHandler
  ) {
    configuration = detector.configuration
    self.detector = detector
    self.triggerHandler = triggerHandler
  }

  var shouldStop: Bool { lock.withLock { stopped } }

  func stop() {
    lock.withLock { stopped = true }
  }

  func setDesktopGeometry(_ geometry: PointerEdgeDesktopGeometry?) {
    lock.withLock {
      desktopGeometry = geometry
      // A gesture that began against an old monitor boundary must never finish
      // after the desktop has been rearranged.
      detector = PointerEdgeDetector(configuration: configuration)
    }
  }

  func refreshDesktopGeometry() {
    setDesktopGeometry(MacPointerEdgeMonitor.activeDesktopGeometry())
  }

  func setTap(_ tap: CFMachPort?) {
    lock.withLock { self.tap = tap }
  }

  func setBridgedModifierFlags(_ flags: CGEventFlags) {
    lock.withLock { modifierLatch.setBridgedFlags(flags) }
  }

  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      let currentTap = lock.withLock { () -> CFMachPort? in
        modifierLatch.reset()
        return tap
      }
      if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    let effectiveModifierFlags = lock.withLock {
      modifierLatch.observe(type: type, eventFlags: event.flags)
    }
    evaluate(
      point: event.location,
      deltaX: event.getIntegerValueField(.mouseEventDeltaX),
      modifierFlags: effectiveModifierFlags
    )
    return Unmanaged.passUnretained(event)
  }

  func advanceDwell() {
    guard lock.withLock({ !stopped && detector.hasPendingGesture }),
      let point = CGEvent(source: nil)?.location
    else { return }
    evaluate(point: point, deltaX: 0, modifierFlags: [])
  }

  private func evaluate(point: CGPoint, deltaX: Int64, modifierFlags: CGEventFlags) {
    let shouldTrigger = lock.withLock { () -> Bool in
      guard let desktopGeometry, !stopped,
        desktopGeometry.containsPhysicalPoint(point),
        let boundary = desktopGeometry.boundary(for: configuration.edge, y: point.y)
      else {
        detector.cancelPendingGesture()
        return false
      }
      return detector.observe(
        x: point.x,
        deltaX: deltaX,
        minimumX: desktopGeometry.minimumX,
        maximumX: desktopGeometry.maximumX,
        y: point.y,
        edgeMinimumY: boundary.minimumY,
        edgeMaximumY: boundary.maximumY,
        modifierFlags: modifierFlags,
        timestampNanoseconds: DispatchTime.now().uptimeNanoseconds
      )
    }
    if shouldTrigger { triggerHandler() }
  }
}
