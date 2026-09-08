import CryptoKit
import DeskMuxCore
import Foundation

public enum SecurePointerMotionCodecError: Error, Equatable, Sendable {
  case emptySharedKey
  case datagramTooLarge(Int)
  case authenticationFailed
  case malformedState
}

/// Authenticated datagrams intentionally have no transport-order counter.
/// PointerMotionState.sequence provides replay and reordering protection after
/// decryption while still allowing packet loss.
public final class SecurePointerMotionCodec: @unchecked Sendable {
  public static let maximumDatagramSize = 1_200

  private let key: SymmetricKey
  private let lock = NSLock()
  private let encoder: PropertyListEncoder = {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return encoder
  }()
  private let decoder = PropertyListDecoder()

  public init(sharedKey: String) throws {
    guard !sharedKey.isEmpty else { throw SecurePointerMotionCodecError.emptySharedKey }
    let material = Data("DeskMux/v1/pointer-motion/\(sharedKey)".utf8)
    key = SymmetricKey(data: Data(SHA256.hash(data: material)))
  }

  public func seal(_ state: PointerMotionState) throws -> Data {
    try lock.withLock {
      let plaintext = try encoder.encode(state)
      let datagram = try ChaChaPoly.seal(plaintext, using: key).combined
      guard datagram.count <= Self.maximumDatagramSize else {
        throw SecurePointerMotionCodecError.datagramTooLarge(datagram.count)
      }
      return datagram
    }
  }

  public func open(_ datagram: Data) throws -> PointerMotionState {
    try lock.withLock {
      guard datagram.count <= Self.maximumDatagramSize else {
        throw SecurePointerMotionCodecError.datagramTooLarge(datagram.count)
      }
      do {
        let box = try ChaChaPoly.SealedBox(combined: datagram)
        let plaintext = try ChaChaPoly.open(box, using: key)
        return try decoder.decode(PointerMotionState.self, from: plaintext)
      } catch is DecodingError {
        throw SecurePointerMotionCodecError.malformedState
      } catch let error as SecurePointerMotionCodecError {
        throw error
      } catch {
        throw SecurePointerMotionCodecError.authenticationFailed
      }
    }
  }
}
