import DeskMuxCore
import Foundation
import Testing
@testable import DeskMuxInputTransport

// DM-036: exercise reconnect state without reading or writing NSPasteboard.general.
@Test func clipboardUnsupportedReplacementCannotReplayEarlierText() {
  var observation = DeskMuxClipboardObservation()
  let changed1 = observation.observe(changeCount: 10)
  #expect(changed1 == false) // Startup does not share old contents.
  #expect(observation.pendingLocalUpdate == nil)
  let changed2 = observation.observe(changeCount: 11)
  #expect(changed2 == true)
  let text = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"), text: "synthetic")
  observation.recordLocal(text)
  #expect(observation.pendingLocalUpdate == text)
  let changed3 = observation.observe(changeCount: 11)
  #expect(changed3 == false)
  #expect(observation.pendingLocalUpdate == text) // Reconnect can resend unchanged text.
  let changed4 = observation.observe(changeCount: 12)
  #expect(changed4 == true) // New image/file/cleared clipboard has no text.
  #expect(observation.pendingLocalUpdate == nil)
  let changed5 = observation.observe(changeCount: 12)
  #expect(changed5 == false)
  #expect(observation.pendingLocalUpdate == nil)
}

@Test func clipboardOversizedReplacementInvalidatesPendingTextAndCanRecover() {
  var observation = DeskMuxClipboardObservation()
  _ = observation.observe(changeCount: 1)
  let changed6 = observation.observe(changeCount: 2)
  #expect(changed6 == true)
  let text = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"), text: "synthetic")
  observation.recordLocal(text)
  let changed7 = observation.observe(changeCount: 3)
  #expect(changed7 == true)
  let oversized = DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"),
    text: String(repeating: "é", count: DeskMuxClipboardUpdate.maximumUTF8Size / 2 + 1))
  observation.recordLocal(oversized)
  #expect(observation.pendingLocalUpdate == nil)
  let changed8 = observation.observe(changeCount: 4)
  #expect(changed8 == true)
  observation.recordLocal(text)
  #expect(observation.pendingLocalUpdate == text)
}

@Test func clipboardRemoteApplicationSuppressesEchoAndClearsReconnectState() {
  var observation = DeskMuxClipboardObservation()
  _ = observation.observe(changeCount: 1)
  let changed9 = observation.observe(changeCount: 2)
  #expect(changed9 == true)
  observation.recordLocal(DeskMuxClipboardUpdate(sourcePeerID: PeerID(rawValue: "fixture"), text: "synthetic"))
  observation.appliedRemote(changeCount: 3)
  #expect(observation.pendingLocalUpdate == nil)
  let changed10 = observation.observe(changeCount: 3)
  #expect(changed10 == false)
  let changed11 = observation.observe(changeCount: 4)
  #expect(changed11 == true)
}
