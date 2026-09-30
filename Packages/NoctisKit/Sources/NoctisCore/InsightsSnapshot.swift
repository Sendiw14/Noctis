import Foundation
import InsightsKit
import SleepKit

/// Everything the Insights tab, its History and its detail page show, built
/// by `InsightsRepository` from the stored library. Views read this and
/// nothing else (APP_RULES.md R20).
public nonisolated struct InsightsSnapshot: Sendable, Equatable {
    /// Which of Home's data states the tab is in (`.learning` under 7
    /// nights, `.empty`, `.permissionRequired`, `.healthDataUnavailable`,
    /// `.failed`; otherwise `.ready`).
    public let dataState: HomeDataState
    /// The night the insights are about (last night), when there is one.
    public let night: SleepNightKey?
    public let nightsRecorded: Int
    /// The featured story (top-ranked, after fatigue), if any.
    public let featured: InsightRecord?
    /// Latest of each type from the last 14 nights, newest night first.
    public let recent: [StoredInsight]
    /// Everything stored and not hidden, newest night first (History).
    public let all: [StoredInsight]
    /// New (not yet opened) insights from the last 7 nights.
    public let newThisWeek: Int
    /// The records that stand over the last 90 nights.
    public let records: [StandingRecord]
    public let lastUpdated: Date

    public init(
        dataState: HomeDataState, night: SleepNightKey?, nightsRecorded: Int, featured: InsightRecord?, recent: [StoredInsight],
        all: [StoredInsight], newThisWeek: Int, records: [StandingRecord], lastUpdated: Date
    ) {
        self.dataState = dataState
        self.night = night
        self.nightsRecorded = nightsRecorded
        self.featured = featured
        self.recent = recent
        self.all = all
        self.newThisWeek = newThisWeek
        self.records = records
        self.lastUpdated = lastUpdated
    }

    /// A snapshot with no insights: a state and nothing else.
    public static func placeholder(_ state: HomeDataState, nightsRecorded: Int = 0, now: Date) -> InsightsSnapshot {
        InsightsSnapshot(
            dataState: state, night: nil, nightsRecorded: nightsRecorded, featured: nil, recent: [], all: [],
            newThisWeek: 0, records: [], lastUpdated: now
        )
    }

    /// The stored insight with `id`.
    public func insight(id: String) -> StoredInsight? {
        all.first { $0.id == id }
    }
}
