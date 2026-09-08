import DeskMuxAgentIPC
import Foundation

struct CommandError: Error, CustomStringConvertible {
  let executable: String
  let status: Int32
  let stderr: String

  var description: String {
    "\(executable) exited with status \(status): \(stderr)"
  }
}

enum CommandRunner {
  static func run(_ executable: String, arguments: [String]) throws -> Data {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      throw CommandError(
        executable: executable,
        status: process.terminationStatus,
        stderr: String(decoding: errorOutput, as: UTF8.self)
      )
    }
    return output
  }
}

struct Machine: Codable, Equatable {
  let name: String?
  let identifier: String?
  let chip: String?
  let memory: String?
  let macOS: String
  let architecture: String
}

struct Display: Codable, Equatable {
  let name: String
  let resolution: String?
  let isMain: Bool
  let isOnline: Bool
}

struct USBDevice: Codable, Equatable, Hashable {
  let name: String
  let manufacturer: String?
  let vendorID: String?
  let productID: String?
}

struct BluetoothDevice: Codable, Equatable, Hashable {
  let name: String
  let connected: Bool
}

struct Diagnostics: Codable, Equatable {
  let schemaVersion: Int
  let machine: Machine
  let displays: [Display]
  let usbDevices: [USBDevice]
  let bluetoothDevices: [BluetoothDevice]
}

enum DiagnosticsParser {
  static func parse(
    profilerData: Data,
    macOSVersion: String,
    architecture: String
  ) throws -> Diagnostics {
    let root = try JSONSerialization.jsonObject(with: profilerData) as? [String: Any] ?? [:]
    let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:]

    let machine = Machine(
      name: hardware["machine_name"] as? String,
      identifier: hardware["machine_model"] as? String,
      chip: hardware["chip_type"] as? String,
      memory: hardware["physical_memory"] as? String,
      macOS: macOSVersion,
      architecture: architecture
    )

    let displays = parseDisplays(root["SPDisplaysDataType"])
    let usbDevices = parseUSBDevices(root["SPUSBHostDataType"] ?? root["SPUSBDataType"])
    let bluetoothDevices = parseBluetoothDevices(root["SPBluetoothDataType"])

    return Diagnostics(
      schemaVersion: 1,
      machine: machine,
      displays: displays,
      usbDevices: usbDevices,
      bluetoothDevices: bluetoothDevices
    )
  }

  private static func parseDisplays(_ value: Any?) -> [Display] {
    guard let adapters = value as? [[String: Any]] else { return [] }
    return adapters.flatMap { adapter -> [Display] in
      guard let entries = adapter["spdisplays_ndrvs"] as? [[String: Any]] else { return [] }
      return entries.compactMap { entry in
        guard let name = entry["_name"] as? String else { return nil }
        return Display(
          name: name,
          resolution: entry["_spdisplays_resolution"] as? String,
          isMain: (entry["spdisplays_main"] as? String) == "spdisplays_yes",
          isOnline: (entry["spdisplays_online"] as? String) == "spdisplays_yes"
        )
      }
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private static func parseUSBDevices(_ value: Any?) -> [USBDevice] {
    var results = Set<USBDevice>()

    func visit(_ node: Any) {
      if let array = node as? [Any] {
        array.forEach(visit)
        return
      }
      guard let dictionary = node as? [String: Any] else { return }

      let vendorID =
        (dictionary["USBDeviceKeyVendorID"] ?? dictionary["spusb_vendor_id"]) as? String
      let productID =
        (dictionary["USBDeviceKeyProductID"] ?? dictionary["spusb_product_id"]) as? String
      let manufacturer =
        (dictionary["USBDeviceKeyVendorName"] ?? dictionary["manufacturer"]) as? String

      if let name = dictionary["_name"] as? String,
        vendorID != nil || productID != nil
      {
        results.insert(
          USBDevice(
            name: name,
            manufacturer: manufacturer,
            vendorID: vendorID,
            productID: productID
          )
        )
      }
      dictionary.values.forEach(visit)
    }

    if let value { visit(value) }
    return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private static func parseBluetoothDevices(_ value: Any?) -> [BluetoothDevice] {
    guard let sections = value as? [[String: Any]], let bluetooth = sections.first else {
      return []
    }
    var results = Set<BluetoothDevice>()

    func addNames(from value: Any?, connected: Bool) {
      guard let devices = value as? [[String: Any]] else { return }
      for device in devices {
        for name in device.keys where !name.isEmpty {
          results.insert(BluetoothDevice(name: name, connected: connected))
        }
      }
    }

    addNames(from: bluetooth["device_connected"], connected: true)
    addNames(from: bluetooth["device_not_connected"], connected: false)

    return results.sorted { lhs, rhs in
      if lhs.connected != rhs.connected { return lhs.connected && !rhs.connected }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}

enum HostInfo {
  static func macOSVersion() throws -> String {
    let data = try CommandRunner.run("/usr/bin/sw_vers", arguments: ["-productVersion"])
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func architecture() throws -> String {
    let data = try CommandRunner.run("/usr/bin/uname", arguments: ["-m"])
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private final class AgentProbeResult: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Result<Data, Error>?

  func set(_ value: Result<Data, Error>) {
    lock.lock()
    self.value = value
    lock.unlock()
  }

  func get() -> Result<Data, Error>? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

private enum AgentProbe {
  static func run(requestPermissions: Bool = false) throws -> Data {
    let connection = NSXPCConnection(machServiceName: deskMuxAgentMachServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: DeskMuxAgentXPCProtocol.self)
    connection.resume()
    defer { connection.invalidate() }

    let semaphore = DispatchSemaphore(value: 0)
    let result = AgentProbeResult()
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        result.set(.failure(error))
        semaphore.signal()
      }) as? DeskMuxAgentXPCProtocol
    else {
      throw CommandError(executable: "DeskMuxService", status: 1, stderr: "XPC unavailable")
    }
    let reply: @Sendable (Data) -> Void = { data in
      result.set(.success(data))
      semaphore.signal()
    }
    if requestPermissions {
      proxy.requestPermissions(withReply: reply)
    } else {
      proxy.status(withReply: reply)
    }
    guard semaphore.wait(timeout: .now() + 3) == .success else {
      throw CommandError(executable: "DeskMuxService", status: 1, stderr: "XPC timed out")
    }
    return try result.get()!.get()
  }

  static func runLogitechStatus() throws -> Data {
    let connection = NSXPCConnection(machServiceName: deskMuxAgentMachServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: DeskMuxAgentXPCProtocol.self)
    connection.resume()
    defer { connection.invalidate() }

    let semaphore = DispatchSemaphore(value: 0)
    let result = AgentProbeResult()
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        result.set(.failure(error))
        semaphore.signal()
      }) as? DeskMuxAgentXPCProtocol
    else {
      throw CommandError(executable: "DeskMuxService", status: 1, stderr: "XPC unavailable")
    }
    proxy.logitechStatus { data in
      result.set(.success(data))
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 3) == .success else {
      throw CommandError(executable: "DeskMuxService", status: 1, stderr: "XPC timed out")
    }
    return try result.get()!.get()
  }
}

@main
struct DeskMuxDiagnosticsCommand {
  static func main() {
    do {
      if CommandLine.arguments.dropFirst().first == "--agent-status" {
        FileHandle.standardOutput.write(try AgentProbe.run())
        FileHandle.standardOutput.write(Data("\n".utf8))
        return
      }
      if CommandLine.arguments.dropFirst().first == "--request-agent-permissions" {
        FileHandle.standardOutput.write(try AgentProbe.run(requestPermissions: true))
        FileHandle.standardOutput.write(Data("\n".utf8))
        return
      }
      if CommandLine.arguments.dropFirst().first == "--agent-logitech-status" {
        FileHandle.standardOutput.write(try AgentProbe.runLogitechStatus())
        FileHandle.standardOutput.write(Data("\n".utf8))
        return
      }
      let profilerData = try CommandRunner.run(
        "/usr/sbin/system_profiler",
        arguments: [
          "-json",
          "SPHardwareDataType",
          "SPDisplaysDataType",
          "SPUSBHostDataType",
          "SPBluetoothDataType",
        ]
      )
      let diagnostics = try DiagnosticsParser.parse(
        profilerData: profilerData,
        macOSVersion: HostInfo.macOSVersion(),
        architecture: HostInfo.architecture()
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      FileHandle.standardOutput.write(try encoder.encode(diagnostics))
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("deskmux-diagnostics: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
