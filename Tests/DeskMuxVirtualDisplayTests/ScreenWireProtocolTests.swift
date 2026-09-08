@testable import DeskMuxScreenTransport
import Foundation
import Testing

@Test func encryptedScreenMessagesRoundTripAcrossFragmentedFrames() throws {
  let sender = try DeskMuxSecureScreenCodec(sharedKey: "test-screen-key", role: .initiator)
  let receiver = try DeskMuxSecureScreenCodec(sharedKey: "test-screen-key", role: .acceptor)
  let expected = DeskMuxScreenWireMessage.frame(
    DeskMuxScreenVideoFrame(
      data: Data(repeating: 0x5a, count: 4096),
      isKeyFrame: true,
      sequence: 4
    )
  )
  let sealed = try sender.seal(expected)
  var parser = DeskMuxScreenFrameParser()
  var payloads: [Data] = []
  for byte in sealed {
    payloads.append(contentsOf: try parser.append(Data([byte])))
  }
  #expect(payloads.count == 1)
  #expect(try receiver.open(payloads[0]) == expected)
}

@Test func screenCodecRejectsWrongKeys() throws {
  let sender = try DeskMuxSecureScreenCodec(sharedKey: "first-screen-key", role: .initiator)
  let receiver = try DeskMuxSecureScreenCodec(sharedKey: "second-screen-key", role: .acceptor)
  let sealed = try sender.seal(.stop)
  var parser = DeskMuxScreenFrameParser()
  let payload = try #require(parser.append(sealed).first)
  #expect(throws: (any Error).self) { try receiver.open(payload) }
}
