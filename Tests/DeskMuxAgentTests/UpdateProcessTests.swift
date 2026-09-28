import CryptoKit
import Foundation
import Testing

@testable import DeskMuxInputTransport

@Test func updateProcessDrainsLargeSuccessfulOutputBeforeWaiting() throws {
  // A child-local alarm makes an old wait-before-drain implementation fail
  // instead of leaving the Swift test worker blocked indefinitely.
  let script = """
    import signal, sys
    signal.alarm(5)
    sys.stdout.buffer.write(b'A' * 524288)
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(b'B' * 524288)
    sys.stderr.buffer.flush()
    signal.alarm(0)
    """
  let output = try runDeskMuxUpdateProcess(
    executable: "/usr/bin/python3", arguments: ["-I", "-c", script])
  let expected = Data(repeating: 65, count: 524288) + Data(repeating: 66, count: 524288)
  #expect(output.count == expected.count)
  #expect(SHA256.hash(data: output) == SHA256.hash(data: expected))
}

@Test func updateProcessDrainsLargeFailureThroughFinalDiagnostic() throws {
  let script = """
    import signal, sys
    signal.alarm(5)
    sys.stdout.buffer.write(b'X' * 1048576)
    sys.stdout.buffer.flush()
    sys.stderr.write('synthetic failure complete\\n')
    sys.stderr.flush()
    signal.alarm(0)
    sys.exit(7)
    """
  do {
    try runDeskMuxUpdateProcess(executable: "/usr/bin/python3", arguments: ["-I", "-c", script])
    Issue.record("A failing subprocess was accepted")
  } catch DeskMuxAppUpdateError.processFailed(let message) {
    // Do not print megabytes of fixture output if this assertion fails.
    let retainedDiagnostic = message.hasPrefix("python3 failed: ")
      && message.hasSuffix("synthetic failure complete\n")
      && message.utf8.count > 1048576
    #expect(retainedDiagnostic)
  }
}
