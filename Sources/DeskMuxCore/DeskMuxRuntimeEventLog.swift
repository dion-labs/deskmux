import Darwin
import Foundation

/// The existing network/handoff JSONL diagnostics, isolated from service and UI
/// lifecycle. Callers supply metadata explicitly; this writer never reads user
/// defaults, clipboard, credentials, hardware or the home directory. Appends
/// are synchronous and best effort: I/O failure or lock contention drops the
/// current record, without retrying or waiting for the competing lock.
public final class DeskMuxRuntimeEventLog: Sendable {
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public func recordNetwork(_ event: String, peer: String, build: String, detail: String) {
    append("network.jsonl", fields: [
      "event": event, "peer": peer, "build": build, "detail": detail,
    ])
  }

  public func recordHandoff(
    _ event: String, peer: String, build: String, anchor: String,
    keyboardRelayState: String, keyboardRelayError: String,
    logitechFlowConflict: Bool, detail: String? = nil
  ) {
    append("handoff.jsonl", fields: [
      "event": event, "peer": peer, "build": build, "anchor": anchor,
      "keyboardRelayState": keyboardRelayState, "keyboardRelayError": keyboardRelayError,
      "logitechFlowConflict": String(logitechFlowConflict), "detail": detail ?? "",
    ])
  }

  private func append(_ filename: String, fields: [String: String]) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var record = fields
    record["timestamp"] = formatter.string(from: Date())
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent(filename)
      var bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
      bytes.append(0x0a)
      // Create without a check/truncate race, and append without a stale seek
      // offset. The inode lock keeps a complete JSONL record contiguous even
      // when multiple writer instances target the same file.
      let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o666)
      guard descriptor >= 0 else { return }
      defer { close(descriptor) }
      // Best effort: a paused competing writer must not delay handoff/UI.
      // Drop this record on contention; a later call retries normally.
      guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
      defer { flock(descriptor, LOCK_UN) }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
      try handle.write(contentsOf: bytes)
    } catch {
      // Diagnostics must never interfere with input routing or handoff.
    }
  }
}
