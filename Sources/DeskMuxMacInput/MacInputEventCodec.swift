import CoreGraphics
import DeskMuxCore
import Foundation

public enum MacInputCodecError: Error, Equatable, Sendable {
  case unsupportedEventType(UInt32)
  case eventCouldNotBeFlattened
  case eventCouldNotBeRestored
}

public enum MacInputEventCodec {
  // Marks events injected by DeskMux so a local capture tap never relays them again.
  public static let injectedEventMarker: Int64 = 0x4445_534B_4D55_58

  public static func encode(
    _ event: CGEvent,
    sessionID: UUID,
    sequence: UInt64
  ) throws -> InputEventPacket {
    let kind = try kind(for: event.type)
    guard let flattened = event.data else { throw MacInputCodecError.eventCouldNotBeFlattened }
    return InputEventPacket(
      sessionID: sessionID,
      sequence: sequence,
      kind: kind,
      eventData: flattened as Data
    )
  }

  public static func decode(_ packet: InputEventPacket) throws -> CGEvent {
    guard
      let event = CGEvent(
        withDataAllocator: nil,
        data: packet.eventData as CFData
      )
    else {
      throw MacInputCodecError.eventCouldNotBeRestored
    }
    // CGEvent timestamps are relative to the source Mac's uptime and are not
    // meaningful on another machine.
    event.timestamp = CGEvent(source: nil)?.timestamp ?? 0
    event.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
    return event
  }

  public static func isInjectedByDeskMux(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == injectedEventMarker
  }

  public static func kind(for type: CGEventType) throws -> InputEventKind {
    switch type {
    case .keyDown: return .keyDown
    case .keyUp: return .keyUp
    case .flagsChanged: return .flagsChanged
    case .mouseMoved: return .mouseMoved
    case .leftMouseDown: return .leftMouseDown
    case .leftMouseUp: return .leftMouseUp
    case .leftMouseDragged: return .leftMouseDragged
    case .rightMouseDown: return .rightMouseDown
    case .rightMouseUp: return .rightMouseUp
    case .rightMouseDragged: return .rightMouseDragged
    case .otherMouseDown: return .otherMouseDown
    case .otherMouseUp: return .otherMouseUp
    case .otherMouseDragged: return .otherMouseDragged
    case .scrollWheel: return .scrollWheel
    default: throw MacInputCodecError.unsupportedEventType(type.rawValue)
    }
  }

  public static func post(_ packet: InputEventPacket) throws {
    try decode(packet).post(tap: .cghidEventTap)
  }

}
