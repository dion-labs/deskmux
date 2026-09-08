import DeskMuxCore
import Foundation

final class MotionTraceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private let recordedAt = Date()
  private var firstSampleAt: UInt64?
  private var samples: [MotionTraceSample] = []

  func record(_ packet: InputEventPacket, at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
    guard Self.isMotion(packet.kind) else { return }
    lock.withLock {
      let origin = firstSampleAt ?? now
      firstSampleAt = origin
      samples.append(
        MotionTraceSample(
          offsetNanoseconds: now >= origin ? now - origin : 0,
          kind: packet.kind,
          eventData: packet.eventData
        ))
    }
  }

  var trace: MotionReplayTrace {
    lock.withLock {
      MotionReplayTrace(recordedAt: recordedAt, samples: samples)
    }
  }

  private static func isMotion(_ kind: InputEventKind) -> Bool {
    kind == .mouseMoved
  }
}
