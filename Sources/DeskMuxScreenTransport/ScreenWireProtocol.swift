import CryptoKit
import Foundation

public struct DeskMuxScreenFormat: Codable, Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let parameterSets: [Data]

  public init(width: Int, height: Int, parameterSets: [Data]) {
    self.width = width
    self.height = height
    self.parameterSets = parameterSets
  }
}

public struct DeskMuxScreenVideoFrame: Codable, Equatable, Sendable {
  public let data: Data
  public let isKeyFrame: Bool
  public let sequence: UInt64

  public init(data: Data, isKeyFrame: Bool, sequence: UInt64) {
    self.data = data
    self.isKeyFrame = isKeyFrame
    self.sequence = sequence
  }
}

public enum DeskMuxScreenInputEvent: Codable, Equatable, Sendable {
  case pointerMove(x: Double, y: Double, draggingButton: Int?)
  case mouseButton(x: Double, y: Double, button: Int, isDown: Bool, clickCount: Int)
  case scroll(x: Double, y: Double, deltaX: Double, deltaY: Double)
  case key(keyCode: UInt16, isDown: Bool, flags: UInt64)
  case flagsChanged(keyCode: UInt16, isDown: Bool, flags: UInt64)
  case releaseAll
}

public enum DeskMuxScreenWireMessage: Codable, Equatable, Sendable {
  case hello(peerID: String, protocolVersion: Int)
  case ready(sourcePeerID: String)
  case format(DeskMuxScreenFormat)
  case frame(DeskMuxScreenVideoFrame)
  case input(DeskMuxScreenInputEvent)
  case stop
  case failure(String)

  public static let currentProtocolVersion = 1
}

enum DeskMuxScreenFrameError: Error {
  case emptySharedKey
  case frameTooLarge(Int)
  case frameTooShort
  case unexpectedSequence
  case authenticationFailed
  case malformedMessage
}

enum DeskMuxScreenChannelRole {
  case initiator
  case acceptor
}

final class DeskMuxSecureScreenCodec: @unchecked Sendable {
  static let maximumFrameSize = 4_194_304

  private let sendKey: SymmetricKey
  private let receiveKey: SymmetricKey
  private let lock = NSLock()
  private var nextSendSequence: UInt64 = 0
  private var nextReceiveSequence: UInt64 = 0
  private let encoder: PropertyListEncoder = {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return encoder
  }()
  private let decoder = PropertyListDecoder()

  init(sharedKey: String, role: DeskMuxScreenChannelRole) throws {
    guard !sharedKey.isEmpty else { throw DeskMuxScreenFrameError.emptySharedKey }
    let initiator = Self.deriveKey(sharedKey: sharedKey, context: "viewer-to-source")
    let acceptor = Self.deriveKey(sharedKey: sharedKey, context: "source-to-viewer")
    switch role {
    case .initiator:
      sendKey = initiator
      receiveKey = acceptor
    case .acceptor:
      sendKey = acceptor
      receiveKey = initiator
    }
  }

  func seal(_ message: DeskMuxScreenWireMessage) throws -> Data {
    try lock.withLock {
      let sequence = nextSendSequence
      let sequenceData = Self.encode(sequence)
      let plaintext = try encoder.encode(message)
      let box = try ChaChaPoly.seal(
        plaintext,
        using: sendKey,
        authenticating: sequenceData
      )
      var payload = sequenceData
      payload.append(box.combined)
      guard payload.count <= Self.maximumFrameSize else {
        throw DeskMuxScreenFrameError.frameTooLarge(payload.count)
      }
      nextSendSequence &+= 1
      return Self.lengthPrefix(payload.count) + payload
    }
  }

  func open(_ payload: Data) throws -> DeskMuxScreenWireMessage {
    try lock.withLock {
      guard payload.count >= 8 else { throw DeskMuxScreenFrameError.frameTooShort }
      let sequenceData = payload.prefix(8)
      let sequence = Self.decode(sequenceData)
      guard sequence == nextReceiveSequence else {
        throw DeskMuxScreenFrameError.unexpectedSequence
      }
      do {
        let box = try ChaChaPoly.SealedBox(combined: payload.dropFirst(8))
        let plaintext = try ChaChaPoly.open(
          box,
          using: receiveKey,
          authenticating: sequenceData
        )
        let message = try decoder.decode(DeskMuxScreenWireMessage.self, from: plaintext)
        nextReceiveSequence &+= 1
        return message
      } catch is DecodingError {
        throw DeskMuxScreenFrameError.malformedMessage
      } catch {
        throw DeskMuxScreenFrameError.authenticationFailed
      }
    }
  }

  private static func deriveKey(sharedKey: String, context: String) -> SymmetricKey {
    SymmetricKey(data: SHA256.hash(data: Data("DeskMux/screen/v1/\(context)/\(sharedKey)".utf8)))
  }

  private static func encode(_ value: UInt64) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
  }

  private static func decode(_ data: Data.SubSequence) -> UInt64 {
    data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }

  private static func lengthPrefix(_ count: Int) -> Data {
    var bigEndian = UInt32(count).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
  }
}

struct DeskMuxScreenFrameParser {
  private var buffer = Data()

  mutating func append(_ data: Data) throws -> [Data] {
    buffer.append(data)
    var frames: [Data] = []
    while buffer.count >= 4 {
      let length = buffer.prefix(4).reduce(Int(0)) { ($0 << 8) | Int($1) }
      guard length <= DeskMuxSecureScreenCodec.maximumFrameSize else {
        throw DeskMuxScreenFrameError.frameTooLarge(length)
      }
      guard buffer.count >= length + 4 else { break }
      let start = buffer.index(buffer.startIndex, offsetBy: 4)
      let end = buffer.index(start, offsetBy: length)
      frames.append(Data(buffer[start..<end]))
      buffer.removeSubrange(buffer.startIndex..<end)
    }
    return frames
  }
}
