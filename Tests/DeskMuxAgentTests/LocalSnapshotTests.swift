import DeskMuxCore
import Foundation
import Testing

@testable import DeskMuxAgent

@Test func snapshotParserKeepsOnlyRoutingRelevantDisplayData() throws {
  let json = #"""
    {
      "SPHardwareDataType": [{
        "machine_model": "Mac13,2",
        "platform_UUID": "must-not-escape"
      }],
      "SPDisplaysDataType": [{
        "spdisplays_ndrvs": [{
          "_name": "VP2768",
          "_spdisplays_resolution": "2560 x 1440 @ 60.00Hz",
          "spdisplays_main": "spdisplays_yes",
          "spdisplays_online": "spdisplays_yes",
          "spdisplays_serial_number": "must-not-escape"
        }]
      }]
    }
    """#
  let date = Date(timeIntervalSince1970: 1_725_000_000)
  let snapshot = try LocalSnapshotCollector.parse(
    profilerData: Data(json.utf8),
    peerID: PeerID(rawValue: "studio"),
    observedAt: date
  )

  #expect(snapshot.machineModel == "Mac13,2")
  #expect(snapshot.peerID == PeerID(rawValue: "studio"))
  #expect(
    snapshot.displays == [
      LocalDisplaySnapshot(
        name: "VP2768",
        resolution: "2560 x 1440 @ 60.00Hz",
        isMain: true,
        isOnline: true
      )
    ])
  #expect(
    !String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("must-not-escape")
  )
}
