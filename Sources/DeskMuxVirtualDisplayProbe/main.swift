import AppKit
import DeskMuxVirtualDisplay
import Foundation

private struct ProbeReport: Codable {
  let supported: Bool
  let configuration: DeskMuxVirtualDisplayConfiguration
  let displaysBefore: [DeskMuxDisplaySnapshot]
  let virtualDisplayID: UInt32?
  let appeared: Bool
  let displaysDuring: [DeskMuxDisplaySnapshot]
  let screenCapture: DeskMuxScreenCaptureCheck?
  let disappeared: Bool
  let displaysAfter: [DeskMuxDisplaySnapshot]
  let error: String?
}

@main
struct DeskMuxVirtualDisplayProbe {
  @MainActor
  static func main() async {
    _ = NSApplication.shared
    let configuration = DeskMuxVirtualDisplayConfiguration()
    let displaysBefore = DeskMuxVirtualDisplayInspector.onlineDisplays()
    var session: DeskMuxVirtualDisplaySession?
    var displayID: UInt32?
    var appeared = false
    var displaysDuring: [DeskMuxDisplaySnapshot] = []
    var captureCheck: DeskMuxScreenCaptureCheck?
    var errorMessage: String?

    do {
      session = try DeskMuxVirtualDisplaySession(configuration: configuration)
      if let createdID = session?.displayID {
        displayID = createdID
        appeared = await DeskMuxVirtualDisplayInspector.waitForDisplay(createdID, present: true)
        displaysDuring = DeskMuxVirtualDisplayInspector.onlineDisplays()
        captureCheck = await DeskMuxVirtualDisplayInspector.captureFirstFrame(displayID: createdID)
      }
    } catch {
      errorMessage = String(describing: error)
    }

    session?.invalidate()
    session = nil
    let disappeared =
      if let displayID {
        await DeskMuxVirtualDisplayInspector.waitForDisplay(displayID, present: false)
      } else {
        false
      }
    let report = ProbeReport(
      supported: DeskMuxVirtualDisplaySession.isSupported,
      configuration: configuration,
      displaysBefore: displaysBefore,
      virtualDisplayID: displayID,
      appeared: appeared,
      displaysDuring: displaysDuring,
      screenCapture: captureCheck,
      disappeared: disappeared,
      displaysAfter: DeskMuxVirtualDisplayInspector.onlineDisplays(),
      error: errorMessage
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(report) {
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data([0x0a]))
    }
    if errorMessage != nil || !appeared || !disappeared {
      exit(EXIT_FAILURE)
    }
  }
}
