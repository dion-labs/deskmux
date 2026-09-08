import DeskMuxVirtualDisplay
import Testing

@Test func defaultVirtualDisplayIsAValid1920By1200HiDPIConfiguration() {
  let configuration = DeskMuxVirtualDisplayConfiguration()
  #expect(configuration.isValid)
  #expect(configuration.logicalWidth == 1920)
  #expect(configuration.logicalHeight == 1200)
  #expect(configuration.nativeWidth == 3840)
  #expect(configuration.nativeHeight == 2400)
}

@Test func rejectsInvalidVirtualDisplayConfigurations() {
  #expect(!DeskMuxVirtualDisplayConfiguration(name: "").isValid)
  #expect(
    !DeskMuxVirtualDisplayConfiguration(
      nativeWidth: 1280,
      nativeHeight: 720,
      logicalWidth: 1920,
      logicalHeight: 1200
    ).isValid
  )
  #expect(!DeskMuxVirtualDisplayConfiguration(refreshRate: 10).isValid)
}
