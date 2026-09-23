import Foundation
import HealthProviding
import SleepKit

public enum InsightCategory: String, Sendable, CaseIterable {
    case sleep
    case recovery
    case timing
    case consistency
    case longTerm

    public var displayName: String {
        switch self {
        case .sleep: "Sleep"
        case .recovery: "Recovery"
        case .timing: "Timing"
        case .consistency: "Consistency"
        case .longTerm: "Long-Term"
        }
    }
}

public struct InsightEvidencePoint: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct Insight: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Stable identifier for "this same detector's finding," independent of
    /// `id` (which is fresh every generation). Fatigue/novelty tracking
    /// keys off this, not `id` or `title` (title text can vary by direction,
    /// e.g. "increased" vs "decreased").
    public let kind: String
    public let category: InsightCategory
    public let title: String
    public let evidence: [InsightEvidencePoint]
    public let context: String
    public let interpretation: String
    public let whatToNotice: String
    public let suggestion: String?
    public let confidence: DataConfidence
    public let generatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: String,
        category: InsightCategory,
        title: String,
        evidence: [InsightEvidencePoint],
        context: String,
        interpretation: String,
        whatToNotice: String,
        suggestion: String? = nil,
        confidence: DataConfidence,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.category = category
        self.title = title
        self.evidence = evidence
        self.context = context
        self.interpretation = interpretation
        self.whatToNotice = whatToNotice
        self.suggestion = suggestion
        self.confidence = confidence
        self.generatedAt = generatedAt
    }

    public static func == (lhs: Insight, rhs: Insight) -> Bool { lhs.id == rhs.id }
}

public struct ScoredSession: Sendable {
    public let session: SleepSession
    public let quality: SleepQualityBreakdown

    public init(session: SleepSession, quality: SleepQualityBreakdown) {
        self.session = session
        self.quality = quality
    }
}

public struct RecoveryHistoryPoint: Sendable {
    public let date: Date
    public let score: Int

    public init(date: Date, score: Int) {
        self.date = date
        self.score = score
    }
}
