import CoreGraphics
import DeskMuxCore
import Foundation

public enum MacInputInjectorError: Error, CustomStringConvertible {
  case postPermissionMissing
  case wrongSession(expected: UUID, received: UUID)
  case outOfOrder(expected: UInt64, received: UInt64)

  public var description: String {
    switch self {
    case .postPermissionMissing:
      return "Accessibility permission is required on the destination Mac"
    case .wrongSession(let expected, let received):
      return "received input for session \(received), expected \(expected)"
    case .outOfOrder(let expected, let received):
      return "received input sequence \(received), expected \(expected)"
    }
  }
}

public final class MacInputInjector: @unchecked Sendable {
  public let sessionID: UUID
  private let lock = NSLock()
  private var nextSequence: UInt64 = 0
  private var pressedKeys = Set<CGKeyCode>()
  private var modifierState = MacKeyboardModifierState()
  private var pressedButtons = Set<CGMouseButton>()
  private var pointerLocation = CGEvent(source: nil)?.location ?? .zero
  private var lastMotionSequence: UInt64?
  private var cumulativeDeltaX: Int64 = 0
  private var cumulativeDeltaY: Int64 = 0

  public init(sessionID: UUID) throws {
    guard MacInputPermissions.status().canPost else {
      throw MacInputInjectorError.postPermissionMissing
    }
    self.sessionID = sessionID
  }

  public func inject(_ packet: InputEventPacket) throws {
    try lock.withLock {
      guard packet.sessionID == sessionID else {
        throw MacInputInjectorError.wrongSession(expected: sessionID, received: packet.sessionID)
      }
      guard packet.sequence == nextSequence else {
        throw MacInputInjectorError.outOfOrder(
          expected: nextSequence,
          received: packet.sequence
        )
      }
      let event = try MacInputEventCodec.decode(packet)
      normalizePointerLocation(event)
      modifierState.normalize(event)
      if event.type == .flagsChanged {
        MacInputModifierBridge.publish(event.flags)
      }
      track(event)
      event.post(tap: .cghidEventTap)
      nextSequence += 1
    }
  }

  /// Injects only the newest authenticated pointer state. Missing datagrams do
  /// not lose distance because the sender transmits cumulative deltas.
  public func injectPointerMotion(_ state: PointerMotionState) throws {
    try lock.withLock {
      guard state.sessionID == sessionID else {
        throw MacInputInjectorError.wrongSession(
          expected: sessionID,
          received: state.sessionID
        )
      }
      if let lastMotionSequence, state.sequence <= lastMotionSequence { return }
      guard let motionType = Self.motionType(for: state.kind) else { return }
      let deltaX = state.cumulativeDeltaX - cumulativeDeltaX
      let deltaY = state.cumulativeDeltaY - cumulativeDeltaY
      lastMotionSequence = state.sequence
      cumulativeDeltaX = state.cumulativeDeltaX
      cumulativeDeltaY = state.cumulativeDeltaY
      guard deltaX != 0 || deltaY != 0 else { return }

      pointerLocation.x += CGFloat(deltaX)
      pointerLocation.y += CGFloat(deltaY)
      guard
        let event = CGEvent(
          mouseEventSource: nil,
          mouseType: motionType.type,
          mouseCursorPosition: pointerLocation,
          mouseButton: motionType.button
        )
      else { return }
      event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
      event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
      event.setIntegerValueField(
        .eventSourceUserData,
        value: MacInputEventCodec.injectedEventMarker
      )
      event.post(tap: .cghidEventTap)
    }
  }

  public func releaseAll() {
    lock.withLock {
      for key in pressedKeys {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        event?.setIntegerValueField(
          .eventSourceUserData,
          value: MacInputEventCodec.injectedEventMarker
        )
        event?.post(tap: .cghidEventTap)
      }
      for event in modifierState.releaseEvents() {
        event.setIntegerValueField(
          .eventSourceUserData,
          value: MacInputEventCodec.injectedEventMarker
        )
        event.post(tap: .cghidEventTap)
      }
      for button in pressedButtons {
        let type: CGEventType =
          button == .left
          ? .leftMouseUp
          : button == .right
            ? .rightMouseUp : .otherMouseUp
        let event = CGEvent(
          mouseEventSource: nil,
          mouseType: type,
          mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero,
          mouseButton: button
        )
        event?.setIntegerValueField(
          .eventSourceUserData,
          value: MacInputEventCodec.injectedEventMarker
        )
        event?.post(tap: .cghidEventTap)
      }
      pressedKeys.removeAll()
      pressedButtons.removeAll()
      MacInputModifierBridge.publish([])
    }
  }

  private func track(_ event: CGEvent) {
    let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let button = CGMouseButton(
      rawValue: UInt32(event.getIntegerValueField(.mouseEventButtonNumber)))
    switch event.type {
    case .keyDown:
      pressedKeys.insert(key)
    case .keyUp:
      pressedKeys.remove(key)
    case .flagsChanged:
      break
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      if let button { pressedButtons.insert(button) }
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
      if let button { pressedButtons.remove(button) }
    default:
      break
    }
  }

  private func normalizePointerLocation(_ event: CGEvent) {
    switch event.type {
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      pointerLocation.x += CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
      pointerLocation.y += CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
      event.location = pointerLocation
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
      .otherMouseDown, .otherMouseUp:
      event.location = pointerLocation
    default:
      break
    }
  }

  private static func motionType(
    for kind: InputEventKind
  ) -> (type: CGEventType, button: CGMouseButton)? {
    switch kind {
    case .mouseMoved:
      return (.mouseMoved, .left)
    case .leftMouseDragged:
      return (.leftMouseDragged, .left)
    case .rightMouseDragged:
      return (.rightMouseDragged, .right)
    case .otherMouseDragged:
      return (.otherMouseDragged, .center)
    default:
      return nil
    }
  }
}
