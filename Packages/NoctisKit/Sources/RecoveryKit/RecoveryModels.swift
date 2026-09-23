import Foundation
import HealthProviding

public enum RecoveryFactorKind: String, Sendable, CaseIterable, Identifiable {
    case sleep
    case hrv
    case restingHeartRate
    case consistency
    case load

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sleep: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .consistency: "Consistency"
        case .load: "Recent Load"
        }
    }

    public var systemImage: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .hrv: "waveform.path.ecg"
        case .restingHeartRate: "heart.fill"
        case .consistency: "repeat.circle.fill"
        case .load: "figure.run"
        }
    }
}

public struct RecoveryFactor: Sendable, Equatable, Identifiable {
    public let kind: RecoveryFactorKind
    public let score: Int
    public let currentValue: Double?
    public let baselineValue: Double?
    public let unit: String
    public let confidence: DataConfidence

    public var id: RecoveryFactorKind { kind }

    public init(kind: RecoveryFactorKind, score: Int, currentValue: Double?, baselineValue: Double?, unit: String, confidence: DataConfidence) {
        self.kind = kind
        self.score = score
        self.currentValue = currentValue
        self.baselineValue = baselineValue
        self.unit = unit
        self.confidence = confidence
    }
}

public struct RecoveryScore: Sendable, Equatable {
    public let overall: Int
    public let factors: [RecoveryFactor]
    public let confidence: DataConfidence
    public let modelVersion: Int
    public let computedAt: Date
    public let deltaVsRecentBaseline: Int?

    public init(overall: Int, factors: [RecoveryFactor], confidence: DataConfidence, modelVersion: Int, computedAt: Date, deltaVsRecentBaseline: Int?) {
        self.overall = overall
        self.factors = factors
        self.confidence = confidence
        self.modelVersion = modelVersion
        self.computedAt = computedAt
        self.deltaVsRecentBaseline = deltaVsRecentBaseline
    }
}

public struct RecoveryInput: Sendable {
    public var sleepQualityOverall: Int?
    public var sleepHours: Double?
    public var hrvToday: Double?
    public var hrvBaseline: Baseline?
    public var restingHRToday: Double?
    public var restingHRBaseline: Baseline?
    public var consistencyScore: Int?
    public var loadScore: Int?
    public var recentAverageRecovery: Double?

    public init(
        sleepQualityOverall: Int? = nil,
        sleepHours: Double? = nil,
        hrvToday: Double? = nil,
        hrvBaseline: Baseline? = nil,
        restingHRToday: Double? = nil,
        restingHRBaseline: Baseline? = nil,
        consistencyScore: Int? = nil,
        loadScore: Int? = nil,
        recentAverageRecovery: Double? = nil
    ) {
        self.sleepQualityOverall = sleepQualityOverall
        self.sleepHours = sleepHours
        self.hrvToday = hrvToday
        self.hrvBaseline = hrvBaseline
        self.restingHRToday = restingHRToday
        self.restingHRBaseline = restingHRBaseline
        self.consistencyScore = consistencyScore
        self.loadScore = loadScore
        self.recentAverageRecovery = recentAverageRecovery
    }
}
