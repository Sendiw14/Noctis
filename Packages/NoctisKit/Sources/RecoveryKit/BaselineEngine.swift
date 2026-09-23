import Foundation
import HealthProviding

public struct Baseline: Sendable, Equatable {
    public let averageValue: Double?
    public let sampleCount: Int
    public let confidence: DataConfidence

    public init(averageValue: Double?, sampleCount: Int, confidence: DataConfidence) {
        self.averageValue = averageValue
        self.sampleCount = sampleCount
        self.confidence = confidence
    }
}

/// Rolling personal baselines. Never a fixed population norm — every
/// comparison in NOCTIS is "you, compared with your own recent history."
public enum BaselineEngine {
    public static let windowDays = 30

    public static func baseline(from values: [Double], fullAt: Int = windowDays) -> Baseline {
        guard !values.isEmpty else { return Baseline(averageValue: nil, sampleCount: 0, confidence: .low) }
        let average = values.reduce(0, +) / Double(values.count)
        return Baseline(averageValue: average, sampleCount: values.count, confidence: .forSampleCount(values.count, fullAt: fullAt))
    }
}
