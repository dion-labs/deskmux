import Testing

@testable import DeskMuxMacInput

@Suite("Logitech HID++")
struct LogitechHIDPlusTests {
  @Test("parses a matching IRoot getFeature response")
  func parsesMatchingResponse() {
    let report: [UInt8] = [
      0x11, 0x01, 0x00, 0x0D, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]
    #expect(
      LogitechHIDPlus.parseFeatureResponse(report, deviceIndex: 0x01) == 0x09)
  }

  @Test("rejects stale or unrelated responses")
  func rejectsUnrelatedResponse() {
    #expect(
      LogitechHIDPlus.parseFeatureResponse(
        [0x11, 0x02, 0x00, 0x0D, 0x09], deviceIndex: 0x01
      ) == nil)
    #expect(
      LogitechHIDPlus.parseFeatureResponse(
        [0x11, 0x01, 0x00, 0x0E, 0x09], deviceIndex: 0x01
      ) == nil)
    #expect(
      LogitechHIDPlus.parseFeatureResponse(
        [0x11, 0x01, 0x00, 0x0D, 0x00], deviceIndex: 0x01
      ) == nil)
  }

  @Test("finds a secondary Bluetooth HID++ collection")
  func findsSecondaryBluetoothControlUsage() {
    let selected = LogitechHIDPlus.selectControlUsage(
      primary: (page: 0x0001, usage: 0x0002),
      usagePairs: [
        (page: 0x0001, usage: 0x0002),
        (page: 0xFF43, usage: 0x0202),
      ]
    )
    #expect(selected.page == 0xFF43)
    #expect(selected.usage == 0x0202)
  }

  @Test("keeps the Bolt receiver control collection")
  func keepsReceiverControlUsage() {
    let selected = LogitechHIDPlus.selectControlUsage(
      primary: (page: 0xFF00, usage: 0x0001),
      usagePairs: [(page: 0xFF00, usage: 0x0002)]
    )
    #expect(selected.page == 0xFF00)
    #expect(selected.usage == 0x0001)
  }
}
