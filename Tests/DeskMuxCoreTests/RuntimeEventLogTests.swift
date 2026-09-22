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
  // Contended diagnostic records may be dropped, but persisted records must
  // remain complete, unique and in each synchronous producer's order.
  #expect(!rows.isEmpty && rows.count <= 320)
  #expect(Set(rows.compactMap { $0["event"] }).count == rows.count)
  #expect(rows.allSatisfy { $0["detail"] == detail })
  for producer in writers.indices {
    let events = rows.compactMap { $0["event"] }.filter { $0.hasPrefix("producer-\(producer)-") }
    let indices = events.compactMap { Int($0.split(separator: "-").last ?? "") }
    #expect(indices.count == events.count)
    #expect(indices == indices.sorted())
    #expect(indices.allSatisfy { (0..<40).contains($0) })
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

@Test(arguments: RuntimeLogKind.allCases)
private func runtimeLogHeldProcessLockDoesNotDelayCallerAndRecovers(_ kind: RuntimeLogKind) throws {
  let root = try runtimeLogDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let writer = DeskMuxRuntimeEventLog(directory: root)
  kind.record(writer, event: "before-lock")
  let holder = try RuntimeLogLockHolder(url: root.appendingPathComponent(kind.filename))
  defer { holder.release() }
  let returned = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    kind.record(writer, event: "contended-best-effort")
    returned.signal()
  }
  let prompt = returned.wait(timeout: .now() + 1) == .success
  holder.release()
  #expect(prompt)
  if !prompt { #expect(returned.wait(timeout: .now() + 5) == .success) }
  kind.record(writer, event: "after-lock")
  #expect(try runtimeLogRows(root.appendingPathComponent(kind.filename)).compactMap { $0["event"] }
    == ["before-lock", "after-lock"])
}

// This owned fixture only holds a lock on one synthetic file and waits on stdin.
// It never starts a DeskMux service or inherits any application configuration.
private final class RuntimeLogLockHolder {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()

  init(url: URL) throws {
    let ready = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    process.arguments = ["-I", "-u", "-c", """
      import fcntl, os, sys
      fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
      fcntl.flock(fd, fcntl.LOCK_EX)
      print("LOCKED", flush=True)
      sys.stdin.buffer.read(1)
      os.close(fd)
      """, url.path]
    process.standardInput = input
    process.standardOutput = output
    output.fileHandleForReading.readabilityHandler = { handle in
      if !handle.availableData.isEmpty { ready.signal() }
    }
    do {
      try process.run()
      guard ready.wait(timeout: .now() + 5) == .success else {
        release()
        throw RuntimeLogFixtureError.lockHolderDidNotStart
      }
      output.fileHandleForReading.readabilityHandler = nil
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      throw error
    }
  }

  func release() {
    guard process.isRunning else { return }
    try? input.fileHandleForWriting.write(contentsOf: Data([0x0a]))
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()
  }
}

private enum RuntimeLogFixtureError: Error { case lockHolderDidNotStart }
