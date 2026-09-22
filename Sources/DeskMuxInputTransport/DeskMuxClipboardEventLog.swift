import DeskMuxCore
import Foundation

/// Metadata-only clipboard diagnostics. The directory is injectable so disk
/// failure, persistence and redaction can be tested without a live user log.
final class DeskMuxClipboardEventLog: Sendable {
  private let directory: URL
  private let queue: DispatchQueue

  init(
    directory: URL,
    queue: DispatchQueue = DispatchQueue(label: "dev.deskmux.clipboard.log", qos: .utility)
  ) {
    self.directory = directory
    self.queue = queue
  }

  func record(_ event: String, update: DeskMuxClipboardUpdate) {
    record(event, updateID: update.id, sourcePeerID: update.sourcePeerID.rawValue,
      byteCount: update.text.lengthOfBytes(using: .utf8))
  }

  func record(_ event: String, updateID: UUID, sourcePeerID: String? = nil, byteCount: Int? = nil) {
    queue.async { [directory] in
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var record: [String: Any] = [
        "timestamp": formatter.string(from: Date()),
        "event": event,
        "update_id": updateID.uuidString,
      ]
      if let sourcePeerID { record["source"] = sourcePeerID }
      if let byteCount { record["bytes"] = byteCount }
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("clipboard.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
          FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
        try handle.write(contentsOf: Data([0x0a]))
      } catch {
        // Clipboard diagnostics must never affect synchronization.
      }
    }
  }
}
