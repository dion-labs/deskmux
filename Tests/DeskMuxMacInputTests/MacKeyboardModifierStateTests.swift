import CoreGraphics
import Testing

@testable import DeskMuxMacInput

@Test func inheritedCommandFlagCannotTurnTypedQIntoQuitShortcut() throws {
  var state = MacKeyboardModifierState()
  let q = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true))
  q.flags = [.maskCommand]

  state.normalize(q)

  #expect(!q.flags.contains(.maskCommand))
  #expect(state.pressedKeyCodes.isEmpty)
}

@Test func commandIsForwardedOnlyAfterItsSessionTransition() throws {
  var state = MacKeyboardModifierState()
  let commandDown = try #require(
    CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true)
  )
  commandDown.type = .flagsChanged
  commandDown.flags = [.maskCommand]
  state.normalize(commandDown)

  let q = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true))
  q.flags = [.maskCommand]
  state.normalize(q)
  #expect(q.flags.contains(.maskCommand))

  let commandUp = try #require(
    CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)
  )
  commandUp.type = .flagsChanged
  commandUp.flags = []
  state.normalize(commandUp)

  let nextQ = try #require(
    CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)
  )
  nextQ.flags = [.maskCommand]
  state.normalize(nextQ)
  #expect(!nextQ.flags.contains(.maskCommand))
}

@Test func sessionReleaseEndsWithNoPressedModifiers() throws {
  var state = MacKeyboardModifierState()
  for (keyCode, flag) in [
    (CGKeyCode(55), CGEventFlags.maskCommand),
    (CGKeyCode(56), CGEventFlags.maskShift),
  ] {
    let event = try #require(
      CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    )
    event.type = .flagsChanged
    event.flags = flag
    state.normalize(event)
  }

  let releases = state.releaseEvents()

  #expect(releases.count == 2)
  #expect(releases.last?.flags.intersection([.maskCommand, .maskShift]).isEmpty == true)
  #expect(state.pressedKeyCodes.isEmpty)
}

@Test func capsLockSurvivesSessionModifierSanitizing() throws {
  var state = MacKeyboardModifierState()
  let letter = try #require(
    CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
  )
  letter.flags = [.maskAlphaShift, .maskCommand]

  state.normalize(letter)

  #expect(letter.flags.contains(.maskAlphaShift))
  #expect(!letter.flags.contains(.maskCommand))
}
