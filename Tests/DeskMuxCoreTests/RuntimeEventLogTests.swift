import Foundation
import Testing
@testable import DeskMuxCore

private enum RuntimeLogKind: String, CaseIterable, Sendable {
  case network, handoff
  var filename: String { rawValue + ".jsonl" }
  func record(_ writer: DeskMuxRuntimeEventLog, event: String, detail: String = "") {
    switch self {
    case .network:
      writer.recordNetwork(event, peer: "synthetic-peer", build: "fixture", detail: detail)
    case .handoff:
      writer.recordHandoff(event, peer: "synthetic-peer", build: "fixture", anchor: "fixture-anchor",
        keyboardRelayState: "idle", keyboardRelayError: "", logitechFlowConflict: false, detail: detail)
    }
  }
}

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogPersistsInOrderAcrossWriterRecreation(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let first = DeskMuxRuntimeEventLog(directory: root)
  for index in 0..<50 { kind.record(first, event: "fixture-\(index)") }
  let second = DeskMuxRuntimeEventLog(directory: root)
  for index in 50..<100 { kind.record(second, event: "fixture-\(index)") }
  let rows = try runtimeLogRows(root.appendingPathComponent(kind.filename))
  #expect(rows.compactMap { $0["event"] } == (0..<100).map { "fixture-\($0)" })
  #expect(rows.allSatisfy { $0["peer"] == "synthetic-peer" && $0["build"] == "fixture" })
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  #expect(rows.allSatisfy { formatter.date(from: $0["timestamp"] ?? "") != nil })
}

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogConcurrentWritersPreserveWholeOrderedRecords(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let writers = (0..<8).map { _ in DeskMuxRuntimeEventLog(directory: root) }
  let detail = String(repeating: "synthetic-🧪\n", count: 512)
  DispatchQueue.concurrentPerform(iterations: writers.count) { producer in
    for index in 0..<40 {
      kind.record(writers[producer], event: "producer-\(producer)-\(index)", detail: detail)
    }
  }
  let rows = try runtimeLogRows(root.appendingPathComponent(kind.filename))
  #expect(rows.count == 320)
  #expect(rows.allSatisfy { $0["detail"] == detail })
  for producer in writers.indices {
    let events = rows.compactMap { $0["event"] }.filter { $0.hasPrefix("producer-\(producer)-") }
    #expect(events == (0..<40).map { "producer-\(producer)-\($0)" })
  }
}

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogReopensAfterExternalRotationAndRemoval(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let writer = DeskMuxRuntimeEventLog(directory: root)
  let active = root.appendingPathComponent(kind.filename)
  let rotated = root.appendingPathComponent(kind.filename + ".previous")
  kind.record(writer, event: "before-rotation")
  try FileManager.default.moveItem(at: active, to: rotated)
  kind.record(writer, event: "after-rotation")
  #expect(try runtimeLogRows(rotated).compactMap { $0["event"] } == ["before-rotation"])
  #expect(try runtimeLogRows(active).compactMap { $0["event"] } == ["after-rotation"])
  try FileManager.default.removeItem(at: active)
  kind.record(writer, event: "after-removal")
  #expect(try runtimeLogRows(active).compactMap { $0["event"] } == ["after-removal"])
}

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogRecoversFromBlockedDirectoryWithoutChangingBlocker(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let blocked = root.appendingPathComponent("blocked")
  let canary = Data("SYNTHETIC-NOT-A-LOG".utf8)
  try canary.write(to: blocked)
  let writer = DeskMuxRuntimeEventLog(directory: blocked)
  kind.record(writer, event: "dropped")
  #expect(try Data(contentsOf: blocked) == canary)
  try FileManager.default.removeItem(at: blocked)
  kind.record(writer, event: "recovered")
  #expect(try runtimeLogRows(blocked.appendingPathComponent(kind.filename)).compactMap { $0["event"] } == ["recovered"])
}

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogRecoversWhenLogPathWasADirectory(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let path = root.appendingPathComponent(kind.filename)
  try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  let sentinel = path.appendingPathComponent("preserve")
  try Data("synthetic".utf8).write(to: sentinel)
  let writer = DeskMuxRuntimeEventLog(directory: root)
  kind.record(writer, event: "dropped")
  #expect(try Data(contentsOf: sentinel) == Data("synthetic".utf8))
  try FileManager.default.removeItem(at: path)
  kind.record(writer, event: "recovered")
  #expect(try runtimeLogRows(path).compactMap { $0["event"] } == ["recovered"])
}

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogSchemaAndEscapingDoNotInventPrivateFields(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  // These are diagnostic metadata canaries, deliberately passed to detail.
  // Verbatim detail is existing behavior, NOT a credential-redaction promise.
  let detail = "fixture error é\n{\"clipboard\":\"CANARY\",\"pairingKey\":\"CANARY\"}"
  kind.record(DeskMuxRuntimeEventLog(directory: root), event: "fixture", detail: detail)
  let url = root.appendingPathComponent(kind.filename)
  let bytes = try Data(contentsOf: url)
  #expect(bytes.filter { $0 == 0x0a }.count == 1)
  let rows = try runtimeLogRows(url)
  #expect(rows.count == 1)
  let row = try #require(rows.first)
  let base: Set<String> = ["timestamp", "event", "peer", "build", "detail"]
  let extra: Set<String> = ["anchor", "keyboardRelayState", "keyboardRelayError", "logitechFlowConflict"]
  #expect(Set(row.keys) == (kind == .network ? base : base.union(extra)))
  #expect(row["detail"] == detail)
  #expect(row["clipboard"] == nil && row["pairingKey"] == nil)
}

private func runtimeLogDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("deskmux-runtime-log-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func runtimeLogRows(_ url: URL) throws -> [[String: String]] {
  let bytes = try Data(contentsOf: url)
  #expect(bytes.last == 0x0a)
  return try bytes.split(separator: 0x0a).map {
    try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: String])
  }
}
