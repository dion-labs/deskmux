import CoreGraphics

public enum MacInputCaptureScope: String, Codable, Equatable, Sendable {
  case allInput
  case keyboardOnly

  public var eventTypes: [CGEventType] {
    switch self {
    case .allInput: return MacInputEventMask.relayTypes
    case .keyboardOnly: return MacInputEventMask.keyboardTypes
    }
  }

  public var eventMask: CGEventMask {
    eventTypes.reduce(0) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }
  }

  public func includes(_ type: CGEventType) -> Bool {
    eventTypes.contains(type)
  }
}

public enum MacInputEventMask {
  public static let keyboardTypes: [CGEventType] = [
    .keyDown,
    .keyUp,
    .flagsChanged,
  ]

  public static let relayTypes: [CGEventType] = [
    .keyDown,
    .keyUp,
    .flagsChanged,
    .mouseMoved,
    .leftMouseDown,
    .leftMouseUp,
    .leftMouseDragged,
    .rightMouseDown,
    .rightMouseUp,
    .rightMouseDragged,
    .otherMouseDown,
    .otherMouseUp,
    .otherMouseDragged,
    .scrollWheel,
  ]

  public static let relay: CGEventMask = relayTypes.reduce(0) { mask, type in
    mask | (CGEventMask(1) << type.rawValue)
  }

  public static let keyboard: CGEventMask = MacInputCaptureScope.keyboardOnly.eventMask
}
