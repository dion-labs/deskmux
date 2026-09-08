import Testing

@testable import DeskMuxMacInput

@Suite("ASUS HID inspector")
struct ASUSHIDInspectorTests {
  @Test("formats reports without changing their bytes")
  func hexadecimalReportFormatting() {
    #expect(ASUSHIDInspector.hexadecimalBytes([0x00, 0x08, 0xA5, 0xFF]) == "00 08 A5 FF")
  }

  @Test("targets the observed Scope RX vendor interface")
  func observedHardwareIdentity() {
    #expect(ASUSHIDInspector.vendorID == 0x0B05)
    #expect(ASUSHIDInspector.productID == 0x1A05)
    #expect(ASUSHIDInspector.vendorUsagePage == 0xFF00)
    #expect(ASUSHIDInspector.vendorUsage == 0x0001)
  }

  @Test("decodes the locally observed USB device revision")
  func observedUSBRevision() {
    #expect(String(format: "%04X", 0x0117) == "0117")
  }

  @Test("classifies only the exact wired and receiver product IDs")
  func researchInventoryRoles() {
    #expect(ASUSKeyboardResearchInventory.role(productID: 0x1A05) == .wiredKeyboard)
    #expect(ASUSKeyboardResearchInventory.role(productID: 0x1A07) == .rfReceiver)
    #expect(ASUSKeyboardResearchInventory.role(productID: 0x1A09) == nil)
  }

  @Test("parses only a bounded receiver status response")
  func receiverStatusResponse() {
    var response = [UInt8](repeating: 0, count: 64)
    response[0] = 0x12
    response[1] = 0x01
    response[5] = 87
    response[8] = 1
    response[10] = 87
    let parsed = ASUSReceiverStatusProbe.parse(response)
    #expect(parsed?.battery == 87)
    #expect(parsed?.charging == true)
    #expect(parsed?.duplicateBattery == 87)

    response[5] = 101
    #expect(ASUSReceiverStatusProbe.parse(response) == nil)
  }

  @Test("RF experiment payloads are fixed-size and reversible")
  func rfExperimentPayloads() {
    let enter = ASUSRFModeExperiment.payload(prefix: ASUSRFModeExperiment.enterRFPrefix)
    let leave = ASUSRFModeExperiment.payload(prefix: ASUSRFModeExperiment.leaveRFPrefix)
    #expect(enter.count == 64)
    #expect(leave.count == 64)
    #expect(Array(enter.prefix(5)) == [0xFA, 0x20, 0x04, 0x00, 0x00])
    #expect(Array(leave.prefix(5)) == [0xFA, 0x20, 0x05, 0x00, 0x00])
    #expect(enter.dropFirst(5).allSatisfy { $0 == 0 })
    #expect(leave.dropFirst(5).allSatisfy { $0 == 0 })
  }

  @Test("factory RF experiment contains only transient mode and connection payloads")
  func factoryRFExperimentPayloads() {
    let enterFactory = ASUSFactoryRFModeExperiment.payload(
      prefix: ASUSFactoryRFModeExperiment.enterFactoryPrefix
    )
    let leaveFactory = ASUSFactoryRFModeExperiment.payload(
      prefix: ASUSFactoryRFModeExperiment.leaveFactoryPrefix
    )
    let checkConnection = ASUSFactoryRFModeExperiment.payload(
      prefix: ASUSFactoryRFModeExperiment.checkRFConnectionPrefix
    )
    #expect(Array(enterFactory.prefix(5)) == [0xFA, 0x00, 0xD6, 0xA5, 0x00])
    #expect(Array(leaveFactory.prefix(5)) == [0xFA, 0x00, 0x00, 0x00, 0x00])
    #expect(Array(checkConnection.prefix(5)) == [0xFA, 0x20, 0x06, 0x00, 0x00])
    #expect([enterFactory, leaveFactory, checkConnection].allSatisfy { payload in
      payload.count == 64 && payload.dropFirst(5).allSatisfy { $0 == 0 }
    })
    #expect(ASUSFactoryRFModeExperiment.enterFactoryPrefix != [0xFA, 0x20, 0x07])
  }

  @Test("kernel input report counter parsing tolerates absent entries")
  func kernelInputReportCounterParsing() {
    #expect(ASUSKeyboardPathMonitor.inputReportCount(0) == nil)
  }

  @Test("report deltas preserve unknown baselines and counter resets")
  func reportDeltas() {
    #expect(ASUSKeyboardPathMonitor.reportDelta(before: nil, after: 12) == nil)
    #expect(ASUSKeyboardPathMonitor.reportDelta(before: 12, after: nil) == nil)
    #expect(ASUSKeyboardPathMonitor.reportDelta(before: 12, after: 3) == nil)
    #expect(ASUSKeyboardPathMonitor.reportDelta(before: 12, after: 12) == 0)
    #expect(ASUSKeyboardPathMonitor.reportDelta(before: 12, after: 18) == 6)
  }
}
