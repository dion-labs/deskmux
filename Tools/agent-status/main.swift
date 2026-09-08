import Foundation

let connection = NSXPCConnection(machServiceName: deskMuxAgentMachServiceName)
connection.remoteObjectInterface = NSXPCInterface(with: DeskMuxAgentXPCProtocol.self)
connection.resume()

let completed = DispatchSemaphore(value: 0)
var output = Data()
var failure: String?
guard
  let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
    failure = error.localizedDescription
    completed.signal()
  }) as? DeskMuxAgentXPCProtocol
else {
  FileHandle.standardError.write(Data("Could not create agent proxy.\n".utf8))
  Foundation.exit(EXIT_FAILURE)
}

switch CommandLine.arguments.dropFirst().first {
case "mouse-fresh":
  proxy.freshLogitechStatus { data in
    output = data
    completed.signal()
  }
case "start":
  proxy.startKeyboardRelay(to: "macbook") { data in
    output = data
    completed.signal()
  }
case "stop":
  proxy.stopKeyboardRelay { data in
    output = data
    completed.signal()
  }
default:
  proxy.status { data in
    output = data
    completed.signal()
  }
}

let timeout: TimeInterval = CommandLine.arguments.dropFirst().first == "start" ? 15 : 3
guard completed.wait(timeout: .now() + timeout) == .success else {
  FileHandle.standardError.write(Data("Agent status timed out.\n".utf8))
  Foundation.exit(EXIT_FAILURE)
}
connection.invalidate()
if let failure {
  FileHandle.standardError.write(Data("Agent status failed: \(failure)\n".utf8))
  Foundation.exit(EXIT_FAILURE)
}
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
