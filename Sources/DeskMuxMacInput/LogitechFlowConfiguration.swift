import Foundation

public enum LogitechFlowConfiguration {
  public struct DisableResult: Equatable, Sendable {
    public let modifiedFileCount: Int
    public let backupDirectory: URL?

    public init(modifiedFileCount: Int, backupDirectory: URL?) {
      self.modifiedFileCount = modifiedFileCount
      self.backupDirectory = backupDirectory
    }
  }

  public static func isEnabled(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)
    -> Bool
  {
    let directory = homeDirectory.appendingPathComponent(
      "Library/Application Support/LogiOptionsPlus/flow/devices", isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
    else { return false }
    return files.contains { url in
      guard url.pathExtension == "xml",
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size <= 1_048_576,
        let data = try? Data(contentsOf: url)
      else { return false }
      return isEnabled(in: data)
    }
  }

  public static func isEnabled(in data: Data) -> Bool {
    let delegate = FlowSettingsParser()
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    return parser.parse() && delegate.enabled
  }

  /// Disables only Logitech Flow's mouse setting. The original XML files are
  /// copied into DeskMux's application-support directory before any write.
  /// Pairing data, device identifiers, and all non-Flow settings are preserved.
  @discardableResult
  public static func disable(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> DisableResult {
    let fileManager = FileManager.default
    let flowDirectory = homeDirectory.appendingPathComponent(
      "Library/Application Support/LogiOptionsPlus/flow/devices", isDirectory: true)
    guard let files = try? fileManager.contentsOfDirectory(
      at: flowDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
    else {
      return DisableResult(modifiedFileCount: 0, backupDirectory: nil)
    }

    let changes: [(url: URL, original: Data, disabled: Data)] = files.compactMap { url in
      guard url.pathExtension.lowercased() == "xml",
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size <= 1_048_576,
        let original = try? Data(contentsOf: url),
        let disabled = disabledData(from: original)
      else { return nil }
      return (url, original, disabled)
    }
    guard !changes.isEmpty else {
      return DisableResult(modifiedFileCount: 0, backupDirectory: nil)
    }

    let backupDirectory = homeDirectory
      .appendingPathComponent("Library/Application Support/DeskMux/Flow Backups", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

    for change in changes {
      try fileManager.copyItem(
        at: change.url,
        to: backupDirectory.appendingPathComponent(change.url.lastPathComponent))
    }

    var written: [(url: URL, original: Data)] = []
    do {
      for change in changes {
        try change.disabled.write(to: change.url, options: .atomic)
        written.append((change.url, change.original))
      }
    } catch {
      for change in written {
        try? change.original.write(to: change.url, options: .atomic)
      }
      throw error
    }
    return DisableResult(
      modifiedFileCount: changes.count,
      backupDirectory: backupDirectory
    )
  }

  static func disabledData(from data: Data) -> Data? {
    guard isEnabled(in: data), let xml = String(data: data, encoding: .utf8) else { return nil }
    let entireRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
    guard
      let deviceExpression = try? NSRegularExpression(
        pattern: #"<device\b[^>]*\btype\s*=\s*(['\"])mouse\1[^>]*>"#,
        options: [.caseInsensitive]),
      let device = deviceExpression.firstMatch(in: xml, range: entireRange),
      let deviceRange = Range(device.range, in: xml)
    else { return nil }

    let afterDevice = deviceRange.upperBound..<xml.endIndex
    guard let deviceEnd = xml.range(
      of: "</device>", options: [.caseInsensitive], range: afterDevice)
    else { return nil }
    let bodyRange = NSRange(afterDevice.lowerBound..<deviceEnd.lowerBound, in: xml)
    guard
      let settingsExpression = try? NSRegularExpression(
        pattern: #"<settings\b[^>]*>"#, options: [.caseInsensitive]),
      let settings = settingsExpression.firstMatch(in: xml, range: bodyRange),
      let settingsRange = Range(settings.range, in: xml)
    else { return nil }

    let settingsTag = String(xml[settingsRange])
    let settingsTagRange = NSRange(settingsTag.startIndex..<settingsTag.endIndex, in: settingsTag)
    guard
      let onExpression = try? NSRegularExpression(
        pattern: #"\bon\s*=\s*(['\"])(true)\1"#, options: [.caseInsensitive]),
      let on = onExpression.firstMatch(in: settingsTag, range: settingsTagRange),
      let valueRangeInTag = Range(on.range(at: 2), in: settingsTag)
    else { return nil }

    let offset = settingsTag.distance(from: settingsTag.startIndex, to: valueRangeInTag.lowerBound)
    let length = settingsTag.distance(from: valueRangeInTag.lowerBound, to: valueRangeInTag.upperBound)
    let valueStart = xml.index(settingsRange.lowerBound, offsetBy: offset)
    let valueEnd = xml.index(valueStart, offsetBy: length)
    var disabledXML = xml
    disabledXML.replaceSubrange(valueStart..<valueEnd, with: "false")
    let disabled = Data(disabledXML.utf8)
    return isEnabled(in: disabled) ? nil : disabled
  }
}

private final class FlowSettingsParser: NSObject, XMLParserDelegate {
  private var elements: [String] = []
  private var isMouse = false
  private(set) var enabled = false

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    if elements.isEmpty, elementName == "device" {
      isMouse = attributeDict["type"] == "mouse"
    }
    if isMouse, elements == ["device"], elementName == "settings" {
      enabled = attributeDict["on"]?.lowercased() == "true"
    }
    elements.append(elementName)
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if !elements.isEmpty { elements.removeLast() }
  }
}
