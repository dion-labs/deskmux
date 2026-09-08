import CoreGraphics
import DeskMuxCore
import DeskMuxMacInput
import Foundation

public enum SyntheticMotionTraceFactory {
  /// A deterministic Lissajous path whose integer deltas sum to zero. It is
  /// useful for unattended transport experiments; a natural HID trace remains
  /// the authority for pointer acceleration and subjective feel.
  public static func make(
    durationSeconds: Double = 8,
    sampleRateHz: Double = 125,
    recordedAt: Date = Date()
  ) throws -> MotionReplayTrace {
    guard durationSeconds > 0, durationSeconds <= 30,
      sampleRateHz >= 30, sampleRateHz <= 1_000
    else {
      throw SyntheticMotionTraceError.invalidParameters
    }
    let count = max(Int((durationSeconds * sampleRateHz).rounded()), 2)
    let interval = UInt64((1_000_000_000 / sampleRateHz).rounded())
    let sessionID = UUID()
    var previousX: Int64 = 0
    var previousY: Int64 = 0
    var samples: [MotionTraceSample] = []
    samples.reserveCapacity(count)

    for index in 1...count {
      let phase = 2 * Double.pi * Double(index) / Double(count)
      let x = Int64((480 * sin(phase)).rounded())
      let y = Int64((280 * sin(2 * phase)).rounded())
      guard
        let event = CGEvent(
          mouseEventSource: nil,
          mouseType: .mouseMoved,
          mouseCursorPosition: .zero,
          mouseButton: .left
        )
      else { throw SyntheticMotionTraceError.couldNotCreateEvent }
      event.setIntegerValueField(.mouseEventDeltaX, value: x - previousX)
      event.setIntegerValueField(.mouseEventDeltaY, value: y - previousY)
      let packet = try MacInputEventCodec.encode(
        event,
        sessionID: sessionID,
        sequence: UInt64(index - 1)
      )
      samples.append(
        MotionTraceSample(
          offsetNanoseconds: UInt64(index - 1) * interval,
          kind: .mouseMoved,
          eventData: packet.eventData
        ))
      previousX = x
      previousY = y
    }
    return MotionReplayTrace(recordedAt: recordedAt, samples: samples)
  }
}

public enum SyntheticMotionTraceError: Error, Equatable, Sendable {
  case invalidParameters
  case couldNotCreateEvent
}
