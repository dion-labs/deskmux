import CoreGraphics
import DeskMuxCore
import Foundation
import Testing

@testable import DeskMuxMacInput

@Test func keyboardEventRoundTripsWithoutLosingKeyState() throws {
  let source = CGEventSource(stateID: .hidSystemState)
  let original = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
  original.flags = [.maskCommand, .maskShift]

  let packet = try MacInputEventCodec.encode(original, sessionID: UUID(), sequence: 42)
  let restored = try MacInputEventCodec.decode(packet)

  #expect(packet.kind == .keyDown)
  #expect(packet.sequence == 42)
  #expect(restored.type == .keyDown)
  #expect(restored.getIntegerValueField(.keyboardEventKeycode) == 0)
  #expect(restored.flags.contains(.maskCommand))
  #expect(restored.flags.contains(.maskShift))
  #expect(MacInputEventCodec.isInjectedByDeskMux(restored))
}

@Test func mouseAndScrollEventsRoundTrip() throws {
  let mouse = try #require(
    CGEvent(
      mouseEventSource: nil,
      mouseType: .leftMouseDown,
      mouseCursorPosition: CGPoint(x: 123, y: 456),
      mouseButton: .left
    )
  )
  mouse.setIntegerValueField(.mouseEventClickState, value: 2)
  let mousePacket = try MacInputEventCodec.encode(mouse, sessionID: UUID(), sequence: 1)
  let restoredMouse = try MacInputEventCodec.decode(mousePacket)
  #expect(mousePacket.kind == .leftMouseDown)
  #expect(restoredMouse.getIntegerValueField(.mouseEventClickState) == 2)

  let scroll = try #require(
    CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: -12,
      wheel2: 7,
      wheel3: 0
    )
  )
  let scrollPacket = try MacInputEventCodec.encode(scroll, sessionID: UUID(), sequence: 2)
  let restoredScroll = try MacInputEventCodec.decode(scrollPacket)
  #expect(scrollPacket.kind == .scrollWheel)
  #expect(restoredScroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -12)
  #expect(restoredScroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 7)
}
