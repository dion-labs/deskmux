import DeskMuxScreenTransport
import Foundation
import Security

private final class ProbeState: @unchecked Sendable {
  private let lock = NSLock()
  private var clientState: DeskMuxScreenClientState = .idle
  private var format: DeskMuxScreenFormat?
  private var frames = 0
  private var bytes = 0
  private var keyFrames = 0

  func record(state: DeskMuxScreenClientState) {
    lock.withLock { clientState = state }
  }

  func record(message: DeskMuxScreenWireMessage) {
    lock.withLock {
      switch message {
      case .format(let format): self.format = format
      case .frame(let frame):
        frames += 1
        bytes += frame.data.count
        if frame.isKeyFrame { keyFrames += 1 }
      default: break
      }
    }
  }

  var finished: Bool { lock.withLock { frames >= 30 } }

  func report() -> Report {
    lock.withLock {
      Report(
        state: String(describing: clientState),
        width: format?.width,
        height: format?.height,
        parameterSets: format?.parameterSets.count ?? 0,
        frames: frames,
        keyFrames: keyFrames,
        encodedBytes: bytes
      )
    }
  }
}

private struct Report: Codable {
  let state: String
  let width: Int?
  let height: Int?
  let parameterSets: Int
  let frames: Int
  let keyFrames: Int
  let encodedBytes: Int
}

@main
struct DeskMuxScreenLoopbackProbe {
  static func main() async {
    let arguments = CommandLine.arguments
    let destination = value(after: "--destination", in: arguments) ?? "loopback-source"
    let local = value(after: "--local", in: arguments) ?? "loopback-viewer"
    let isLoopback = destination == "loopback-source"
    let sharedKey = isLoopback
      ? "deskmux-loopback-screen-probe-key"
      : loadPairingKey() ?? ProcessInfo.processInfo.environment["DESKMUX_PAIRING_KEY"] ?? ""
    let state = ProbeState()
    let server = isLoopback
      ? BonjourScreenStreamServer(peerID: destination, sharedKey: sharedKey)
      : nil
    let client = BonjourScreenStreamClient(
      localPeerID: local,
      destinationPeerID: destination,
      sharedKey: sharedKey,
      stateHandler: { state.record(state: $0) },
      messageHandler: { state.record(message: $0) }
    )
    do {
      guard !sharedKey.isEmpty else {
        throw ProbeError.missingPairingKey
      }
      try server?.start()
      client.start()
      for _ in 0..<200 where !state.finished {
        try? await Task.sleep(for: .milliseconds(50))
      }
    } catch {
      state.record(state: .failed(String(describing: error)))
    }
    let report = state.report()
    client.stop()
    server?.stop()
    try? await Task.sleep(for: .milliseconds(500))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(report) {
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data([0x0a]))
    }
    if report.frames < 30 || report.parameterSets < 2 {
      exit(EXIT_FAILURE)
    }
  }

  private static func value(after option: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
  }

  private static func loadPairingKey() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "dev.deskmux.app.pairing",
      kSecAttrAccount as String: "default",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

private enum ProbeError: Error {
  case missingPairingKey
}
