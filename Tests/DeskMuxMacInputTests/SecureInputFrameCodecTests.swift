import CoreGraphics
import DeskMuxCore
import Foundation
import Testing

@testable import DeskMuxMacInput

@Test func encryptedMessagesRoundTripAcrossFragmentedFrames() throws {
  let sender = try SecureInputFrameCodec(
    sharedKey: "correct horse battery staple", role: .initiator)
  let receiver = try SecureInputFrameCodec(
    sharedKey: "correct horse battery staple", role: .acceptor)
  let messages: [InputWireMessage] = [
    .hello(peerID: PeerID(rawValue: "studio"), protocolVersion: 2, purpose: .inputRelay),
    .ready(peerID: PeerID(rawValue: "macbook"), motionPort: 49_876),
    .ping(42),
    .pong(42),
    .beginInput(
      sessionID: UUID(),
      mode: .keyboardOnly,
      initialModifierFlags: CGEventFlags.maskAlternate.rawValue
    ),
    .eventAck(sequence: 7, receiverProcessingNanoseconds: 123_456),
    .appUpdate(
      DeskMuxUpdatePackage(
        version: "0.1.0",
        build: "20260824175000",
        bundleIdentifier: "dev.deskmux.app",
        archiveSHA256: "fixture",
        archiveData: Data(repeating: 0xA5, count: 4_096)
      )),
    .appUpdateResult(.accepted(build: "20260824175000")),
    .clipboardUpdate(
      DeskMuxClipboardUpdate(
        id: UUID(),
        sourcePeerID: PeerID(rawValue: "studio"),
        text: "shared clipboard text"
      )),
    .clipboardUpdateApplied(UUID()),
    .goodbye,
  ]
  let wireData = try messages.reduce(into: Data()) { data, message in
    data.append(try sender.seal(message))
  }

  var parser = InputFrameParser()
  var opened: [InputWireMessage] = []
  for byte in wireData {
    for frame in try parser.append(Data([byte])) {
      opened.append(try receiver.open(frame))
    }
  }
  #expect(opened == messages)
}

@Test func pointerMotionDatagramsRecoverStateAfterLossAndRejectTampering() throws {
  let codec = try SecurePointerMotionCodec(sharedKey: "correct horse battery staple")
  let sessionID = UUID()
  let first = PointerMotionState(
    sessionID: sessionID,
    sequence: 0,
    kind: .mouseMoved,
    cumulativeDeltaX: 7,
    cumulativeDeltaY: -3
  )
  let recovered = PointerMotionState(
    sessionID: sessionID,
    sequence: 2,
    kind: .leftMouseDragged,
    cumulativeDeltaX: 19,
    cumulativeDeltaY: 4
  )

  #expect(try codec.open(codec.seal(first)) == first)
  #expect(try codec.open(codec.seal(recovered)) == recovered)

  var tampered = try codec.seal(first)
  tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
  #expect(throws: SecurePointerMotionCodecError.authenticationFailed) {
    try codec.open(tampered)
  }
}

@Test func wrongKeyAndReplayAreRejected() throws {
  let sender = try SecureInputFrameCodec(sharedKey: "one", role: .initiator)
  let wrongReceiver = try SecureInputFrameCodec(sharedKey: "two", role: .acceptor)
  let frame = try sender.seal(.goodbye)
  var parser = InputFrameParser()
  let payload = try #require(parser.append(frame).first)

  #expect(throws: SecureInputFrameError.authenticationFailed) {
    try wrongReceiver.open(payload)
  }

  let receiver = try SecureInputFrameCodec(sharedKey: "one", role: .acceptor)
  #expect(try receiver.open(payload) == .goodbye)
  #expect(throws: SecureInputFrameError.unexpectedSequence(expected: 1, received: 0)) {
    try receiver.open(payload)
  }
}

@Test func emptySharedKeyIsRejected() {
  #expect(throws: SecureInputFrameError.emptySharedKey) {
    try SecureInputFrameCodec(sharedKey: "", role: .initiator)
  }
}

@Test func reflectedFramesCannotBeOpenedByTheirSender() throws {
  let sender = try SecureInputFrameCodec(sharedKey: "shared", role: .initiator)
  let frame = try sender.seal(.goodbye)
  var parser = InputFrameParser()
  let payload = try #require(parser.append(frame).first)

  #expect(throws: SecureInputFrameError.authenticationFailed) {
    try sender.open(payload)
  }
}

// DM-016: an untrusted header must be rejected without allocating its body.
@Test func inputParserRejectsOversizedHeaderAndBuffersIncompleteFrames() throws {
  var invalidParser = InputFrameParser()
  let oversized = SecureInputFrameCodec.maximumFrameSize + 1
  var header = UInt32(oversized).bigEndian
  let bytes = withUnsafeBytes(of: &header) { Data($0) }
  #expect(try invalidParser.append(Data(bytes.prefix(3))).isEmpty)
  #expect(throws: SecureInputFrameError.frameTooLarge(oversized)) {
    try invalidParser.append(Data(bytes.suffix(1)))
  }

  let sender = try SecureInputFrameCodec(sharedKey: "synthetic", role: .initiator)
  let receiver = try SecureInputFrameCodec(sharedKey: "synthetic", role: .acceptor)
  let first = try sender.seal(.ping(1))
  let second = try sender.seal(.pong(1))
  var parser = InputFrameParser()
  #expect(try parser.append(Data(first.dropLast())).isEmpty)
  let frames = try parser.append(Data(first.suffix(1)) + second)
  #expect(try frames.map { try receiver.open($0) } == [.ping(1), .pong(1)])
  #expect(try parser.append(Data()).isEmpty)
}

// DM-017: rejection cannot consume a sequence number or poison a valid message.
@Test func inputAuthenticationAndOrderFailuresDoNotAdvanceSequence() throws {
  let sender = try SecureInputFrameCodec(sharedKey: "synthetic", role: .initiator)
  let receiver = try SecureInputFrameCodec(sharedKey: "synthetic", role: .acceptor)
  var parser = InputFrameParser()
  let frames = try parser.append(sender.seal(.ping(4)) + sender.seal(.pong(4)))
  #expect(frames.count == 2)
  #expect(throws: SecureInputFrameError.frameTooShort) { try receiver.open(Data([0])) }
  #expect(throws: SecureInputFrameError.unexpectedSequence(expected: 0, received: 1)) {
    try receiver.open(frames[1])
  }
  var corrupt = frames[0]
  corrupt[corrupt.index(before: corrupt.endIndex)] ^= 1
  #expect(throws: SecureInputFrameError.authenticationFailed) { try receiver.open(corrupt) }
  #expect(try receiver.open(frames[0]) == .ping(4))
  #expect(try receiver.open(frames[1]) == .pong(4))
}
