import Foundation
import InsightsKit
import SwiftData

/// Persisted record of when a given insight *kind* (see `Insight.kind`) was
/// last shown, and how often — the state `InsightEngine` itself deliberately
/// has nowhere to keep, since it stays a pure, stateless function.
@Model
public final class InsightFatigueRecord {
    @Attribute(.unique) public var insightKind: String = ""
    public var firstShownAt: Date = Date.now
    public var lastShownAt: Date = Date.now
    public var timesShown: Int = 0

    public init(insightKind: String, firstShownAt: Date, lastShownAt: Date, timesShown: Int) {
        self.insightKind = insightKind
        self.firstShownAt = firstShownAt
        self.lastShownAt = lastShownAt
        self.timesShown = timesShown
    }
}

public enum InsightNovelty: Sendable, Equatable {
    /// Never recorded before.
    case new
    /// Recorded before, but not within the repeat window — safe to
    /// resurface as if fresh.
    case recurring
    /// Recorded within the repeat window — showing it again risks
    /// insight fatigue.
    case repeatedRecently
}

public struct InsightRelevance: Sendable, Equatable {
    public let insight: Insight
    public let novelty: InsightNovelty
    public let timesShownRecently: Int
    public let lastShownAt: Date?

    public init(insight: Insight, novelty: InsightNovelty, timesShownRecently: Int, lastShownAt: Date?) {
        self.insight = insight
        self.novelty = novelty
        self.timesShownRecently = timesShownRecently
        self.lastShownAt = lastShownAt
    }

    /// A single, obvious relevance signal for a future UI pass to filter or
    /// de-prioritize on — not consulted by any view yet.
    public var isWorthShowingProminently: Bool {
        novelty != .repeatedRecently
    }
}

/// Tracks last-shown/frequency per insight kind so a future pass can avoid
/// showing the same finding every single day. Read-only for `InsightEngine`
/// — this store is consulted and updated by `AppModel`, never by the engine
/// itself, which stays pure and stateless.
public final class InsightFatigueStore {
    private let context: ModelContext
    private let repeatWindow: TimeInterval

    public init(context: ModelContext, repeatWindow: TimeInterval = 3 * 24 * 3600) {
        self.context = context
        self.repeatWindow = repeatWindow
    }

    public func relevance(for insights: [Insight], asOf date: Date = .now) -> [InsightRelevance] {
        insights.map { insight in
            guard let record = fetchRecord(kind: insight.kind) else {
                return InsightRelevance(insight: insight, novelty: .new, timesShownRecently: 0, lastShownAt: nil)
            }
            let sinceLastShown = date.timeIntervalSince(record.lastShownAt)
            let novelty: InsightNovelty = sinceLastShown < repeatWindow ? .repeatedRecently : .recurring
            return InsightRelevance(insight: insight, novelty: novelty, timesShownRecently: record.timesShown, lastShownAt: record.lastShownAt)
        }
    }

    public func recordShown(_ insights: [Insight], on date: Date = .now) {
        guard !insights.isEmpty else { return }
        for insight in insights {
            if let record = fetchRecord(kind: insight.kind) {
                record.lastShownAt = date
                record.timesShown += 1
            } else {
                context.insert(InsightFatigueRecord(insightKind: insight.kind, firstShownAt: date, lastShownAt: date, timesShown: 1))
            }
        }
        try? context.save()
    }

    private func fetchRecord(kind: String) -> InsightFatigueRecord? {
        let descriptor = FetchDescriptor<InsightFatigueRecord>(predicate: #Predicate { $0.insightKind == kind })
        return try? context.fetch(descriptor).first
    }
}
