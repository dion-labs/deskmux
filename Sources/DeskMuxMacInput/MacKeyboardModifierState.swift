import CoreGraphics
import Foundation

/// Establishes a fresh modifier boundary for every remote-input session.
///
/// CGEvent key events contain a snapshot of macOS's global modifier flags. A
/// modifier held before capture begins can therefore appear on a later key even
/// though the session never delivered its key-down transition. Trusting that
/// snapshot could turn ordinary text into a shortcut such as Command-Q.
struct MacKeyboardModifierState {
  private(set) var pressedKeyCodes = Set<CGKeyCode>()

  mutating func normalize(_ event: CGEvent) {
    guard Self.isKeyboardEvent(event.type) else { return }

    if event.type == .flagsChanged {
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      if let flag = Self.modifierFlag(for: keyCode) {
        if event.flags.contains(flag) {
          pressedKeyCodes.insert(keyCode)
        } else {
          pressedKeyCodes.remove(keyCode)
        }
      }
    }

    // Caps Lock and keyboard-origin metadata are safe to preserve. Shortcut
    // modifiers are rebuilt solely from transitions observed in this session.
    let passiveFlags = event.flags.intersection([
      .maskAlphaShift,
      .maskNumericPad,
      .maskHelp,
      .maskNonCoalesced,
    ])
    event.flags = passiveFlags.union(activeFlags)
  }

  mutating func releaseEvents() -> [CGEvent] {
    var events: [CGEvent] = []
    for keyCode in pressedKeyCodes.sorted() {
      pressedKeyCodes.remove(keyCode)
      guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
      else { continue }
      event.type = .flagsChanged
      event.flags = activeFlags
      events.append(event)
    }
    return events
  }

  private var activeFlags: CGEventFlags {
    pressedKeyCodes.reduce(into: CGEventFlags()) { flags, keyCode in
      if let flag = Self.modifierFlag(for: keyCode) { flags.insert(flag) }
    }
  }

  private static func isKeyboardEvent(_ type: CGEventType) -> Bool {
    type == .keyDown || type == .keyUp || type == .flagsChanged
  }

  private static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
    switch keyCode {
    case 54, 55: return .maskCommand
    case 56, 60: return .maskShift
    case 58, 61: return .maskAlternate
    case 59, 62: return .maskControl
    case 63: return .maskSecondaryFn
    default: return nil
    }
  }
}
