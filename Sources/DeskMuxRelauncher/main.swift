import Darwin
import Foundation

@main
struct DeskMuxRelauncher {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2, let parentPID = Int32(arguments[1]) else {
      Foundation.exit(EXIT_FAILURE)
    }
    let appPath = arguments[0]
    let deadline = Date().addingTimeInterval(15)
    while kill(parentPID, 0) == 0, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", appPath]
    do {
      try process.run()
      process.waitUntilExit()
      Foundation.exit(process.terminationStatus)
    } catch {
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
