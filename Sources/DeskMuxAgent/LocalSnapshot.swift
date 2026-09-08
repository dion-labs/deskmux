import DeskMuxCore
import Foundation

struct LocalDisplaySnapshot: Codable, Equatable, Sendable {
  let name: String
  let resolution: String?
  let isMain: Bool
  let isOnline: Bool
}

struct LocalAgentSnapshot: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let peerID: PeerID
  let machineModel: String?
  let displays: [LocalDisplaySnapshot]
  let observedAt: Date
}

enum LocalSnapshotCollector {
  static func collect(peerID: PeerID) throws -> LocalAgentSnapshot {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["-json", "SPHardwareDataType", "SPDisplaysDataType"]
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      let message = String(
        decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      throw LocalSnapshotError.profilerFailed(status: process.terminationStatus, message: message)
    }
    return try parse(profilerData: data, peerID: peerID)
  }

  static func parse(
    profilerData: Data,
    peerID: PeerID,
    observedAt: Date = Date()
  ) throws -> LocalAgentSnapshot {
    let root = try JSONSerialization.jsonObject(with: profilerData) as? [String: Any] ?? [:]
    let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first
    let adapters = root["SPDisplaysDataType"] as? [[String: Any]] ?? []
    let displays = adapters.flatMap { adapter -> [LocalDisplaySnapshot] in
      let entries = adapter["spdisplays_ndrvs"] as? [[String: Any]] ?? []
      return entries.compactMap { entry in
        guard let name = entry["_name"] as? String else { return nil }
        return LocalDisplaySnapshot(
          name: name,
          resolution: entry["_spdisplays_resolution"] as? String,
          isMain: entry["spdisplays_main"] as? String == "spdisplays_yes",
          isOnline: entry["spdisplays_online"] as? String == "spdisplays_yes"
        )
      }
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    return LocalAgentSnapshot(
      schemaVersion: 1,
      peerID: peerID,
      machineModel: hardware?["machine_model"] as? String,
      displays: displays,
      observedAt: observedAt
    )
  }
}

enum LocalSnapshotError: Error, CustomStringConvertible {
  case profilerFailed(status: Int32, message: String)

  var description: String {
    switch self {
    case .profilerFailed(let status, let message):
      return "system_profiler exited with status \(status): \(message)"
    }
  }
}
