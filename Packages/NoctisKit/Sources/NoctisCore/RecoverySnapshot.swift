import Foundation
import HealthProviding
import RecoveryKit
import SleepKit

/// The Recovery tab's segments: today's score built from its factors, and
/// the last 7, 30 or 90 nights.
public nonisolated enum RecoverySegment: String, Sendable, CaseIterable, Hashable, Codable {
    case today
    case week
    case month
    case quarter

    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }

    /// The history range a segment shows; nil for Today.
    public var historyRange: RecoveryHistoryRange? {
        switch self {
        case .today: nil
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        }
    }

    public init(range: RecoveryHistoryRange) {
        switch range {
        case .week: self = .week
        case .month: self = .month
        case .quarter: self = .quarter
        }
    }
}

/// What the Recovery tab is showing: a segment, and (with a factor's
/// detail open) a factor and how many nights of it.
public nonisolated struct RecoverySelection: Sendable, Hashable {
    public var segment: RecoverySegment
    public var factor: RecoveryFactorKind?
    public var factorRange: RecoveryFactorRange

    public init(segment: RecoverySegment = .today, factor: RecoveryFactorKind? = nil, factorRange: RecoveryFactorRange = .fortnight) {
        self.segment = segment
        self.factor = factor
        self.factorRange = factorRange
    }
}

/// Everything Recovery shows, derived from Health by `RecoveryRepository`.
/// Views read this and nothing else (APP_RULES.md R20).
public nonisolated struct RecoverySnapshot: Sendable, Equatable {
    /// The same states as Home, in the same order of precedence.
    public let dataState: HomeDataState
    /// Today's score, exactly as Home has it.
    public let recovery: RecoveryState?
    public let contributions: RecoveryContributions?
    public let confidence: RecoveryConfidenceReport?
    /// Every scored night, oldest first.
    public let scores: [RecoveryDayScore]
    /// One per `RecoveryHistoryRange`, in case order.
    public let histories: [RecoveryHistory]
    /// One per factor and `RecoveryFactorRange`.
    public let factorSeries: [RecoveryFactorSeries]
    public let needMinutes: Int
    /// The night that should be "last night" by now.
    public let anchorNight: SleepNightKey
    public let newestSample: Date?
    public let lastUpdated: Date

    public init(
        dataState: HomeDataState, recovery: RecoveryState?, contributions: RecoveryContributions?, confidence: RecoveryConfidenceReport?,
        scores: [RecoveryDayScore], histories: [RecoveryHistory], factorSeries: [RecoveryFactorSeries], needMinutes: Int,
        anchorNight: SleepNightKey, newestSample: Date?, lastUpdated: Date
    ) {
        self.dataState = dataState
        self.recovery = recovery
        self.contributions = contributions
        self.confidence = confidence
        self.scores = scores
        self.histories = histories
        self.factorSeries = factorSeries
        self.needMinutes = needMinutes
        self.anchorNight = anchorNight
        self.newestSample = newestSample
        self.lastUpdated = lastUpdated
    }

    /// Today's result, when there is one.
    public var result: RecoveryResult? {
        if case .scored(let result)? = recovery { return result }
        return nil
    }

    public func history(_ range: RecoveryHistoryRange) -> RecoveryHistory? {
        histories.first { $0.range == range }
    }

    public func series(_ kind: RecoveryFactorKind, _ range: RecoveryFactorRange) -> RecoveryFactorSeries? {
        factorSeries.first { $0.kind == kind && $0.range == range }
    }
}

public nonisolated enum RecoverySnapshotBuilder {
    /// Nights of history to read: the 90 nights the longest range shows, the
    /// 14-night baseline behind the oldest of them, and a few to spare.
    public static let historyNights = 90 + BaselineEngine.windowNights + 6

    public static func build(_ inputs: HomeHealthInputs, profile: UserProfileSnapshot, now: Date, timeZone: TimeZone) -> RecoverySnapshot {
        let dates = inputs.sleep.map(\.end) + inputs.hrv.map(\.date) + inputs.restingHeartRate.map(\.date) + inputs.heartRate.map(\.date)
        guard let newest = dates.filter({ $0 <= now }).max() else {
            return placeholder(.empty, profile: profile, now: now, timeZone: timeZone)
        }
        let sessions = SleepSessionEngine.history(from: inputs.sleep, asOf: now, timeZone: timeZone)
        let metrics = NightMetricsBuilder.metrics(for: sessions, hrv: inputs.hrv, restingHeartRate: inputs.restingHeartRate)
        let need = Double(profile.needMinutes)
        let recovery = RecoveryEngine.evaluate(history: metrics, needMinutes: need, asOf: now)
        let lastNight = sessions.lastNight(asOf: now, within: RecoveryModelV1.lastNightWindow)

        let dataState: HomeDataState
        if now.timeIntervalSince(newest) > HomeSnapshotBuilder.staleAfter {
            dataState = .stale(newestSample: newest)
        } else if case .learning(let nights) = recovery {
            dataState = .learning(nightsSoFar: nights)
        } else if lastNight == nil {
            dataState = .noSleepLastNight
        } else {
            dataState = .ready
        }

        let scores = RecoveryHistoryEngine.scores(history: metrics, needMinutes: need, asOf: now)
        var contributions: RecoveryContributions?
        var confidence: RecoveryConfidenceReport?
        if case .scored(let result) = recovery {
            contributions = RecoveryContributionEngine.contributions(for: result)
            confidence = RecoveryConfidenceReportBuilder.report(for: result)
        }
        // The window ends on the newest night with a score, or on last night.
        let end = scores.last?.night
        let histories = RecoveryHistoryRange.allCases.map { RecoveryHistoryEngine.history(scores: scores, range: $0, endingAt: end) }
        var series: [RecoveryFactorSeries] = []
        for kind in RecoveryContributionEngine.factorOrder {
            for range in RecoveryFactorRange.allCases {
                series.append(RecoveryFactorSeriesBuilder.series(kind, range: range, history: metrics, needMinutes: need, asOf: now, endingAt: end))
            }
        }
        return RecoverySnapshot(
            dataState: dataState, recovery: recovery, contributions: contributions, confidence: confidence,
            scores: scores, histories: histories, factorSeries: series, needMinutes: profile.needMinutes,
            anchorNight: HomeSnapshotBuilder.expectedLastNight(now: now, timeZone: timeZone, wakeMinutes: profile.typicalWakeMinutes),
            newestSample: newest, lastUpdated: now
        )
    }

    /// A snapshot with no Health data in it.
    public static func placeholder(_ state: HomeDataState, profile: UserProfileSnapshot, now: Date, timeZone: TimeZone) -> RecoverySnapshot {
        RecoverySnapshot(
            dataState: state, recovery: nil, contributions: nil, confidence: nil, scores: [],
            histories: RecoveryHistoryRange.allCases.map { RecoveryHistoryEngine.history(scores: [], range: $0) },
            factorSeries: [], needMinutes: profile.needMinutes,
            anchorNight: HomeSnapshotBuilder.expectedLastNight(now: now, timeZone: timeZone, wakeMinutes: profile.typicalWakeMinutes),
            newestSample: nil, lastUpdated: now
        )
    }
}
