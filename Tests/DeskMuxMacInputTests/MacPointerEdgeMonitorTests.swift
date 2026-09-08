import CoreGraphics
import Foundation
import Testing

@testable import DeskMuxMacInput

@Suite("Pointer edge switching")
struct MacPointerEdgeMonitorTests {
  @Test("requires an outward push and dwell")
  func requiresPushAndDwell() {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true, edge: .right, dwellMilliseconds: 200))
    let armed = detector.observe(
      x: 1_800, deltaX: -20, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 900_000_000)
    let initial = detector.observe(
      x: 1_919, deltaX: 5, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_000_000_000)
    let early = detector.observe(
      x: 1_919, deltaX: 4, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_100_000_000)
    let completed = detector.observe(
      x: 1_919, deltaX: 4, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_210_000_000)
    #expect(!armed)
    #expect(detector.armed == false)
    #expect(!initial)
    #expect(!early)
    #expect(completed)
  }

  @Test("does not bounce back until the pointer moves inward")
  func requiresRearm() {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true, edge: .left, dwellMilliseconds: 100))
    let armed = detector.observe(
      x: 40, deltaX: 40, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 900_000_000)
    let initial = detector.observe(
      x: 0, deltaX: -5, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_000_000_000)
    let completed = detector.observe(
      x: 0, deltaX: -5, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_110_000_000)
    let bounced = detector.observe(
      x: 0, deltaX: -20, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 2_000_000_000)
    let movedInward = detector.observe(
      x: 40, deltaX: 40, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 2_100_000_000)
    #expect(!armed)
    #expect(!initial)
    #expect(completed)
    #expect(!bounced)
    #expect(!movedInward)
    #expect(detector.armed)
  }

  @Test("a mouse arriving at the edge cannot immediately switch back")
  func arrivalAtEdgeRequiresInwardMovement() {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true, edge: .right, dwellMilliseconds: 100))

    let arrival = detector.observe(
      x: 1_919, deltaX: 10, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_000_000_000)
    let continuedPush = detector.observe(
      x: 1_919, deltaX: 10, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_200_000_000)
    let movedInward = detector.observe(
      x: 1_800, deltaX: -119, minimumX: 0, maximumX: 1_920,
      timestampNanoseconds: 1_300_000_000)

    #expect(!arrival)
    #expect(!continuedPush)
    #expect(!movedInward)
    #expect(detector.armed)
  }

  @Test(
    "a push finishes on a timer tick without more mouse movement",
    arguments: MacPointerEdge.allCases)
  func stationaryDwell(edge: MacPointerEdge) {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true, edge: edge, dwellMilliseconds: 200))
    let x = edge == .left ? 0.0 : 1_919.0
    let delta: Int64 = edge == .left ? -12 : 12
    #expect(!observe(&detector, x: 960, deltaX: 1, milliseconds: 0))
    #expect(!observe(&detector, x: x, deltaX: delta, milliseconds: 1_000))
    #expect(detector.hasPendingGesture)
    #expect(!observe(&detector, x: x, deltaX: 0, milliseconds: 1_199))
    #expect(observe(&detector, x: x, deltaX: 0, milliseconds: 1_200))
    #expect(!detector.hasPendingGesture)
    #expect(!observe(&detector, x: x, deltaX: delta, milliseconds: 2_000))
  }

  @Test("zero horizontal motion and one-pixel jitter do not reset dwell")
  func toleratesJitter() {
    var detector = rightEdgeDetector()
    arm(&detector)
    #expect(!observe(&detector, x: 1_919, deltaX: 10, milliseconds: 1_000))
    #expect(!observe(&detector, x: 1_919, deltaX: 0, milliseconds: 1_100))
    #expect(!observe(&detector, x: 1_918, deltaX: -1, milliseconds: 1_150))
    #expect(observe(&detector, x: 1_918, deltaX: 0, milliseconds: 1_200))
  }

  @Test("moving out of the edge zone cancels the pending gesture")
  func retreatCancelsDwell() {
    var detector = rightEdgeDetector()
    arm(&detector)
    #expect(!observe(&detector, x: 1_919, deltaX: 10, milliseconds: 1_000))
    #expect(!observe(&detector, x: 1_915, deltaX: -4, milliseconds: 1_150))
    #expect(!detector.hasPendingGesture)
    #expect(!observe(&detector, x: 1_919, deltaX: 10, milliseconds: 1_200))
    #expect(!observe(&detector, x: 1_919, deltaX: 0, milliseconds: 1_399))
    #expect(observe(&detector, x: 1_919, deltaX: 0, milliseconds: 1_400))
  }

  @Test("parking at the edge without an outward push never starts dwell")
  func parkedPointerDoesNotTrigger() {
    var detector = rightEdgeDetector()
    arm(&detector)
    #expect(!observe(&detector, x: 1_919, deltaX: 0, milliseconds: 1_000))
    #expect(!observe(&detector, x: 1_919, deltaX: 0, milliseconds: 3_000))
    #expect(!detector.hasPendingGesture)
  }

  @Test("holding the configured modifier triggers immediately at the edge")
  func modifierTriggersImmediately() {
    var detector = modifierEdgeDetector()
    arm(&detector)

    #expect(
      !observe(
        &detector,
        x: 1_919,
        deltaX: 1,
        milliseconds: 1_000
      )
    )
    #expect(
      observe(
        &detector,
        x: 1_919,
        deltaX: 0,
        modifierFlags: .maskAlternate,
        milliseconds: 1_001
      )
    )
    #expect(!detector.hasPendingGesture)
  }

  @Test("an unmodified edge never triggers in modifier mode")
  func modifierIsRequired() {
    var detector = modifierEdgeDetector()
    arm(&detector)

    #expect(!observe(&detector, x: 1_919, deltaX: 100, milliseconds: 1_000))
    #expect(!observe(&detector, x: 1_919, deltaX: 100, milliseconds: 10_000))
    #expect(detector.armed)
  }

  @Test("modifier mode honors the configured logical key")
  func configuredModifierIsRequired() {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true,
        edge: .right,
        dwellMilliseconds: 200,
        triggerMode: .holdModifier,
        modifier: .command
      )
    )
    arm(&detector)

    #expect(
      !observe(
        &detector,
        x: 1_919,
        deltaX: 1,
        modifierFlags: .maskAlternate,
        milliseconds: 1_000
      )
    )
    #expect(
      observe(
        &detector,
        x: 1_919,
        deltaX: 0,
        modifierFlags: .maskCommand,
        milliseconds: 1_001
      )
    )
  }

  @Test("an injected keyboard modifier remains active for native mouse movement")
  func modifierLatchBridgesKeyboardAndMouseStreams() {
    var latch = PointerEdgeModifierLatch()

    let keyDown = latch.observe(type: .flagsChanged, eventFlags: .maskAlternate)
    let nativeMouse = latch.observe(type: .mouseMoved, eventFlags: [])
    let keyUp = latch.observe(type: .flagsChanged, eventFlags: [])
    let mouseAfterRelease = latch.observe(type: .mouseMoved, eventFlags: [])

    #expect(keyDown.contains(.maskAlternate))
    #expect(nativeMouse.contains(.maskAlternate))
    #expect(!keyUp.contains(.maskAlternate))
    #expect(!mouseAfterRelease.contains(.maskAlternate))
  }

  @Test("a native mouse event can still carry a local physical modifier")
  func modifierLatchAcceptsEventLocalFlags() {
    var latch = PointerEdgeModifierLatch()

    let nativeMouse = latch.observe(type: .mouseMoved, eventFlags: .maskCommand)

    #expect(nativeMouse.contains(.maskCommand))
    #expect(latch.flags.isEmpty)
  }

  @Test("session startup bridges a modifier held before keyboard capture")
  func sessionModifierBridgesToNativeMouse() {
    var latch = PointerEdgeModifierLatch()
    latch.setBridgedFlags(.maskAlternate)

    let whileHeld = latch.observe(type: .mouseMoved, eventFlags: [])
    latch.setBridgedFlags([])
    let afterRelease = latch.observe(type: .mouseMoved, eventFlags: [])

    #expect(whileHeld.contains(.maskAlternate))
    #expect(!afterRelease.contains(.maskAlternate))
  }

  @Test("modifier bridge accepts only supported flag data")
  func modifierBridgeDecodesNotification() throws {
    let notification = Notification(
      name: MacInputModifierBridge.notificationName,
      userInfo: [
        MacInputModifierBridge.flagsUserInfoKey: NSNumber(
          value: CGEventFlags.maskAlternate.union(.maskSecondaryFn).rawValue
        )
      ]
    )
    let flags = try #require(MacInputModifierBridge.flags(from: notification))

    #expect(flags.contains(.maskAlternate))
    #expect(!flags.contains(.maskSecondaryFn))
  }

  @Test("older saved edge configurations retain push and dwell behavior")
  func decodesLegacyConfiguration() throws {
    let data = try #require(
      #"{"enabled":true,"edge":"left","dwellMilliseconds":300}"#.data(using: .utf8)
    )
    let configuration = try JSONDecoder().decode(MacPointerEdgeConfiguration.self, from: data)

    #expect(configuration.triggerMode == .pushAndDwell)
    #expect(configuration.modifier == .option)
    #expect(configuration.dwellMilliseconds == 300)
  }

  @Test("a timer cannot bypass minimum outward pressure")
  func insufficientPushDoesNotTrigger() {
    var detector = rightEdgeDetector()
    arm(&detector)
    #expect(!observe(&detector, x: 1_919, deltaX: 3, milliseconds: 1_000))
    #expect(!observe(&detector, x: 1_919, deltaX: 0, milliseconds: 3_000))
    #expect(!observe(&detector, x: 1_919, deltaX: 4, milliseconds: 3_010))
    #expect(observe(&detector, x: 1_919, deltaX: 1, milliseconds: 3_020))
  }

  @Test("disabled edge detection never arms or triggers")
  func disabledDetector() {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: false, edge: .right, dwellMilliseconds: 200))
    arm(&detector)
    #expect(!observe(&detector, x: 1_919, deltaX: 20, milliseconds: 1_000))
    #expect(!observe(&detector, x: 1_919, deltaX: 20, milliseconds: 2_000))
    #expect(!detector.armed)
    #expect(!detector.hasPendingGesture)
  }

  @Test("edge thresholds work on displays left of the primary display")
  func negativeDisplayOrigin() {
    var detector = PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true, edge: .left, dwellMilliseconds: 200))
    let armed = detector.observe(
      x: -1_800, deltaX: 1, minimumX: -1_920, maximumX: 1_920,
      timestampNanoseconds: 0)
    let pushed = detector.observe(
      x: -1_920, deltaX: -10, minimumX: -1_920, maximumX: 1_920,
      timestampNanoseconds: 1_000_000_000)
    let completed = detector.observe(
      x: -1_920, deltaX: 0, minimumX: -1_920, maximumX: 1_920,
      timestampNanoseconds: 1_200_000_000)
    #expect(!armed)
    #expect(!pushed)
    #expect(completed)
  }

  @Test("top and bottom corners are reserved for macOS window tiling", arguments: [20.0, 1_180.0])
  func cornersDoNotTrigger(y: Double) {
    var detector = rightEdgeDetector()
    arm(&detector)
    let started = detector.observe(
      x: 1_919, deltaX: 10, minimumX: 0, maximumX: 1_920,
      y: y, edgeMinimumY: 0, edgeMaximumY: 1_200,
      timestampNanoseconds: 1_000_000_000)
    let waited = detector.observe(
      x: 1_919, deltaX: 10, minimumX: 0, maximumX: 1_920,
      y: y, edgeMinimumY: 0, edgeMaximumY: 1_200,
      timestampNanoseconds: 1_500_000_000)
    #expect(!started)
    #expect(!waited)
    #expect(!detector.hasPendingGesture)
  }

  @Test("the middle of the edge remains available")
  func middleEdgeTriggers() {
    var detector = rightEdgeDetector()
    arm(&detector)
    let started = detector.observe(
      x: 1_919, deltaX: 10, minimumX: 0, maximumX: 1_920,
      y: 600, edgeMinimumY: 0, edgeMaximumY: 1_200,
      timestampNanoseconds: 1_000_000_000)
    let completed = detector.observe(
      x: 1_919, deltaX: 0, minimumX: 0, maximumX: 1_920,
      y: 600, edgeMinimumY: 0, edgeMaximumY: 1_200,
      timestampNanoseconds: 1_200_000_000)
    #expect(!started)
    #expect(completed)
  }

  @Test("edge vertical bounds come from the outermost monitor")
  func outermostMonitorBoundary() throws {
    let geometry = try #require(
      PointerEdgeDesktopGeometry(displayBounds: [
        CGRect(x: 0, y: 0, width: 1_440, height: 900),
        CGRect(x: 1_440, y: -200, width: 2_560, height: 1_440),
      ]))
    #expect(geometry.maximumX == 4_000)
    #expect(
      geometry.boundary(for: .right, y: -100)
        == PointerEdgeBoundary(minimumY: -200, maximumY: 1_240))
    #expect(geometry.boundary(for: .right, y: 1_300) == nil)
  }

  private func rightEdgeDetector() -> PointerEdgeDetector {
    PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true, edge: .right, dwellMilliseconds: 200))
  }

  private func modifierEdgeDetector() -> PointerEdgeDetector {
    PointerEdgeDetector(
      configuration: MacPointerEdgeConfiguration(
        enabled: true,
        edge: .right,
        dwellMilliseconds: 200,
        triggerMode: .holdModifier,
        modifier: .option
      )
    )
  }

  private func arm(_ detector: inout PointerEdgeDetector) {
    _ = observe(&detector, x: 960, deltaX: 1, milliseconds: 0)
  }

  private func observe(
    _ detector: inout PointerEdgeDetector,
    x: Double,
    deltaX: Int64,
    modifierFlags: CGEventFlags = [],
    milliseconds: UInt64
  ) -> Bool {
    detector.observe(
      x: x,
      deltaX: deltaX,
      minimumX: 0,
      maximumX: 1_920,
      modifierFlags: modifierFlags,
      timestampNanoseconds: milliseconds * 1_000_000
    )
  }
}
