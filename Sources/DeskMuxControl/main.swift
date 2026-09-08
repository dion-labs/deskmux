import DeskMuxAgentIPC
import Foundation

private final class ResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func set(_ value: Bool) { lock.withLock { self.value = value } }
  func get() -> Bool { lock.withLock { value } }
}

@main
struct DeskMuxControl {
  static func main() {
    guard CommandLine.arguments.dropFirst() == ["return-input"] else {
      FileHandle.standardError.write(Data("Usage: deskmux-control return-input\n".utf8))
      exit(EXIT_FAILURE)
    }

    let connection = NSXPCConnection(machServiceName: deskMuxAgentMachServiceName)
    connection.remoteObjectInterface = NSXPCInterface(with: DeskMuxAgentXPCProtocol.self)
    let finished = DispatchSemaphore(value: 0)
    let resultBox = ResultBox()
    connection.resume()
    let errorHandler: @Sendable (Error) -> Void = { error in
      FileHandle.standardError.write(Data("DeskMux Agent error: \(error)\n".utf8))
      finished.signal()
    }
    let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
    guard let agent = proxy as? DeskMuxAgentXPCProtocol else {
      FileHandle.standardError.write(Data("DeskMux Agent is unavailable.\n".utf8))
      connection.invalidate()
      exit(EXIT_FAILURE)
    }
    let reply: @Sendable (Data) -> Void = { data in
      if let status = try? JSONDecoder().decode(DeskMuxAgentStatus.self, from: data) {
        let succeeded = status.keyboardRelayState == .idle
        resultBox.set(succeeded)
        let result = succeeded ? "Input returned to this Mac.\n" : "Return was not confirmed.\n"
        FileHandle.standardOutput.write(Data(result.utf8))
      }
      finished.signal()
    }
    agent.stopKeyboardRelay(withReply: reply)
    if finished.wait(timeout: .now() + 5) == .timedOut {
      FileHandle.standardError.write(Data("DeskMux Agent timed out.\n".utf8))
    }
    connection.invalidate()
    exit(resultBox.get() ? EXIT_SUCCESS : EXIT_FAILURE)
  }
}
