import DeskMuxCore
import Foundation
import Testing
@testable import DeskMuxInputTransport

// DM-043/014: actual async JSONL persistence, using only a fresh disposable log directory.
@Test func clipboardLogPersistsOnlyMetadataAcrossWriterRecreation() throws {
  let root = try temporaryClipboardLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let queue = DispatchQueue(label: "dev.deskmux.tests.clipboard-log")
  let secret = "SYNTHETIC-DO-NOT-LOG-\(UUID().uuidString)-é"
  let update = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "synthetic-peer"), text: secret)
  let first = DeskMuxClipboardEventLog(directory: root, queue: queue)
  first.record("sent", update: update)
  first.record("acknowledged", updateID: update.id)
  queue.sync {}
  let resumed = DeskMuxClipboardEventLog(directory: root, queue: queue)
  resumed.record("applied", update: update)
  queue.sync {}
  let bytes = try Data(contentsOf: root.appendingPathComponent("clipboard.jsonl"))
  #expect(!String(decoding: bytes, as: UTF8.self).contains(secret))
  let rows = try logRows(bytes)
  #expect(rows.compactMap { $0["event"] as? String } == ["sent", "acknowledged", "applied"])
  #expect(rows.allSatisfy { $0["update_id"] as? String == update.id.uuidString })
  #expect(rows[0]["bytes"] as? Int == secret.utf8.count)
  #expect(Set(rows[0].keys) == ["timestamp", "event", "update_id", "source", "bytes"])
  #expect(Set(rows[1].keys) == ["timestamp", "event", "update_id"])
  #expect(Set(rows[2].keys) == Set(rows[0].keys))
}

@Test func clipboardLogConcurrentAppendsRemainWholeMetadataRecords() throws {
  let root = try temporaryClipboardLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let queue = DispatchQueue(label: "dev.deskmux.tests.clipboard-log-concurrent")
  let logger = DeskMuxClipboardEventLog(directory: root, queue: queue)
  let updates = (0..<100).map { index in
    DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "synthetic-peer"), text: "PRIVATE-TEXT-\(index)")
  }
  DispatchQueue.concurrentPerform(iterations: updates.count) { index in
    logger.record("sent", update: updates[index])
  }
  queue.sync {}
  let bytes = try Data(contentsOf: root.appendingPathComponent("clipboard.jsonl"))
  let rows = try logRows(bytes)
  #expect(rows.count == updates.count)
  #expect(Set(rows.compactMap { $0["update_id"] as? String }) == Set(updates.map { $0.id.uuidString }))
  #expect(!String(decoding: bytes, as: UTF8.self).contains("PRIVATE-TEXT-"))
  #expect(rows.allSatisfy { Set($0.keys) == ["timestamp", "event", "update_id", "source", "bytes"] })
}

@Test func clipboardLogUnwritableDestinationDoesNotPreventLaterRecovery() throws {
  let root = try temporaryClipboardLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let destination = root.appendingPathComponent("blocked")
  try Data("synthetic blocker".utf8).write(to: destination) // A file cannot be a log directory.
  let queue = DispatchQueue(label: "dev.deskmux.tests.clipboard-log-recovery")
  let logger = DeskMuxClipboardEventLog(directory: destination, queue: queue)
  logger.record("sent", updateID: UUID())
  queue.sync {}
  #expect(try String(contentsOf: destination, encoding: .utf8) == "synthetic blocker")
  try FileManager.default.removeItem(at: destination)
  let accepted = UUID()
  logger.record("acknowledged", updateID: accepted)
  queue.sync {}
  let rows = try logRows(Data(contentsOf: destination.appendingPathComponent("clipboard.jsonl")))
  #expect(rows.count == 1)
  #expect(rows[0]["update_id"] as? String == accepted.uuidString)
}

private func temporaryClipboardLogDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("deskmux-log-fixture-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func logRows(_ data: Data) throws -> [[String: Any]] {
  try data.split(separator: 0x0a).map { line in
    try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
  }
}
