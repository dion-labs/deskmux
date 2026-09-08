import Foundation

public struct MotionResearchAssessment: Codable, Equatable, Sendable {
  public let sampleCount: Int
  public let expectedSampleCount: Int
  public let echoDeliveryRatio: Double
  public let medianMilliseconds: Double?
  public let p95Milliseconds: Double?
  public let p99Milliseconds: Double?
  public let maximumMilliseconds: Double?
  public let score: Double
  public let meetsNativeLatencyTarget: Bool
  public let rejectionReasons: [String]

  public static func assess(_ report: InputRelayLatencyReport) -> Self {
    let samples = report.motionRoundTripSamplesMilliseconds
    let expected = report.motionEchoesExpected
    let delivery = expected == 0 ? 0 : min(Double(samples.count) / Double(expected), 1)
    let median = percentile(samples, 0.5)
    let p95 = percentile(samples, 0.95)
    let p99 = percentile(samples, 0.99)
    let maximum = samples.max()
    var reasons: [String] = []
    if samples.count < 30 { reasons.append("fewer than 30 receiver echoes") }
    if delivery < 0.98 { reasons.append("echo delivery below 98%") }
    if median.map({ $0 > 8 }) ?? true { reasons.append("median RTT above 8 ms") }
    if p95.map({ $0 > 16.7 }) ?? true { reasons.append("p95 RTT above 16.7 ms") }
    if p99.map({ $0 > 25 }) ?? true { reasons.append("p99 RTT above 25 ms") }
    if maximum.map({ $0 > 50 }) ?? true { reasons.append("maximum RTT above 50 ms") }

    let lossPenalty = (1 - delivery) * 1_000
    let score =
      (median ?? 1_000)
      + 2 * (p95 ?? 1_000)
      + 2 * (p99 ?? 1_000)
      + 0.25 * (maximum ?? 1_000)
      + lossPenalty
    return Self(
      sampleCount: samples.count,
      expectedSampleCount: expected,
      echoDeliveryRatio: delivery,
      medianMilliseconds: median,
      p95Milliseconds: p95,
      p99Milliseconds: p99,
      maximumMilliseconds: maximum,
      score: score,
      meetsNativeLatencyTarget: reasons.isEmpty,
      rejectionReasons: reasons
    )
  }

  private static func percentile(_ samples: [Double], _ fraction: Double) -> Double? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    let position = fraction * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower != upper else { return sorted[lower] }
    let weight = position - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
  }
}
