import CryptoKit
import DeskMuxCore
import Foundation

public enum SecureInputFrameError: Error, Equatable, Sendable {
  case emptySharedKey
  case frameTooLarge(Int)
  case frameTooShort
  case unexpectedSequence(expected: UInt64, received: UInt64)
  case authenticationFailed
  case malformedMessage
}

public enum SecureChannelRole: Sendable {
  case initiator
  case acceptor
}

public final class SecureInputFrameCodec: @unchecked Sendable {
  public static let maximumFrameSize = 16_777_216

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

  public init(sharedKey: String, role: SecureChannelRole) throws {
    guard !sharedKey.isEmpty else { throw SecureInputFrameError.emptySharedKey }
    let initiatorKey = Self.deriveKey(sharedKey: sharedKey, context: "initiator-to-acceptor")
    let acceptorKey = Self.deriveKey(sharedKey: sharedKey, context: "acceptor-to-initiator")
    switch role {
    case .initiator:
      sendKey = initiatorKey
      receiveKey = acceptorKey
    case .acceptor:
      sendKey = acceptorKey
      receiveKey = initiatorKey
    }
  }

  public func seal(_ message: InputWireMessage) throws -> Data {
    try lock.withLock {
      let sequence = nextSendSequence
      let sequenceData = Self.encode(sequence)
      let plaintext = try encoder.encode(message)
      let sealed = try ChaChaPoly.seal(
        plaintext,
        using: sendKey,
        authenticating: sequenceData
      )
      let combined = sealed.combined
      var payload = sequenceData
      payload.append(combined)
      guard payload.count <= Self.maximumFrameSize else {
        throw SecureInputFrameError.frameTooLarge(payload.count)
      }
      nextSendSequence += 1
      return Self.lengthPrefix(payload.count) + payload
    }
  }

  public func open(_ payload: Data) throws -> InputWireMessage {
    try lock.withLock {
      guard payload.count >= 8 else { throw SecureInputFrameError.frameTooShort }
      let sequenceData = payload.prefix(8)
      let sequence = Self.decode(sequenceData)
      guard sequence == nextReceiveSequence else {
        throw SecureInputFrameError.unexpectedSequence(
          expected: nextReceiveSequence,
          received: sequence
        )
      }
      do {
        let box = try ChaChaPoly.SealedBox(combined: payload.dropFirst(8))
        let plaintext = try ChaChaPoly.open(
          box,
          using: receiveKey,
          authenticating: sequenceData
        )
        let message = try decoder.decode(InputWireMessage.self, from: plaintext)
        nextReceiveSequence += 1
        return message
      } catch let error as SecureInputFrameError {
        throw error
      } catch is DecodingError {
        throw SecureInputFrameError.malformedMessage
      } catch {
        throw SecureInputFrameError.authenticationFailed
      }
    }
  }

  private static func encode(_ value: UInt64) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
  }

  private static func deriveKey(sharedKey: String, context: String) -> SymmetricKey {
    let material = Data("DeskMux/v1/\(context)/\(sharedKey)".utf8)
    return SymmetricKey(data: Data(SHA256.hash(data: material)))
  }

  private static func decode(_ data: Data.SubSequence) -> UInt64 {
    data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }

  private static func lengthPrefix(_ count: Int) -> Data {
    var bigEndian = UInt32(count).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
  }
}

public struct InputFrameParser: Sendable {
  private var buffer = Data()

  public init() {}

  public mutating func append(_ data: Data) throws -> [Data] {
    buffer.append(data)
    var frames: [Data] = []
    while buffer.count >= 4 {
      let length = buffer.prefix(4).reduce(Int(0)) { ($0 << 8) | Int($1) }
      guard length <= SecureInputFrameCodec.maximumFrameSize else {
        throw SecureInputFrameError.frameTooLarge(length)
      }
      guard buffer.count >= 4 + length else { break }
      let frameStart = buffer.index(buffer.startIndex, offsetBy: 4)
      let frameEnd = buffer.index(frameStart, offsetBy: length)
      frames.append(Data(buffer[frameStart..<frameEnd]))
      buffer.removeSubrange(buffer.startIndex..<frameEnd)
    }
    return frames
  }
}
