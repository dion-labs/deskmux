import CoreGraphics
import DeskMuxCore
import DeskMuxMacInput
import Foundation
import Testing

@testable import DeskMuxInputTransport

@Test func syntheticMotionTraceIsSafeDeterministicAndNetZero() throws {
  let trace = try SyntheticMotionTraceFactory.make(
    durationSeconds: 1,
    sampleRateHz: 125,
    recordedAt: Date(timeIntervalSince1970: 0)
  )
  #expect(trace.samples.count == 125)
  #expect(trace.samples.first?.offsetNanoseconds == 0)
  #expect(trace.samples.last?.offsetNanoseconds == 992_000_000)
  #expect(trace.samples.allSatisfy { $0.kind == .mouseMoved })

  let sessionID = UUID()
  let deltas = try trace.samples.enumerated().map { index, sample in
    let event = try MacInputEventCodec.decode(
      InputEventPacket(
        sessionID: sessionID,
        sequence: UInt64(index),
        kind: sample.kind,
        eventData: sample.eventData
      ))
    return (
      event.getIntegerValueField(.mouseEventDeltaX),
      event.getIntegerValueField(.mouseEventDeltaY)
    )
  }
  #expect(deltas.reduce(0) { $0 + $1.0 } == 0)
  #expect(deltas.reduce(0) { $0 + $1.1 } == 0)
}
