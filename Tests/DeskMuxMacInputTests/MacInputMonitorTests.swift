import CoreGraphics
import DeskMuxCore
import Testing

@testable import DeskMuxMacInput

@Test func zeroDurationMonitorIsANoOpWithoutPermissions() throws {
  let report = try MacInputMonitor.run(durationSeconds: 0)
  #expect(report.durationSeconds == 0)
  #expect(report.eventCounts.isEmpty)
  #expect(report.tapDisableNotifications == 0)
}

@Test func relayMaskContainsEverySupportedInputKind() {
  #expect(MacInputEventMask.relayTypes.count == InputEventKind.allCases.count)
}

@Test func keyboardOnlyCaptureCannotInterceptPointingDeviceEvents() {
  #expect(
    MacInputCaptureScope.keyboardOnly.eventTypes == [
      .keyDown,
      .keyUp,
      .flagsChanged,
    ])
  for type in MacInputEventMask.relayTypes where !MacInputEventMask.keyboardTypes.contains(type) {
    #expect(!MacInputCaptureScope.keyboardOnly.includes(type))
    #expect(MacInputEventMask.keyboard & (CGEventMask(1) << type.rawValue) == 0)
  }
}
