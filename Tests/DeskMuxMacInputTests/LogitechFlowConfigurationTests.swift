@testable import DeskMuxMacInput
import Foundation
import Testing

@Test func detectsEnabledMouseFlowWithoutKeyboardLink() {
  let xml = """
    <device type="mouse"><settings on="true" keyboardLink="false">
      <peer0 channel="1" enabled="true"/>
    </settings></device>
    """
  #expect(LogitechFlowConfiguration.isEnabled(in: Data(xml.utf8)))
}

@Test func ignoresEnabledPeersWhenFlowIsOff() {
  let xml = """
    <device type="mouse"><settings on="false"><peer0 enabled="true"/></settings></device>
    """
  #expect(!LogitechFlowConfiguration.isEnabled(in: Data(xml.utf8)))
}

@Test func rejectsUnrelatedOrMalformedFlowSettings() {
  for xml in [
    "<device type='keyboard'><settings on='true'/></device>",
    "<features isFlowEnabled='true'/>",
    "<device type='mouse'><settings on='true'>",
  ] {
    #expect(!LogitechFlowConfiguration.isEnabled(in: Data(xml.utf8)))
  }
}

@Test func disablesOnlyTheMouseFlowSettingAndPreservesOtherContent() throws {
  let xml = """
    <device serial="private-id" type="mouse"><settings keyboardLink="false" on="TRUE">
      <peer0 address="private-address" enabled="true"/>
    </settings></device>
    """
  let disabled = try #require(LogitechFlowConfiguration.disabledData(from: Data(xml.utf8)))
  let result = try #require(String(data: disabled, encoding: .utf8))
  #expect(result.contains(#"on="false""#))
  #expect(result.contains(#"serial="private-id""#))
  #expect(result.contains(#"address="private-address""#))
  #expect(!LogitechFlowConfiguration.isEnabled(in: disabled))
}

@Test func disableBacksUpTheOriginalAndIsIdempotent() throws {
  let fileManager = FileManager.default
  let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? fileManager.removeItem(at: home) }
  let flowDirectory = home.appendingPathComponent(
    "Library/Application Support/LogiOptionsPlus/flow/devices", isDirectory: true)
  try fileManager.createDirectory(at: flowDirectory, withIntermediateDirectories: true)
  let configuration = flowDirectory.appendingPathComponent("mouse.xml")
  let original = Data(
    #"<device type="mouse"><settings on="true"><peer0 enabled="true"/></settings></device>"#.utf8)
  try original.write(to: configuration)

  let first = try LogitechFlowConfiguration.disable(homeDirectory: home)
  #expect(first.modifiedFileCount == 1)
  let backupDirectory = try #require(first.backupDirectory)
  #expect(try Data(contentsOf: backupDirectory.appendingPathComponent("mouse.xml")) == original)
  #expect(!LogitechFlowConfiguration.isEnabled(homeDirectory: home))

  let second = try LogitechFlowConfiguration.disable(homeDirectory: home)
  #expect(second.modifiedFileCount == 0)
  #expect(second.backupDirectory == nil)
}
