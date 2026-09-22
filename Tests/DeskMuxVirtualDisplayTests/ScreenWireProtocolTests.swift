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

// DM-018: screen transport needs replay and direction isolation like input.
@Test func screenAuthenticationReplayAndReflectionFailWithoutConsumingSequence() throws {
  let sender = try DeskMuxSecureScreenCodec(sharedKey: "synthetic", role: .initiator)
  let receiver = try DeskMuxSecureScreenCodec(sharedKey: "synthetic", role: .acceptor)
  var parser = DeskMuxScreenFrameParser()
  let frames = try parser.append(sender.seal(.ready(sourcePeerID: "fixture")) + sender.seal(.stop))
  #expect(frames.count == 2)
  #expect(throws: (any Error).self) { try receiver.open(Data([0])) }
  #expect(throws: (any Error).self) { try receiver.open(frames[1]) }
  #expect(throws: (any Error).self) { try sender.open(frames[0]) }
  var corrupt = frames[0]
  corrupt[corrupt.index(before: corrupt.endIndex)] ^= 1
  #expect(throws: (any Error).self) { try receiver.open(corrupt) }
  #expect(try receiver.open(frames[0]) == .ready(sourcePeerID: "fixture"))
  #expect(throws: (any Error).self) { try receiver.open(frames[0]) }
  #expect(try receiver.open(frames[1]) == .stop)
}

// DM-019: oversized declarations fail without waiting for attacker payloads.
@Test func screenParserRejectsOversizedHeaderAndBuffersIncompleteFrames() throws {
  var invalidParser = DeskMuxScreenFrameParser()
  var header = UInt32(DeskMuxSecureScreenCodec.maximumFrameSize + 1).bigEndian
  let bytes = withUnsafeBytes(of: &header) { Data($0) }
  #expect(try invalidParser.append(Data(bytes.prefix(3))).isEmpty)
  #expect(throws: (any Error).self) { try invalidParser.append(Data(bytes.suffix(1))) }
  let sender = try DeskMuxSecureScreenCodec(sharedKey: "synthetic", role: .initiator)
  let receiver = try DeskMuxSecureScreenCodec(sharedKey: "synthetic", role: .acceptor)
  let wire = try sender.seal(.stop)
  var parser = DeskMuxScreenFrameParser()
  #expect(try parser.append(Data(wire.dropLast())).isEmpty)
  let frames = try parser.append(Data(wire.suffix(1)))
  #expect(frames.count == 1)
  #expect(try receiver.open(frames[0]) == .stop)
  #expect(try parser.append(Data()).isEmpty)
}

@Test func screenOversizedSealDoesNotConsumeSequence() throws {
  let sender = try DeskMuxSecureScreenCodec(sharedKey: "synthetic", role: .initiator)
  let receiver = try DeskMuxSecureScreenCodec(sharedKey: "synthetic", role: .acceptor)
  let oversized = DeskMuxScreenWireMessage.frame(DeskMuxScreenVideoFrame(
    data: Data(repeating: 0, count: DeskMuxSecureScreenCodec.maximumFrameSize),
    isKeyFrame: true, sequence: 0))
  #expect(throws: (any Error).self) { try sender.seal(oversized) }
  var parser = DeskMuxScreenFrameParser()
  let payload = try #require(parser.append(sender.seal(.stop)).first)
  #expect(try receiver.open(payload) == .stop)
}
