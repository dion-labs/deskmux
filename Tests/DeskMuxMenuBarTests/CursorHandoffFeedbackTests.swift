import AppKit
import Testing

@testable import DeskMuxMenuBar

@Test func cursorCueStaysInsideDisplayAtEveryCorner() {
  let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
  for point in [
    NSPoint(x: 0, y: 0), NSPoint(x: 0, y: 1080),
    NSPoint(x: 1920, y: 0), NSPoint(x: 1920, y: 1080),
  ] {
    let frame = CursorHandoffLayout.frame(near: point, within: screen)
    #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
  }
}

@Test func cursorCueAppearsInwardFromLeftAndRightEdges() {
  let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
  let left = CursorHandoffLayout.frame(near: NSPoint(x: 1, y: 500), within: screen)
  let right = CursorHandoffLayout.frame(near: NSPoint(x: 1919, y: 500), within: screen)
  #expect(left.minX > 1)
  #expect(right.maxX < 1919)
}

@Test func cursorCueSupportsDisplaysLeftOfAndBelowPrimary() {
  let screen = NSRect(x: -1920, y: -1080, width: 1920, height: 1080)
  let frame = CursorHandoffLayout.frame(near: NSPoint(x: -1919, y: -540), within: screen)
  #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
  #expect(frame.minX > -1919)
}

@Test func acceptedMouseCommandDoesNotClaimReconnection() {
  #expect(CursorHandoffPhase.sent.detail == "Switch sent · mouse reconnecting…")
  #expect(CursorHandoffPhase.failed.detail == "Check DeskMux for details")
}

@Test func permissionHelperTargetsTheBundledStableAgent() {
  let appURL = URL(fileURLWithPath: "/Applications/DeskMux.app", isDirectory: true)
  let agentURL = DeskMuxPermissionComponent.agent.bundleURL(mainBundleURL: appURL)

  #expect(
    agentURL.path
      == "/Applications/DeskMux.app/Contents/Library/LoginItems/DeskMux Agent.app"
  )
}

@Test func permissionHelperNamesTheExactDropDestination() {
  let request = DeskMuxPermissionAssistantRequest(
    pane: .screenRecording,
    component: .agent
  )

  #expect(
    request.instruction
      == "Drag DeskMux Agent into the Screen & System Audio Recording list"
  )
  #expect(DeskMuxPermissionPane.accessibility.settingsPane == "Privacy_Accessibility")
  #expect(DeskMuxPermissionPane.inputMonitoring.settingsPane == "Privacy_ListenEvent")
}
