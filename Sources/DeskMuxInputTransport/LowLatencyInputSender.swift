import CoreGraphics
import DeskMuxCore
import DeskMuxMacInput
import Foundation

/// Keeps reliable input ordered while preventing high-rate pointer samples from
/// building a stale TCP backlog. Pointer deltas are accumulated and emitted at
/// most once per display-frame-sized interval.
final class LowLatencyInputSender: @unchecked Sendable {
  typealias PacketSender = @Sendable (InputEventPacket) throws -> Void
  typealias MotionSender = @Sendable (InputEventPacket) throws -> Void
  typealias FailureHandler = @Sendable (Error) -> Void

  private let interval: TimeInterval
  private let preferredMaximumUnacknowledgedPackets: Int
  private let packetSender: PacketSender
  private let motionSender: MotionSender?
  private let failureHandler: FailureHandler
  private let queue = DispatchQueue(label: "dev.deskmux.input.motion", qos: .userInteractive)
  private let condition = NSCondition()
  private var pendingMotion: InputEventPacket?
  private var unacknowledgedSequences = Set<UInt64>()
  private var activeMaximumUnacknowledgedPackets: Int
  private var nextReliableSequence: UInt64 = 0
  private var nextMotionSequence: UInt64 = 0
  private var flushGeneration: UInt64 = 0
  private var flushScheduled = false
  private var stopped = false

  init(
    maximumMotionRate: Double = 120,
    maximumUnacknowledgedPackets: Int = 8,
    preferredMaximumUnacknowledgedPackets: Int = 2,
    packetSender: @escaping PacketSender,
    motionSender: MotionSender? = nil,
    failureHandler: @escaping FailureHandler
  ) {
    interval = 1 / max(maximumMotionRate, 1)
    activeMaximumUnacknowledgedPackets = max(maximumUnacknowledgedPackets, 1)
    self.preferredMaximumUnacknowledgedPackets =
      max(min(preferredMaximumUnacknowledgedPackets, maximumUnacknowledgedPackets), 1)
    self.packetSender = packetSender
    self.motionSender = motionSender
    self.failureHandler = failureHandler
  }

  @discardableResult
  func submit(_ packet: InputEventPacket) -> Bool {
    var immediate: [InputEventPacket] = []
    var scheduledGeneration: UInt64?
    let accepted = condition.withLock { () -> Bool in
      guard !stopped else { return false }
      if Self.isPointerMotion(packet.kind), motionSender != nil {
        if let pendingMotion { immediate.append(resequence(pendingMotion)) }
        pendingMotion = nil
        flushScheduled = false
        flushGeneration &+= 1
        immediate.append(resequence(packet))
      } else if Self.isCoalescible(packet.kind) {
        if let pendingMotion,
          let merged = Self.mergeCoalescible(pendingMotion, packet)
        {
          self.pendingMotion = merged
        } else {
          if let pendingMotion { immediate.append(resequence(pendingMotion)) }
          pendingMotion = packet
        }
        if !flushScheduled {
          flushScheduled = true
          flushGeneration &+= 1
          scheduledGeneration = flushGeneration
        }
      } else {
        if let pendingMotion { immediate.append(resequence(pendingMotion)) }
        pendingMotion = nil
        flushScheduled = false
        flushGeneration &+= 1
        immediate.append(resequence(packet))
      }
      return true
    }

    if !immediate.isEmpty { enqueue(immediate) }
    if let scheduledGeneration {
      queue.asyncAfter(deadline: .now() + interval) { [weak self] in
        self?.flushScheduledMotion(generation: scheduledGeneration)
      }
    }
    return accepted
  }

  /// Drains all already-enqueued reliable packets and the newest pointer state.
  func flush() {
    let finalMotion = condition.withLock { () -> InputEventPacket? in
      guard !stopped else { return nil }
      defer {
        pendingMotion = nil
        flushScheduled = false
        flushGeneration &+= 1
      }
      return pendingMotion.map(resequence)
    }
    queue.sync {
      if let finalMotion { send([finalMotion]) }
    }
  }

  func stop(discardPending: Bool) {
    condition.withLock {
      guard !stopped else { return }
      stopped = true
      if discardPending { pendingMotion = nil }
      flushScheduled = false
      flushGeneration &+= 1
      unacknowledgedSequences.removeAll()
      condition.broadcast()
    }
  }

  /// Receiver acknowledgements are cumulative. Limiting unacknowledged sends
  /// prevents stale pointer samples from filling TCP while the destination is
  /// briefly unable to inject events.
  func acknowledge(through sequence: UInt64) {
    condition.withLock {
      let acknowledged = unacknowledgedSequences.filter { $0 <= sequence }
      unacknowledgedSequences.subtract(acknowledged)
      // Protocol-v3 receivers originally acknowledged only sequence numbers
      // divisible by eight. Acknowledgement of any other sequence proves the
      // receiver supports per-packet flow control, so the pipeline can shrink
      // to the low-latency limit without breaking older installed agents.
      if !sequence.isMultiple(of: 8) {
        activeMaximumUnacknowledgedPackets = preferredMaximumUnacknowledgedPackets
      }
      if !acknowledged.isEmpty { condition.broadcast() }
    }
  }

  private func flushScheduledMotion(generation: UInt64) {
    let packet = condition.withLock { () -> InputEventPacket? in
      guard !stopped, flushScheduled, flushGeneration == generation,
        let pendingMotion
      else { return nil }
      self.pendingMotion = nil
      flushScheduled = false
      return resequence(pendingMotion)
    }
    if let packet { send([packet]) }
  }

  private func enqueue(_ packets: [InputEventPacket]) {
    queue.async { [weak self] in self?.send(packets) }
  }

  private func send(_ packets: [InputEventPacket]) {
    do {
      for packet in packets {
        if Self.isPointerMotion(packet.kind), let motionSender {
          try motionSender(packet)
          continue
        }
        condition.lock()
        while !stopped
          && unacknowledgedSequences.count >= activeMaximumUnacknowledgedPackets
        {
          condition.wait()
        }
        guard !stopped else {
          condition.unlock()
          return
        }
        unacknowledgedSequences.insert(packet.sequence)
        condition.unlock()
        do {
          try packetSender(packet)
        } catch {
          condition.withLock {
            unacknowledgedSequences.remove(packet.sequence)
            condition.broadcast()
          }
          throw error
        }
      }
    } catch {
      stop(discardPending: true)
      failureHandler(error)
    }
  }

  private func resequence(_ packet: InputEventPacket) -> InputEventPacket {
    let sequence: UInt64
    if Self.isPointerMotion(packet.kind), motionSender != nil {
      sequence = nextMotionSequence
      nextMotionSequence &+= 1
    } else {
      sequence = nextReliableSequence
      nextReliableSequence &+= 1
    }
    return InputEventPacket(
      sessionID: packet.sessionID,
      sequence: sequence,
      kind: packet.kind,
      eventData: packet.eventData
    )
  }

  private static func isCoalescible(_ kind: InputEventKind) -> Bool {
    switch kind {
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
      .scrollWheel:
      return true
    default:
      return false
    }
  }

  private static func isPointerMotion(_ kind: InputEventKind) -> Bool {
    switch kind {
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      return true
    default:
      return false
    }
  }

  private static func mergeCoalescible(
    _ earlier: InputEventPacket,
    _ later: InputEventPacket
  ) -> InputEventPacket? {
    guard earlier.sessionID == later.sessionID, earlier.kind == later.kind,
      let earlierEvent = try? MacInputEventCodec.decode(earlier),
      let laterEvent = try? MacInputEventCodec.decode(later)
    else { return nil }
    if later.kind == .scrollWheel {
      let fields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventDeltaAxis3,
        .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis3,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventPointDeltaAxis2,
        .scrollWheelEventPointDeltaAxis3,
      ]
      for field in fields {
        let combined =
          earlierEvent.getIntegerValueField(field)
          + laterEvent.getIntegerValueField(field)
        laterEvent.setIntegerValueField(field, value: combined)
      }
    } else {
      let deltaX =
        earlierEvent.getIntegerValueField(.mouseEventDeltaX)
        + laterEvent.getIntegerValueField(.mouseEventDeltaX)
      let deltaY =
        earlierEvent.getIntegerValueField(.mouseEventDeltaY)
        + laterEvent.getIntegerValueField(.mouseEventDeltaY)
      laterEvent.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
      laterEvent.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
    }
    guard let data = laterEvent.data else { return nil }
    return InputEventPacket(
      sessionID: later.sessionID,
      sequence: later.sequence,
      kind: later.kind,
      eventData: data as Data
    )
  }
}
